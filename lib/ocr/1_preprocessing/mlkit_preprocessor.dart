import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Preprocesses a receipt image before passing to MLKit.
/// Runs in a background isolate — does not block the UI.
///
/// Pipeline: downscale → grayscale → contrast stretch → unsharp mask
class MlKitPreprocessor {
  static Future<File> preprocess(File input) async {
    final bytes = await input.readAsBytes();
    final processed = await compute(_run, bytes);
    if (processed == null) return input; // fallback to original on error
    final tmp = await getTemporaryDirectory();
    final out = File('${tmp.path}/ocr_preprocessed.jpg');
    await out.writeAsBytes(processed);
    return out;
  }
}

// Top-level so compute() can send it to a separate isolate.
Uint8List? _run(Uint8List bytes) {
  try {
    var image = img.decodeImage(bytes);
    if (image == null) return null;

    // 1. Downscale to max 1800px wide — MLKit doesn't need more and it's faster
    if (image.width > 1800) {
      image = img.copyResize(image, width: 1800,
          interpolation: img.Interpolation.linear);
    }

    // 2. Grayscale — eliminates colour noise
    image = img.grayscale(image);

    // 3. Contrast stretch (auto-levels) — helps faded thermal receipts
    image = _contrastStretch(image);

    // 4. Unsharp mask — sharpens soft/blurry captures without adding noise
    image = _unsharpMask(image, sigma: 1.0, strength: 1.5);

    return Uint8List.fromList(img.encodeJpg(image, quality: 92));
  } catch (_) {
    return null;
  }
}

/// Stretches the pixel histogram from [min,max] to [0,255].
img.Image _contrastStretch(img.Image gray) {
  int lo = 255, hi = 0;
  for (int y = 0; y < gray.height; y++) {
    for (int x = 0; x < gray.width; x++) {
      final v = gray.getPixel(x, y).r.toInt();
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
  }
  if (hi == lo) return gray;
  final range = hi - lo;
  final out = img.Image(width: gray.width, height: gray.height);
  for (int y = 0; y < gray.height; y++) {
    for (int x = 0; x < gray.width; x++) {
      final v = gray.getPixel(x, y).r.toInt();
      final s = ((v - lo) * 255 ~/ range).clamp(0, 255);
      out.setPixelRgb(x, y, s, s, s);
    }
  }
  return out;
}

/// Unsharp mask: sharpened = original + strength * (original - blurred).
img.Image _unsharpMask(img.Image src, {double sigma = 1.0, double strength = 1.5}) {
  final blurred = img.gaussianBlur(src, radius: sigma.round().clamp(1, 3));
  final out = img.Image(width: src.width, height: src.height);
  for (int y = 0; y < src.height; y++) {
    for (int x = 0; x < src.width; x++) {
      final o = src.getPixel(x, y).r.toInt();
      final b = blurred.getPixel(x, y).r.toInt();
      final s = (o + strength * (o - b)).round().clamp(0, 255);
      out.setPixelRgb(x, y, s, s, s);
    }
  }
  return out;
}
