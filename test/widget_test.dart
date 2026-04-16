import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:receipt_iq/main.dart';

void main() {
  testWidgets('App loads login UI', (WidgetTester tester) async {
    await tester.pumpWidget(const ReceiptIQApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Login'), findsWidgets);
  });
}
