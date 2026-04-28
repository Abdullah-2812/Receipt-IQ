import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../utils/constants.dart';
import '../ocr/ocr_engine.dart';
import '../models/receipt_model.dart';
import '../services/database_service.dart';
import '../services/fallback_service.dart';
import '../services/sync_service.dart';
import '../services/receipt_classifier_service.dart';
import '../services/receipt_parser_service.dart';
import '../widgets/classifier_debug_card.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final _picker = ImagePicker();
  late OcrEngine _engine;
  late final Future<void> _engineFuture;
  late ReceiptClassifierService _classifier;
  late final Future<void> _classifierFuture;
  final _parser = ReceiptParserService();

  File? _selectedImage;
  OcrResult? _result;
  ClassificationResult? _classification;
  ParsedReceipt? _parsedReceipt;
  bool _isProcessing = false;
  bool _isEngineReady = false;
  bool _isClassifierReady = false;
  bool _isSaving = false;
  bool _saved = false;
  // debug only — set to null to clear, never used in release builds
  Map<String, double>? _classifierScores;

  @override
  void initState() {
    super.initState();
    _engineFuture = _initEngine();
    _classifierFuture = _initClassifier();
  }

  Future<void> _initClassifier() async {
    _classifier = ReceiptClassifierService();
    await _classifier.initialize();
    if (mounted) setState(() => _isClassifierReady = true);
  }

  /// Always assigns [_engine] so [_pickImage] never hits a [LateInitializationError],
  /// and never leaves [_isProcessing] stuck after a failed recognition.
  Future<void> _initEngine() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final storePath = '${dir.path}/ocr_templates.json';
      _engine = OcrEngine(k: 3, storePath: storePath);
      await _engine.loadSavedTemplates();
    } catch (_) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        final storePath = '${dir.path}/ocr_templates.json';
        _engine = OcrEngine(k: 3, storePath: storePath);
        await _engine.loadSavedTemplates();
      } catch (_) {
        final tmp = Directory.systemTemp.createTempSync('receipt_iq_ocr');
        _engine = OcrEngine(k: 3, storePath: '${tmp.path}/ocr_templates.json');
        await _engine.loadSavedTemplates();
      }
    }
    if (mounted) {
      setState(() => _isEngineReady = true);
    }
  }

  Future<void> _saveReceipt() async {
    if (_parsedReceipt == null) return;
    setState(() => _isSaving = true);

    final parsed = _parsedReceipt!;
    final category = ClassifierCategoryMap.labelToCategory[
            _classification?.category ?? ''] ??
        'Other';
    final total = parsed.total ??
        parsed.categoryData['amount'] as double? ??
        0.0;
    final id = 'receipt_${DateTime.now().millisecondsSinceEpoch}';

    final receipt = Receipt(
      id: id,
      merchantName: parsed.vendorName?.isNotEmpty == true
          ? parsed.vendorName!
          : 'Unknown Merchant',
      date: parsed.receiptDate ?? DateTime.now(),
      totalAmount: total,
      category: category,
      imagePath: _selectedImage?.path,
      items: parsed.items
          .map((i) => ReceiptItem(
                name: i.name,
                quantity: i.quantity,
                price: i.unitPrice,
                totalPrice: i.itemTotal,
              ))
          .toList(),
      createdAt: DateTime.now(),
      rawOcrText: _result?.text,
      vendorAddress: parsed.vendorAddress,
      receiptTime: parsed.receiptTime,
      subtotal: parsed.subtotal,
      tax: parsed.tax,
      fbrPosFee: parsed.fbrPosFee,
      discount: parsed.discount,
      cashPaid: parsed.cashPaid,
      changeDue: parsed.changeDue,
      paymentMethod: parsed.paymentMethod,
      fbrInvoiceId: parsed.fbrInvoiceId,
      ntn: parsed.ntn,
      invoiceNumber: parsed.invoiceNumber,
    );

    await DatabaseService.instance.insertReceipt(receipt);
    SyncService.instance.pushPending();

    if (mounted) {
      setState(() { _isSaving = false; _saved = true; });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receipt saved successfully')),
      );
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    await _engineFuture;

    // Request permission
    PermissionStatus status;
    if (source == ImageSource.camera) {
      status = await Permission.camera.request();
    } else {
      if (await Permission.photos.request().isGranted) {
        status = PermissionStatus.granted;
      } else {
        status = await Permission.storage.request();
      }
    }

    if (!status.isGranted) {
      _showSnack('Permission denied — please allow access in phone settings');
      return;
    }

    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 90,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (picked == null) return;

    // Camera always produces JPEG; gallery may return other formats
    if (source == ImageSource.gallery) {
      final ext = picked.path.split('.').last.toLowerCase();
      const allowed = {'jpg', 'jpeg', 'png'};
      if (!allowed.contains(ext)) {
        _showSnack('Unsupported file type ".$ext". Please upload a JPG or PNG image.');
        return;
      }
    }

    setState(() {
      _selectedImage = File(picked.path);
      _isProcessing = true;
      _result = null;
      _classification = null;
      _parsedReceipt = null;
      _classifierScores = null;
      _saved = false;
    });

    // ── Step 1: ML Kit (Latin); fall back to k-NN if empty or error ─────
    String? ocrText;
    OcrResult ocrResult;

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFile(_selectedImage!);
      final recognized = await recognizer.processImage(inputImage);
      debugPrint('ML Kit result: ${recognized.text}');
      final text = recognized.text.trim();
      if (text.isNotEmpty) {
        ocrText = recognized.text;
        ocrResult = OcrResult(
          text: recognized.text,
          lines: recognized.text.split('\n'),
          success: true,
        );
      } else {
        ocrResult = OcrResult(text: '', lines: [], success: true);
      }
    } catch (e) {
      debugPrint('ML Kit error: $e');
      ocrResult = OcrResult(text: '', lines: [], success: false);
    } finally {
      await recognizer.close();
    }

    // ── Step 2: Fallback to custom k-NN pipeline ──────────────────────────
    if (ocrText == null || ocrText.isEmpty) {
      try {
        ocrResult = await _engine.recognize(_selectedImage!);
        if (ocrResult.success && ocrResult.text.trim().isNotEmpty) {
          ocrText = ocrResult.text;
        }
      } catch (e) {
        ocrResult = OcrResult(
          text: '',
          lines: [],
          success: false,
          error: e.toString(),
        );
      }
    }

    // ── Step 3: Classify + Parse ──────────────────────────────────────────
    ClassificationResult? classification;
    ParsedReceipt? parsedReceipt;

    if (ocrText != null && ocrText.isNotEmpty) {
      try {
        await _classifierFuture;
        final allScores = _classifier.classifyAll(ocrText);
        if (kDebugMode) _classifierScores = allScores;
        final top = allScores.entries.first;
        classification = ClassificationResult(
          category: top.key,
          confidence: top.value,
          useFallback: top.value < ReceiptClassifierService.confidenceThreshold,
        );
        debugPrint(
          'Classifier → category: ${classification.category}  '
          'confidence: ${(classification.confidence * 100).toStringAsFixed(1)}%  '
          'useFallback: ${classification.useFallback}',
        );
        parsedReceipt = _parser.parse(ocrText, classification.category);
        if (parsedReceipt.extractionFailed) {
          debugPrint('Local parser failed — trying Gemini fallback');
          parsedReceipt = await GeminiFallbackService().parse(ocrText, classification.category);
        }
      } catch (e) {
        debugPrint('Classify/parse error: $e');
      }
    }

    if (!mounted) return;
    setState(() {
      _isProcessing = false;
      _result = ocrResult;
      _classification = classification;
      _parsedReceipt = parsedReceipt;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Bottom nav + (when visible) center FAB sit over the body; keep tappable targets clear.
    final bottomInset = MediaQuery.paddingOf(context).bottom +
        kBottomNavigationBarHeight +
        24;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          Text(
            'Upload Receipt',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Scan or upload a receipt image to extract details',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 32),

          if (!_isEngineReady) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(
              'Preparing scanner…',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Upload Zone ──────────────────────────────────────────────────
          _buildUploadZone(context),
          const SizedBox(height: 24),

          // ── Camera Button ────────────────────────────────────────────────
          OutlinedButton.icon(
            onPressed: (_isProcessing || !_isEngineReady)
                ? null
                : () => _pickImage(ImageSource.camera),
            icon: const Icon(Icons.camera_alt),
            label: const Text('Open Camera'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Gallery Button ───────────────────────────────────────────────
          FilledButton.icon(
            onPressed: (_isProcessing || !_isEngineReady)
                ? null
                : () => _pickImage(ImageSource.gallery),
            icon: const Icon(Icons.photo_library),
            label: const Text('Choose from Gallery'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.surface,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          // ── Processing Indicator ─────────────────────────────────────────
          if (_isProcessing) ...[
            const SizedBox(height: 24),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Center(child: Text('Reading receipt...')),
          ],

          // ── Result ───────────────────────────────────────────────────────
          if (_result != null && !_isProcessing) ...[
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Extracted Text',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const Divider(height: 16),
                    if (!_result!.success)
                      Text(
                        'Error: ${_result!.error}',
                        style: const TextStyle(color: Colors.red),
                      )
                    else
                      SelectableText(
                        _result!.text.isEmpty
                            ? '(no text detected — try training the engine first)'
                            : _result!.text,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 13),
                      ),
                  ],
                ),
              ),
            ),
          ],

          // ── Classifier Debug (debug builds only) ─────────────────────────
          if (kDebugMode && _classifierScores != null && !_isProcessing) ...[
            const SizedBox(height: 16),
            ClassifierDebugCard(scores: _classifierScores!),
          ],

          // ── Parsed Receipt ────────────────────────────────────────────────
          if (_parsedReceipt != null && !_isProcessing) ...[
            const SizedBox(height: 16),
            Card(
              color: _parsedReceipt!.extractionFailed
                  ? const Color(0xFFFFF3E0)
                  : const Color(0xFFE8F5E9),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _parsedReceipt!.extractionFailed
                              ? Icons.warning_amber_rounded
                              : Icons.check_circle_outline,
                          color: _parsedReceipt!.extractionFailed
                              ? Colors.orange
                              : Colors.green,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Parsed Receipt',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    if (_classification != null)
                      _infoRow(
                        'Category',
                        '${_classification!.category}  '
                            '(${(_classification!.confidence * 100).toStringAsFixed(1)}%)',
                      ),
                    if (_parsedReceipt!.vendorName != null)
                      _infoRow('Merchant', _parsedReceipt!.vendorName!),
                    if (_parsedReceipt!.vendorAddress != null)
                      _infoRow('Address', _parsedReceipt!.vendorAddress!),
                    if (_parsedReceipt!.receiptDate != null)
                      _infoRow(
                        'Date',
                        '${_parsedReceipt!.receiptDate!.day}/'
                            '${_parsedReceipt!.receiptDate!.month}/'
                            '${_parsedReceipt!.receiptDate!.year}',
                      ),
                    if (_parsedReceipt!.receiptTime != null)
                      _infoRow('Time', _parsedReceipt!.receiptTime!),
                    if (_parsedReceipt!.invoiceNumber != null)
                      _infoRow('Invoice #', _parsedReceipt!.invoiceNumber!),
                    if (_parsedReceipt!.paymentMethod != null)
                      _infoRow('Payment', _parsedReceipt!.paymentMethod!),
                    if (_parsedReceipt!.subtotal != null)
                      _infoRow('Subtotal',
                          'Rs. ${_parsedReceipt!.subtotal!.toStringAsFixed(2)}'),
                    if (_parsedReceipt!.tax != null)
                      _infoRow('Tax',
                          'Rs. ${_parsedReceipt!.tax!.toStringAsFixed(2)}'),
                    if (_parsedReceipt!.fbrPosFee != null)
                      _infoRow('FBR POS Fee',
                          'Rs. ${_parsedReceipt!.fbrPosFee!.toStringAsFixed(2)}'),
                    if (_parsedReceipt!.discount != null)
                      _infoRow('Discount',
                          'Rs. ${_parsedReceipt!.discount!.toStringAsFixed(2)}'),
                    if (_parsedReceipt!.total != null)
                      _infoRow(
                        'Total',
                        'Rs. ${_parsedReceipt!.total!.toStringAsFixed(2)}',
                        bold: true,
                      ),
                    if (_parsedReceipt!.cashPaid != null)
                      _infoRow('Cash Paid',
                          'Rs. ${_parsedReceipt!.cashPaid!.toStringAsFixed(2)}'),
                    if (_parsedReceipt!.changeDue != null)
                      _infoRow('Change Due',
                          'Rs. ${_parsedReceipt!.changeDue!.toStringAsFixed(2)}'),
                    if (_parsedReceipt!.ntn != null)
                      _infoRow('NTN', _parsedReceipt!.ntn!),
                    if (_parsedReceipt!.fbrInvoiceId != null)
                      _infoRow('FBR Invoice', _parsedReceipt!.fbrInvoiceId!),
                    if (_parsedReceipt!.items.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Items (${_parsedReceipt!.items.length})',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      ..._parsedReceipt!.items.map(
                        (item) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${item.quantity}x ${item.name}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              Text(
                                'Rs. ${item.itemTotal.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (_parsedReceipt!.extractionFailed)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Extraction incomplete — some fields could not be parsed.',
                          style: TextStyle(
                              fontSize: 12, color: Colors.orange.shade800),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _saved
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.check_circle, color: Colors.green, size: 20),
                      SizedBox(width: 6),
                      Text('Saved to receipts',
                          style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
                    ],
                  )
                : FilledButton.icon(
                    onPressed: _isSaving ? null : _saveReceipt,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_isSaving ? 'Saving…' : 'Save Receipt'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
          ],
        ],
      ),
    );
  }

  Widget _buildUploadZone(BuildContext context) {
    return GestureDetector(
      onTap: (_isProcessing || !_isEngineReady)
          ? null
          : () => _pickImage(ImageSource.gallery),
      child: Container(
        height: 220,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primaryLight,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: _selectedImage != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(_selectedImage!, fit: BoxFit.cover),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.cloud_upload_outlined,
                    size: 56,
                    color: AppColors.primary.withOpacity(0.7),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Tap to scan or upload',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Supported: JPG, PNG',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    if (_isClassifierReady) _classifier.dispose();
    super.dispose();
  }
}