import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_storage_mocks/firebase_storage_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:capfiscal_app/screens/user_profile_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('UserProfileScreen shows profile header', (tester) async {
    const uid = 'uid';
    final firestore = FakeFirebaseFirestore();
    final storage = MockFirebaseStorage();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: uid, email: 'user@example.com'),
    );

    await firestore.collection('users').doc(uid).set({
      'name': 'Usuario Demo',
      'email': 'user@example.com',
      'city': 'CDMX',
      'createdAt': DateTime.now().toUtc(),
      'subscription': {
        'status': 'active',
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        home: UserProfileScreen(
          auth: auth,
          firestore: firestore,
          storage: storage,
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('PERFIL'), findsOneWidget);
  });
}
