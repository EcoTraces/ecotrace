import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'firebase_options.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _EcoTraceBootstrap());
}

class _EcoTraceBootstrap extends StatefulWidget {
  const _EcoTraceBootstrap();

  @override
  State<_EcoTraceBootstrap> createState() => _EcoTraceBootstrapState();
}

class _EcoTraceBootstrapState extends State<_EcoTraceBootstrap> {
  bool _ready = false;
  bool _takingLonger = false;
  Object? _error;
  Timer? _slowTimer;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    _slowTimer?.cancel();
    setState(() {
      _ready = false;
      _takingLonger = false;
      _error = null;
    });
    _slowTimer = Timer(const Duration(seconds: 15), () {
      if (mounted) setState(() => _takingLonger = true);
    });
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      await _connectToFirebaseEmulators();
      if (mounted) setState(() => _ready = true);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      _slowTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return const EcoTraceApp();
    return MaterialApp(
      title: 'EcoTrace',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF167D57)),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5EE),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Image.asset(
                        'assets/icons/ecotrace_app_icon.png',
                        height: 72,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'EcoTrace',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 20),
                    if (_error == null) ...[
                      const CircularProgressIndicator(),
                      const SizedBox(height: 18),
                      Text(
                        _takingLonger
                            ? 'Still connecting to Firebase. A slow or restricted network can make the first web launch take longer.'
                            : 'Connecting securely…',
                        textAlign: TextAlign.center,
                      ),
                    ] else ...[
                      Icon(
                        Icons.cloud_off_outlined,
                        size: 42,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'EcoTrace could not finish starting.',
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        _error.toString(),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _initialize,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
