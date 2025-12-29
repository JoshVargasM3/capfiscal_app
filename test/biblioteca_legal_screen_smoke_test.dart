import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:capfiscal_app/screens/biblioteca_legal_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('BibliotecaLegalScreen loads without crashing', (tester) async {
    final storage = MockFirebaseStorage();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'uid', email: 'user@example.com'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BibliotecaLegalScreen(storage: storage, auth: auth),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(BibliotecaLegalScreen), findsOneWidget);
  });
}
