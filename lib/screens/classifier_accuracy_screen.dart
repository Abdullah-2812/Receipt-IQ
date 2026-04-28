import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import '../services/receipt_classifier_service.dart';
import '../utils/constants.dart';
import '../widgets/classifier_debug_card.dart';

// ---------------------------------------------------------------------------
// Data model for one test entry
// ---------------------------------------------------------------------------
class _TestEntry {
  final String imagePath;
  final String filename;
  String groundTruth;
  String? predictedCategory;
  double? confidence;
  Map<String, double> allScores = {};
  String? ocrText;
  bool isProcessed = false;
  bool hasError = false;

  _TestEntry({
    required this.imagePath,
    required this.filename,
    required this.groundTruth,
  });

  bool get isCorrect =>
      isProcessed && !hasError && predictedCategory == groundTruth;
}

// ---------------------------------------------------------------------------
// All 76 test images: relative path within _imageBaseDir + ground-truth label
// ---------------------------------------------------------------------------
String get _imageBaseDir => defaultTargetPlatform == TargetPlatform.windows
    ? r'D:\receipt_project\Parser testing sample\images'
    : '/sdcard/receipt_images';

const List<Map<String, String>> _testData = [
  // ATM — 6 images
  {'p': r'atm\202.png', 'gt': 'atm'},
  {'p': r'atm\214.png', 'gt': 'atm'},
  {'p': r'atm\246.png', 'gt': 'atm'},
  {'p': r'atm\266.png', 'gt': 'atm'},
  {'p': r'atm\273.png', 'gt': 'atm'},
  {'p': r'atm\289.png', 'gt': 'atm'},
  // Food — 20 images
  {'p': r'food\138.png', 'gt': 'food'},
  {'p': r'food\24.png', 'gt': 'food'},
  {'p': r'food\33.png', 'gt': 'food'},
  {'p': r'food\35.png', 'gt': 'food'},
  {'p': r'food\386.png', 'gt': 'food'},
  {'p': r'food\392.png', 'gt': 'food'},
  {'p': r'food\394.png', 'gt': 'food'},
  {'p': r'food\404.png', 'gt': 'food'},
  {'p': r'food\415.png', 'gt': 'food'},
  {'p': r'food\428.png', 'gt': 'food'},
  {'p': r'food\429.png', 'gt': 'food'},
  {'p': r'food\430.png', 'gt': 'food'},
  {'p': r'food\431.png', 'gt': 'food'},
  {'p': r'food\432.png', 'gt': 'food'},
  {'p': r'food\433.png', 'gt': 'food'},
  {'p': r'food\434.png', 'gt': 'food'},
  {'p': r'food\450.png', 'gt': 'food'},
  {'p': r'food\475.png', 'gt': 'food'},
  {'p': r'food\479.png', 'gt': 'food'},
  {'p': r'food\481.png', 'gt': 'food'},
  // Grocery — 9 images
  {'p': r'grocery\110.png', 'gt': 'grocery'},
  {'p': r'grocery\139.png', 'gt': 'grocery'},
  {'p': r'grocery\423.png', 'gt': 'grocery'},
  {'p': r'grocery\49.png', 'gt': 'grocery'},
  {'p': r'grocery\50.png', 'gt': 'grocery'},
  {'p': r'grocery\52.png', 'gt': 'grocery'},
  {'p': r'grocery\55.png', 'gt': 'grocery'},
  {'p': r'grocery\60.png', 'gt': 'grocery'},
  {'p': r'grocery\77.png', 'gt': 'grocery'},
  // POS Fuel — 9 images
  {'p': r'pos fuel\148.png', 'gt': 'pos_fuel'},
  {'p': r'pos fuel\150.png', 'gt': 'pos_fuel'},
  {'p': r'pos fuel\156.png', 'gt': 'pos_fuel'},
  {'p': r'pos fuel\158.png', 'gt': 'pos_fuel'},
  {'p': r'pos fuel\192.png', 'gt': 'pos_fuel'},
  {'p': r'pos fuel\195.png', 'gt': 'pos_fuel'},
  {'p': r'pos fuel\380.png', 'gt': 'pos_fuel'},
  {'p': r'pos fuel\385.png', 'gt': 'pos_fuel'},
  {'p': r'pos fuel\487.png', 'gt': 'pos_fuel'},
  // POS Store — 18 images
  {'p': r'pos store\149.png', 'gt': 'pos_store'},
  {'p': r'pos store\152.png', 'gt': 'pos_store'},
  {'p': r'pos store\153.png', 'gt': 'pos_store'},
  {'p': r'pos store\155.png', 'gt': 'pos_store'},
  {'p': r'pos store\157.png', 'gt': 'pos_store'},
  {'p': r'pos store\159.png', 'gt': 'pos_store'},
  {'p': r'pos store\165.png', 'gt': 'pos_store'},
  {'p': r'pos store\166.png', 'gt': 'pos_store'},
  {'p': r'pos store\170.png', 'gt': 'pos_store'},
  {'p': r'pos store\171.png', 'gt': 'pos_store'},
  {'p': r'pos store\172.png', 'gt': 'pos_store'},
  {'p': r'pos store\176.png', 'gt': 'pos_store'},
  {'p': r'pos store\387.png', 'gt': 'pos_store'},
  {'p': r'pos store\391.png', 'gt': 'pos_store'},
  {'p': r'pos store\495.png', 'gt': 'pos_store'},
  {'p': r'pos store\497.png', 'gt': 'pos_store'},
  {'p': r'pos store\498.png', 'gt': 'pos_store'},
  {'p': r'pos store\500.png', 'gt': 'pos_store'},
  // Store — 14 images
  {'p': r'store\28.png', 'gt': 'store'},
  {'p': r'store\29.png', 'gt': 'store'},
  {'p': r'store\374.png', 'gt': 'store'},
  {'p': r'store\395.png', 'gt': 'store'},
  {'p': r'store\425.png', 'gt': 'store'},
  {'p': r'store\43.png', 'gt': 'store'},
  {'p': r'store\53.png', 'gt': 'store'},
  {'p': r'store\56.png', 'gt': 'store'},
  {'p': r'store\62.png', 'gt': 'store'},
  {'p': r'store\63.png', 'gt': 'store'},
  {'p': r'store\64.png', 'gt': 'store'},
  {'p': r'store\65.png', 'gt': 'store'},
  {'p': r'store\66.png', 'gt': 'store'},
  {'p': r'store\67.png', 'gt': 'store'},
];

const List<String> _validCategories = [
  'atm',
  'food',
  'grocery',
  'pos_fuel',
  'pos_store',
  'store',
];

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class ClassifierAccuracyScreen extends StatefulWidget {
  const ClassifierAccuracyScreen({super.key});

  @override
  State<ClassifierAccuracyScreen> createState() =>
      _ClassifierAccuracyScreenState();
}

class _ClassifierAccuracyScreenState
    extends State<ClassifierAccuracyScreen> {
  late List<_TestEntry> _entries;
  bool _isRunning = false;
  bool _isDone = false;
  int _processedCount = 0;
  bool _classifierReady = false;
  String _statusMessage = 'Initializing classifier…';

  final ReceiptClassifierService _classifier = ReceiptClassifierService();
  late final TextRecognizer _textRecognizer;

  // ---- lifecycle -----------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _textRecognizer = TextRecognizer();
    final sep = Platform.pathSeparator;
    _entries = _testData
        .map((d) {
          final rel = d['p']!.replaceAll('\\', sep);
          return _TestEntry(
            imagePath: '$_imageBaseDir$sep$rel',
            filename: d['p']!.split('\\').last,
            groundTruth: d['gt']!,
          );
        })
        .toList();
    _initClassifier();
  }

  @override
  void dispose() {
    _classifier.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  Future<void> _initClassifier() async {
    try {
      await _classifier.initialize();
      if (mounted) {
        setState(() {
          _classifierReady = true;
          _statusMessage = 'Ready — ${_entries.length} images loaded.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusMessage = 'Classifier init failed: $e');
      }
    }
  }

  // ---- test runner ---------------------------------------------------------

  Future<void> _runTest() async {
    if (!_classifierReady || _isRunning) return;
    setState(() {
      _isRunning = true;
      _isDone = false;
      _processedCount = 0;
      for (final e in _entries) {
        e.predictedCategory = null;
        e.confidence = null;
        e.isProcessed = false;
        e.hasError = false;
      }
      _statusMessage = 'Running…';
    });

    for (int i = 0; i < _entries.length; i++) {
      if (!_isRunning) break;
      final entry = _entries[i];
      try {
        final inputImage = InputImage.fromFile(File(entry.imagePath));
        final recognized = await _textRecognizer.processImage(inputImage);
        entry.ocrText = recognized.text;
        final allScores = _classifier.classifyAll(recognized.text);
        entry.allScores = allScores;
        final top = allScores.entries.first;
        entry.predictedCategory = top.key;
        entry.confidence = top.value;
        entry.isProcessed = true;
      } catch (e) {
        entry.hasError = true;
        entry.isProcessed = true;
      }
      setState(() {
        _processedCount = i + 1;
        _statusMessage =
            'Processing ${i + 1} / ${_entries.length}: ${entry.filename}';
      });
    }

    setState(() {
      _isRunning = false;
      _isDone = true;
      _statusMessage = 'Done — $_processedCount images processed.';
    });
  }

  void _stopTest() => setState(() => _isRunning = false);

  // ---- inspector -----------------------------------------------------------

  void _showInspector(_TestEntry entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.88,
        minChildSize: 0.4,
        maxChildSize: 0.97,
        expand: false,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              entry.filename,
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600, fontSize: 15),
            ),
            Text(
              'Ground truth: ${entry.groundTruth}  |  '
              'Predicted: ${entry.predictedCategory ?? "—"}',
              style: GoogleFonts.poppins(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            // Receipt image
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                File(entry.imagePath),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  height: 120,
                  color: Colors.grey.shade100,
                  alignment: Alignment.center,
                  child: Text('Image not found',
                      style: TextStyle(color: Colors.grey.shade500)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // All 6 probability bars
            if (entry.allScores.isNotEmpty)
              ClassifierDebugCard(scores: entry.allScores),
            const SizedBox(height: 12),
            // OCR text
            if (entry.ocrText != null && entry.ocrText!.isNotEmpty) ...[
              Text('OCR Text',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  entry.ocrText!,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ] else
              Text('No OCR text captured.',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade500,
                      fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }

  // ---- metrics -------------------------------------------------------------

  Map<String, dynamic> _computeMetrics() {
    final processed =
        _entries.where((e) => e.isProcessed && !e.hasError).toList();
    if (processed.isEmpty) return {};

    final total = processed.length;
    final correct = processed.where((e) => e.isCorrect).length;

    // Per category
    final Map<String, _CatStats> perCat = {
      for (final c in _validCategories) c: _CatStats(),
    };
    for (final e in processed) {
      final s = perCat[e.groundTruth];
      if (s == null) continue;
      s.total++;
      if (e.isCorrect) s.correct++;
      s.confSum += e.confidence ?? 0;
    }

    // Confusion matrix — rows = actual, cols = predicted
    final Map<String, Map<String, int>> cm = {
      for (final c in _validCategories)
        c: {for (final d in _validCategories) d: 0},
    };
    for (final e in processed) {
      final row = cm[e.groundTruth];
      if (row == null) continue;
      final col = e.predictedCategory ?? 'unknown';
      row[col] = (row[col] ?? 0) + 1;
    }

    return {
      'total': total,
      'correct': correct,
      'accuracy': correct / total * 100,
      'perCat': perCat,
      'cm': cm,
    };
  }

  // ---- CSV export ----------------------------------------------------------

  Future<void> _exportCsv() async {
    final buf = StringBuffer();
    buf.writeln('filename,ground_truth,predicted_category,confidence,correct');
    for (final e in _entries) {
      if (!e.isProcessed) continue;
      final correct = e.hasError ? 'error' : (e.isCorrect ? 'true' : 'false');
      final pred = e.hasError ? 'ERROR' : (e.predictedCategory ?? '');
      final conf = e.confidence?.toStringAsFixed(4) ?? '';
      buf.writeln(
          '"${e.filename}","${e.groundTruth}","$pred","$conf","$correct"');
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final file = File('${dir.path}\\classifier_accuracy_$ts.csv');
      await file.writeAsString(buf.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('CSV saved: ${file.path}'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  // ---- UI ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final metrics =
        _isDone ? _computeMetrics() : <String, dynamic>{};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Classifier Accuracy Test'),
        actions: [
          if (_isDone && _processedCount > 0)
            IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Export CSV',
              onPressed: _exportCsv,
            ),
        ],
      ),
      body: Column(
        children: [
          _buildControlPanel(metrics),
          const Divider(height: 1),
          Expanded(
            child: _isDone && metrics.isNotEmpty
                ? _buildResultsWithMetrics(metrics)
                : Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      child: _buildResultsTable(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ---- control panel -------------------------------------------------------

  Widget _buildControlPanel(Map<String, dynamic> metrics) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _statusMessage,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (_isRunning) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: _entries.isEmpty
                            ? 0
                            : _processedCount / _entries.length,
                        backgroundColor: AppColors.background,
                        color: AppColors.primary,
                      ),
                    ],
                    if (_isDone && metrics.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Overall Accuracy: ${(metrics['accuracy'] as double).toStringAsFixed(1)}%'
                        '  (${metrics['correct']}/${metrics['total']})',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (_isRunning)
                OutlinedButton.icon(
                  onPressed: _stopTest,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                )
              else
                ElevatedButton.icon(
                  onPressed: _classifierReady ? _runTest : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Run Test'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- results + metrics layout -------------------------------------------

  Widget _buildResultsWithMetrics(Map<String, dynamic> metrics) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMetricsCards(metrics),
          const SizedBox(height: 20),
          _buildPerCategoryTable(metrics),
          const SizedBox(height: 20),
          _buildConfusionMatrix(metrics),
          const SizedBox(height: 20),
          _buildDetailedResultsTable(),
        ],
      ),
    );
  }

  // ---- metric cards --------------------------------------------------------

  Widget _buildMetricsCards(Map<String, dynamic> metrics) {
    final perCat = metrics['perCat'] as Map<String, _CatStats>;
    double totalConf = 0;
    int confCount = 0;
    for (final e in _entries) {
      if (e.isProcessed && !e.hasError && e.confidence != null) {
        totalConf += e.confidence!;
        confCount++;
      }
    }
    final avgConf = confCount > 0 ? totalConf / confCount * 100 : 0.0;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _MetricCard(
          label: 'Overall Accuracy',
          value:
              '${(metrics['accuracy'] as double).toStringAsFixed(1)}%',
          subtitle: '${metrics['correct']} / ${metrics['total']} correct',
          color: AppColors.primary,
        ),
        _MetricCard(
          label: 'Avg Confidence',
          value: '${avgConf.toStringAsFixed(1)}%',
          subtitle: 'across all predictions',
          color: AppColors.accent,
        ),
        _MetricCard(
          label: 'Images Tested',
          value: '${metrics['total']}',
          subtitle: '${_validCategories.length} categories',
          color: Colors.orange,
        ),
        _MetricCard(
          label: 'Best Category',
          value: () {
            String bestCat = '';
            double bestAcc = -1;
            for (final e in perCat.entries) {
              if (e.value.total > 0) {
                final acc = e.value.correct / e.value.total;
                if (acc > bestAcc) {
                  bestAcc = acc;
                  bestCat = e.key;
                }
              }
            }
            return '${(bestAcc * 100).toStringAsFixed(0)}%  ($bestCat)';
          }(),
          subtitle: 'highest per-category accuracy',
          color: Colors.purple,
        ),
      ],
    );
  }

  // ---- per category table --------------------------------------------------

  Widget _buildPerCategoryTable(Map<String, dynamic> metrics) {
    final perCat = metrics['perCat'] as Map<String, _CatStats>;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Per-Category Accuracy',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 12),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1),
                3: FlexColumnWidth(2),
                4: FlexColumnWidth(2),
              },
              children: [
                _tableHeaderRow(
                    ['Category', 'Correct', 'Total', 'Accuracy', 'Avg Conf']),
                ...(_validCategories.map((cat) {
                  final s = perCat[cat]!;
                  final acc = s.total > 0
                      ? '${(s.correct / s.total * 100).toStringAsFixed(1)}%'
                      : '-';
                  final avgC = s.total > 0
                      ? '${(s.confSum / s.total * 100).toStringAsFixed(1)}%'
                      : '-';
                  final color = s.total > 0
                      ? _accuracyColor(s.correct / s.total)
                      : Colors.grey;
                  return TableRow(
                    decoration: BoxDecoration(
                      color: _validCategories.indexOf(cat).isEven
                          ? AppColors.background
                          : AppColors.surface,
                    ),
                    children: [
                      _tableCell(cat),
                      _tableCell('${s.correct}'),
                      _tableCell('${s.total}'),
                      _tableCellColored(acc, color),
                      _tableCell(avgC),
                    ],
                  );
                })),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---- confusion matrix ----------------------------------------------------

  Widget _buildConfusionMatrix(Map<String, dynamic> metrics) {
    final cm = metrics['cm'] as Map<String, Map<String, int>>;
    const cats = _validCategories;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Confusion Matrix',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              'Rows = Actual  |  Columns = Predicted',
              style: GoogleFonts.poppins(
                  fontSize: 11, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                defaultColumnWidth: const FixedColumnWidth(72),
                border: TableBorder.all(
                  color: AppColors.textHint,
                  width: 0.5,
                ),
                children: [
                  // Header row
                  TableRow(
                    decoration:
                        const BoxDecoration(color: AppColors.primary),
                    children: [
                      _cmCell('↓Act / Pred→',
                          bold: true, color: Colors.white),
                      ...cats.map((c) =>
                          _cmCell(c, bold: true, color: Colors.white)),
                    ],
                  ),
                  // Data rows
                  ...cats.map((actual) {
                    final rowData = cm[actual]!;
                    return TableRow(children: [
                      _cmCell(actual, bold: true),
                      ...cats.map((pred) {
                        final val = rowData[pred] ?? 0;
                        final isDiag = actual == pred;
                        final bgColor = isDiag && val > 0
                            ? AppColors.accent.withValues(alpha: 0.25)
                            : val > 0 && !isDiag
                                ? AppColors.error.withValues(alpha: 0.15)
                                : null;
                        return _cmCell(
                          '$val',
                          background: bgColor,
                          bold: isDiag,
                        );
                      }),
                    ]);
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- detailed results table ----------------------------------------------

  Widget _buildDetailedResultsTable() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Detailed Results',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 12),
            _buildResultsTable(),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsTable() {
    return Table(
      columnWidths: const {
        0: FixedColumnWidth(28),
        1: FlexColumnWidth(2),
        2: FlexColumnWidth(2),
        3: FlexColumnWidth(1.5),
        4: FlexColumnWidth(2),
        5: FixedColumnWidth(32),
      },
      children: [
        _tableHeaderRow(['#', 'File', 'Predicted', 'Conf', 'Ground Truth', '']),
        ..._entries.asMap().entries.map((entry) {
          final i = entry.key;
          final e = entry.value;
          Color? rowColor;
          if (e.isProcessed) {
            rowColor = e.hasError
                ? AppColors.error.withValues(alpha: 0.07)
                : e.isCorrect
                    ? AppColors.accent.withValues(alpha: 0.07)
                    : AppColors.error.withValues(alpha: 0.07);
          } else if (i.isEven) {
            rowColor = AppColors.background;
          }

          return TableRow(
            decoration: BoxDecoration(color: rowColor),
            children: [
              _tableCell('${i + 1}',
                  style: const TextStyle(fontSize: 11)),
              _tableCell(e.filename,
                  style: const TextStyle(fontSize: 11)),
              _tableCell(
                e.hasError
                    ? 'ERROR'
                    : e.isProcessed
                        ? (e.predictedCategory ?? '…')
                        : '—',
                style: TextStyle(
                  fontSize: 11,
                  color: e.isProcessed && !e.hasError
                      ? (e.isCorrect
                          ? AppColors.accent
                          : AppColors.error)
                      : AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              _tableCell(
                e.isProcessed && !e.hasError && e.confidence != null
                    ? '${(e.confidence! * 100).toStringAsFixed(1)}%'
                    : '—',
                style: const TextStyle(fontSize: 11),
              ),
              // Ground-truth — popup menu, more compact than DropdownButton
              PopupMenuButton<String>(
                initialValue: e.groundTruth,
                onSelected: (v) => setState(() => e.groundTruth = v),
                padding: EdgeInsets.zero,
                itemBuilder: (_) => _validCategories
                    .map((c) => PopupMenuItem(
                          value: c,
                          height: 36,
                          child: Text(c,
                              style: GoogleFonts.poppins(fontSize: 12)),
                        ))
                    .toList(),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          e.groundTruth,
                          style: GoogleFonts.poppins(
                              fontSize: 11, color: AppColors.textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down, size: 14,
                          color: Colors.grey),
                    ],
                  ),
                ),
              ),
              // Inspect button — only after processing
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: e.isProcessed
                    ? InkWell(
                        onTap: () => _showInspector(e),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.image_search_outlined,
                            size: 16,
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          );
        }),
      ],
    );
  }

  // ---- table helpers -------------------------------------------------------

  TableRow _tableHeaderRow(List<String> headers) {
    return TableRow(
      decoration: const BoxDecoration(color: AppColors.primary),
      children: headers
          .map((h) => Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                child: Text(
                  h,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ))
          .toList(),
    );
  }

  Widget _tableCell(String text, {TextStyle? style}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      child: Text(
        text,
        style: style ??
            GoogleFonts.poppins(
                fontSize: 12, color: AppColors.textPrimary),
      ),
    );
  }

  Widget _tableCellColored(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _cmCell(String text,
      {bool bold = false, Color? color, Color? background}) {
    return Container(
      color: background,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      alignment: Alignment.center,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GoogleFonts.poppins(
          fontSize: 10,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          color: color ?? AppColors.textPrimary,
        ),
      ),
    );
  }

  Color _accuracyColor(double acc) {
    if (acc >= 0.8) return AppColors.accent;
    if (acc >= 0.6) return Colors.orange;
    return AppColors.error;
  }
}

// ---------------------------------------------------------------------------
// Helper classes
// ---------------------------------------------------------------------------
class _CatStats {
  int total = 0;
  int correct = 0;
  double confSum = 0;
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;
  final Color color;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            subtitle,
            style: GoogleFonts.poppins(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
