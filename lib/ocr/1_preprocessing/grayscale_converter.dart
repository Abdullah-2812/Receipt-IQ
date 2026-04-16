import 'package:image/image.dart' as img;

class GrayscaleConverter {
  static img.Image convert(img.Image src) {
    final output = img.Image(width: src.width, height: src.height);

    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final pixel = src.getPixel(x, y);
        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();
        final gray = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
        output.setPixelRgb(x, y, gray, gray, gray);
      }
    }
    return output;
  }
}