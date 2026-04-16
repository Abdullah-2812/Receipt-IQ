import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Copies [assets/ocr/ocr_templates.json] into app documents on first run so
/// [OcrEngine] / [TemplateStore] can load the same path as today without
/// changing the OCR module.
class OcrTemplateBootstrap {
  OcrTemplateBootstrap._();

  static const String assetPath = 'assets/ocr/ocr_templates.json';

  /// Writes bundled templates to `getApplicationDocumentsDirectory()/ocr_templates.json`
  /// only when that file does not exist yet.
  static Future<void> ensureBundledTemplates() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/ocr_templates.json');
    if (await file.exists()) return;

    try {
      final raw = await rootBundle.loadString(assetPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(raw);
    } catch (_) {
      // Asset missing or unreadable — leave engine untrained.
    }
  }
}
