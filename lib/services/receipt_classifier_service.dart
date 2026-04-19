import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class ClassificationResult {
  final String category;
  final double confidence;
  final bool useFallback;

  const ClassificationResult({
    required this.category,
    required this.confidence,
    required this.useFallback,
  });
}

class ReceiptClassifierService {
  static const _modelAsset = 'assets/ml/receipt_classifier.tflite';
  static const _vocabAsset = 'assets/ml/tfidf_vocab.json';
  static const _categoriesAsset = 'assets/ml/categories.json';
  static const _vectorSize = 3000;
  static const _confidenceThreshold = 0.75;

  Interpreter? _interpreter;
  Map<String, int> _vocabulary = {};
  List<double> _idfWeights = [];
  List<String> _categories = [];
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    await Future.wait([_loadModel(), _loadVocab(), _loadCategories()]);
    _isInitialized = true;
  }

  Future<void> _loadModel() async {
    _interpreter = await Interpreter.fromAsset(_modelAsset);
  }

  Future<void> _loadVocab() async {
    final raw = await rootBundle.loadString(_vocabAsset);
    final data = json.decode(raw) as Map<String, dynamic>;
    _vocabulary = (data['vocabulary'] as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, v as int));
    _idfWeights = (data['idf_weights'] as List).cast<double>();
  }

  Future<void> _loadCategories() async {
    final raw = await rootBundle.loadString(_categoriesAsset);
    final data = json.decode(raw) as Map<String, dynamic>;
    _categories = (data['classes'] as List).cast<String>();
  }

  ClassificationResult classify(String ocrText) {
    if (!_isInitialized) {
      throw StateError('Call initialize() before classify().');
    }

    final vector = _buildTfidfVector(ocrText);
    final scores = _runInference(vector);

    int maxIdx = 0;
    for (int i = 1; i < scores.length; i++) {
      if (scores[i] > scores[maxIdx]) maxIdx = i;
    }

    return ClassificationResult(
      category: _categories[maxIdx],
      confidence: scores[maxIdx],
      useFallback: scores[maxIdx] < _confidenceThreshold,
    );
  }

  Float32List _buildTfidfVector(String text) {
    final tokens = _tokenize(text);
    final counts = <String, int>{};

    // Unigrams
    for (final t in tokens) {
      counts[t] = (counts[t] ?? 0) + 1;
    }
    // Bigrams
    for (int i = 0; i < tokens.length - 1; i++) {
      final bg = '${tokens[i]} ${tokens[i + 1]}';
      counts[bg] = (counts[bg] ?? 0) + 1;
    }

    final vector = Float32List(_vectorSize);
    for (final entry in counts.entries) {
      final idx = _vocabulary[entry.key];
      if (idx == null) continue;
      // sublinear_tf: tf = 1 + log(raw_count)
      final tf = 1.0 + log(entry.value.toDouble());
      vector[idx] = (tf * _idfWeights[idx]).toDouble();
    }

    return vector;
  }

  // Mirrors sklearn's default token_pattern r"(?u)\b\w\w+\b"
  List<String> _tokenize(String text) {
    return RegExp(r'\w\w+')
        .allMatches(text.toLowerCase())
        .map((m) => m.group(0)!)
        .toList();
  }

  List<double> _runInference(Float32List vector) {
    // Input tensor shape: [1, 3000], output shape: [1, 6]
    final input = [vector.toList()];
    final output = [List<double>.filled(_categories.length, 0.0)];

    _interpreter!.run(input, output);

    return _softmax(output[0]);
  }

  List<double> _softmax(List<double> logits) {
    final maxVal = logits.reduce(max);
    final exps = logits.map((v) => exp(v - maxVal)).toList();
    final sum = exps.reduce((a, b) => a + b);
    return exps.map((e) => e / sum).toList();
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }
}
