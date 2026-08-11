import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';
import '../domain/audit_event.dart';

class AuditRepository {
  AuditRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    ApiClient? apiClient,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _api = apiClient ?? ApiClient.instance,
       _useApi = apiClient != null || (firestore == null && ApiConfig.enabled);

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final ApiClient _api;
  final bool _useApi;

  Stream<List<AuditEvent>> watchEvents({int limit = 500}) => _useApi
      ? _pollEvents(limit)
      : _db
            .collection('auditLogs')
            .orderBy('createdAt', descending: true)
            .limit(limit)
            .snapshots()
            .map(
              (snapshot) => snapshot.docs.map(AuditEvent.fromDoc).toList(),
            );

  Stream<List<AuditEvent>> _pollEvents(int limit) async* {
    while (true) {
      final data = await _api.getList(
        '/api/v1/audit/events',
        query: {'limit': '$limit'},
      );
      yield data.map(AuditEvent.fromJson).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Future<String> record({
    required AuditAction action,
    required String entityType,
    required String entityId,
    required String description,
    Map<String, dynamic> changes = const {},
    AuditSeverity severity = AuditSeverity.information,
    bool success = true,
    String? actorName,
    String? actorRole,
  }) async {
    if (_useApi) {
      final result = await _api.post('/api/v1/audit/events', {
        'action': action.name,
        'resourceType': entityType.trim(),
        'resourceId': entityId.trim(),
        'outcome': success ? 'success' : 'failure',
        'description': description.trim(),
        'metadata': {...changes, 'severity': severity.name},
      });
      return result['id']?.toString() ?? '';
    }
    final user = _auth.currentUser;
    if (user == null) throw StateError('An authenticated actor is required.');
    final token = await user.getIdTokenResult();
    final doc = await _db.collection('auditLogs').add({
      'actorId': user.uid,
      'actorName': actorName ?? user.displayName ?? user.email ?? user.uid,
      'actorRole': actorRole ?? token.claims?['role'] as String? ?? '',
      'action': action.name,
      'entityType': entityType.trim(),
      'entityId': entityId.trim(),
      'description': description.trim(),
      'changes': changes,
      // A trusted backend may enrich this field from request metadata.
      'ipAddress': '',
      'deviceInformation': _deviceInformation,
      'success': success,
      'severity': severity.name,
      'source': 'client',
      'integrityVersion': 1,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<AuditIntegrityResult?> checkIntegrity() async {
    if (!_useApi) return null;
    final data = await _api.get('/api/v1/audit/integrity');
    return AuditIntegrityResult.fromJson(data);
  }

  String get _deviceInformation {
    final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
    return '$platform / Flutter';
  }
}
