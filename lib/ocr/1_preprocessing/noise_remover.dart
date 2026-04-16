import 'package:image/image.dart' as img;

class NoiseRemover {
  static img.Image medianFilter(img.Image binary) {
    final output = img.Image(width: binary.width, height: binary.height);

    for (int y = 0; y < binary.height; y++) {
      for (int x = 0; x < binary.width; x++) {
        final neighbors = <int>[];

        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            final nx = (x + dx).clamp(0, binary.width - 1);
            final ny = (y + dy).clamp(0, binary.height - 1);
            neighbors.add(binary.getPixel(nx, ny).r.toInt());
          }
        }

        neighbors.sort();
        final median = neighbors[4];
        output.setPixelRgb(x, y, median, median, median);
      }
    }
    return output;
  }

  static img.Image morphologicalOpen(img.Image binary, {int kernelSize = 2}) {
    return _dilate(_erode(binary, kernelSize), kernelSize);
  }

  static img.Image _erode(img.Image src, int k) {
    final out = img.Image(width: src.width, height: src.height);
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        int minVal = 255;
        for (int dy = -k; dy <= k; dy++) {
          for (int dx = -k; dx <= k; dx++) {
            final nx = (x + dx).clamp(0, src.width - 1);
            final ny = (y + dy).clamp(0, src.height - 1);
            final v = src.getPixel(nx, ny).r.toInt();
            if (v < minVal) minVal = v;
          }
        }
        out.setPixelRgb(x, y, minVal, minVal, minVal);
      }
    }
    return out;
  }

  static img.Image _dilate(img.Image src, int k) {
    final out = img.Image(width: src.width, height: src.height);
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        int maxVal = 0;
        for (int dy = -k; dy <= k; dy++) {
          for (int dx = -k; dx <= k; dx++) {
            final nx = (x + dx).clamp(0, src.width - 1);
            final ny = (y + dy).clamp(0, src.height - 1);
            final v = src.getPixel(nx, ny).r.toInt();
            if (v > maxVal) maxVal = v;
          }
        }
        out.setPixelRgb(x, y, maxVal, maxVal, maxVal);
      }
    }
    return out;
  }
}