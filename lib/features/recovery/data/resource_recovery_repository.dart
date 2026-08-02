import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';

import '../../recycling/domain/recycling_batch.dart';
import '../domain/recovered_material.dart';

class ResourceRecoveryRepository {
  ResourceRecoveryRepository({
    FirebaseFirestore? firestore,
    ApiClient? apiClient,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _api = apiClient ?? ApiClient.instance,
       _useApi = apiClient != null || (firestore == null && ApiConfig.enabled);
  final FirebaseFirestore _db;
  final ApiClient _api;
  final bool _useApi;

  CollectionReference<Map<String, dynamic>> get _lots =>
      _db.collection('recoveredMaterialLots');

  Stream<List<RecoveredMaterialLot>> watchLots() => _useApi
      ? _pollLots()
      : _lots.snapshots().map(
          (snapshot) => snapshot.docs.map(RecoveredMaterialLot.fromDoc).toList()
            ..sort(
              (a, b) => b.createdAt?.compareTo(a.createdAt ?? DateTime(0)) ?? 0,
            ),
        );
  Stream<List<RecoveredMaterialLot>> _pollLots() async* {
    while (true) {
      final data = await _api.getList('/api/v1/recovery/lots');
      yield data.map(RecoveredMaterialLot.fromJson).toList()..sort(
        (a, b) => b.createdAt?.compareTo(a.createdAt ?? DateTime(0)) ?? 0,
      );
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<List<MaterialBuyer>> watchBuyers() => _useApi
      ? _pollBuyers()
      : _db
            .collection('materialBuyers')
            .snapshots()
            .map(
              (snapshot) =>
                  snapshot.docs.map(MaterialBuyer.fromDoc).toList()
                    ..sort((a, b) => a.name.compareTo(b.name)),
            );
  Stream<List<MaterialBuyer>> _pollBuyers() async* {
    while (true) {
      final data = await _api.getList('/api/v1/recovery/buyers');
      yield data.map(MaterialBuyer.fromJson).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<List<MaterialCategoryDefinition>> watchCategories() => _useApi
      ? _pollCategories()
      : _db
            .collection('materialCategories')
            .snapshots()
            .map(
              (snapshot) => snapshot.docs
                  .map(MaterialCategoryDefinition.fromDoc)
                  .toList(),
            );
  Stream<List<MaterialCategoryDefinition>> _pollCategories() async* {
    while (true) {
      final data = await _api.getList('/api/v1/recovery/categories');
      yield data.map(MaterialCategoryDefinition.fromJson).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<List<RecyclingBatch>> watchRecyclingBatches() => _useApi
      ? _pollBatches()
      : _db
            .collection('recyclingBatches')
            .snapshots()
            .map(
              (snapshot) => snapshot.docs.map(RecyclingBatch.fromDoc).toList(),
            );
  Stream<List<RecyclingBatch>> _pollBatches() async* {
    while (true) {
      final data = await _api.getList('/api/v1/recycling/batches');
      yield data.map(RecyclingBatch.fromJson).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<List<MaterialTransferRecord>> watchTransfers(String lotId) => _useApi
      ? _pollTransfers(lotId)
      : _lots
            .doc(lotId)
            .collection('transfers')
            .orderBy('createdAt', descending: true)
            .snapshots()
            .map(
              (snapshot) =>
                  snapshot.docs.map(MaterialTransferRecord.fromDoc).toList(),
            );
  Stream<List<MaterialTransferRecord>> _pollTransfers(String lotId) async* {
    while (true) {
      final data = await _api.getList('/api/v1/recovery/lots/$lotId/transfers');
      yield data.map(MaterialTransferRecord.fromJson).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Future<void> upsertCategory(
    RecoverableMaterial material, {
    required double defaultUnitValue,
    required bool active,
  }) async {
    if (_useApi) {
      await _api.patch('/api/v1/recovery/categories/${material.name}', {
        'defaultUnitValue': defaultUnitValue,
        'active': active,
      });
      return;
    }
    await _db.collection('materialCategories').doc(material.name).set({
      'material': material.name,
      'defaultUnitValue': defaultUnitValue,
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> addBuyer({
    required String name,
    required String contact,
    required List<RecoverableMaterial> materials,
  }) async {
    if (_useApi) {
      await _api.post('/api/v1/recovery/buyers', {
        'name': name.trim(),
        'contact': contact.trim(),
        'materials': materials.map((material) => material.name).toList(),
      });
      return;
    }
    await _db.collection('materialBuyers').add({
      'name': name.trim(),
      'contact': contact.trim(),
      'materials': materials.map((material) => material.name).toList(),
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> recordMaterial({
    required RecyclingBatch batch,
    required RecoverableMaterial material,
    required double weightKg,
    required int quantity,
    required MaterialQualityGrade qualityGrade,
    required String storageLocation,
    required double unitMarketValue,
    required String actorId,
  }) async {
    if (weightKg <= 0 || quantity < 0) throw ArgumentError('Invalid quantity.');
    if (_useApi) {
      await _api.post('/api/v1/recovery/lots', {
        'recyclingBatchId': batch.id,
        'material': material.name,
        'weightKg': weightKg,
        'quantity': quantity,
        'qualityGrade': qualityGrade.name,
        'storageLocation': storageLocation.trim(),
        'unitMarketValue': unitMarketValue,
      });
      return;
    }
    final batchRef = _db.collection('recyclingBatches').doc(batch.id);
    final lotRef = _lots.doc();
    await _db.runTransaction((transaction) async {
      final current = RecyclingBatch.fromDoc(await transaction.get(batchRef));
      if (current.accountedWeightKg + weightKg > current.inputWeightKg) {
        throw StateError('Recovered weight exceeds the batch mass balance.');
      }
      transaction.set(lotRef, {
        'lotCode': 'MAT-${lotRef.id.substring(0, 8).toUpperCase()}',
        'recyclingBatchId': current.id,
        'recyclingBatchCode': current.code,
        'material': material.name,
        'weightKg': weightKg,
        'quantity': quantity,
        'qualityGrade': qualityGrade.name,
        'storageLocation': storageLocation.trim(),
        'unitMarketValue': unitMarketValue,
        'buyerId': '',
        'status': MaterialLotStatus.stored.name,
        'saleRevenue': 0,
        'recordedBy': actorId,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(batchRef, {
        'recoveredWeightKg': FieldValue.increment(weightKg),
        'stage': RecyclingStage.materialRecovery.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> assignBuyer(RecoveredMaterialLot lot, String buyerId) async {
    if (_useApi) {
      await _api.patch('/api/v1/recovery/lots/${lot.id}/buyer', {
        'buyerId': buyerId,
      });
      return;
    }
    await _lots.doc(lot.id).update({
      'buyerId': buyerId,
      'status': MaterialLotStatus.reserved.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markSalesReady(RecoveredMaterialLot lot) async {
    if (_useApi) {
      await _api.patch('/api/v1/recovery/lots/${lot.id}/sales-ready', {});
      return;
    }
    await _lots.doc(lot.id).update({
      'status': MaterialLotStatus.salesReady.name,
      'salesReadyAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> recordTransfer(
    RecoveredMaterialLot lot, {
    required String destination,
    required String carrier,
    required String reference,
    required String actorId,
  }) async {
    if (_useApi) {
      await _api.post('/api/v1/recovery/lots/${lot.id}/transfers', {
        'destination': destination.trim(),
        'carrier': carrier.trim(),
        'reference': reference.trim(),
      });
      return;
    }
    final ref = _lots.doc(lot.id);
    final write = _db.batch();
    write.update(ref, {
      'storageLocation': destination.trim(),
      'status': MaterialLotStatus.transferred.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    write.set(ref.collection('transfers').doc(), {
      'from': lot.storageLocation,
      'to': destination.trim(),
      'weightKg': lot.weightKg,
      'carrier': carrier.trim(),
      'reference': reference.trim(),
      'actorId': actorId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await write.commit();
  }

  Future<void> recordSale(
    RecoveredMaterialLot lot, {
    required double revenue,
    required String actorId,
  }) async {
    if (_useApi) {
      await _api.post('/api/v1/recovery/lots/${lot.id}/sale', {
        'revenue': revenue,
      });
      return;
    }
    await _lots.doc(lot.id).update({
      'status': MaterialLotStatus.sold.name,
      'saleRevenue': revenue,
      'soldBy': actorId,
      'soldAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
