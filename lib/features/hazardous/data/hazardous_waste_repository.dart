import 'package:cloud_firestore/cloud_firestore.dart';

import '../../recycling/domain/recycling_batch.dart';
import '../domain/hazardous_waste.dart';

class HazardousWasteRepository {
  HazardousWasteRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;
  CollectionReference<Map<String, dynamic>> get _records =>
      _db.collection('hazardousWasteRecords');

  Stream<List<HazardousWasteRecord>> watchRecords() => _records.snapshots().map(
    (snapshot) => snapshot.docs.map(HazardousWasteRecord.fromDoc).toList()
      ..sort((a, b) => b.createdAt?.compareTo(a.createdAt ?? DateTime(0)) ?? 0),
  );
  Stream<HazardousWasteRecord> watchRecord(String id) => _records
      .doc(id)
      .snapshots()
      .where((document) => document.exists)
      .map(HazardousWasteRecord.fromDoc);
  Stream<List<HazardousIncident>> watchIncidents(String id) => _records
      .doc(id)
      .collection('incidents')
      .orderBy('reportedAt', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(HazardousIncident.fromDoc).toList());
  Stream<List<HazardousTransferRecord>> watchTransfers(String id) => _records
      .doc(id)
      .collection('transfers')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.docs.map(HazardousTransferRecord.fromDoc).toList(),
      );
  Stream<List<SafetyTrainingRecord>> watchTraining() => _db
      .collection('hazardousSafetyTraining')
      .orderBy('completedAt', descending: true)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs.map(SafetyTrainingRecord.fromDoc).toList(),
      );
  Stream<List<RecyclingBatch>> watchRecyclingBatches() => _db
      .collection('recyclingBatches')
      .snapshots()
      .map((snapshot) => snapshot.docs.map(RecyclingBatch.fromDoc).toList());
  Stream<List<Map<String, dynamic>>> watchComplianceDocuments(String id) =>
      _records
          .doc(id)
          .collection('complianceDocuments')
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());

  Future<void> identify({
    required RecyclingBatch? sourceBatch,
    required String sourceReference,
    required HazardousMaterialCategory category,
    required String classification,
    required double weightKg,
    required int quantity,
    required String safetyInstructions,
    required String actorId,
  }) async {
    if (weightKg <= 0 || quantity < 0) throw ArgumentError('Invalid quantity.');
    final record = _records.doc();
    if (sourceBatch == null) {
      await record.set(
        _newRecord(
          record,
          sourceBatchId: '',
          sourceReference: sourceReference,
          category: category,
          classification: classification,
          weightKg: weightKg,
          quantity: quantity,
          safetyInstructions: safetyInstructions,
          actorId: actorId,
        ),
      );
      return;
    }
    final batchRef = _db.collection('recyclingBatches').doc(sourceBatch.id);
    await _db.runTransaction((transaction) async {
      final current = RecyclingBatch.fromDoc(await transaction.get(batchRef));
      if (current.accountedWeightKg + weightKg > current.inputWeightKg) {
        throw StateError('Hazardous weight exceeds the batch mass balance.');
      }
      transaction.set(
        record,
        _newRecord(
          record,
          sourceBatchId: current.id,
          sourceReference: current.code,
          category: category,
          classification: classification,
          weightKg: weightKg,
          quantity: quantity,
          safetyInstructions: safetyInstructions,
          actorId: actorId,
        ),
      );
      transaction.update(batchRef, {
        'hazardousWeightKg': FieldValue.increment(weightKg),
        'stage': RecyclingStage.hazardousHandling.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Map<String, dynamic> _newRecord(
    DocumentReference<Map<String, dynamic>> record, {
    required String sourceBatchId,
    required String sourceReference,
    required HazardousMaterialCategory category,
    required String classification,
    required double weightKg,
    required int quantity,
    required String safetyInstructions,
    required String actorId,
  }) => {
    'wasteCode': 'HAZ-${record.id.substring(0, 8).toUpperCase()}',
    'sourceBatchId': sourceBatchId,
    'sourceReference': sourceReference.trim(),
    'category': category.name,
    'classification': classification.trim(),
    'weightKg': weightKg,
    'quantity': quantity,
    'storageLocation': '',
    'safetyInstructions': safetyInstructions.trim(),
    'ppeChecklist': <String, bool>{},
    'disposalFacility': '',
    'status': HazardousWasteStatus.identified.name,
    'certificateNumber': '',
    'identifiedBy': actorId,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  Future<void> assignStorage(
    HazardousWasteRecord record, {
    required String location,
    required String safetyInstructions,
  }) => _records.doc(record.id).update({
    'storageLocation': location.trim(),
    'safetyInstructions': safetyInstructions.trim(),
    'status': HazardousWasteStatus.stored.name,
    'storedAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<void> recordPpeChecklist(
    HazardousWasteRecord record,
    Map<String, bool> checklist,
    String actorId,
  ) => _records.doc(record.id).update({
    'ppeChecklist': checklist,
    'ppeCheckedBy': actorId,
    'ppeCheckedAt': FieldValue.serverTimestamp(),
    'status': checklist.values.every((value) => value)
        ? HazardousWasteStatus.secured.name
        : record.status.name,
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<void> recordBatteryHandling(
    HazardousWasteRecord record, {
    required bool terminalsInsulated,
    required bool damagedIsolated,
    required bool chargeProtected,
    required String notes,
    required String actorId,
  }) => _records.doc(record.id).collection('handlingRecords').add({
    'type': 'batteryHandling',
    'terminalsInsulated': terminalsInsulated,
    'damagedIsolated': damagedIsolated,
    'chargeProtected': chargeProtected,
    'notes': notes.trim(),
    'actorId': actorId,
    'createdAt': FieldValue.serverTimestamp(),
  });

  Future<void> reportIncident(
    HazardousWasteRecord record, {
    required IncidentSeverity severity,
    required String description,
    required String emergencyActions,
    required String actorId,
  }) async {
    final ref = _records.doc(record.id);
    final write = _db.batch();
    write.update(ref, {
      'status': HazardousWasteStatus.incidentHold.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    write.set(ref.collection('incidents').doc(), {
      'severity': severity.name,
      'description': description.trim(),
      'emergencyActions': emergencyActions.trim(),
      'status': IncidentStatus.reported.name,
      'reportedBy': actorId,
      'reportedAt': FieldValue.serverTimestamp(),
    });
    await write.commit();
  }

  Future<void> updateEmergencyResponse(
    HazardousWasteRecord record,
    HazardousIncident incident, {
    required IncidentStatus status,
    required String actions,
    required String actorId,
  }) async {
    final incidentRef = _records
        .doc(record.id)
        .collection('incidents')
        .doc(incident.id);
    final write = _db.batch();
    write.update(incidentRef, {
      'status': status.name,
      'emergencyActions': actions.trim(),
      'lastResponderId': actorId,
      'updatedAt': FieldValue.serverTimestamp(),
      if (status == IncidentStatus.closed)
        'closedAt': FieldValue.serverTimestamp(),
    });
    if (status == IncidentStatus.closed) {
      write.update(_records.doc(record.id), {
        'status': HazardousWasteStatus.stored.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await write.commit();
  }

  Future<void> addComplianceDocument(
    HazardousWasteRecord record, {
    required String title,
    required String reference,
    required DateTime? expiresAt,
    required String notes,
    required String actorId,
  }) => _records.doc(record.id).collection('complianceDocuments').add({
    'title': title.trim(),
    'reference': reference.trim(),
    'expiresAt': expiresAt == null ? null : Timestamp.fromDate(expiresAt),
    'notes': notes.trim(),
    'recordedBy': actorId,
    'createdAt': FieldValue.serverTimestamp(),
  });

  Future<void> assignDisposalFacility(
    HazardousWasteRecord record,
    String facility,
  ) => _records.doc(record.id).update({
    'disposalFacility': facility.trim(),
    'status': HazardousWasteStatus.transferApproved.name,
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<void> recordTransfer(
    HazardousWasteRecord record, {
    required String carrier,
    required String manifestNumber,
    required String actorId,
  }) async {
    if (record.disposalFacility.isEmpty) {
      throw StateError('Assign a disposal facility first.');
    }
    final ref = _records.doc(record.id);
    final write = _db.batch();
    write.update(ref, {
      'status': HazardousWasteStatus.transferred.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    write.set(ref.collection('transfers').doc(), {
      'from': record.storageLocation,
      'to': record.disposalFacility,
      'carrier': carrier.trim(),
      'manifestNumber': manifestNumber.trim(),
      'actorId': actorId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await write.commit();
  }

  Future<void> completeDisposal(
    HazardousWasteRecord record, {
    required String method,
    required String receiptNumber,
    required String actorId,
  }) => _records.doc(record.id).update({
    'status': HazardousWasteStatus.disposed.name,
    'disposalMethod': method.trim(),
    'disposalReceiptNumber': receiptNumber.trim(),
    'disposedBy': actorId,
    'disposedAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<void> certify(HazardousWasteRecord record, String actorId) =>
      _records.doc(record.id).update({
        'status': HazardousWasteStatus.certified.name,
        'certificateNumber': 'HZC-${record.id.substring(0, 8).toUpperCase()}',
        'certifiedBy': actorId,
        'certifiedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> recordTraining({
    required String staffId,
    required String course,
    required DateTime completedAt,
    required DateTime expiresAt,
    required String certificateReference,
  }) => _db.collection('hazardousSafetyTraining').add({
    'staffId': staffId.trim(),
    'course': course.trim(),
    'completedAt': Timestamp.fromDate(completedAt),
    'expiresAt': Timestamp.fromDate(expiresAt),
    'certificateReference': certificateReference.trim(),
    'createdAt': FieldValue.serverTimestamp(),
  });
}
