import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/media/cloudinary_upload_service.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';

import '../domain/compliance_record.dart';

class ComplianceRepository {
  ComplianceRepository({FirebaseFirestore? firestore, ApiClient? apiClient})
    : _db = firestore ?? FirebaseFirestore.instance,
      _api = apiClient ?? ApiClient.instance,
      _useApi = apiClient != null || (firestore == null && ApiConfig.enabled);
  final FirebaseFirestore _db;
  final ApiClient _api;
  final bool _useApi;

  Stream<List<RegulatoryBody>> watchRegulatoryBodies() =>
      _useApi ? _poll('/api/v1/compliance/regulatory-bodies', RegulatoryBody.fromJson) : _watch('regulatoryBodies', RegulatoryBody.fromDoc);
  Stream<List<ComplianceDocument>> watchDocuments() =>
      _useApi ? _poll('/api/v1/compliance/documents', ComplianceDocument.fromJson) : _watch('complianceDocuments', ComplianceDocument.fromDoc);
  Stream<List<ComplianceRequirement>> watchRequirements() =>
      _useApi ? _poll('/api/v1/compliance/requirements', ComplianceRequirement.fromJson) : _watch('complianceRequirements', ComplianceRequirement.fromDoc);
  Stream<List<ComplianceInspection>> watchInspections() =>
      _useApi ? _poll('/api/v1/compliance/inspections', ComplianceInspection.fromJson) : _watch('complianceInspections', ComplianceInspection.fromDoc);
  Stream<List<ComplianceViolation>> watchViolations() =>
      _useApi ? _poll('/api/v1/compliance/violations', ComplianceViolation.fromJson) : _watch('complianceViolations', ComplianceViolation.fromDoc);
  Stream<List<PenaltyRecord>> watchPenalties() =>
      _useApi ? _poll('/api/v1/compliance/penalties', PenaltyRecord.fromJson) : _watch('penaltyRecords', PenaltyRecord.fromDoc);

  Stream<List<T>> _poll<T>(String path, T Function(Map<String, dynamic>) convert) async* {
    while (true) {
      final data = await _api.getList(path);
      yield data.map(convert).toList();
      await Future<void>.delayed(const Duration(seconds: ApiConfig.pollingSeconds));
    }
  }

  Stream<List<T>> _watch<T>(
    String collection,
    T Function(DocumentSnapshot<Map<String, dynamic>>) convert,
  ) => _db
      .collection(collection)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(convert).toList());

  Future<void> saveRegulatoryBody({
    required String name,
    required String jurisdiction,
    required String contactName,
    required String contactEmail,
    required String contactPhone,
  }) {
    if (name.trim().isEmpty || jurisdiction.trim().isEmpty) {
      throw StateError('Regulatory body and jurisdiction are required.');
    }
    if (_useApi) {
      return _api.post('/api/v1/compliance/regulatory-bodies', {
        'name': name.trim(), 'jurisdiction': jurisdiction.trim(),
        'contactEmail': contactEmail.trim(), 'contactPhone': contactPhone.trim(), 'active': true,
      }).then((_) {});
    }
    return _db.collection('regulatoryBodies').add({
      'name': name.trim(),
      'jurisdiction': jurisdiction.trim(),
      'contactName': contactName.trim(),
      'contactEmail': contactEmail.trim(),
      'contactPhone': contactPhone.trim(),
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveDocument({
    required ComplianceDocumentType type,
    required String title,
    required String referenceNumber,
    required String entityName,
    required RegulatoryBody? regulatoryBody,
    required DateTime? issuedAt,
    required DateTime? expiresAt,
    required String notes,
    required List<Uint8List> files,
    required String actorId,
  }) async {
    if (title.trim().isEmpty || referenceNumber.trim().isEmpty) {
      throw StateError('Document title and reference are required.');
    }
    final ref = _db.collection('complianceDocuments').doc();
    final urls = await _upload(ref.id, 'documents', files);
    if (_useApi) {
      await _api.post('/api/v1/compliance/documents', {
        'type': type.name, 'title': title.trim(), 'referenceNumber': referenceNumber.trim(),
        'entityName': entityName.trim(), 'regulatoryBodyId': regulatoryBody?.id ?? '',
        'regulatoryBodyName': regulatoryBody?.name ?? '', 'status': ComplianceDocumentStatus.valid.name,
        'documentUrls': urls, 'issuedAt': issuedAt?.toUtc().toIso8601String(),
        'expiresAt': expiresAt?.toUtc().toIso8601String(), 'notes': notes.trim(),
      });
      return;
    }
    await ref.set({
      'type': type.name,
      'title': title.trim(),
      'referenceNumber': referenceNumber.trim(),
      'entityName': entityName.trim(),
      'regulatoryBodyId': regulatoryBody?.id ?? '',
      'regulatoryBodyName': regulatoryBody?.name ?? '',
      'status': ComplianceDocumentStatus.valid.name,
      'documentUrls': urls,
      'issuedAt': issuedAt == null ? null : Timestamp.fromDate(issuedAt),
      'expiresAt': expiresAt == null ? null : Timestamp.fromDate(expiresAt),
      'notes': notes.trim(),
      'createdBy': actorId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateDocumentStatus(
    ComplianceDocument document,
    ComplianceDocumentStatus status,
  ) => _useApi ? _api.patch('/api/v1/compliance/documents/${document.id}/status', {'status': status.name}).then((_) {}) : _db.collection('complianceDocuments').doc(document.id).update({
    'status': status.name,
    if (status == ComplianceDocumentStatus.pendingReview)
      'submittedAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<void> saveRequirement({
    required String category,
    required String title,
    required String description,
    required bool mandatory,
  }) {
    if (title.trim().isEmpty) {
      throw StateError('Requirement title is required.');
    }
    if (_useApi) {
      return _api.post('/api/v1/compliance/requirements', {
        'category': category.trim(), 'title': title.trim(), 'description': description.trim(),
        'mandatory': mandatory, 'active': true,
      }).then((_) {});
    }
    return _db.collection('complianceRequirements').add({
      'category': category.trim(),
      'title': title.trim(),
      'description': description.trim(),
      'mandatory': mandatory,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> scheduleInspection({
    required String entityName,
    required RegulatoryBody? regulatoryBody,
    required String inspectorName,
    required DateTime scheduledAt,
    required List<ComplianceRequirement> requirements,
    required String actorId,
  }) {
    if (requirements.isEmpty) {
      throw StateError('Add at least one active checklist requirement first.');
    }
    if (_useApi) {
      return _api.post('/api/v1/compliance/inspections', {
        'entityId': entityName.trim(), 'entityType': 'organization', 'entityName': entityName.trim(),
        'regulatoryBodyId': regulatoryBody?.id ?? '', 'inspectorName': inspectorName.trim(),
        'scheduledAt': scheduledAt.toUtc().toIso8601String(), 'status': ComplianceInspectionStatus.scheduled.name,
        'checklist': {for (final requirement in requirements) requirement.title: false},
      }).then((_) {});
    }
    return _db.collection('complianceInspections').add({
      'entityName': entityName.trim(),
      'regulatoryBodyId': regulatoryBody?.id ?? '',
      'inspectorName': inspectorName.trim(),
      'scheduledAt': Timestamp.fromDate(scheduledAt),
      'status': ComplianceInspectionStatus.scheduled.name,
      'checklist': {
        for (final requirement in requirements) requirement.title: false,
      },
      'score': 0,
      'findings': '',
      'recommendations': '',
      'reportUrls': [],
      'scheduledBy': actorId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> completeInspection(
    ComplianceInspection inspection, {
    required Map<String, bool> checklist,
    required String findings,
    required String recommendations,
    required List<Uint8List> reports,
    required String actorId,
  }) async {
    if (checklist.isEmpty) {
      throw StateError('Inspection checklist is required.');
    }
    final passed = checklist.values.where((value) => value).length;
    final score = passed / checklist.length * 100;
    final urls = await _upload(inspection.id, 'inspections', reports);
    if (_useApi) {
      await _api.patch('/api/v1/compliance/inspections/${inspection.id}/report', {
        'status': score >= 80 ? ComplianceInspectionStatus.completed.name : ComplianceInspectionStatus.followUpRequired.name,
        'checklist': checklist, 'score': score, 'findings': findings.trim(),
        'recommendations': recommendations.trim(), 'reportUrls': urls,
      });
      return;
    }
    await _db.collection('complianceInspections').doc(inspection.id).update({
      'status': score >= 80
          ? ComplianceInspectionStatus.completed.name
          : ComplianceInspectionStatus.followUpRequired.name,
      'checklist': checklist,
      'score': score,
      'findings': findings.trim(),
      'recommendations': recommendations.trim(),
      'reportUrls': urls,
      'completedBy': actorId,
      'completedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> recordViolation({
    required String entityName,
    required String requirement,
    required String description,
    required ViolationSeverity severity,
    required String actorId,
  }) {
    if (description.trim().isEmpty) {
      throw StateError('Violation description is required.');
    }
    if (_useApi) {
      return _api.post('/api/v1/compliance/violations', {
        'entityId': entityName.trim(), 'entityType': 'organization', 'entityName': entityName.trim(),
        'violationType': requirement.trim().isEmpty ? 'General' : requirement.trim(), 'requirement': requirement.trim(),
        'description': description.trim(), 'severity': severity == ViolationSeverity.minor ? 'low' : severity == ViolationSeverity.major ? 'high' : 'critical',
        'detectedAt': DateTime.now().toUtc().toIso8601String(),
      }).then((_) {});
    }
    return _db.collection('complianceViolations').add({
      'referenceNumber': 'VIO-${DateTime.now().millisecondsSinceEpoch}',
      'entityName': entityName.trim(),
      'requirement': requirement.trim(),
      'description': description.trim(),
      'severity': severity.name,
      'status': ComplianceViolationStatus.open.name,
      'correctiveActionPlan': '',
      'correctiveActionOwner': '',
      'resolutionEvidence': '',
      'reportedBy': actorId,
      'reportedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setCorrectiveAction(
    ComplianceViolation violation, {
    required String plan,
    required String owner,
    required DateTime dueAt,
  }) {
    if (plan.trim().isEmpty || owner.trim().isEmpty) {
      throw StateError('Corrective action and owner are required.');
    }
    if (_useApi) {
      return _api.patch('/api/v1/compliance/violations/${violation.id}/corrective-action', {
        'plan': plan.trim(), 'owner': owner.trim(), 'dueAt': dueAt.toUtc().toIso8601String(),
      }).then((_) {});
    }
    return _db.collection('complianceViolations').doc(violation.id).update({
      'status': ComplianceViolationStatus.correctiveAction.name,
      'correctiveActionPlan': plan.trim(),
      'correctiveActionOwner': owner.trim(),
      'correctiveActionDueAt': Timestamp.fromDate(dueAt),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> resolveViolation(
    ComplianceViolation violation, {
    required String evidence,
    required String actorId,
  }) {
    if (evidence.trim().isEmpty) {
      throw StateError('Resolution evidence is required.');
    }
    if (_useApi) return _api.patch('/api/v1/compliance/violations/${violation.id}/resolve', {'evidence': evidence.trim()}).then((_) {});
    return _db.collection('complianceViolations').doc(violation.id).update({
      'status': ComplianceViolationStatus.resolved.name,
      'resolutionEvidence': evidence.trim(),
      'resolvedBy': actorId,
      'resolvedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> recordPenalty(
    ComplianceViolation violation, {
    required String referenceNumber,
    required double amount,
    required String currency,
    required DateTime dueAt,
    required String notes,
  }) async {
    if (amount < 0) throw StateError('Penalty cannot be negative.');
    if (_useApi) {
      await _api.post('/api/v1/compliance/penalties', {
        'entityId': violation.entityName, 'entityType': 'organization', 'violationId': violation.id,
        'penaltyType': notes.trim().isEmpty ? 'Compliance violation' : notes.trim(),
        'referenceNumber': referenceNumber.trim(), 'amount': amount, 'currency': currency.trim(),
        'issuedAt': DateTime.now().toUtc().toIso8601String(), 'dueAt': dueAt.toUtc().toIso8601String(),
        'status': PenaltyStatus.issued.name, 'notes': notes.trim(),
      });
      return;
    }
    final write = _db.batch();
    write.set(_db.collection('penaltyRecords').doc(), {
      'violationId': violation.id,
      'referenceNumber': referenceNumber.trim(),
      'amount': amount,
      'currency': currency.trim(),
      'status': PenaltyStatus.issued.name,
      'dueAt': Timestamp.fromDate(dueAt),
      'notes': notes.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    write.update(_db.collection('complianceViolations').doc(violation.id), {
      'status': ComplianceViolationStatus.penalized.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await write.commit();
  }

  Future<void> updatePenaltyStatus(
    PenaltyRecord penalty,
    PenaltyStatus status,
  ) => _useApi ? _api.patch('/api/v1/compliance/penalties/${penalty.id}/status', {'status': status.name}).then((_) {}) : _db.collection('penaltyRecords').doc(penalty.id).update({
    'status': status.name,
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<List<String>> _upload(
    String recordId,
    String folder,
    List<Uint8List> files,
  ) async {
    return CloudinaryUploadService.instance.uploadImages(
      files,
      scope: 'compliance',
    );
  }
}
