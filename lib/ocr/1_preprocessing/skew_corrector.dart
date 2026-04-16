import 'dart:math';
import 'package:image/image.dart' as img;

class SkewCorrector {
  static img.Image correct(img.Image binary) {
    final angle = _detectSkewAngle(binary);
    if (angle.abs() < 0.5) return binary;
    return _rotateImage(binary, angle);
  }

  static List<List<bool>> _sobelEdges(img.Image binary) {
    final w = binary.width;
    final h = binary.height;
    final edges = List.generate(h, (_) => List<bool>.filled(w, false));

    const kernelX = [[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]];
    const kernelY = [[-1, -2, -1], [0, 0, 0], [1, 2, 1]];

    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        double gx = 0, gy = 0;

        for (int ky = -1; ky <= 1; ky++) {
          for (int kx = -1; kx <= 1; kx++) {
            final pixel = binary.getPixel(x + kx, y + ky).r.toDouble();
            final val = (255 - pixel) / 255.0;
            gx += val * kernelX[ky + 1][kx + 1];
            gy += val * kernelY[ky + 1][kx + 1];
          }
        }

        final magnitude = sqrt(gx * gx + gy * gy);
        edges[y][x] = magnitude > 0.3;
      }
    }
    return edges;
  }

  static double _detectSkewAngle(img.Image binary) {
    final w = binary.width;
    final h = binary.height;
    const step = 3;
    const minAngle = -45.0;
    const maxAngle = 45.0;
    const angleStep = 0.5;
    final numAngles = ((maxAngle - minAngle) / angleStep).round() + 1;
    final maxR = sqrt((w * w + h * h).toDouble()).ceil();
    final numR = maxR * 2 + 1;

    final accumulator =
        List.generate(numAngles, (_) => List<int>.filled(numR, 0));

    final cosTheta = <double>[];
    final sinTheta = <double>[];
    for (int ai = 0; ai < numAngles; ai++) {
      final theta = (minAngle + ai * angleStep) * pi / 180.0;
      cosTheta.add(cos(theta));
      sinTheta.add(sin(theta));
    }

    final edges = _sobelEdges(binary);

    for (int y = 0; y < h; y += step) {
      for (int x = 0; x < w; x += step) {
        if (!edges[y][x]) continue;
        for (int ai = 0; ai < numAngles; ai++) {
          final r = x * cosTheta[ai] + y * sinTheta[ai];
          final ri = (r + maxR).round();
          if (ri >= 0 && ri < numR) {
            accumulator[ai][ri]++;
          }
        }
      }
    }

    int bestAngleIdx = 0;
    int bestVotes = 0;

    for (int ai = 0; ai < numAngles; ai++) {
      int totalVotes = 0;
      for (int ri = 0; ri < numR; ri++) {
        totalVotes += accumulator[ai][ri];
      }
      if (totalVotes > bestVotes) {
        bestVotes = totalVotes;
        bestAngleIdx = ai;
      }
    }

    double skewAngle = minAngle + bestAngleIdx * angleStep;
    if (skewAngle > 45) skewAngle -= 90;
    if (skewAngle < -45) skewAngle += 90;

    return skewAngle;
  }

  static img.Image _rotateImage(img.Image src, double angleDeg) {
    final corrected = img.copyRotate(src, angle: -angleDeg);

    for (int y = 0; y < corrected.height; y++) {
      for (int x = 0; x < corrected.width; x++) {
        final pixel = corrected.getPixel(x, y);
        if (pixel.r == 0 && pixel.g == 0 && pixel.b == 0 &&
            _isCornerRegion(x, y, corrected.width, corrected.height)) {
          corrected.setPixelRgb(x, y, 255, 255, 255);
        }
      }
    }
    return corrected;
  }

  static bool _isCornerRegion(int x, int y, int w, int h) {
    final margin = (min(w, h) * 0.05).round();
    return x < margin || x > w - margin || y < margin || y > h - margin;
  }
}