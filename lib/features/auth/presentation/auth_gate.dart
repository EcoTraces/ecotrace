import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/auth_repository.dart';
import '../domain/user_profile.dart';
import 'auth_screens.dart';
import '../../pickups/data/notification_service.dart';
import '../../workspace/presentation/role_workspace_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.repository});

  final AuthRepository repository;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  // `authStateChanges` is backed by FirebaseAuth.userChanges(), which fires
  // on every ID token refresh in addition to real sign-in/sign-out (needed
  // so the email-verification gate below updates after `reload()`). Calling
  // `watchProfile` directly inside build() would therefore tear down and
  // restart the profile-polling stream on every token refresh. Since a 401
  // from that very stream triggers a force-refresh (see ApiClient), that
  // recreation becomes a self-sustaining loop the UI shows as a constant
  // restart. Caching the stream per-uid decouples it from unrelated
  // token-refresh rebuilds.
  String? _profileStreamUid;
  Stream<UserProfile?>? _profileStream;

  Stream<UserProfile?> _profileStreamFor(String uid) {
    if (_profileStreamUid != uid) {
      _profileStreamUid = uid;
      _profileStream = widget.repository.watchProfile(uid);
    }
    return _profileStream!;
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    return StreamBuilder<User?>(
      stream: repository.authStateChanges,
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        }
        final user = authSnapshot.data;
        if (user == null) {
          _profileStreamUid = null;
          _profileStream = null;
          return LoginScreen(repository: repository);
        }
        if (!user.emailVerified) {
          return EmailVerificationScreen(repository: repository, user: user);
        }

        return StreamBuilder<UserProfile?>(
          stream: _profileStreamFor(user.uid),
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
              // The normal path here is a first-time federated (Google/
              // Apple/GitHub) sign-in, which creates the Firebase Auth user
              // without the role/terms step email/password registration
              // collects up front -- this screen collects it. It also
              // covers the rarer case of any other profile-less auth user.
              return CompleteProfileScreen(repository: repository, user: user);
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
