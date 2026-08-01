import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';
import '../../audit/data/audit_repository.dart';
import '../../audit/domain/audit_event.dart';
import '../../auth/domain/app_role.dart';
import '../../auth/domain/user_profile.dart';
import '../domain/system_administration.dart';

class AdminRepository {
  AdminRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    AuditRepository? auditRepository,
    ApiClient? apiClient,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _api = apiClient ?? ApiClient.instance {
    _audit = auditRepository ?? AuditRepository(firestore: _db, auth: _auth);
  }

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final ApiClient _api;
  late final AuditRepository _audit;

  bool get canSeedDemoData => ApiConfig.enabled;

  Future<int> seedDemoData() async {
    if (!ApiConfig.enabled) {
      throw StateError(
        'Configure API_BASE_URL before generating demo data.',
      );
    }
    final result = await _api.post('/api/v1/admin/demo-data', const {});
    return (result['records'] as num? ?? 0).toInt();
  }

  Stream<List<UserProfile>> watchUsers() => _db
      .collection('users')
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.docs.map(UserProfile.fromSnapshot).toList()
              ..sort((a, b) => a.displayName.compareTo(b.displayName)),
      );

  Stream<List<RoleDefinition>> watchRoles() => _db
      .collection('systemRoles')
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.docs.map(RoleDefinition.fromDoc).toList()
              ..sort((a, b) => a.role.index.compareTo(b.role.index)),
      );

  Stream<SystemConfiguration> watchConfiguration() => _db
      .collection('systemConfiguration')
      .doc('platform')
      .snapshots()
      .map(SystemConfiguration.fromDoc);

  Future<void> updateAccountStatus(
    UserProfile user,
    AccountStatus status,
  ) async {
    await _db.collection('users').doc(user.uid).update({
      'accountStatus': status.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _audit.record(
      action: AuditAction.update,
      entityType: 'user',
      entityId: user.uid,
      description: 'Account status changed to ${status.name}.',
      changes: {
        'accountStatus': {
          'before': user.accountStatus.name,
          'after': status.name,
        },
      },
      severity: status == AccountStatus.suspended
          ? AuditSeverity.warning
          : AuditSeverity.notice,
    );
  }

  Future<void> changeRole(UserProfile user, AppRole role) async {
    if (user.uid == _auth.currentUser?.uid &&
        role != AppRole.administrator &&
        role != AppRole.superAdministrator) {
      throw StateError('Administrators cannot remove their own access.');
    }
    final request = _db.collection('roleChangeRequests').doc();
    final batch = _db.batch();
    batch.update(_db.collection('users').doc(user.uid), {
      'role': role.value,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(request, {
      'userId': user.uid,
      'previousRole': user.role.value,
      'requestedRole': role.value,
      'requestedBy': _auth.currentUser!.uid,
      'status': 'pendingClaimSync',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    await _audit.record(
      action: AuditAction.roleChange,
      entityType: 'user',
      entityId: user.uid,
      description: 'Role changed from ${user.role.value} to ${role.value}.',
      changes: {
        'role': {'before': user.role.value, 'after': role.value},
      },
      severity: AuditSeverity.warning,
    );
  }

  Future<void> saveRole(RoleDefinition role) async {
    await _db.collection('systemRoles').doc(role.role.value).set({
      'description': role.description,
      'permissions': role.permissions.toList()..sort(),
      'updatedBy': _auth.currentUser!.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _audit.record(
      action: AuditAction.permissionChange,
      entityType: 'systemRole',
      entityId: role.role.value,
      description: 'Permissions updated for ${role.role.label}.',
      changes: {'permissions': role.permissions.toList()..sort()},
      severity: AuditSeverity.warning,
    );
  }

  Future<void> saveConfiguration(SystemConfiguration configuration) async {
    await _db.collection('systemConfiguration').doc('platform').set({
      ...configuration.toMap(),
      'updatedBy': _auth.currentUser!.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _audit.record(
      action: AuditAction.configurationChange,
      entityType: 'systemConfiguration',
      entityId: 'platform',
      description: 'Platform configuration updated.',
      changes: configuration.toMap(),
      severity: AuditSeverity.notice,
    );
  }

  Future<void> saveNotificationTemplate({
    required String name,
    required String title,
    required String body,
  }) async {
    final doc = _db.collection('notificationTemplates').doc();
    await doc.set({
      'name': name.trim(),
      'type': 'general',
      'title': title.trim(),
      'body': body.trim(),
      'active': true,
      'createdBy': _auth.currentUser!.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _audit.record(
      action: AuditAction.create,
      entityType: 'notificationTemplate',
      entityId: doc.id,
      description: 'Notification template ${name.trim()} created.',
    );
  }

  Future<PlatformHealthSnapshot> checkHealth() async {
    final services = <String, PlatformServiceStatus>{
      'Authentication': _auth.currentUser == null
          ? PlatformServiceStatus.degraded
          : PlatformServiceStatus.operational,
    };
    var userCount = 0;
    var pending = 0;
    try {
      final results = await Future.wait([
        _db.collection('users').get(),
        _db
            .collection('roleChangeRequests')
            .where('status', isEqualTo: 'pendingClaimSync')
            .get(),
        _db.collection('systemConfiguration').limit(1).get(),
      ]);
      userCount = results[0].docs.length;
      pending = results[1].docs.length;
      services['Cloud Firestore'] = PlatformServiceStatus.operational;
      services['Configuration'] = results[2].docs.isEmpty
          ? PlatformServiceStatus.degraded
          : PlatformServiceStatus.operational;
    } catch (_) {
      services['Cloud Firestore'] = PlatformServiceStatus.unavailable;
      services['Configuration'] = PlatformServiceStatus.unavailable;
    }
    return PlatformHealthSnapshot(
      services: services,
      userCount: userCount,
      pendingRoleChanges: pending,
      checkedAt: DateTime.now(),
    );
  }
}
