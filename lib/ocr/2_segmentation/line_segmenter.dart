import 'package:image/image.dart' as img;
import 'connected_components.dart';
import 'character_segmenter.dart';

class TextLine {
  final int top, bottom;
  final List<BoundingBox> characters;

  TextLine({required this.top, required this.bottom, required this.characters});
  int get height => bottom - top;
}

class LineSegmenter {
  static List<TextLine> segment(img.Image binary, List<BoundingBox> charBoxes) {
    if (charBoxes.isEmpty) return [];

    final profile = List<int>.filled(binary.height, 0);
    for (int y = 0; y < binary.height; y++) {
      for (int x = 0; x < binary.width; x++) {
        if (binary.getPixel(x, y).r.toInt() < 128) profile[y]++;
      }
    }

    final lineSpans = <(int, int)>[];
    bool inLine = false;
    int lineStart = 0;
    const minGap = 3;

    for (int y = 0; y < binary.height; y++) {
      if (!inLine && profile[y] > 2) {
        inLine = true;
        lineStart = y;
      } else if (inLine && profile[y] <= 2) {
        int gapLen = 0;
        for (int gy = y; gy < binary.height && profile[gy] <= 2; gy++) {
          gapLen++;
        }
        if (gapLen >= minGap) {
          inLine = false;
          lineSpans.add((lineStart, y - 1));
        }
      }
    }
    if (inLine) lineSpans.add((lineStart, binary.height - 1));

    final lines = <TextLine>[];

    for (final span in lineSpans) {
      var chars = charBoxes.where((b) {
        final centerY = b.y + b.height / 2;
        return centerY >= span.$1 && centerY <= span.$2;
      }).toList();

      if (chars.isNotEmpty) {
        chars.sort((a, b) => a.x.compareTo(b.x));
        final line = TextLine(top: span.$1, bottom: span.$2, characters: chars);
        final refined = _refineWithVpp(binary, line);
        lines.add(refined);
      }
    }

    return lines;
  }

  static TextLine _refineWithVpp(img.Image binary, TextLine line) {
    if (line.characters.isEmpty) return line;

    final widths = line.characters.map((c) => c.width).toList()..sort();
    final medianWidth = widths[widths.length ~/ 2];

    final refined = <BoundingBox>[];

    for (final box in line.characters) {
      if (box.width > medianWidth * 2.5) {
        final subChars = CharacterSegmenter.segmentLine(
          binary,
          TextLine(top: box.y, bottom: box.bottom, characters: [box]),
        );
        if (subChars.length > 1) {
          refined.addAll(subChars);
          continue;
        }
      }
      refined.add(box);
    }

    refined.sort((a, b) => a.x.compareTo(b.x));
    return TextLine(top: line.top, bottom: line.bottom, characters: refined);
  }
}