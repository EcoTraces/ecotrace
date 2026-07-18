import 'package:cloud_firestore/cloud_firestore.dart';

import '../../inventory/domain/inventory_item.dart';
import '../domain/recycling_batch.dart';

class RecyclingRepository {
  RecyclingRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _batches =>
      _db.collection('recyclingBatches');

  Stream<List<RecyclingBatch>> watchBatches() => _batches.snapshots().map(
    (snapshot) => snapshot.docs.map(RecyclingBatch.fromDoc).toList()
      ..sort((a, b) => b.createdAt?.compareTo(a.createdAt ?? DateTime(0)) ?? 0),
  );
  Stream<RecyclingBatch> watchBatch(String id) => _batches
      .doc(id)
      .snapshots()
      .where((document) => document.exists)
      .map(RecyclingBatch.fromDoc);
  Stream<List<RecyclingProcessRecord>> watchProcessRecords(String id) =>
      _batches
          .doc(id)
          .collection('processRecords')
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map(
            (snapshot) =>
                snapshot.docs.map(RecyclingProcessRecord.fromDoc).toList(),
          );
  Stream<List<FinalDisposalRecord>> watchDisposals(String id) => _batches
      .doc(id)
      .collection('finalDisposals')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs.map(FinalDisposalRecord.fromDoc).toList(),
      );

  Future<void> createBatch({
    required List<InventoryItem> items,
    required String facilityId,
    required String facilityName,
    required String actorId,
  }) async {
    if (items.isEmpty) throw ArgumentError('Select at least one item.');
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
  }) => _batches.doc(batch.id).update({
    'facilityId': facilityId.trim(),
    'facilityName': facilityName.trim(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<void> updateStage(
    RecyclingBatch batch,
    RecyclingStage stage,
    String actorId,
  ) async {
    if (stage.index < batch.stage.index &&
        stage != RecyclingStage.hazardousHandling) {
      throw StateError('Processing stages cannot move backwards.');
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
    final ref = _batches.doc(batch.id);
    final write = _db.batch();
    write.update(ref, {
      'disposedWeightKg': FieldValue.increment(weightKg),
      'stage': RecyclingStage.finalDisposal.name,
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
