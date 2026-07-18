import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../domain/compliance_record.dart';

class ComplianceRepository {
  ComplianceRepository({FirebaseFirestore? firestore, FirebaseStorage? storage})
    : _db = firestore ?? FirebaseFirestore.instance,
      _storage = storage ?? FirebaseStorage.instance;
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  Stream<List<RegulatoryBody>> watchRegulatoryBodies() =>
      _watch('regulatoryBodies', RegulatoryBody.fromDoc);
  Stream<List<ComplianceDocument>> watchDocuments() =>
      _watch('complianceDocuments', ComplianceDocument.fromDoc);
  Stream<List<ComplianceRequirement>> watchRequirements() =>
      _watch('complianceRequirements', ComplianceRequirement.fromDoc);
  Stream<List<ComplianceInspection>> watchInspections() =>
      _watch('complianceInspections', ComplianceInspection.fromDoc);
  Stream<List<ComplianceViolation>> watchViolations() =>
      _watch('complianceViolations', ComplianceViolation.fromDoc);
  Stream<List<PenaltyRecord>> watchPenalties() =>
      _watch('compliancePenalties', PenaltyRecord.fromDoc);

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
  ) => _db.collection('complianceDocuments').doc(document.id).update({
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
    final write = _db.batch();
    write.set(_db.collection('compliancePenalties').doc(), {
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
  ) => _db.collection('compliancePenalties').doc(penalty.id).update({
    'status': status.name,
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<List<String>> _upload(
    String recordId,
    String folder,
    List<Uint8List> files,
  ) async {
    final urls = <String>[];
    for (var index = 0; index < files.length; index++) {
      final ref = _storage.ref(
        'compliance/$folder/$recordId/${DateTime.now().millisecondsSinceEpoch}-$index.jpg',
      );
      await ref.putData(
        files[index],
        SettableMetadata(contentType: 'image/jpeg'),
      );
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  }
}
