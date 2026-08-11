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
       _api = apiClient ?? ApiClient.instance,
       _useApi = apiClient != null || (firestore == null && ApiConfig.enabled) {
    _audit = auditRepository ?? AuditRepository(firestore: _db, auth: _auth);
  }

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final ApiClient _api;
  final bool _useApi;
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

  Stream<List<UserProfile>> watchUsers() => _useApi
      ? _pollUsers()
      : _db
            .collection('users')
            .snapshots()
            .map(
              (snapshot) =>
                  snapshot.docs.map(UserProfile.fromSnapshot).toList()
                    ..sort((a, b) => a.displayName.compareTo(b.displayName)),
            );

  Stream<List<UserProfile>> _pollUsers() async* {
    while (true) {
      final data = await _api.getList('/api/v1/administration/users');
      yield data.map(UserProfile.fromJson).toList()
        ..sort((a, b) => a.displayName.compareTo(b.displayName));
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<List<RoleDefinition>> watchRoles() => _useApi
      ? _pollRoles()
      : _db
            .collection('systemRoles')
            .snapshots()
            .map(
              (snapshot) =>
                  snapshot.docs.map(RoleDefinition.fromDoc).toList()
                    ..sort((a, b) => a.role.index.compareTo(b.role.index)),
            );

  Stream<List<RoleDefinition>> _pollRoles() async* {
    while (true) {
      final data = await _api.getList('/api/v1/administration/roles');
      yield data.map(RoleDefinition.fromJson).toList()
        ..sort((a, b) => a.role.index.compareTo(b.role.index));
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  /// Waste categories, item conditions, service areas, and supported
  /// languages come from the real administration catalog endpoints.
  /// Pickup fees, reward rules, and notification templates are
  /// deliberately left out here: each is actually read from a different,
  /// disconnected Firestore location by the code that consumes it
  /// (billing fee calculation reads systemSettings/billing; reward point
  /// values read a top-level rewardRules collection; notification
  /// templates are already managed properly in the Notifications screen),
  /// so wiring this screen's fields to the administration catalog would
  /// silently have no effect on real calculations. Reconciling those
  /// requires touching the consuming code too, not just this screen.
  Stream<SystemConfiguration> watchConfiguration() => _useApi
      ? _pollConfiguration()
      : _db
            .collection('systemConfiguration')
            .doc('platform')
            .snapshots()
            .map(SystemConfiguration.fromDoc);

  Stream<SystemConfiguration> _pollConfiguration() async* {
    while (true) {
      final results = await Future.wait([
        _catalogNames('wasteCategories'),
        _catalogNames('itemConditions'),
        _catalogNames('serviceAreas'),
        _catalogNames('supportedLanguages'),
        _api.get('/api/v1/impact/formulas'),
        _api.get('/api/v1/administration/configuration/systemSettings'),
        _api.get('/api/v1/administration/configuration/integrations'),
      ]);
      final integrations = Map<String, dynamic>.from(
        (results[6] as Map<String, dynamic>)['values'] as Map? ?? const {},
      );
      yield SystemConfiguration(
        wasteCategories: results[0] as List<String>,
        itemConditions: results[1] as List<String>,
        serviceAreas: results[2] as List<String>,
        supportedLanguages: results[3] as List<String>,
        integrationNames: integrations.keys.toList(),
        notificationTemplateNames: const [],
        pickupFees: SystemConfiguration.defaults.pickupFees,
        rewardRules: SystemConfiguration.defaults.rewardRules,
        environmentalFormulas: Map<String, dynamic>.from(
          (results[4] as Map<String, dynamic>),
        ).map((key, value) => MapEntry(key, (value as num).toDouble())),
        settings: Map<String, dynamic>.from(
          (results[5] as Map<String, dynamic>)['values'] as Map? ?? const {},
        ).map((key, value) => MapEntry(key, value.toString())),
      );
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Future<List<String>> _catalogNames(String catalogName) async {
    final items = await _api.getList(
      '/api/v1/administration/catalogs/$catalogName',
    );
    return items
        .where((item) => item['active'] != false)
        .map((item) => (item['name'] ?? item['code'] ?? '').toString())
        .where((name) => name.isNotEmpty)
        .toList();
  }

  Future<void> _syncCatalog(String catalogName, List<String> names) async {
    final existing = await _catalogNames(catalogName);
    for (final name in names) {
      if (existing.contains(name)) continue;
      await _api.post('/api/v1/administration/catalogs/$catalogName', {
        'name': name,
        'code': name,
        'active': true,
      });
    }
  }

  Future<void> updateAccountStatus(
    UserProfile user,
    AccountStatus status,
  ) async {
    if (_useApi) {
      await _api.patch('/api/v1/administration/users/${user.uid}', {
        'accountStatus': status.name,
      });
    } else {
      await _db.collection('users').doc(user.uid).update({
        'accountStatus': status.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
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
    if (_useApi) {
      // Sets the Firebase custom claim synchronously - unlike the old
      // Firestore-only path, there is no pending-sync step required for
      // this to actually change what the user's API token authorizes.
      await _api.put('/api/v1/administration/users/${user.uid}/role', {
        'role': role.value,
      });
    } else {
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
    }
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
    if (_useApi) {
      await _api.put('/api/v1/administration/roles/${role.role.value}', {
        'name': role.role.label,
        'permissions': role.permissions.toList()..sort(),
        'description': role.description,
      });
    } else {
      await _db.collection('systemRoles').doc(role.role.value).set({
        'description': role.description,
        'permissions': role.permissions.toList()..sort(),
        'updatedBy': _auth.currentUser!.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
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
    if (_useApi) {
      await Future.wait([
        _syncCatalog('wasteCategories', configuration.wasteCategories),
        _syncCatalog('itemConditions', configuration.itemConditions),
        _syncCatalog('serviceAreas', configuration.serviceAreas),
        _syncCatalog('supportedLanguages', configuration.supportedLanguages),
        _api.put(
          '/api/v1/impact/formulas',
          configuration.environmentalFormulas,
        ),
        _api.put('/api/v1/administration/configuration/systemSettings', {
          'values': configuration.settings,
        }),
      ]);
    } else {
      await _db.collection('systemConfiguration').doc('platform').set({
        ...configuration.toMap(),
        'updatedBy': _auth.currentUser!.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await _audit.record(
      action: AuditAction.configurationChange,
      entityType: 'systemConfiguration',
      entityId: 'platform',
      description: 'Platform configuration updated.',
      changes: configuration.toMap(),
      severity: AuditSeverity.notice,
    );
  }

  Future<PlatformHealthSnapshot> checkHealth() async {
    if (_useApi) {
      final results = await Future.wait([
        _api.get('/api/v1/administration/health'),
        _api.get('/api/v1/administration/dashboard'),
      ]);
      final counts = Map<String, dynamic>.from(
        (results[1])['counts'] as Map? ?? const {},
      );
      return PlatformHealthSnapshot.fromJson(
        results[0],
        userCount: (counts['users'] as num? ?? 0).toInt(),
      );
    }
    final services = <String, PlatformServiceStatus>{
      'Authentication': _auth.currentUser == null
          ? PlatformServiceStatus.degraded
          : PlatformServiceStatus.operational,
    };
    var userCount = 0;
    try {
      final results = await Future.wait([
        _db.collection('users').get(),
        _db.collection('systemConfiguration').limit(1).get(),
      ]);
      userCount = results[0].docs.length;
      services['Cloud Firestore'] = PlatformServiceStatus.operational;
      services['Configuration'] = results[1].docs.isEmpty
          ? PlatformServiceStatus.degraded
          : PlatformServiceStatus.operational;
    } catch (_) {
      services['Cloud Firestore'] = PlatformServiceStatus.unavailable;
      services['Configuration'] = PlatformServiceStatus.unavailable;
    }
    return PlatformHealthSnapshot(
      services: services,
      userCount: userCount,
      pendingRoleChanges: 0,
      checkedAt: DateTime.now(),
    );
  }
}
