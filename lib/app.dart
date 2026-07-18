import 'package:flutter/material.dart';

import 'features/auth/data/auth_repository.dart';
import 'features/auth/presentation/auth_gate.dart';

class EcoTraceApp extends StatelessWidget {
  const EcoTraceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EcoTrace',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF167D57),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: AuthGate(repository: AuthRepository()),
    );
  }
}
