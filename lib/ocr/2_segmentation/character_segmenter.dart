import 'package:image/image.dart' as img;
import 'connected_components.dart';
import 'line_segmenter.dart';

class CharacterSegmenter {
  static List<BoundingBox> segmentLine(img.Image binary, TextLine line) {
    final lineHeight = line.bottom - line.top;
    if (lineHeight <= 0) return [];

    final lineCrop = img.copyCrop(
      binary,
      x: 0,
      y: line.top,
      width: binary.width,
      height: lineHeight,
    );

    final vProfile = _buildVerticalProfile(lineCrop);
    final spans = _findInkSpans(vProfile, lineCrop.width);

    final boxes = <BoundingBox>[];
    for (final span in spans) {
      final charX = span.$1;
      final charWidth = span.$2 - span.$1 + 1;
      final vertBounds = _findVerticalBounds(lineCrop, span.$1, span.$2);
      if (vertBounds == null) continue;

      boxes.add(BoundingBox(
        charX,
        line.top + vertBounds.$1,
        charWidth,
        vertBounds.$2 - vertBounds.$1 + 1,
      ));
    }

    return _mergeNarrowBoxes(boxes);
  }

  static List<int> _buildVerticalProfile(img.Image lineCrop) {
    final profile = List<int>.filled(lineCrop.width, 0);
    for (int x = 0; x < lineCrop.width; x++) {
      for (int y = 0; y < lineCrop.height; y++) {
        if (lineCrop.getPixel(x, y).r.toInt() < 128) {
          profile[x]++;
        }
      }
    }
    return profile;
  }

  static List<(int, int)> _findInkSpans(List<int> profile, int width) {
    final spans = <(int, int)>[];
    bool inChar = false;
    int spanStart = 0;
    const minInkInColumn = 1;

    for (int x = 0; x < width; x++) {
      final hasInk = profile[x] >= minInkInColumn;

      if (!inChar && hasInk) {
        inChar = true;
        spanStart = x;
      } else if (inChar && !hasInk) {
        final gapSize = _lookAheadGap(profile, x, width);
        if (gapSize >= 2) {
          inChar = false;
          spans.add((spanStart, x - 1));
        }
      }
    }

    if (inChar) spans.add((spanStart, width - 1));
    return spans;
  }

  static int _lookAheadGap(List<int> profile, int x, int width) {
    int gap = 0;
    for (int i = x; i < width && profile[i] < 1; i++) gap++;
    return gap;
  }

  static (int, int)? _findVerticalBounds(
      img.Image lineCrop, int xStart, int xEnd) {
    int top = lineCrop.height;
    int bottom = 0;

    for (int x = xStart; x <= xEnd && x < lineCrop.width; x++) {
      for (int y = 0; y < lineCrop.height; y++) {
        if (lineCrop.getPixel(x, y).r.toInt() < 128) {
          if (y < top) top = y;
          if (y > bottom) bottom = y;
        }
      }
    }

    if (top > bottom) return null;
    return (top, bottom);
  }

  static List<BoundingBox> _mergeNarrowBoxes(List<BoundingBox> boxes,
      {int minWidth = 3, int maxGap = 5}) {
    if (boxes.length <= 1) return boxes;

    final merged = <BoundingBox>[];
    int i = 0;

    while (i < boxes.length) {
      final current = boxes[i];

      if (i + 1 < boxes.length) {
        final next = boxes[i + 1];
        final gap = next.x - current.right;
        final isTooNarrow = current.width < minWidth || next.width < minWidth;

        if (isTooNarrow && gap <= maxGap) {
          final mergedX = current.x;
          final mergedY = current.y < next.y ? current.y : next.y;
          final mergedRight = next.right;
          final mergedBottom =
              current.bottom > next.bottom ? current.bottom : next.bottom;

          merged.add(BoundingBox(
            mergedX,
            mergedY,
            mergedRight - mergedX,
            mergedBottom - mergedY,
          ));
          i += 2;
          continue;
        }
      }

      merged.add(current);
      i++;
    }

    return merged;
  }
}