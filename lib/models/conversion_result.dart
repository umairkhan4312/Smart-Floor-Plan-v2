class ConversionResult {
  const ConversionResult({
    required this.outputPath,
    required this.fileName,
    required this.width,
    required this.height,
  });

  final String outputPath;
  final String fileName;
  final int width;
  final int height;
}

enum FloorPlanStyle {
  original('Original', 'Only convert the file to PNG'),
  clean2d('Clean 2D', 'Crisp black drawing on a white background'),
  colored2d('Coloured 2D', 'Warm floor colour with dark architectural lines');

  const FloorPlanStyle(this.label, this.description);

  final String label;
  final String description;
}

class SelectedFloorPlan {
  const SelectedFloorPlan({
    required this.path,
    required this.name,
    required this.extension,
    required this.pdfPages,
  });

  final String path;
  final String name;
  final String extension;
  final int pdfPages;

  bool get isPdf => extension.toLowerCase() == 'pdf';
}
