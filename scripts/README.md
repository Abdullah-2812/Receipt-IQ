# EMNIST + synthetic k-NN template pretraining

This script builds `ocr_templates.json` in the same format as the Flutter app’s
`TemplateStore` (version 1), using the same preprocessing and 288-D feature
layout as the Dart OCR pipeline (`GrayscaleConverter` → Otsu → skew → median →
morph open → largest connected component → 16×16 grid + projection profiles).

## Setup

```bash
cd scripts
python -m venv .venv
.venv\Scripts\activate   # Windows
pip install -r requirements.txt
```

## Generate templates

From the **repository root** (so `assets/ocr/` exists):

```bash
python scripts/pretrain_emnist_templates.py --out assets/ocr/ocr_templates.json
```

Useful options:

| Flag | Default | Meaning |
|------|---------|---------|
| `--max-per-class` | 12 | Max EMNIST samples per character class |
| `--synthetic-per-base` | 2 | Extra synthetic variants per base image (rotation/scale/noise) |
| `--digits` | on | Include EMNIST digits |
| `--letters` | on | Include EMNIST letters (A–Z) |
| `--seed` | 42 | RNG seed |

After generation, run `flutter pub get` (if needed) and rebuild the app. The
bundled asset is copied into app documents on **first launch** only (see
`lib/bootstrap/ocr_template_bootstrap.dart`).

## Notes

- Larger JSON improves coverage but increases app size and load time.
- Synthetic augmentations help k-NN generalize but stay in the same feature space
  as the runtime pipeline.
