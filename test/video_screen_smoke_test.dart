import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:capfiscal_app/screens/video_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('VideoScreen renders empty state', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'uid', email: 'user@example.com'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: VideoScreen(
          firestore: firestore,
          auth: auth,
          videosStream: firestore.collection('videos').snapshots(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('VIDEOS'), findsOneWidget);
  });
}
