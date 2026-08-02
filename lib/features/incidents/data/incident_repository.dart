import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';
import '../../../core/media/cloudinary_upload_service.dart';
import '../domain/safety_incident.dart';

class IncidentRepository {
  IncidentRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    ApiClient? apiClient,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _api = apiClient ?? ApiClient.instance,
       _useApi =
           apiClient != null ||
           (firestore == null && auth == null && ApiConfig.enabled);
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final ApiClient _api;
  final bool _useApi;
  CollectionReference<Map<String, dynamic>> get _incidents =>
      _db.collection('safetyIncidents');
  Stream<List<SafetyIncident>> watchIncidents() => _useApi
      ? _pollIncidents()
      : _incidents.snapshots().map(
          (s) => s.docs.map(SafetyIncident.fromDoc).toList()
            ..sort(
              (a, b) => (b.reportedAt ?? DateTime(0)).compareTo(
                a.reportedAt ?? DateTime(0),
              ),
            ),
        );
  Stream<List<SafetyIncident>> _pollIncidents() async* {
    while (true) {
      final data = await _api.getList('/api/v1/incidents');
      yield data.map(SafetyIncident.fromJson).toList()..sort(
        (a, b) => (b.reportedAt ?? DateTime(0)).compareTo(
          a.reportedAt ?? DateTime(0),
        ),
      );
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<SafetyIncident> watchIncident(String id) => _useApi
      ? _pollIncident(id)
      : _incidents.doc(id).snapshots().map(SafetyIncident.fromDoc);
  Stream<SafetyIncident> _pollIncident(String id) async* {
    while (true) {
      final data = await _api.get('/api/v1/incidents/$id');
      yield SafetyIncident.fromJson({'id': id, ...data});
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<List<IncidentFollowUp>> watchFollowUps(String id) => _useApi
      ? _pollFollowUps(id)
      : _incidents
          .doc(id)
          .collection('followUps')
          .snapshots()
          .map((s) => s.docs.map(IncidentFollowUp.fromDoc).toList());

  Stream<List<IncidentFollowUp>> _pollFollowUps(String id) async* {
    while (true) {
      final data = await _api.getList('/api/v1/incidents/$id/follow-ups');
      yield data.map(IncidentFollowUp.fromJson).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }
  Stream<List<EmergencyContact>> watchContacts() => _db
      .collection('emergencyContacts')
      .snapshots()
      .map((s) => s.docs.map(EmergencyContact.fromDoc).toList());
  Future<void> report({
    required SafetyIncidentType type,
    required SafetyIncidentSeverity severity,
    required String title,
    required String description,
    required String location,
    required double? latitude,
    required double? longitude,
    required List<String> staff,
    required String injuryDetails,
    required String hazardType,
    required String response,
    required List<Uint8List> evidence,
    required String actorId,
  }) async {
    if (title.trim().isEmpty ||
        description.trim().isEmpty ||
        location.trim().isEmpty) {
      throw StateError('Title, description and location are required.');
    }
    final urls = await CloudinaryUploadService.instance.uploadImages(
      evidence,
      scope: 'incidents',
    );
    if (_useApi) {
      await _api.post('/api/v1/incidents', {
        'title': title.trim(),
        'description': description.trim(),
        'incidentType': type.name,
        'location': location.trim(),
        'reportedBy': actorId,
        'staffInvolved': staff,
        'injuryDetails': injuryDetails.trim(),
        'hazardType': hazardType.trim(),
        'immediateResponseAction': response.trim(),
        'photoUrls': urls,
        'severity': severity.name,
        'occurredAt': DateTime.now().toIso8601String(),
      });
      return;
    }
    final ref = _incidents.doc();
    await ref.set({
      'incidentNumber': 'INC-${DateTime.now().millisecondsSinceEpoch}',
      'type': type.name,
      'severity': severity.name,
      'status': SafetyIncidentStatus.reported.name,
      'title': title.trim(),
      'description': description.trim(),
      'location': location.trim(),
      'latitude': latitude,
      'longitude': longitude,
      'staffInvolved': staff,
      'injuryDetails': injuryDetails.trim(),
      'hazardType': hazardType.trim(),
      'immediateResponse': response.trim(),
      'evidenceUrls': urls,
      'investigatorId': '',
      'rootCause': '',
      'correctiveAction': '',
      'correctiveOwner': '',
      'closureNotes': '',
      'reportedBy': actorId,
      'reportedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> startInvestigation(SafetyIncident i, String investigator) =>
      _useApi
      ? _api.patch('/api/v1/incidents/${i.id}/investigate', {})
      : _incidents.doc(i.id).update({
          'status': SafetyIncidentStatus.investigating.name,
          'investigatorId': investigator,
          'investigationStartedAt': FieldValue.serverTimestamp(),
        });
  Future<void> recordRootCause(
    SafetyIncident i, {
    required String rootCause,
    required String correctiveAction,
    required String owner,
    required DateTime dueAt,
  }) => _useApi
      ? _api.patch('/api/v1/incidents/${i.id}/root-cause', {
          'rootCause': rootCause.trim(),
          'correctiveAction': correctiveAction.trim(),
          'correctiveOwner': owner.trim(),
          'correctiveDueAt': dueAt.toUtc().toIso8601String(),
        }).then((_) {})
      : _incidents.doc(i.id).update({
          'status': SafetyIncidentStatus.correctiveAction.name,
          'rootCause': rootCause.trim(),
          'correctiveAction': correctiveAction.trim(),
          'correctiveOwner': owner.trim(),
          'correctiveDueAt': Timestamp.fromDate(dueAt),
          'updatedAt': FieldValue.serverTimestamp(),
        });
  Future<void> followUp(
    SafetyIncident i, {
    required String findings,
    required bool riskRemaining,
    required String actorId,
  }) async {
    if (_useApi) {
      await _api.post('/api/v1/incidents/${i.id}/follow-ups', {
        'findings': findings.trim(),
        'riskRemaining': riskRemaining,
      });
      return;
    }
    final ref = _incidents.doc(i.id), batch = _db.batch();
    batch.set(ref.collection('followUps').doc(), {
      'findings': findings.trim(),
      'riskRemaining': riskRemaining,
      'recordedBy': actorId,
      'recordedAt': FieldValue.serverTimestamp(),
    });
    batch.update(ref, {
      'status': riskRemaining
          ? SafetyIncidentStatus.followUp.name
          : SafetyIncidentStatus.correctiveAction.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> close(SafetyIncident i, String notes, String actor) => _useApi
      ? _api.patch('/api/v1/incidents/${i.id}/close', {
          'closureNotes': notes.trim(),
        }).then((_) {})
      : _incidents.doc(i.id).update({
          'status': SafetyIncidentStatus.closed.name,
          'closureNotes': notes.trim(),
          'closedBy': actor,
          'closedAt': FieldValue.serverTimestamp(),
        });
  Future<void> contact({
    required String name,
    required String role,
    required String phone,
    required String email,
    required String region,
  }) => _db.collection('emergencyContacts').add({
    'name': name,
    'role': role,
    'phone': phone,
    'email': email,
    'region': region,
    'active': true,
    'createdAt': FieldValue.serverTimestamp(),
  });
}
