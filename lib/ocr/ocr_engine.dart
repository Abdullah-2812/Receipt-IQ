import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

import '1_preprocessing/grayscale_converter.dart';
import '1_preprocessing/binarizer.dart';
import '1_preprocessing/noise_remover.dart';
import '1_preprocessing/skew_corrector.dart';
import '2_segmentation/connected_components.dart';
import '2_segmentation/line_segmenter.dart';
import '3_recognition/feature_extractor.dart';
import '3_recognition/knn_classifier.dart';
import '3_recognition/template_store.dart';

class OcrResult {
  final String text;
  final List<String> lines;
  final bool success;
  final String? error;

  OcrResult({
    required this.text,
    required this.lines,
    required this.success,
    this.error,
  });
}

class OcrEngine {
  final KnnClassifier _classifier;
  late final TemplateStore _store;
  bool get isReady => _classifier.isTrained;

  int get templateCount => _classifier.templateCount;

  OcrEngine({int k = 3, required String storePath})
      : _classifier = KnnClassifier(k: k) {
    _store = TemplateStore(storePath: storePath);
  }

  // ─── Persistence ──────────────────────────────────────────────────────────

  Future<int> loadSavedTemplates() => _store.load(_classifier);
  Future<void> saveTemplates() => _store.save(_classifier);
  Future<void> clearTemplates() => _store.clear();

  // ─── Training ─────────────────────────────────────────────────────────────

  Future<void> trainWithSample(File imageFile, String label) async {
    final binary = await _preprocess(imageFile);
    final boxes = ConnectedComponents.label(binary, minArea: 10);
    if (boxes.isEmpty) return;

    boxes.sort((a, b) => b.area.compareTo(a.area));
    final features = FeatureExtractor.extract(binary, boxes.first);
    _classifier.addTemplate(label, features);
    await saveTemplates();
  }

  Future<void> trainWithSheet(File sheetFile, List<String> labels) async {
    final binary = await _preprocess(sheetFile);
    final boxes = ConnectedComponents.label(binary, minArea: 20);
    final lines = LineSegmenter.segment(binary, boxes);

    final allChars = <BoundingBox>[];
    for (final line in lines) allChars.addAll(line.characters);

    for (int i = 0; i < labels.length && i < allChars.length; i++) {
      final features = FeatureExtractor.extract(binary, allChars[i]);
      _classifier.addTemplate(labels[i], features);
    }
    await saveTemplates();
  }

  // ─── Recognition ──────────────────────────────────────────────────────────

  Future<OcrResult> recognize(File imageFile) async {
    if (!isReady) {
      return OcrResult(
        text: '',
        lines: [],
        success: false,
        error: 'OCR engine not trained. Please train first.',
      );
    }

    try {
      final binary = await _preprocess(imageFile);

      final boxes = ConnectedComponents.label(binary);
      if (boxes.isEmpty) {
        return OcrResult(text: '', lines: [], success: true);
      }

      final textLines = LineSegmenter.segment(binary, boxes);

      final recognizedLines = <String>[];
      for (final line in textLines) {
        final buffer = StringBuffer();
        BoundingBox? prevBox;

        for (final charBox in line.characters) {
          if (prevBox != null) {
            final gap = charBox.x - prevBox.right;
            final avgCharWidth = charBox.width;
            if (gap > avgCharWidth * 0.5) buffer.write(' ');
          }

          final features = FeatureExtractor.extract(binary, charBox);
          final label = _classifier.classify(features);
          buffer.write(label);
          prevBox = charBox;
        }

        recognizedLines.add(buffer.toString());
      }

      final fullText = recognizedLines.join('\n');
      return OcrResult(text: fullText, lines: recognizedLines, success: true);
    } catch (e) {
      return OcrResult(
          text: '', lines: [], success: false, error: e.toString());
    }
  }

  // ─── Preprocessing Pipeline ───────────────────────────────────────────────

  Future<img.Image> _preprocess(File file) async {
    final bytes = await file.readAsBytes();
    img.Image? decoded = img.decodeImage(Uint8List.fromList(bytes));
    if (decoded == null) throw Exception('Could not decode image');

    if (decoded.width > 1500) {
      decoded = img.copyResize(decoded, width: 1500);
    }

    final gray = GrayscaleConverter.convert(decoded);
    final binary = Binarizer.binarize(gray);
    final deskewed = SkewCorrector.correct(binary);
    final denoised = NoiseRemover.medianFilter(deskewed);
    return NoiseRemover.morphologicalOpen(denoised);
  }
}