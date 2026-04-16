import 'dart:math';

class KnnClassifier {
  final List<_Template> _templates = [];
  final int k;

  KnnClassifier({this.k = 3});

  void addTemplate(String label, List<double> features) {
    _templates.add(_Template(label, features));
  }

  bool get isTrained => _templates.isNotEmpty;

  int get templateCount => _templates.length;

  String classify(List<double> features) {
    if (_templates.isEmpty) return '?';

    final distances = _templates
        .map((t) => _ScoredTemplate(
            t.label, _euclideanDistance(features, t.features)))
        .toList();

    distances.sort((a, b) => a.distance.compareTo(b.distance));

    final topK = distances.take(k);
    final votes = <String, int>{};
    for (final s in topK) {
      votes[s.label] = (votes[s.label] ?? 0) + 1;
    }

    return votes.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  List<_Template> exportTemplates() => List.unmodifiable(_templates);

  double _euclideanDistance(List<double> a, List<double> b) {
    double sum = 0;
    for (int i = 0; i < a.length; i++) {
      final diff = a[i] - b[i];
      sum += diff * diff;
    }
    return sqrt(sum);
  }
}

class _Template {
  final String label;
  final List<double> features;
  _Template(this.label, this.features);
}

class _ScoredTemplate {
  final String label;
  final double distance;
  _ScoredTemplate(this.label, this.distance);
}