import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/auth_repository.dart';
import '../domain/user_profile.dart';
import 'auth_screens.dart';
import '../../pickups/data/notification_service.dart';
import '../../workspace/presentation/role_workspace_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.repository});

  final AuthRepository repository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: repository.authStateChanges,
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        }
        final user = authSnapshot.data;
        if (user == null) return LoginScreen(repository: repository);
        if (!user.emailVerified) {
          return EmailVerificationScreen(repository: repository, user: user);
        }

        return StreamBuilder<UserProfile?>(
          stream: repository.watchProfile(user.uid),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.hasError) {
              return MessageScreen(
                title: 'Profile unavailable',
                message: profileSnapshot.error.toString(),
                actionLabel: 'Sign out',
                onAction: repository.signOut,
              );
            }
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const LoadingScreen();
            }
            final profile = profileSnapshot.data;
            if (profile == null) {
              return MessageScreen(
                title: 'Profile not found',
                message:
                    'Your identity exists, but its EcoTrace profile is missing.',
                actionLabel: 'Sign out',
                onAction: repository.signOut,
              );
            }
            if (profile.accountStatus != AccountStatus.active) {
              return MessageScreen(
                title: 'Account ${profile.accountStatus.name}',
                message:
                    'Contact EcoTrace support if you believe this is an error.',
                actionLabel: 'Sign out',
                onAction: repository.signOut,
              );
            }
            return _NotificationBootstrap(
              uid: profile.uid,
              child: RoleWorkspaceScreen(
                authRepository: repository,
                profile: profile,
              ),
            );
          },
        );
      },
    );
  }
}

class _NotificationBootstrap extends StatefulWidget {
  const _NotificationBootstrap({required this.uid, required this.child});
  final String uid;
  final Widget child;
  @override
  State<_NotificationBootstrap> createState() => _NotificationBootstrapState();
}

class _NotificationBootstrapState extends State<_NotificationBootstrap> {
  StreamSubscription? _subscription;
  @override
  void initState() {
    super.initState();
    NotificationService.registerDevice(widget.uid).catchError((_) {});
    _subscription = NotificationService.foregroundMessages.listen((message) {
      if (!mounted) return;
      final notification = message.notification;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            notification?.body ?? 'Your pickup request was updated.',
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
