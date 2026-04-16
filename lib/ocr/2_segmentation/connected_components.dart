import 'package:image/image.dart' as img;

class BoundingBox {
  final int x, y, width, height;
  const BoundingBox(this.x, this.y, this.width, this.height);

  int get area => width * height;
  double get aspectRatio => width / height;
  int get right => x + width;
  int get bottom => y + height;
}

class ConnectedComponents {
  static List<BoundingBox> label(img.Image binary,
      {int minArea = 50, int maxArea = 50000}) {
    final w = binary.width;
    final h = binary.height;
    final labels = List<int>.filled(w * h, 0);
    final parent = <int, int>{};

    int find(int x) {
      while (parent[x] != x) {
        parent[x] = parent[parent[x]!]!;
        x = parent[x]!;
      }
      return x;
    }

    void union(int a, int b) {
      final ra = find(a), rb = find(b);
      if (ra != rb) parent[ra] = rb;
    }

    int nextLabel = 1;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (binary.getPixel(x, y).r.toInt() > 128) continue;

        final above = y > 0 ? labels[(y - 1) * w + x] : 0;
        final left = x > 0 ? labels[y * w + (x - 1)] : 0;

        if (above == 0 && left == 0) {
          labels[y * w + x] = nextLabel;
          parent[nextLabel] = nextLabel;
          nextLabel++;
        } else if (above != 0 && left == 0) {
          labels[y * w + x] = above;
        } else if (above == 0 && left != 0) {
          labels[y * w + x] = left;
        } else {
          labels[y * w + x] = left;
          union(above, left);
        }
      }
    }

    final bboxes = <int, _Box>{};
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final lbl = labels[y * w + x];
        if (lbl == 0) continue;
        final root = find(lbl);
        final box = bboxes.putIfAbsent(root, () => _Box());
        box.expand(x, y);
      }
    }

    return bboxes.values
        .map((b) => BoundingBox(
            b.minX, b.minY, b.maxX - b.minX + 1, b.maxY - b.minY + 1))
        .where((b) => b.area >= minArea && b.area <= maxArea)
        .toList();
  }
}

class _Box {
  int minX = 999999, minY = 999999, maxX = 0, maxY = 0;
  void expand(int x, int y) {
    if (x < minX) minX = x;
    if (y < minY) minY = y;
    if (x > maxX) maxX = x;
    if (y > maxY) maxY = y;
  }
}