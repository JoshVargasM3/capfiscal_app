import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:capfiscal_app/screens/home_screen.dart';

void main() {
  testWidgets('HomeScreen renders basic sections', (tester) async {
    final storage = MockFirebaseStorage();

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(storage: storage),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('PRÓXIMOS CURSOS'), findsOneWidget);
    expect(find.text('CATEGORÍAS'), findsOneWidget);
  });
}
