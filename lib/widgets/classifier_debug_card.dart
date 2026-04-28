import 'package:flutter/material.dart';

/// Shows all 6 classifier probabilities as labelled bars.
/// Self-contained — delete this file and its import to remove entirely.
class ClassifierDebugCard extends StatelessWidget {
  final Map<String, double> scores;

  const ClassifierDebugCard({super.key, required this.scores});

  @override
  Widget build(BuildContext context) {
    // Already sorted descending from classifyAll()
    final entries = scores.entries.toList();
    final topKey = entries.first.key;

    return Card(
      color: Colors.grey.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.science_outlined, size: 15, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  'Classifier Debug — All 6 Scores',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...entries.map((e) => _bar(e.key, e.value, e.key == topKey)),
          ],
        ),
      ),
    );
  }

  Widget _bar(String category, double score, bool isTop) {
    final color = isTop ? Colors.indigo.shade600 : Colors.grey.shade400;
    final textColor = isTop ? Colors.indigo.shade700 : Colors.grey.shade600;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              category,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isTop ? FontWeight.w700 : FontWeight.normal,
                color: textColor,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: score,
                backgroundColor: Colors.grey.shade200,
                color: color,
                minHeight: 11,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            child: Text(
              '${(score * 100).toStringAsFixed(1)}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isTop ? FontWeight.w700 : FontWeight.normal,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
