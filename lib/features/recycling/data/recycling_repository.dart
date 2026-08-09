import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';

import '../../inventory/domain/inventory_item.dart';
import '../domain/recycling_batch.dart';

class RecyclingRepository {
  RecyclingRepository({FirebaseFirestore? firestore, ApiClient? apiClient})
    : _db = firestore ?? FirebaseFirestore.instance,
      _api = apiClient ?? ApiClient.instance,
      _useApi = apiClient != null || (firestore == null && ApiConfig.enabled);
  final FirebaseFirestore _db;
  final ApiClient _api;
  final bool _useApi;

  CollectionReference<Map<String, dynamic>> get _batches =>
      _db.collection('recyclingBatches');

  Stream<List<RecyclingBatch>> watchBatches() => _useApi
      ? _pollBatches()
      : _batches.snapshots().map(
          (snapshot) => snapshot.docs.map(RecyclingBatch.fromDoc).toList()
            ..sort(
              (a, b) => b.createdAt?.compareTo(a.createdAt ?? DateTime(0)) ?? 0,
            ),
        );
  Stream<List<RecyclingBatch>> _pollBatches() async* {
    while (true) {
      final data = await _api.getList('/api/v1/recycling/batches');
      yield data.map(RecyclingBatch.fromJson).toList()..sort(
        (a, b) => b.createdAt?.compareTo(a.createdAt ?? DateTime(0)) ?? 0,
      );
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<RecyclingBatch> watchBatch(String id) => _useApi
      ? _pollBatch(id)
      : _batches
            .doc(id)
            .snapshots()
            .where((document) => document.exists)
            .map(RecyclingBatch.fromDoc);
  Stream<RecyclingBatch> _pollBatch(String id) async* {
    while (true) {
      yield RecyclingBatch.fromJson(
        await _api.get('/api/v1/recycling/batches/$id'),
      );
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<List<RecyclingProcessRecord>> watchProcessRecords(String id) => _useApi
      ? _pollProcessRecords(id)
      : _batches
            .doc(id)
            .collection('processRecords')
            .orderBy('createdAt', descending: true)
            .snapshots()
            .map(
              (snapshot) =>
                  snapshot.docs.map(RecyclingProcessRecord.fromDoc).toList(),
            );
  Stream<List<RecyclingProcessRecord>> _pollProcessRecords(String id) async* {
    while (true) {
      final data = await _api.getList(
        '/api/v1/recycling/batches/$id/process-records',
      );
      yield data.map(RecyclingProcessRecord.fromJson).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<List<FinalDisposalRecord>> watchDisposals(String id) => _useApi
      ? _pollDisposals(id)
      : _batches
            .doc(id)
            .collection('finalDisposals')
            .orderBy('createdAt', descending: true)
            .snapshots()
            .map(
              (snapshot) =>
                  snapshot.docs.map(FinalDisposalRecord.fromDoc).toList(),
            );
  Stream<List<FinalDisposalRecord>> _pollDisposals(String id) async* {
    while (true) {
      final data = await _api.getList(
        '/api/v1/recycling/batches/$id/disposals',
      );
      yield data.map(FinalDisposalRecord.fromJson).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Future<void> createBatch({
    required List<InventoryItem> items,
    required String facilityId,
    required String facilityName,
    required String actorId,
  }) async {
    if (items.isEmpty) throw ArgumentError('Select at least one item.');
    if (_useApi) {
      await _api.post('/api/v1/recycling/batches', {
        'itemIds': items.map((item) => item.id).toList(),
        'facilityId': facilityId.trim(),
        'facilityName': facilityName.trim(),
      });
      return;
    }
    final batchRef = _batches.doc();
    final totalWeight = items.fold<double>(
      0,
      (total, item) => total + item.weight,
    );
    final write = _db.batch();
    write.set(batchRef, {
      'batchCode': 'REC-${batchRef.id.substring(0, 8).toUpperCase()}',
      'facilityId': facilityId.trim(),
      'facilityName': facilityName.trim(),
      'itemIds': items.map((item) => item.id).toList(),
      'itemCodes': items.map((item) => item.itemCode).toList(),
      'inputWeightKg': totalWeight,
      'recoveredWeightKg': 0,
      'hazardousWeightKg': 0,
      'disposedWeightKg': 0,
      'processingLossKg': 0,
      'stage': RecyclingStage.created.name,
      'completionVerified': false,
      'verificationNotes': '',
      'createdBy': actorId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    for (final item in items) {
      final itemRef = _db.collection('inventoryItems').doc(item.id);
      write.update(itemRef, {
        'processingStatus': ProcessingStatus.assignedForRecycling.name,
        'recyclingBatchId': batchRef.id,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      write.set(itemRef.collection('history').doc(), {
        'action': 'recyclingBatchAssigned',
        'details': 'Assigned to ${batchRef.id} at ${facilityName.trim()}',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await write.commit();
  }

  Future<void> assignFacility(
    RecyclingBatch batch, {
    required String facilityId,
    required String facilityName,
  }) async {
    if (_useApi) {
      await _api.patch('/api/v1/recycling/batches/${batch.id}/facility', {
        'facilityId': facilityId.trim(),
        'facilityName': facilityName.trim(),
      });
      return;
    }
    await _batches.doc(batch.id).update({
      'facilityId': facilityId.trim(),
      'facilityName': facilityName.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateStage(
    RecyclingBatch batch,
    RecyclingStage stage,
    String actorId,
  ) async {
    if (!batch.stage.nextStages.contains(stage)) {
      throw StateError(
        'Cannot move from ${batch.stage.label} to ${stage.label}.',
      );
    }
    if (_useApi) {
      await _api.patch('/api/v1/recycling/batches/${batch.id}/stage', {
        'stage': stage.name,
      });
      return;
    }
    final ref = _batches.doc(batch.id);
    final write = _db.batch();
    write.update(ref, {
      'stage': stage.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    write.set(ref.collection('processRecords').doc(), {
      'type': 'stageUpdated',
      'material': '',
      'component': stage.label,
      'quantity': 0,
      'weightKg': 0,
      'notes': 'Processing stage changed to ${stage.label}',
      'actorId': actorId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await write.commit();
  }

  Future<void> recordProcess(
    RecyclingBatch batch, {
    required String type,
    required String material,
    required String component,
    required int quantity,
    required double weightKg,
    required String notes,
    required String actorId,
  }) async {
    if (weightKg < 0 || quantity < 0) throw ArgumentError('Invalid quantity.');
    if (_useApi) {
      await _api.post('/api/v1/recycling/batches/${batch.id}/process-records', {
        'type': type,
        'material': material.trim(),
        'component': component.trim(),
        'quantity': quantity,
        'weightKg': weightKg,
        'notes': notes.trim(),
      });
      return;
    }
    await _batches.doc(batch.id).collection('processRecords').add({
      'type': type,
      'material': material.trim(),
      'component': component.trim(),
      'quantity': quantity,
      'weightKg': weightKg,
      'notes': notes.trim(),
      'actorId': actorId,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> recordLoss(
    RecyclingBatch batch, {
    required double weightKg,
    required String reason,
    required String actorId,
  }) async {
    if (weightKg <= 0 ||
        batch.accountedWeightKg + weightKg > batch.inputWeightKg) {
      throw StateError(
        'Loss must be positive and within the batch mass balance.',
      );
    }
    if (_useApi) {
      await _api.post('/api/v1/recycling/batches/${batch.id}/losses', {
        'weightKg': weightKg,
        'reason': reason.trim(),
      });
      return;
    }
    final ref = _batches.doc(batch.id);
    final write = _db.batch();
    write.update(ref, {
      'processingLossKg': FieldValue.increment(weightKg),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    write.set(ref.collection('processRecords').doc(), {
      'type': 'processingLoss',
      'material': '',
      'component': '',
      'quantity': 0,
      'weightKg': weightKg,
      'notes': reason.trim(),
      'actorId': actorId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await write.commit();
  }

  Future<void> recordOutput(
    RecyclingBatch batch, {
    required bool hazardous,
    required String material,
    required String component,
    required int quantity,
    required double weightKg,
    required String notes,
    required String actorId,
  }) async {
    if (weightKg <= 0 ||
        batch.accountedWeightKg + weightKg > batch.inputWeightKg) {
      throw StateError('Output weight exceeds the available batch balance.');
    }
    if (_useApi) {
      await _api.post('/api/v1/recycling/batches/${batch.id}/outputs', {
        'kind': hazardous ? 'hazardous' : 'recovered',
        'material': material.trim(),
        'component': component.trim(),
        'quantity': quantity,
        'weightKg': weightKg,
        'notes': notes.trim(),
      });
      return;
    }
    final ref = _batches.doc(batch.id);
    final field = hazardous ? 'hazardousWeightKg' : 'recoveredWeightKg';
    final write = _db.batch();
    write.update(ref, {
      field: FieldValue.increment(weightKg),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    write.set(ref.collection('processRecords').doc(), {
      'type': hazardous ? 'hazardousMaterialHandled' : 'materialRecovered',
      'material': material.trim(),
      'component': component.trim(),
      'quantity': quantity,
      'weightKg': weightKg,
      'notes': notes.trim(),
      'actorId': actorId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await write.commit();
  }

  Future<void> recordFinalDisposal(
    RecyclingBatch batch, {
    required String material,
    required double weightKg,
    required String facility,
    required String method,
    required String manifestNumber,
    required String actorId,
  }) async {
    if (weightKg <= 0 ||
        batch.accountedWeightKg + weightKg > batch.inputWeightKg) {
      throw StateError('Disposal weight exceeds the available batch balance.');
    }
    if (_useApi) {
      await _api.post('/api/v1/recycling/batches/${batch.id}/disposals', {
        'material': material.trim(),
        'weightKg': weightKg,
        'facility': facility.trim(),
        'method': method.trim(),
        'manifestNumber': manifestNumber.trim(),
      });
      return;
    }
    final ref = _batches.doc(batch.id);
    final write = _db.batch();
    write.update(ref, {
      'disposedWeightKg': FieldValue.increment(weightKg),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    write.set(ref.collection('finalDisposals').doc(), {
      'material': material.trim(),
      'weightKg': weightKg,
      'facility': facility.trim(),
      'method': method.trim(),
      'manifestNumber': manifestNumber.trim(),
      'actorId': actorId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await write.commit();
  }

  Future<void> verifyCompletion(
    RecyclingBatch batch, {
    required String notes,
    required String actorId,
  }) async {
    if (batch.accountedWeightKg > batch.inputWeightKg + .001) {
      throw StateError('Recorded outputs exceed the batch input weight.');
    }
    if (batch.unaccountedWeightKg > batch.inputWeightKg * .02) {
      throw StateError('Account for all but at most 2% of the input weight.');
    }
    if (_useApi) {
      await _api.patch('/api/v1/recycling/batches/${batch.id}/verify', {
        'notes': notes.trim(),
      });
      return;
    }
    final ref = _batches.doc(batch.id);
    final write = _db.batch();
    write.update(ref, {
      'stage': RecyclingStage.completed.name,
      'completionVerified': true,
      'verificationNotes': notes.trim(),
      'verifiedBy': actorId,
      'verifiedAt': FieldValue.serverTimestamp(),
      'completedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    for (final itemId in batch.itemIds) {
      final itemRef = _db.collection('inventoryItems').doc(itemId);
      write.update(itemRef, {
        'processingStatus': ProcessingStatus.recovered.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      write.set(itemRef.collection('history').doc(), {
        'action': 'recyclingCompleted',
        'details': 'Recycling completed in ${batch.code}',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await write.commit();
  }
}
