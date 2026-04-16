import 'package:image/image.dart' as img;
import '../2_segmentation/connected_components.dart';

class FeatureExtractor {
  static const int gridSize = 16;

  static List<double> extract(img.Image binary, BoundingBox box) {
    final padded = _cropWithPadding(binary, box, padding: 2);

    final resized = img.copyResize(padded,
        width: gridSize,
        height: gridSize,
        interpolation: img.Interpolation.average);

    final pixels = <double>[];
    for (int y = 0; y < gridSize; y++) {
      for (int x = 0; x < gridSize; x++) {
        final lum = resized.getPixel(x, y).r.toDouble();
        pixels.add(lum < 128 ? 1.0 : 0.0);
      }
    }

    final hProfile = List<double>.filled(gridSize, 0);
    for (int y = 0; y < gridSize; y++) {
      double sum = 0;
      for (int x = 0; x < gridSize; x++) sum += pixels[y * gridSize + x];
      hProfile[y] = sum / gridSize;
    }

    final vProfile = List<double>.filled(gridSize, 0);
    for (int x = 0; x < gridSize; x++) {
      double sum = 0;
      for (int y = 0; y < gridSize; y++) sum += pixels[y * gridSize + x];
      vProfile[x] = sum / gridSize;
    }

    return [...pixels, ...hProfile, ...vProfile];
  }

  static img.Image _cropWithPadding(img.Image src, BoundingBox box,
      {int padding = 2}) {
    final x1 = (box.x - padding).clamp(0, src.width - 1);
    final y1 = (box.y - padding).clamp(0, src.height - 1);
    final x2 = (box.right + padding).clamp(0, src.width - 1);
    final y2 = (box.bottom + padding).clamp(0, src.height - 1);

    return img.copyCrop(src, x: x1, y: y1, width: x2 - x1, height: y2 - y1);
  }
}