import 'dart:convert';
import 'dart:io';
import 'knn_classifier.dart';

class TemplateStore {
  final String storePath;

  TemplateStore({required this.storePath});

  Future<void> save(KnnClassifier classifier) async {
    final templates = classifier.exportTemplates();

    final data = {
      'version': 1,
      'count': templates.length,
      'templates': templates
          .map((t) => {
                'label': t.label,
                'features': t.features,
              })
          .toList(),
    };

    final file = File(storePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(data));
  }

  Future<int> load(KnnClassifier classifier) async {
    final file = File(storePath);
    if (!await file.exists()) return 0;

    try {
      final raw = await file.readAsString();
      final data = jsonDecode(raw) as Map<String, dynamic>;

      final templates = data['templates'] as List<dynamic>;
      for (final t in templates) {
        final label = t['label'] as String;
        final features = (t['features'] as List<dynamic>)
            .map((f) => (f as num).toDouble())
            .toList();
        classifier.addTemplate(label, features);
      }

      return templates.length;
    } catch (e) {
      await file.delete();
      return 0;
    }
  }

  Future<void> clear() async {
    final file = File(storePath);
    if (await file.exists()) await file.delete();
  }

  Future<bool> get hasSavedData async => File(storePath).exists();
}