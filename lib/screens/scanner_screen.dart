import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../ocr/ocr_engine.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  late OcrEngine _engine;
  final _picker = ImagePicker();
  final _labelController = TextEditingController();

  File? _scannedImage;
  OcrResult? _result;
  bool _isProcessing = false;
  bool _isEngineReady = false;
  int _trainedSamples = 0;

  // ─── Init ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initEngine();
  }

  Future<void> _initEngine() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final storePath = '${dir.path}/ocr_templates.json';

      _engine = OcrEngine(k: 3, storePath: storePath);
      final loaded = await _engine.loadSavedTemplates();

      setState(() {
        _trainedSamples = loaded;
        _isEngineReady = true;
      });

      if (loaded > 0) {
        _showSnack('Loaded $loaded saved templates');
      }
    } catch (e) {
      setState(() {
        _isEngineReady = true;
        _trainedSamples = 0;
      });
      _showSnack('Engine init error: $e');
    }
  }

  // ─── Training ────────────────────────────────────────────────────────────

  Future<void> _trainSample() async {
    final label = _labelController.text.trim();
    if (label.isEmpty) {
      _showSnack('Enter the character label first');
      return;
    }

    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() => _isProcessing = true);
    await _engine.trainWithSample(File(picked.path), label);
    setState(() {
      _isProcessing = false;
      _trainedSamples++;
    });
    _showSnack('Trained "$label" — $_trainedSamples samples total');
  }

  // ─── Reset Training ───────────────────────────────────────────────────────

  Future<void> _resetTraining() async {
    await _engine.clearTemplates();
    setState(() => _trainedSamples = 0);
    _showSnack('All training data cleared');
  }

  // ─── Scanning ────────────────────────────────────────────────────────────

  Future<void> _scan(ImageSource source) async {
    if (!_engine.isReady) {
      _showSnack('Train the engine with at least a few characters first');
      return;
    }

    // Request permission first
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
      _scannedImage = File(picked.path);
      _isProcessing = true;
      _result = null;
    });

    final result = await _engine.recognize(_scannedImage!);
    setState(() {
      _result = result;
      _isProcessing = false;
    });
  }

  // ─── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_isEngineReady) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Loading OCR engine...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt OCR (Traditional)'),
        actions: [
          if (_trainedSamples > 0)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Reset training data',
              onPressed: _resetTraining,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Training Section ──────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Step 1: Train',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Add single-character images and label them. More samples = better accuracy.',
                      style: TextStyle(
                          color: Colors.grey.shade600, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _labelController,
                      maxLength: 1,
                      decoration: const InputDecoration(
                        labelText: 'Character label (e.g. A, 3, \$)',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add_photo_alternate),
                      label: Text(
                          'Add Training Sample ($_trainedSamples added)'),
                      onPressed: _isProcessing ? null : _trainSample,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Scanning Section ──────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Step 2: Scan Receipt',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Camera'),
                            onPressed: _isProcessing
                                ? null
                                : () => _scan(ImageSource.camera),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.photo_library),
                            label: const Text('Gallery'),
                            onPressed: _isProcessing
                                ? null
                                : () => _scan(ImageSource.gallery),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Image Preview ─────────────────────────────────────────────
            if (_scannedImage != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(_scannedImage!,
                    height: 200, fit: BoxFit.cover),
              ),

            if (_isProcessing) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Center(child: Text('Processing...')),
            ],

            // ── Result ────────────────────────────────────────────────────
            if (_result != null && !_isProcessing) ...[
              const SizedBox(height: 16),
              if (!_result!.success)
                Text('Error: ${_result!.error}',
                    style: const TextStyle(color: Colors.red))
              else
                Card(
                  color: Colors.grey.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Recognized Text',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 18),
                              onPressed: () {},
                            ),
                          ],
                        ),
                        const Divider(),
                        SelectableText(
                          _result!.text.isEmpty
                              ? '(no text detected)'
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