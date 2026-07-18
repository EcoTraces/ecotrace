import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _connectToFirebaseEmulators();
  runApp(const EcoTraceApp());
}

Future<void> _connectToFirebaseEmulators() async {
  const enabled = bool.fromEnvironment('USE_FIREBASE_EMULATORS');
  if (!enabled) return;

  const configuredHost = String.fromEnvironment('FIREBASE_EMULATOR_HOST');
  final host = configuredHost.isNotEmpty
      ? configuredHost
      : (!kIsWeb && defaultTargetPlatform == TargetPlatform.android
            ? '10.0.2.2'
            : '127.0.0.1');

  await FirebaseAuth.instance.useAuthEmulator(host, 9099);
  FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
  FirebaseStorage.instance.useStorageEmulator(host, 9199);
}
