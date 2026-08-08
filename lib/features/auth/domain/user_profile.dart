import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_role.dart';

enum AccountStatus {
  active,
  suspended,
  pendingDeletion;

  static AccountStatus fromValue(String? value) => values.firstWhere(
    (status) => status.name == value,
    orElse: () => AccountStatus.active,
  );
}

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    required this.accountStatus,
    this.profilePictureUrl,
  });

  final String uid;
  final String email;
  final String displayName;
  final AppRole role;
  final AccountStatus accountStatus;
  final String? profilePictureUrl;

  factory UserProfile.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return UserProfile(
      uid: snapshot.id,
      email: data['email'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
      role: AppRole.fromValue(data['role'] as String?),
      accountStatus: AccountStatus.fromValue(data['accountStatus'] as String?),
      profilePictureUrl: data['profilePictureUrl'] as String?,
    );
  }
}
