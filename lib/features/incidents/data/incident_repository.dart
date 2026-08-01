import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/media/cloudinary_upload_service.dart';
import '../domain/safety_incident.dart';

class IncidentRepository {
  IncidentRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;
  CollectionReference<Map<String, dynamic>> get _incidents =>
      _db.collection('safetyIncidents');
  Stream<List<SafetyIncident>> watchIncidents() => _incidents.snapshots().map(
    (s) => s.docs.map(SafetyIncident.fromDoc).toList()
      ..sort(
        (a, b) => (b.reportedAt ?? DateTime(0)).compareTo(
          a.reportedAt ?? DateTime(0),
        ),
      ),
  );
  Stream<SafetyIncident> watchIncident(String id) =>
      _incidents.doc(id).snapshots().map(SafetyIncident.fromDoc);
  Stream<List<IncidentFollowUp>> watchFollowUps(String id) => _incidents
      .doc(id)
      .collection('followUps')
      .snapshots()
      .map((s) => s.docs.map(IncidentFollowUp.fromDoc).toList());
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
    final ref = _incidents.doc();
    final urls = await CloudinaryUploadService.instance.uploadImages(
      evidence,
      scope: 'incidents',
    );
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
      _incidents.doc(i.id).update({
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
  }) => _incidents.doc(i.id).update({
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

  Future<void> close(SafetyIncident i, String notes, String actor) =>
      _incidents.doc(i.id).update({
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
