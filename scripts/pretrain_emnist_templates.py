#!/usr/bin/env python3
"""
Build ocr_templates.json for the Receipt IQ k-NN OCR pipeline.

Mirrors Dart preprocessing: grayscale (ITU-R), Otsu binarize, skew correction,
3x3 median, morphological open (k=2), largest CC, then 16x16 + H/V profiles
(288 floats), matching lib/ocr/ without importing Dart.
"""

from __future__ import annotations

import argparse
import json
import math
import random
import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

# try:
#     from emnist import extract_training_samples
# except ImportError:
#     print("Install dependencies: pip install -r scripts/requirements.txt", file=sys.stderr)
#     raise

import urllib.request, gzip, struct

_EMNIST_BASE = "https://ossci-datasets.s3.amazonaws.com/mnist"
_EMNIST_CACHE = Path(".emnist_cache")

def _download_file(url: str, dest: Path) -> None:
    if dest.exists():
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    print(f"Downloading {dest.name}...")
    urllib.request.urlretrieve(url, dest)

def _read_images(path: Path) -> np.ndarray:
    with gzip.open(path, "rb") as f:
        _, n, rows, cols = struct.unpack(">IIII", f.read(16))
        return np.frombuffer(f.read(), dtype=np.uint8).reshape(n, rows, cols)

def _read_labels(path: Path) -> np.ndarray:
    with gzip.open(path, "rb") as f:
        _, n = struct.unpack(">II", f.read(8))
        return np.frombuffer(f.read(), dtype=np.uint8)

def extract_training_samples(dataset: str):
    img_path = _EMNIST_CACHE / "train-images.gz"
    lbl_path = _EMNIST_CACHE / "train-labels.gz"
    _download_file(f"{_EMNIST_BASE}/train-images-idx3-ubyte.gz", img_path)
    _download_file(f"{_EMNIST_BASE}/train-labels-idx1-ubyte.gz", lbl_path)
    images = _read_images(img_path)
    labels = _read_labels(lbl_path)
    return images, labels

GRID = 16
FEATURE_DIM = GRID * GRID + GRID + GRID  # 288


@dataclass
class BBox:
    x: int
    y: int
    width: int
    height: int

    @property
    def area(self) -> int:
        return self.width * self.height

    @property
    def right(self) -> int:
        return self.x + self.width

    @property
    def bottom(self) -> int:
        return self.y + self.height


def grayscale_itu_r(rgb: np.ndarray) -> np.ndarray:
    """RGB uint8 HxWx3 -> gray uint8 HxW."""
    r = rgb[..., 0].astype(np.float64)
    g = rgb[..., 1].astype(np.float64)
    b = rgb[..., 2].astype(np.float64)
    gray = (0.299 * r + 0.587 * g + 0.114 * b).round().clip(0, 255).astype(np.uint8)
    return gray


def to_grayscale(img: np.ndarray) -> np.ndarray:
    if img.ndim == 2:
        return img.astype(np.uint8)
    if img.ndim == 3 and img.shape[2] >= 3:
        return grayscale_itu_r(img[..., :3])
    raise ValueError(f"Unexpected shape {img.shape}")


def otsu_threshold(gray: np.ndarray) -> int:
    hist = np.bincount(gray.ravel(), minlength=256)
    total = gray.size
    sum_all = float(np.dot(np.arange(256), hist))
    sum_b = 0.0
    w_b = 0
    max_var = 0.0
    threshold = 128
    for t in range(256):
        w_b += hist[t]
        if w_b == 0:
            continue
        w_f = total - w_b
        if w_f == 0:
            break
        sum_b += t * hist[t]
        m_b = sum_b / w_b
        m_f = (sum_all - sum_b) / w_f
        var = w_b * w_f * (m_b - m_f) ** 2
        if var > max_var:
            max_var = var
            threshold = t
    return int(threshold)


def binarize(gray: np.ndarray) -> np.ndarray:
    t = otsu_threshold(gray)
    out = np.where(gray < t, 0, 255).astype(np.uint8)
    return out


def ensure_ink_dark(binary: np.ndarray) -> np.ndarray:
    """Foreground for CC is r<=128 (black ink). Flip if digit/ink is mostly white."""
    ink = binary <= 128
    if ink.mean() > 0.5:
        return 255 - binary
    return binary


def sobel_edges(binary: np.ndarray) -> np.ndarray:
    h, w = binary.shape
    edges = np.zeros((h, w), dtype=bool)
    kernel_x = np.array([[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]], dtype=np.float64)
    kernel_y = np.array([[-1, -2, -1], [0, 0, 0], [1, 2, 1]], dtype=np.float64)
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            gx = gy = 0.0
            for ky in range(-1, 2):
                for kx in range(-1, 2):
                    val = (255.0 - float(binary[y + ky, x + kx])) / 255.0
                    gx += val * kernel_x[ky + 1, kx + 1]
                    gy += val * kernel_y[ky + 1, kx + 1]
            mag = math.sqrt(gx * gx + gy * gy)
            edges[y, x] = mag > 0.3
    return edges


def detect_skew_angle(binary: np.ndarray) -> float:
    w, h = binary.shape[1], binary.shape[0]
    step = 3
    min_angle = -45.0
    max_angle = 45.0
    angle_step = 0.5
    num_angles = int((max_angle - min_angle) / angle_step) + 1
    max_r = int(math.ceil(math.sqrt(w * w + h * h)))
    num_r = max_r * 2 + 1
    accumulator = np.zeros((num_angles, num_r), dtype=np.int32)
    cos_t = []
    sin_t = []
    for ai in range(num_angles):
        theta = (min_angle + ai * angle_step) * math.pi / 180.0
        cos_t.append(math.cos(theta))
        sin_t.append(math.sin(theta))
    edges = sobel_edges(binary)
    for y in range(0, h, step):
        for x in range(0, w, step):
            if not edges[y, x]:
                continue
            for ai in range(num_angles):
                r = x * cos_t[ai] + y * sin_t[ai]
                ri = int(round(r + max_r))
                if 0 <= ri < num_r:
                    accumulator[ai, ri] += 1
    best_angle_idx = 0
    best_votes = 0
    for ai in range(num_angles):
        total = int(accumulator[ai].sum())
        if total > best_votes:
            best_votes = total
            best_angle_idx = ai
    skew_angle = min_angle + best_angle_idx * angle_step
    if skew_angle > 45:
        skew_angle -= 90
    if skew_angle < -45:
        skew_angle += 90
    return float(skew_angle)


def rotate_clear_corners(img: np.ndarray, angle_deg: float) -> np.ndarray:
    """Dart copyRotate then clear black in corner margin."""
    rotated = ndimage.rotate(
        img, angle_deg, reshape=True, order=1, cval=255, mode="constant"
    )
    rh, rw = rotated.shape
    margin = max(1, int(min(rw, rh) * 0.05))
    out = rotated.copy()
    for y in range(rh):
        for x in range(rw):
            if int(out[y, x]) == 0 and (
                x < margin or x > rw - margin or y < margin or y > rh - margin
            ):
                out[y, x] = 255
    return out.astype(np.uint8)


def skew_correct(binary: np.ndarray) -> np.ndarray:
    angle = detect_skew_angle(binary)
    if abs(angle) < 0.5:
        return binary
    # Dart: copyRotate(src, angle: -angleDeg)
    return rotate_clear_corners(binary, -angle)


def median_filter_3x3(binary: np.ndarray) -> np.ndarray:
    h, w = binary.shape
    out = np.zeros_like(binary)
    for y in range(h):
        for x in range(w):
            neigh = []
            for dy in range(-1, 2):
                for dx in range(-1, 2):
                    ny = min(max(y + dy, 0), h - 1)
                    nx = min(max(x + dx, 0), w - 1)
                    neigh.append(int(binary[ny, nx]))
            neigh.sort()
            m = neigh[4]
            out[y, x] = m
    return out.astype(np.uint8)


def morph_open(binary: np.ndarray, k: int = 2) -> np.ndarray:
    def erode(src: np.ndarray) -> np.ndarray:
        hh, ww = src.shape
        o = np.zeros_like(src)
        for y in range(hh):
            for x in range(ww):
                min_v = 255
                for dy in range(-k, k + 1):
                    for dx in range(-k, k + 1):
                        ny = min(max(y + dy, 0), hh - 1)
                        nx = min(max(x + dx, 0), ww - 1)
                        v = int(src[ny, nx])
                        if v < min_v:
                            min_v = v
                o[y, x] = min_v
        return o

    def dilate(src: np.ndarray) -> np.ndarray:
        hh, ww = src.shape
        o = np.zeros_like(src)
        for y in range(hh):
            for x in range(ww):
                max_v = 0
                for dy in range(-k, k + 1):
                    for dx in range(-k, k + 1):
                        ny = min(max(y + dy, 0), hh - 1)
                        nx = min(max(x + dx, 0), ww - 1)
                        v = int(src[ny, nx])
                        if v > max_v:
                            max_v = v
                o[y, x] = max_v
        return o

    return dilate(erode(binary))


def preprocess_pipeline(gray_hw: np.ndarray) -> np.ndarray:
    """Full chain matching ocr_engine._preprocess (without 1500 resize for small images)."""
    h, w = gray_hw.shape
    if w > 1500:
        pil = Image.fromarray(gray_hw, mode="L")
        nh = int(h * 1500 / w)
        pil = pil.resize((1500, nh), Image.Resampling.BILINEAR)
        gray_hw = np.array(pil)
    binary = binarize(gray_hw)
    binary = ensure_ink_dark(binary)
    binary = skew_correct(binary)
    binary = median_filter_3x3(binary)
    binary = morph_open(binary)
    return binary


def connected_components(
    binary: np.ndarray, min_area: int = 10, max_area: int = 50000
) -> list[BBox]:
    h, w = binary.shape
    labels = np.zeros(h * w, dtype=np.int32)
    parent: dict[int, int] = {}

    def find(x: int) -> int:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a: int, b: int) -> None:
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb

    next_label = 1
    for y in range(h):
        for x in range(w):
            if int(binary[y, x]) > 128:
                continue
            above = int(labels[(y - 1) * w + x]) if y > 0 else 0
            left = int(labels[y * w + (x - 1)]) if x > 0 else 0
            idx = y * w + x
            if above == 0 and left == 0:
                labels[idx] = next_label
                parent[next_label] = next_label
                next_label += 1
            elif above != 0 and left == 0:
                labels[idx] = above
            elif above == 0 and left != 0:
                labels[idx] = left
            else:
                labels[idx] = left
                union(above, left)

    boxes: dict[int, list[int]] = {}
    for y in range(h):
        for x in range(w):
            lbl = int(labels[y * w + x])
            if lbl == 0:
                continue
            root = find(lbl)
            b = boxes.setdefault(root, [10**9, 10**9, 0, 0])
            b[0] = min(b[0], x)
            b[1] = min(b[1], y)
            b[2] = max(b[2], x)
            b[3] = max(b[3], y)

    result: list[BBox] = []
    for _root, mm in boxes.items():
        min_x, min_y, max_x, max_y = mm
        bw = max_x - min_x + 1
        bh = max_y - min_y + 1
        area = bw * bh
        if min_area <= area <= max_area:
            result.append(BBox(min_x, min_y, bw, bh))
    result.sort(key=lambda b: b.area, reverse=True)
    return result


def crop_with_padding(binary: np.ndarray, box: BBox, padding: int = 2) -> np.ndarray:
    """Matches lib/ocr/3_recognition/feature_extractor.dart _cropWithPadding + copyCrop."""
    h, w = binary.shape
    x1 = int(np.clip(box.x - padding, 0, w - 1))
    y1 = int(np.clip(box.y - padding, 0, h - 1))
    x2 = int(np.clip(box.right + padding, 0, w - 1))
    y2 = int(np.clip(box.bottom + padding, 0, h - 1))
    cw = max(1, x2 - x1)
    ch = max(1, y2 - y1)
    return binary[y1 : y1 + ch, x1 : x1 + cw]


def resize_like_dart(pil_img: Image.Image) -> Image.Image:
    """Dart img.copyResize(..., Interpolation.average): BOX for downscale, else bilinear."""
    sw, sh = pil_img.size
    if sw >= GRID and sh >= GRID:
        return pil_img.resize((GRID, GRID), Image.Resampling.BOX)
    return pil_img.resize((GRID, GRID), Image.Resampling.BILINEAR)


def extract_features(binary: np.ndarray, box: BBox) -> list[float]:
    padded = crop_with_padding(binary, box, padding=2)
    pil = Image.fromarray(padded, mode="L")
    pil = resize_like_dart(pil)
    arr = np.array(pil).astype(np.float64)
    pixels = []
    for y in range(GRID):
        for x in range(GRID):
            lum = arr[y, x]
            pixels.append(1.0 if lum < 128 else 0.0)
    h_prof = []
    for y in range(GRID):
        s = sum(pixels[y * GRID + x] for x in range(GRID))
        h_prof.append(s / GRID)
    v_prof = []
    for x in range(GRID):
        s = sum(pixels[y * GRID + x] for y in range(GRID))
        v_prof.append(s / GRID)
    return pixels + h_prof + v_prof


def augment_raw(rng: random.Random, img: np.ndarray) -> np.ndarray:
    """Light geometric/noise before grayscale pipeline."""
    a = rng.uniform(-8.0, 8.0)
    z = rng.uniform(0.88, 1.12)
    work = img.astype(np.float64)
    work = ndimage.rotate(work, a, reshape=True, order=1, cval=255.0, mode="constant")
    if z != 1.0:
        h, w = work.shape
        nh, nw = max(5, int(h * z)), max(5, int(w * z))
        pil = Image.fromarray(work.clip(0, 255).astype(np.uint8), mode="L")
        pil = pil.resize((nw, nh), Image.Resampling.BILINEAR)
        work = np.array(pil)
    noise = rng.gauss(0, 8)
    work = np.clip(work + noise, 0, 255).astype(np.uint8)
    return work


def emnist_char(dataset: str, label: int) -> str:
    if dataset == "digits":
        return str(int(label))
    if dataset == "letters":
        # emnist 'letters': labels 1..26 -> A..Z
        v = int(label)
        if not 1 <= v <= 26:
            return "?"
        return chr(ord("A") + v - 1)
    raise ValueError(dataset)


def collect_emnist_samples(
    rng: random.Random,
    max_per_class: int,
    use_digits: bool,
    use_letters: bool,
) -> list[tuple[str, np.ndarray]]:
    """List of (char_label, raw_gray_hw uint8)."""
    out: list[tuple[str, np.ndarray]] = []
    if use_digits:
        images, labels = extract_training_samples("digits")
        by_class: dict[str, list[np.ndarray]] = {}
        for im, lb in zip(images, labels):
            ch = str(int(lb))
            by_class.setdefault(ch, []).append(im)
        for ch, arrs in by_class.items():
            rng.shuffle(arrs)
            for im in arrs[:max_per_class]:
                out.append((ch, im))
    if use_letters:
        images, labels = extract_training_samples("letters")
        by_class: dict[str, list[np.ndarray]] = {}
        for im, lb in zip(images, labels):
            ch = emnist_char("letters", lb)
            by_class.setdefault(ch, []).append(im)
        for ch, arrs in by_class.items():
            rng.shuffle(arrs)
            for im in arrs[:max_per_class]:
                out.append((ch, im))
    rng.shuffle(out)
    return out


def templates_for_image(
    char: str, gray: np.ndarray, rng: random.Random, synth: int
) -> list[dict]:
    variants = [gray]
    for _ in range(synth):
        variants.append(augment_raw(rng, gray))
    out: list[dict] = []
    for v in variants:
        g = to_grayscale(v) if v.ndim == 3 else v
        binary = preprocess_pipeline(g)
        boxes = connected_components(binary, min_area=10)
        if not boxes:
            continue
        feat = extract_features(binary, boxes[0])
        if len(feat) == FEATURE_DIM:
            out.append({"label": char, "features": feat})
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description="Pretrain k-NN templates from EMNIST + synthetic data")
    ap.add_argument(
        "--out",
        type=Path,
        default=Path("assets/ocr/ocr_templates.json"),
        help="Output JSON path (default: assets/ocr/ocr_templates.json)",
    )
    ap.add_argument("--max-per-class", type=int, default=12)
    ap.add_argument("--synthetic-per-base", type=int, default=2)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--no-digits", action="store_true")
    ap.add_argument("--no-letters", action="store_true")
    args = ap.parse_args()

    rng = random.Random(args.seed)
    samples = collect_emnist_samples(
        rng,
        args.max_per_class,
        use_digits=not args.no_digits,
        use_letters=not args.no_letters,
    )

    templates: list[dict] = []
    for char, gray in samples:
        templates.extend(
            templates_for_image(char, gray, rng, args.synthetic_per_base)
        )

    payload = {"version": 1, "count": len(templates), "templates": templates}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(payload), encoding="utf-8")
    print(f"Wrote {len(templates)} templates to {args.out.resolve()}")


if __name__ == "__main__":
    main()
