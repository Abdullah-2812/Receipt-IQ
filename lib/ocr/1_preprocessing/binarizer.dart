import 'package:image/image.dart' as img;

class Binarizer {
  static img.Image binarize(img.Image gray) {
    final threshold = _otsuThreshold(gray);
    final output = img.Image(width: gray.width, height: gray.height);

    for (int y = 0; y < gray.height; y++) {
      for (int x = 0; x < gray.width; x++) {
        final lum = gray.getPixel(x, y).r.toInt();
        final val = lum < threshold ? 0 : 255;
        output.setPixelRgb(x, y, val, val, val);
      }
    }
    return output;
  }

  static int _otsuThreshold(img.Image gray) {
    final hist = List<int>.filled(256, 0);
    for (int y = 0; y < gray.height; y++) {
      for (int x = 0; x < gray.width; x++) {
        hist[gray.getPixel(x, y).r.toInt()]++;
      }
    }

    final total = gray.width * gray.height;
    double sumB = 0, sum = 0;
    int wB = 0, wF = 0;
    double maxVariance = 0;
    int threshold = 128;

    for (int i = 0; i < 256; i++) sum += i * hist[i];

    for (int t = 0; t < 256; t++) {
      wB += hist[t];
      if (wB == 0) continue;
      wF = total - wB;
      if (wF == 0) break;

      sumB += t * hist[t];
      final mB = sumB / wB;
      final mF = (sum - sumB) / wF;

      final variance = wB * wF * (mB - mF) * (mB - mF);
      if (variance > maxVariance) {
        maxVariance = variance;
        threshold = t;
      }
    }
    return threshold;
  }
}