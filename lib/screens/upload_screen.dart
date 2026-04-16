import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../utils/constants.dart';
import '../ocr/ocr_engine.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final _picker = ImagePicker();
  final _labelController = TextEditingController();
  late OcrEngine _engine;
  late final Future<void> _engineFuture;

  File? _selectedImage;
  OcrResult? _result;
  bool _isProcessing = false;
  bool _isEngineReady = false;
  int _templateCount = 0;

  @override
  void initState() {
    super.initState();
    _engineFuture = _initEngine();
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
      setState(() {
        _isEngineReady = true;
        _templateCount = _engine.templateCount;
      });
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

    setState(() {
      _selectedImage = File(picked.path);
      _isProcessing = true;
      _result = null;
    });

    // ── Step 1: ML Kit (Latin); fall back to k-NN if empty or error ─────
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFile(_selectedImage!);
      final recognized = await recognizer.processImage(inputImage);
      debugPrint('ML Kit result: ${recognized.text}');
      final text = recognized.text.trim();
      if (text.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _result = OcrResult(
            text: recognized.text,
            lines: recognized.text.split('\n'),
            success: true,
          );
          _isProcessing = false;
        });
        return;
      }
    } catch (e) {
      debugPrint('ML Kit error: $e');
      // Fall through to traditional OCR
    } finally {
      await recognizer.close();
    }

    // ── Step 2: Fallback to custom k-NN pipeline ──────────────────────────
    OcrResult result;
    try {
      result = await _engine.recognize(_selectedImage!);
    } catch (e) {
      result = OcrResult(
        text: '',
        lines: [],
        success: false,
        error: e.toString(),
      );
    }

    if (!mounted) return;
    setState(() {
      _isProcessing = false;
      _result = result;
    });
  }

  Future<void> _addTrainingSample() async {
    await _engineFuture;
    final label = _labelController.text.trim();
    if (label.isEmpty) {
      _showSnack('Type the character this image shows (one letter or digit)');
      return;
    }
    if (label.length != 1) {
      _showSnack('Use exactly one character per sample (e.g. A, 7, \$)');
      return;
    }

    PermissionStatus status;
    if (await Permission.photos.request().isGranted) {
      status = PermissionStatus.granted;
    } else {
      status = await Permission.storage.request();
    }
    if (!status.isGranted) {
      _showSnack('Permission denied — allow Photos in settings');
      return;
    }

    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (picked == null) return;

    final before = _engine.templateCount;
    setState(() => _isProcessing = true);
    try {
      await _engine.trainWithSample(File(picked.path), label);
    } catch (e) {
      if (mounted) _showSnack('Training failed: $e');
    }
    if (!mounted) return;
    final after = _engine.templateCount;
    setState(() {
      _isProcessing = false;
      _templateCount = after;
    });
    if (after > before) {
      _showSnack(
        'Saved “$label” — $after template(s). You can scan a receipt now.',
      );
    } else if (mounted) {
      _showSnack(
        'No new template saved — crop one clear character (high contrast) and try again',
      );
    }
  }

  Future<void> _clearTraining() async {
    await _engineFuture;
    await _engine.clearTemplates();
    if (!mounted) return;
    setState(() {
      _templateCount = 0;
      _result = null;
    });
    _showSnack('Training data cleared');
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

          if (_isEngineReady) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Train OCR (k-NN)',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (_templateCount > 0)
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 22),
                            tooltip: 'Clear all training',
                            onPressed:
                                _isProcessing ? null : _clearTraining,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'This engine matches shapes to labels you provide. Add one clear photo per character (cropped), then scan receipts that use the same font style.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _labelController,
                      maxLength: 1,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Character on next image',
                        hintText: 'e.g. A, 3',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed:
                          _isProcessing ? null : _addTrainingSample,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(
                        _templateCount == 0
                            ? 'Add training image from gallery'
                            : 'Add another ($_templateCount saved)',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
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

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }
}