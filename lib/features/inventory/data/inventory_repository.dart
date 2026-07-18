import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../audit/data/audit_repository.dart';
import '../../audit/domain/audit_event.dart';
import '../domain/inventory_item.dart';

class InventoryRepository {
  InventoryRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseAuth? auth,
    AuditRepository? auditRepository,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _auth = auth ?? FirebaseAuth.instance {
    _audit = auditRepository ?? AuditRepository(firestore: _db, auth: _auth);
  }
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final FirebaseAuth _auth;
  late final AuditRepository _audit;
  Stream<List<InventoryItem>> watchItems() => _db
      .collection('inventoryItems')
      .snapshots()
      .map(
        (s) =>
            s.docs.map(InventoryItem.fromDoc).toList()
              ..sort((a, b) => a.itemCode.compareTo(b.itemCode)),
      );
  Stream<InventoryItem> watchItem(String id) => _db
      .collection('inventoryItems')
      .doc(id)
      .snapshots()
      .where((d) => d.exists)
      .map(InventoryItem.fromDoc);
  Stream<List<InventoryEvent>> watchHistory(String id) => _db
      .collection('inventoryItems')
      .doc(id)
      .collection('history')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(InventoryEvent.fromDoc).toList());
  Stream<List<InventoryBatch>> watchBatches() => _db
      .collection('inventoryBatches')
      .snapshots()
      .map((s) => s.docs.map(InventoryBatch.fromDoc).toList());
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
    final item = _db.collection('inventoryItems').doc();
    final code =
        'ECO-${DateTime.now().year}-${item.id.substring(0, 8).toUpperCase()}';
    final urls = <String>[];
    for (var i = 0; i < images.length; i++) {
      final ref = _storage.ref('inventoryImages/${item.id}/$i.jpg');
      await ref.putData(images[i], SettableMetadata(contentType: 'image/jpeg'));
      urls.add(await ref.getDownloadURL());
    }
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

  Future<String> createBatch({
    required String name,
    required String location,
  }) async {
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
}
