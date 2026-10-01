import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

import '../models/conversion_result.dart';

class FloorPlanConverter {
  Future<SelectedFloorPlan?> selectFile() async {
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
      allowMultiple: false,
      withData: false,
    );
    if (selection == null || selection.files.single.path == null) return null;

    final file = selection.files.single;
    final extension = (file.extension ?? p.extension(file.name).substring(1))
        .toLowerCase();
    var pages = 1;
    if (extension == 'pdf') {
      final document = await PdfDocument.openFile(file.path!);
      pages = document.pagesCount;
      await document.close();
    }
    return SelectedFloorPlan(
      path: file.path!,
      name: file.name,
      extension: extension,
      pdfPages: pages,
    );
  }

  Future<ConversionResult> generate(
    SelectedFloorPlan source, {
    int pdfPage = 1,
    FloorPlanStyle style = FloorPlanStyle.clean2d,
    bool cropMargins = true,
  }) async {
    final documents = await getApplicationDocumentsDirectory();
    final outputDirectory = Directory(
      p.join(documents.path, 'generated_floor_plans'),
    );
    await outputDirectory.create(recursive: true);

    final base = _safeName(p.basenameWithoutExtension(source.name));
    final pageSuffix = source.isPdf ? '_page_$pdfPage' : '';
    final styleSuffix = switch (style) {
      FloorPlanStyle.original => 'original',
      FloorPlanStyle.clean2d => 'clean_2d',
      FloorPlanStyle.colored2d => 'coloured_2d',
    };
    final outputName = '$base${pageSuffix}_${styleSuffix}_home_assistant.png'; 
    final outputPath = p.join(outputDirectory.path, outputName);

    late final Uint8List sourceBytes;
    if (source.isPdf) {
      sourceBytes = await _renderPdfPage(
        source.path,
        pdfPage,
      );
    } else {
      sourceBytes = await File(source.path).readAsBytes();
    }

    final processed = await Isolate.run(
      () => _processFloorPlan(sourceBytes, style.index, cropMargins),
    );
    await File(outputPath).writeAsBytes(processed.bytes, flush: true);

    return ConversionResult(
      outputPath: outputPath,
      fileName: outputName,
      width: processed.width,
      height: processed.height,
    );
  }

  Future<Uint8List> _renderPdfPage(
    String inputPath,
    int pageNumber,
  ) async {
    final document = await PdfDocument.openFile(inputPath);
    if (pageNumber < 1 || pageNumber > document.pagesCount) {
      await document.close();
      throw RangeError('The selected PDF page does not exist.');
    }
    final page = await document.getPage(pageNumber);
    try {
      const scale = 3.0;
      final image = await page.render(
        width: page.width * scale,
        height: page.height * scale,
        format: PdfPageImageFormat.png,
        backgroundColor: '#FFFFFFFF',
      );
      if (image == null) throw StateError('Could not render this PDF page.');
      return image.bytes;
    } finally {
      await page.close();
      await document.close();
    }
  }

  String _safeName(String value) {
    final normalized = value.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    return normalized.replaceAll(RegExp(r'^_+|_+$'), '').isEmpty
        ? 'floor_plan'
        : normalized.replaceAll(RegExp(r'^_+|_+$'), '');
  }
}

class _ProcessedImage {
  const _ProcessedImage(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final int width;
  final int height;
}

_ProcessedImage _processFloorPlan(
  Uint8List bytes,
  int styleIndex,
  bool cropMargins,
) {
  var source = img.decodeImage(bytes);
  if (source == null) throw StateError('The selected image cannot be decoded.');
  source = img.bakeOrientation(source);

  if (cropMargins) source = _cropWhiteMargins(source);
  final style = FloorPlanStyle.values[styleIndex];
  if (style != FloorPlanStyle.original) {
    final line = style == FloorPlanStyle.clean2d
        ? (r: 20, g: 28, b: 34)
        : (r: 28, g: 47, b: 58);
    final paper = style == FloorPlanStyle.clean2d
        ? (r: 255, g: 255, b: 255)
        : (r: 238, g: 230, b: 211);

    for (final pixel in source) {
      final luminance =
          (pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114).round();
      final ink = ((235 - luminance) / 105).clamp(0.0, 1.0);
      pixel
        ..r = (paper.r + (line.r - paper.r) * ink).round()
        ..g = (paper.g + (line.g - paper.g) * ink).round()
        ..b = (paper.b + (line.b - paper.b) * ink).round()
        ..a = 255;
    }
  }

  return _ProcessedImage(
    Uint8List.fromList(img.encodePng(source, level: 6)),
    source.width,
    source.height,
  );
}

img.Image _cropWhiteMargins(img.Image source) {
  var left = source.width;
  var top = source.height;
  var right = -1;
  var bottom = -1;

  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      final pixel = source.getPixel(x, y);
      if (pixel.r < 245 || pixel.g < 245 || pixel.b < 245) {
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
  }

  if (right < left || bottom < top) return source;
  final padding = (source.width * 0.02).round().clamp(12, 80);
  left = (left - padding).clamp(0, source.width - 1).toInt();
  top = (top - padding).clamp(0, source.height - 1).toInt();
  right = (right + padding).clamp(0, source.width - 1).toInt();
  bottom = (bottom + padding).clamp(0, source.height - 1).toInt();
  return img.copyCrop(
    source,
    x: left,
    y: top,
    width: right - left + 1,
    height: bottom - top + 1,
  );
}
