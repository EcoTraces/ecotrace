import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';
import '../../../core/media/cloudinary_upload_service.dart';
import '../../audit/data/audit_repository.dart';
import '../../audit/domain/audit_event.dart';
import '../domain/inventory_item.dart';

class InventoryRepository {
  InventoryRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    AuditRepository? auditRepository,
    ApiClient? apiClient,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _api = apiClient ?? ApiClient.instance,
       _useApi =
           apiClient != null ||
           (firestore == null && auth == null && ApiConfig.enabled) {
    _audit = auditRepository ?? AuditRepository(firestore: _db, auth: _auth);
  }
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final ApiClient _api;
  final bool _useApi;
  late final AuditRepository _audit;
  Stream<List<InventoryItem>> watchItems() => _useApi
      ? _pollItems()
      : _db
            .collection('inventoryItems')
            .snapshots()
            .map(
              (s) =>
                  s.docs.map(InventoryItem.fromDoc).toList()
                    ..sort((a, b) => a.itemCode.compareTo(b.itemCode)),
            );

  Future<InventorySummary> summary() async {
    if (_useApi) {
      return InventorySummary.fromJson(
        await _api.get('/api/v1/inventory/summary'),
      );
    }
    final items = await _db.collection('inventoryItems').get();
    final batches = await _db.collection('inventoryBatches').count().get();
    final conditions = <String, int>{}, statuses = <String, int>{};
    var weight = 0.0, batched = 0;
    for (final item in items.docs) {
      final data = item.data();
      final condition = data['condition']?.toString() ?? 'unknown';
      final status = data['processingStatus']?.toString() ?? 'unknown';
      conditions[condition] = (conditions[condition] ?? 0) + 1;
      statuses[status] = (statuses[status] ?? 0) + 1;
      weight += (data['weight'] as num? ?? 0).toDouble();
      if (data['batchId'] != null) batched++;
    }
    return InventorySummary(
      totalItems: items.size,
      totalWeightKg: weight,
      batchedItems: batched,
      batches: batches.count ?? 0,
      byCondition: conditions,
      byStatus: statuses,
    );
  }

  Stream<List<InventoryItem>> _pollItems() async* {
    while (true) {
      final data = await _api.getList('/api/v1/inventory/items');
      yield data.map(InventoryItem.fromJson).toList()
        ..sort((a, b) => a.itemCode.compareTo(b.itemCode));
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<InventoryItem> watchItem(String id) => _useApi
      ? _pollItem(id)
      : _db
            .collection('inventoryItems')
            .doc(id)
            .snapshots()
            .where((d) => d.exists)
            .map(InventoryItem.fromDoc);
  Stream<InventoryItem> _pollItem(String id) async* {
    while (true) {
      final data = await _api.get('/api/v1/inventory/items/$id');
      yield InventoryItem.fromJson(data);
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Future<InventoryItem> findByCode(String code) async {
    if (_useApi) {
      final data = await _api.get(
        '/api/v1/inventory/items/by-code/${Uri.encodeComponent(code.trim())}',
      );
      return InventoryItem.fromJson(data);
    }
    final snapshot = await _db
        .collection('inventoryItems')
        .where('itemCode', isEqualTo: code.trim().toUpperCase())
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) {
      throw StateError('Inventory item not found.');
    }
    return InventoryItem.fromDoc(snapshot.docs.first);
  }

  Stream<List<InventoryEvent>> watchHistory(String id) => _useApi
      ? _pollHistory(id)
      : _db
            .collection('inventoryItems')
            .doc(id)
            .collection('history')
            .orderBy('createdAt', descending: true)
            .snapshots()
            .map((s) => s.docs.map(InventoryEvent.fromDoc).toList());
  Stream<List<InventoryEvent>> _pollHistory(String id) async* {
    while (true) {
      final data = await _api.getList('/api/v1/inventory/items/$id/history');
      yield data.map(InventoryEvent.fromJson).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<List<InventoryBatch>> watchBatches() => _useApi
      ? _pollBatches()
      : _db
            .collection('inventoryBatches')
            .snapshots()
            .map((s) => s.docs.map(InventoryBatch.fromDoc).toList());
  Stream<List<InventoryBatch>> _pollBatches() async* {
    while (true) {
      final data = await _api.getList('/api/v1/inventory/batches');
      yield data.map(InventoryBatch.fromJson).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Future<String> register({
    required String deviceType,
    required String brand,
    required String model,
    required String serialNumber,
    required ItemCondition condition,
    required double weight,
    required String source,
    required String location,
    required List<Uint8List> images,
  }) async {
    final urls = await CloudinaryUploadService.instance.uploadImages(
      images,
      scope: 'inventory',
    );
    if (_useApi) {
      final result = await _api.post('/api/v1/inventory/items', {
        'deviceType': deviceType.trim(),
        'brand': brand.trim(),
        'model': model.trim(),
        'serialNumber': serialNumber.trim(),
        'condition': condition.name,
        'weight': weight,
        'source': source.trim(),
        'location': location.trim(),
        'imageUrls': urls,
      });
      return result['id']?.toString() ?? '';
    }
    final item = _db.collection('inventoryItems').doc();
    final code =
        'ECO-${DateTime.now().year}-${item.id.substring(0, 8).toUpperCase()}';
    final batch = _db.batch();
    batch.set(item, {
      'itemCode': code,
      'deviceType': deviceType.trim(),
      'brand': brand.trim(),
      'model': model.trim(),
      'serialNumber': serialNumber.trim(),
      'condition': condition.name,
      'weight': weight,
      'source': source.trim(),
      'currentLocation': location.trim(),
      'processingStatus': ProcessingStatus.registered.name,
      'batchId': null,
      'imageUrls': urls,
      'barcodeValue': code,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(item.collection('history').doc(), {
      'action': 'registered',
      'details': 'Item registered at ${location.trim()}',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    await _audit.record(
      action: AuditAction.create,
      entityType: 'inventoryItem',
      entityId: item.id,
      description: 'Inventory item $code registered.',
      changes: {'location': location.trim(), 'weightKg': weight},
    );
    return item.id;
  }

  Future<void> updateState(
    InventoryItem item, {
    required ProcessingStatus status,
    required String location,
  }) async {
    if (_useApi) {
      await _api.patch('/api/v1/inventory/items/${item.id}/state', {
        'status': status.name,
        'location': location.trim(),
      });
      return;
    }
    final ref = _db.collection('inventoryItems').doc(item.id);
    final batch = _db.batch();
    batch.update(ref, {
      'processingStatus': status.name,
      'currentLocation': location.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(ref.collection('history').doc(), {
      'action': 'statusUpdated',
      'details': '${status.name} at ${location.trim()}',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    await _audit.record(
      action: AuditAction.itemMovement,
      entityType: 'inventoryItem',
      entityId: item.id,
      description: 'Item moved to ${location.trim()} as ${status.name}.',
      changes: {
        'location': {'before': item.location, 'after': location.trim()},
        'status': {'before': item.status.name, 'after': status.name},
      },
    );
  }

  Future<void> updateDetails(
    InventoryItem item, {
    required String deviceType,
    required String brand,
    required String model,
    required String serialNumber,
    required ItemCondition condition,
    required double weight,
    required String source,
  }) async {
    final data = <String, dynamic>{
      'deviceType': deviceType.trim(),
      'brand': brand.trim(),
      'model': model.trim(),
      'serialNumber': serialNumber.trim(),
      'condition': condition.name,
      'weight': weight,
      'source': source.trim(),
    };
    if (_useApi) {
      await _api.patch('/api/v1/inventory/items/${item.id}', data);
    } else {
      await _db.collection('inventoryItems').doc(item.id).update({
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<String> createBatch({
    required String name,
    required String location,
  }) async {
    if (_useApi) {
      final result = await _api.post('/api/v1/inventory/batches', {
        'name': name.trim(),
        'location': location.trim(),
      });
      return result['id']?.toString() ?? '';
    }
    final ref = _db.collection('inventoryBatches').doc();
    await ref.set({
      'batchCode': 'BAT-${ref.id.substring(0, 8).toUpperCase()}',
      'name': name.trim(),
      'currentLocation': location.trim(),
      'processingStatus': 'registered',
      'itemCount': 0,
      'totalWeight': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> assignBatch(InventoryItem item, String batchId) async {
    if (_useApi) {
      await _api.patch('/api/v1/inventory/items/${item.id}/batch', {
        'batchId': batchId,
      });
      return;
    }
    final ref = _db.collection('inventoryItems').doc(item.id);
    final batch = _db.batch();
    batch.update(ref, {
      'batchId': batchId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(ref.collection('history').doc(), {
      'action': 'batchAssigned',
      'details': 'Assigned to batch $batchId',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    await _audit.record(
      action: AuditAction.itemMovement,
      entityType: 'inventoryItem',
      entityId: item.id,
      description: 'Item assigned to inventory batch $batchId.',
      changes: {
        'batchId': {'before': item.batchId, 'after': batchId},
      },
    );
  }

  Future<void> unassignBatch(InventoryItem item) async {
    if (_useApi) {
      await _api.patch('/api/v1/inventory/items/${item.id}/batch', {
        'batchId': null,
      });
      return;
    }
    await _db.collection('inventoryItems').doc(item.id).update({
      'batchId': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateBatch(
    InventoryBatch batch, {
    required String name,
    required String location,
    required ProcessingStatus status,
    required bool closed,
  }) async {
    final data = {
      'name': name.trim(),
      'location': location.trim(),
      'status': status.name,
      'closed': closed,
    };
    if (_useApi) {
      await _api.patch('/api/v1/inventory/batches/${batch.id}', data);
    } else {
      await _db.collection('inventoryBatches').doc(batch.id).update({
        'name': name.trim(),
        'currentLocation': location.trim(),
        'processingStatus': status.name,
        'closed': closed,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> replaceImages(String id, List<Uint8List> images) async {
    final urls = await CloudinaryUploadService.instance.uploadImages(
      images,
      scope: 'inventory',
    );
    if (_useApi) {
      await _api.patch('/api/v1/inventory/items/$id/images', {
        'imageUrls': urls,
      });
      return;
    }
    await _db.collection('inventoryItems').doc(id).update({
      'imageUrls': urls,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
