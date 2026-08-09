import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';
import '../../recycling/domain/recycling_batch.dart';
import '../domain/hazardous_waste.dart';

class HazardousWasteRepository {
  HazardousWasteRepository({FirebaseFirestore? firestore, ApiClient? apiClient})
    : _db = firestore ?? FirebaseFirestore.instance,
      _api = apiClient ?? ApiClient.instance,
      _useApi = apiClient != null || (firestore == null && ApiConfig.enabled);
  final FirebaseFirestore _db;
  final ApiClient _api;
  final bool _useApi;
  CollectionReference<Map<String, dynamic>> get _records =>
      _db.collection('hazardousWasteRecords');

  Stream<List<HazardousWasteRecord>> watchRecords() => _useApi
      ? _pollRecords()
      : _records.snapshots().map(
          (snapshot) => snapshot.docs.map(HazardousWasteRecord.fromDoc).toList()
            ..sort(
              (a, b) => b.createdAt?.compareTo(a.createdAt ?? DateTime(0)) ?? 0,
            ),
        );
  Stream<List<HazardousWasteRecord>> _pollRecords() async* {
    while (true) {
      final data = await _api.getList('/api/v1/hazardous/records');
      yield data.map(HazardousWasteRecord.fromJson).toList()..sort(
        (a, b) => b.createdAt?.compareTo(a.createdAt ?? DateTime(0)) ?? 0,
      );
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<HazardousWasteRecord> watchRecord(String id) => _useApi
      ? _pollRecord(id)
      : _records
            .doc(id)
            .snapshots()
            .where((document) => document.exists)
            .map(HazardousWasteRecord.fromDoc);
  Stream<HazardousWasteRecord> _pollRecord(String id) async* {
    while (true) {
      yield HazardousWasteRecord.fromJson(
        await _api.get('/api/v1/hazardous/records/$id'),
      );
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<List<HazardousIncident>> watchIncidents(String id) => _useApi
      ? _pollIncidents(id)
      : _records
            .doc(id)
            .collection('incidents')
            .orderBy('reportedAt', descending: true)
            .snapshots()
            .map(
              (snapshot) =>
                  snapshot.docs.map(HazardousIncident.fromDoc).toList(),
            );
  Stream<List<HazardousIncident>> _pollIncidents(String id) async* {
    while (true) {
      final data = await _api.getList('/api/v1/hazardous/incidents');
      yield data
          .where((item) => item['recordId']?.toString() == id)
          .map(HazardousIncident.fromJson)
          .toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<List<HazardousTransferRecord>> watchTransfers(String id) => _useApi
      ? _pollTransfers(id)
      : _records
            .doc(id)
            .collection('transfers')
            .orderBy('createdAt', descending: true)
            .snapshots()
            .map(
              (snapshot) =>
                  snapshot.docs.map(HazardousTransferRecord.fromDoc).toList(),
            );
  Stream<List<HazardousTransferRecord>> _pollTransfers(String id) async* {
    while (true) {
      final data = await _api.getList(
        '/api/v1/hazardous/records/$id/transfers',
      );
      yield data.map(HazardousTransferRecord.fromJson).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<List<SafetyTrainingRecord>> watchTraining() => _useApi
      ? _pollTraining()
      : _db
            .collection('hazardousSafetyTraining')
            .orderBy('completedAt', descending: true)
            .snapshots()
            .map(
              (snapshot) =>
                  snapshot.docs.map(SafetyTrainingRecord.fromDoc).toList(),
            );
  Stream<List<SafetyTrainingRecord>> _pollTraining() async* {
    while (true) {
      final data = await _api.getList('/api/v1/hazardous/training-records');
      yield data.map(SafetyTrainingRecord.fromJson).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<List<RecyclingBatch>> watchRecyclingBatches() => _db
      .collection('recyclingBatches')
      .snapshots()
      .map((snapshot) => snapshot.docs.map(RecyclingBatch.fromDoc).toList());
  Stream<List<Map<String, dynamic>>> watchComplianceDocuments(String id) =>
      _useApi
      ? _pollComplianceDocuments(id)
      : _records
            .doc(id)
            .collection('complianceDocuments')
            .orderBy('createdAt', descending: true)
            .snapshots()
            .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  Stream<List<Map<String, dynamic>>> _pollComplianceDocuments(
    String id,
  ) async* {
    while (true) {
      yield await _api.getList(
        '/api/v1/hazardous/records/$id/compliance-documents',
      );
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

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
    if (_useApi) {
      await _api.post('/api/v1/hazardous/records', {
        'sourceType': sourceBatch == null ? 'manual' : 'recyclingBatch',
        'sourceId': sourceBatch?.id ?? sourceReference.trim(),
        'classification': _apiClassification(category),
        'description': classification.trim(),
        'weightKg': weightKg,
        'quantity': quantity,
        'riskLevel': _riskLevel(category),
        'storageLocation': 'Pending assignment',
        'safetyInstructions': safetyInstructions
            .split(RegExp(r'[\n;]+'))
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(),
      });
      return;
    }
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
  }) {
    if (_useApi) {
      return _api
          .patch('/api/v1/hazardous/records/${record.id}/storage', {
            'storageLocation': location.trim(),
            'containmentType': 'Approved hazardous-waste containment',
            'inspectionDueAt': DateTime.now()
                .add(const Duration(days: 30))
                .toIso8601String(),
            'safetyInstructions': safetyInstructions
                .split(RegExp(r'[\n;]+'))
                .map((item) => item.trim())
                .where((item) => item.isNotEmpty)
                .toList(),
          })
          .then((_) {});
    }
    return _records.doc(record.id).update({
      'storageLocation': location.trim(),
      'safetyInstructions': safetyInstructions.trim(),
      'status': HazardousWasteStatus.stored.name,
      'storedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> recordPpeChecklist(
    HazardousWasteRecord record,
    Map<String, bool> checklist,
    String actorId,
  ) {
    if (_useApi) {
      return _api
          .post('/api/v1/hazardous/records/${record.id}/safety-checks', {
            'ppeItems': checklist.entries
                .map((entry) => {'name': entry.key, 'checked': entry.value})
                .toList(),
            'instructionsAcknowledged': true,
            'notes': '',
          })
          .then((_) {});
    }
    return _records.doc(record.id).update({
      'ppeChecklist': checklist,
      'ppeCheckedBy': actorId,
      'ppeCheckedAt': FieldValue.serverTimestamp(),
      'status': checklist.values.every((value) => value)
          ? HazardousWasteStatus.secured.name
          : record.status.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> recordBatteryHandling(
    HazardousWasteRecord record, {
    required bool terminalsInsulated,
    required bool damagedIsolated,
    required bool chargeProtected,
    required String notes,
    required String actorId,
  }) {
    if (_useApi) {
      return _api
          .post('/api/v1/hazardous/records/${record.id}/battery-handling', {
            'batteryType': record.classification.isEmpty
                ? record.category.label
                : record.classification,
            'damaged': damagedIsolated,
            'terminalsIsolated': terminalsInsulated,
            'fireproofContainer': chargeProtected,
            'notes': notes.trim(),
          })
          .then((_) {});
    }
    return _records
        .doc(record.id)
        .collection('handlingRecords')
        .add({
          'type': 'batteryHandling',
          'terminalsInsulated': terminalsInsulated,
          'damagedIsolated': damagedIsolated,
          'chargeProtected': chargeProtected,
          'notes': notes.trim(),
          'actorId': actorId,
          'createdAt': FieldValue.serverTimestamp(),
        })
        .then((_) {});
  }

  Future<void> reportIncident(
    HazardousWasteRecord record, {
    required IncidentSeverity severity,
    required String description,
    required String emergencyActions,
    required String actorId,
  }) async {
    if (_useApi) {
      await _api.post('/api/v1/hazardous/incidents', {
        'recordId': record.id,
        'type': 'other',
        'severity': _apiSeverity(severity),
        'location': record.storageLocation.isEmpty
            ? 'Unknown location'
            : record.storageLocation,
        'description': description.trim(),
        'immediateActions': emergencyActions
            .split(RegExp(r'[\n;]+'))
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(),
        'evidenceUrls': <String>[],
        'staffIds': <String>[],
      });
      return;
    }
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
    if (_useApi) {
      await _api.patch('/api/v1/hazardous/incidents/${incident.id}/response', {
        'responseStatus': status.name,
        'actions': actions
            .split(RegExp(r'[\n;]+'))
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(),
        'emergencyContact': '',
        'rootCause': '',
        'correctiveActions': <String>[],
      });
      return;
    }
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
  }) {
    if (_useApi) {
      return _api
          .post('/api/v1/hazardous/records/${record.id}/compliance-documents', {
            'title': title.trim(),
            'reference': reference.trim(),
            'expiresAt': expiresAt?.toIso8601String(),
            'notes': notes.trim(),
          })
          .then((_) {});
    }
    return _records
        .doc(record.id)
        .collection('complianceDocuments')
        .add({
          'title': title.trim(),
          'reference': reference.trim(),
          'expiresAt': expiresAt == null ? null : Timestamp.fromDate(expiresAt),
          'notes': notes.trim(),
          'recordedBy': actorId,
          'createdAt': FieldValue.serverTimestamp(),
        })
        .then((_) {});
  }

  Future<void> assignDisposalFacility(
    HazardousWasteRecord record,
    String facility,
  ) {
    if (_useApi) {
      return _api
          .patch('/api/v1/hazardous/records/${record.id}/disposal-facility', {
            'facilityId': facility.trim(),
            'facilityName': facility.trim(),
          })
          .then((_) {});
    }
    return _records.doc(record.id).update({
      'disposalFacility': facility.trim(),
      'status': HazardousWasteStatus.transferApproved.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> recordTransfer(
    HazardousWasteRecord record, {
    required String carrier,
    required String manifestNumber,
    required String actorId,
  }) async {
    if (record.disposalFacility.isEmpty) {
      throw StateError('Assign a disposal facility first.');
    }
    if (_useApi) {
      await _api.post('/api/v1/hazardous/records/${record.id}/transfers', {
        'destinationFacilityId': record.disposalFacility,
        'destinationFacilityName': record.disposalFacility,
        'carrier': carrier.trim(),
        'manifestNumber': manifestNumber.trim(),
        'weightKg': record.weightKg,
        'driverName': 'Recorded carrier driver',
        'vehicleRegistration': 'Recorded in manifest',
      });
      return;
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
  }) {
    if (_useApi) {
      return _api
          .patch('/api/v1/hazardous/records/${record.id}/disposal', {
            'facilityId': record.disposalFacility,
            'facilityName': record.disposalFacility,
            'method': method.trim(),
            'disposedWeightKg': record.weightKg,
            'manifestNumber': receiptNumber.trim(),
            'receiptNumber': receiptNumber.trim(),
            'complianceDocumentUrls': <String>[],
          })
          .then((_) {});
    }
    return _records.doc(record.id).update({
      'status': HazardousWasteStatus.disposed.name,
      'disposalMethod': method.trim(),
      'disposalReceiptNumber': receiptNumber.trim(),
      'disposedBy': actorId,
      'disposedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> certify(HazardousWasteRecord record, String actorId) {
    if (_useApi) {
      return _api
          .post('/api/v1/hazardous/records/${record.id}/certificate', {})
          .then((_) {});
    }
    return _records.doc(record.id).update({
      'status': HazardousWasteStatus.certified.name,
      'certificateNumber': 'HZC-${record.id.substring(0, 8).toUpperCase()}',
      'certifiedBy': actorId,
      'certifiedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> recordTraining({
    required String staffId,
    required String course,
    required DateTime completedAt,
    required DateTime expiresAt,
    required String certificateReference,
  }) {
    if (_useApi) {
      return _api
          .post('/api/v1/hazardous/training-records', {
            'staffId': staffId.trim(),
            'courseName': course.trim(),
            'provider': 'EcoTrace approved provider',
            'completedAt': completedAt.toIso8601String(),
            'expiresAt': expiresAt.toIso8601String(),
            'certificateReference': certificateReference.trim(),
          })
          .then((_) {});
    }
    return _db
        .collection('hazardousSafetyTraining')
        .add({
          'staffId': staffId.trim(),
          'course': course.trim(),
          'completedAt': Timestamp.fromDate(completedAt),
          'expiresAt': Timestamp.fromDate(expiresAt),
          'certificateReference': certificateReference.trim(),
          'createdAt': FieldValue.serverTimestamp(),
        })
        .then((_) {});
  }
}

String _apiClassification(HazardousMaterialCategory category) =>
    switch (category) {
      HazardousMaterialCategory.lithiumBattery => 'lithium',
      HazardousMaterialCategory.leadAcidBattery => 'battery',
      HazardousMaterialCategory.mercury => 'mercury',
      HazardousMaterialCategory.lead => 'lead',
      HazardousMaterialCategory.cadmium => 'cadmium',
      HazardousMaterialCategory.toxicChemicals => 'other',
      HazardousMaterialCategory.crtGlass => 'other',
      HazardousMaterialCategory.contaminatedCircuitBoards => 'other',
      HazardousMaterialCategory.other => 'other',
    };

String _riskLevel(HazardousMaterialCategory category) => switch (category) {
  HazardousMaterialCategory.mercury ||
  HazardousMaterialCategory.lead ||
  HazardousMaterialCategory.cadmium => 'critical',
  HazardousMaterialCategory.lithiumBattery ||
  HazardousMaterialCategory.leadAcidBattery ||
  HazardousMaterialCategory.toxicChemicals => 'high',
  _ => 'medium',
};

String _apiSeverity(IncidentSeverity severity) => switch (severity) {
  IncidentSeverity.minor => 'low',
  IncidentSeverity.moderate => 'medium',
  IncidentSeverity.serious => 'high',
  IncidentSeverity.critical => 'critical',
};
