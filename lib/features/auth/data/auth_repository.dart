import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';
import '../../../core/media/cloudinary_upload_service.dart';
import '../../audit/data/audit_repository.dart';
import '../../audit/domain/audit_event.dart';
import '../../pickups/data/notification_service.dart';
import '../domain/app_role.dart';
import '../domain/user_profile.dart';

class AuthRepository {
  AuthRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    AuditRepository? auditRepository,
    ApiClient? apiClient,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _api = apiClient ?? ApiClient.instance,
       _useApi = apiClient != null ||
           (auth == null && firestore == null && ApiConfig.enabled) {
    _audit =
        auditRepository ?? AuditRepository(firestore: _firestore, auth: _auth);
  }

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final ApiClient _api;
  final bool _useApi;
  late final AuditRepository _audit;

  Stream<User?> get authStateChanges => _auth.userChanges();

  Stream<UserProfile?> watchProfile(String uid) => _useApi
      ? _pollProfile()
      : _firestore
      .collection('users')
      .doc(uid)
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.exists ? UserProfile.fromSnapshot(snapshot) : null,
      );

  Stream<UserProfile?> _pollProfile() async* {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      // Ensure we have a user before starting to poll
      yield null;
      return;
    }

    while (_auth.currentUser != null) {
      try {
        final data = await _api.get('/api/v1/identity/profile');
        yield UserProfile.fromJson(data);
      } catch (error) {
        // If the API call fails, emit null to display the profile-not-found
        // screen rather than terminating the entire stream silently.
        yield null;
      }
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Future<void> register({
    required String displayName,
    required String email,
    required String password,
    required AppRole role,
    required bool acceptedTerms,
  }) async {
    if (!AppRole.selfServiceRoles.contains(role)) {
      throw StateError('This role must be assigned by an administrator.');
    }
    if (!acceptedTerms) {
      throw StateError('You must accept the terms and privacy policy.');
    }

    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user!;

    try {
      await user.updateDisplayName(displayName.trim());
      if (_useApi) {
        await _api.post('/api/v1/identity/bootstrap', {
          'displayName': displayName.trim(),
          'role': role.value,
          'termsVersion': '2026-01',
          'privacyVersion': '2026-01',
          'acceptedTerms': true,
          'acceptedPrivacy': true,
        });
      } else {
        await _firestore.collection('users').doc(user.uid).set({
        'email': email.trim().toLowerCase(),
        'displayName': displayName.trim(),
        'role': role.value,
        'accountStatus': AccountStatus.active.name,
        'emailVerified': false,
        'phoneVerified': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
        'termsAcceptedAt': FieldValue.serverTimestamp(),
        'privacyAcceptedAt': FieldValue.serverTimestamp(),
        });
      }
      await user.sendEmailVerification();
      try {
        await _audit.record(
          action: AuditAction.create,
          entityType: 'user',
          entityId: user.uid,
          description: 'Self-service account registered.',
          actorName: displayName.trim(),
          actorRole: role.value,
        );
      } catch (_) {
        // Registration remains valid if audit delivery is temporarily offline.
      }
    } catch (_) {
      await user.delete();
      rethrow;
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    if (_useApi) {
      await _registerSession();
      await _api.post('/api/v1/identity/verification/sync', {});
    } else {
      await _firestore.collection('users').doc(credential.user!.uid).update({
        'lastLoginAt': FieldValue.serverTimestamp(),
      });
    }
    try {
      await _audit.record(
        action: AuditAction.login,
        entityType: 'authenticationSession',
        entityId: credential.user!.uid,
        description: 'User signed in successfully.',
      );
    } catch (_) {
      // Authentication remains available if audit delivery is temporarily offline.
    }
  }

  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    }
  }

  Future<void> refreshUser() => _auth.currentUser!.reload();

  Future<Map<String, dynamic>> securityOverview() async {
    if (!_useApi) return const {};
    final results = await Future.wait([
      _api.get('/api/v1/identity/mfa'),
      _api.get('/api/v1/identity/permissions'),
      _api.get('/api/v1/identity/deletion-request'),
    ]);
    return {'mfa': results[0], 'permissions': results[1], 'deletion': results[2]};
  }

  Future<List<Map<String, dynamic>>> sessions() => _useApi
      ? _api.getList('/api/v1/identity/sessions')
      : Future.value(const []);

  Future<List<Map<String, dynamic>>> loginHistory() => _useApi
      ? _api.getList('/api/v1/identity/login-history')
      : Future.value(const []);

  Future<void> revokeSession(String id) async {
    if (_useApi) await _api.delete('/api/v1/identity/sessions/$id');
  }

  Future<void> revokeAllSessions() async {
    if (_useApi) await _api.post('/api/v1/identity/sessions/revoke-all', {});
  }

  Future<void> removeMfa() async {
    if (_useApi) await _api.delete('/api/v1/identity/mfa');
  }

  Future<void> requestAccountDeletion(String reason) async {
    if (!_useApi) throw StateError('The identity API is required.');
    await _api.post('/api/v1/identity/deletion-request', {
      'reason': reason.trim(),
      'confirmation': 'DELETE MY ACCOUNT',
    });
  }

  Future<void> cancelAccountDeletion() async {
    if (_useApi) await _api.delete('/api/v1/identity/deletion-request');
  }

  Future<void> updateDisplayName(String displayName) async {
    final user = _auth.currentUser;
    final value = displayName.trim();
    if (user == null || value.isEmpty) {
      throw StateError('Enter a display name while signed in.');
    }
    await user.updateDisplayName(value);
    if (_useApi) {
      await _api.patch('/api/v1/identity/profile', {'displayName': value});
    } else {
      await _firestore.collection('users').doc(user.uid).update({
        'displayName': value,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await _audit.record(
      action: AuditAction.update,
      entityType: 'userProfile',
      entityId: user.uid,
      description: 'Display name updated.',
      changes: {'displayName': value},
    );
  }

  Future<String> uploadProfilePicture(XFile file) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('User must be signed in to upload a profile picture.');
    }

    final rawName = file.name.isNotEmpty ? file.name : file.path;
    final safeName = rawName.split('/').last.split('\\').last;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw StateError('Selected file is empty. Please choose a valid image.');
    }

    var fileExtension = '';
    if (safeName.contains('.')) {
      fileExtension = safeName.split('.').last.toLowerCase();
    }

    const allowedExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
    if (!allowedExtensions.contains(fileExtension)) {
      fileExtension = _fileExtensionFromBytes(bytes);
    }
    if (!allowedExtensions.contains(fileExtension)) {
      throw StateError('Invalid file type. Only images are allowed.');
    }

    try {
      final downloadUrl = await CloudinaryUploadService.instance.uploadImage(
        Uint8List.fromList(bytes),
        scope: 'profiles',
        fileName: 'profile.$fileExtension',
      );
      if (_useApi) {
        await _api.patch('/api/v1/identity/profile', {'photoUrl': downloadUrl});
      } else {
        await _firestore.collection('users').doc(user.uid).update({
          'profilePictureUrl': downloadUrl,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // Record audit log
      await _audit.record(
        action: AuditAction.update,
        entityType: 'userProfile',
        entityId: user.uid,
        description: 'Profile picture updated.',
        changes: {'profilePictureUrl': 'updated'},
      );

      return downloadUrl;
    } catch (e) {
      throw StateError('Failed to upload profile picture: $e');
    }
  }

  static String _fileExtensionFromBytes(List<int> bytes) {
    if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return 'jpg';
    }
    if (bytes.length >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      return 'png';
    }
    if (bytes.length >= 3 && bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
      return 'gif';
    }
    if (bytes.length >= 12 && bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
      return 'webp';
    }
    return '';
  }

  Future<void> deleteProfilePicture() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('User must be signed in.');
    }

    try {
      if (_useApi) {
        await _api.patch('/api/v1/identity/profile', {'photoUrl': ''});
      } else {
        await _firestore.collection('users').doc(user.uid).update({
          'profilePictureUrl': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // Record audit log
      await _audit.record(
        action: AuditAction.update,
        entityType: 'userProfile',
        entityId: user.uid,
        description: 'Profile picture removed.',
      );
    } catch (e) {
      throw StateError('Failed to delete profile picture: $e');
    }
  }

  Future<void> signOut() async {
    final user = _auth.currentUser;
    if (user == null) return;
    if (_useApi) {
      try {
        await _api.delete('/api/v1/identity/sessions/${_deviceId(user.uid)}');
      } catch (_) {
        // Signing out locally must remain available while the API is offline.
      }
    }
    unawaited(_recordLogoutBestEffort(user.uid));
    unawaited(NotificationService.removeCurrentDevice().catchError((_) {}));
    await _auth.signOut();
  }

  Future<void> _registerSession() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final platform = _platformName;
    await _api.post('/api/v1/identity/sessions', {
      'deviceId': _deviceId(user.uid),
      'deviceName': kIsWeb ? 'Web browser' : '${defaultTargetPlatform.name} device',
      'platform': platform,
      'appVersion': '',
      'pushTokenId': '',
    });
  }

  String _deviceId(String uid) =>
      'ecotrace-$_platformName-${uid.hashCode.abs()}';

  String get _platformName {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.windows => 'windows',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.linux => 'linux',
      _ => 'unknown',
    };
  }

  Future<void> _recordLogoutBestEffort(String uid) async {
    try {
      await _audit.record(
        action: AuditAction.logout,
        entityType: 'authenticationSession',
        entityId: uid,
        description: 'User signed out.',
      );
    } catch (_) {
      // The local session is cleared even when audit delivery is unavailable.
    }
  }
}
