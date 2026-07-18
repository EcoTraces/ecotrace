import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../domain/audit_event.dart';

class AuditRepository {
  AuditRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _db = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  Stream<List<AuditEvent>> watchEvents({int limit = 500}) => _db
      .collection('auditLogs')
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(AuditEvent.fromDoc).toList());

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

  String get _deviceInformation {
    final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
    return '$platform / Flutter';
  }
}
