import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

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
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance {
    _audit =
        auditRepository ?? AuditRepository(firestore: _firestore, auth: _auth);
  }

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  late final AuditRepository _audit;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Stream<User?> get authStateChanges => _auth.userChanges();

  Stream<UserProfile?> watchProfile(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.exists ? UserProfile.fromSnapshot(snapshot) : null,
      );

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
    await _firestore.collection('users').doc(credential.user!.uid).update({
      'lastLoginAt': FieldValue.serverTimestamp(),
    });
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

  Future<void> updateDisplayName(String displayName) async {
    final user = _auth.currentUser;
    final value = displayName.trim();
    if (user == null || value.isEmpty) {
      throw StateError('Enter a display name while signed in.');
    }
    await user.updateDisplayName(value);
    await _firestore.collection('users').doc(user.uid).update({
      'displayName': value,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _audit.record(
      action: AuditAction.update,
      entityType: 'userProfile',
      entityId: user.uid,
      description: 'Display name updated.',
      changes: {'displayName': value},
    );
  }

  Future<String> uploadProfilePicture(String filePath) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('User must be signed in to upload a profile picture.');
    }

    final file = File(filePath);
    final fileExtension = filePath.split('.').last.toLowerCase();
    
    // Validate file type
    const allowedExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
    if (!allowedExtensions.contains(fileExtension)) {
      throw StateError('Invalid file type. Only images are allowed.');
    }

    try {
      // Upload to Firebase Storage
      final storageRef = _storage
          .ref()
          .child('profile-pictures/${user.uid}/profile-$fileExtension}');
      
      final uploadTask = await storageRef.putFile(file);
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      // Update Firestore with the profile picture URL
      await _firestore.collection('users').doc(user.uid).update({
        'profilePictureUrl': downloadUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });

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

  Future<void> deleteProfilePicture() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('User must be signed in.');
    }

    try {
      // Delete all profile pictures for this user from Storage
      final listResult = await _storage
          .ref()
          .child('profile-pictures/${user.uid}')
          .listAll();
      
      for (final item in listResult.items) {
        await item.delete();
      }

      // Update Firestore to remove the profile picture URL
      await _firestore.collection('users').doc(user.uid).update({
        'profilePictureUrl': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

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
    unawaited(_recordLogoutBestEffort(user.uid));
    unawaited(NotificationService.removeCurrentDevice().catchError((_) {}));
    await _auth.signOut();
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
