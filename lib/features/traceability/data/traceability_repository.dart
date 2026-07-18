import 'package:cloud_firestore/cloud_firestore.dart';
import '../../inventory/domain/inventory_item.dart';

class TraceEvent {
  const TraceEvent({
    required this.type,
    required this.from,
    required this.to,
    required this.actor,
    required this.notes,
    required this.at,
  });
  final String type, from, to, actor, notes;
  final DateTime? at;
  factory TraceEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final x = d.data()!;
    return TraceEvent(
      type: x['type'] ?? '',
      from: x['from'] ?? '',
      to: x['to'] ?? '',
      actor: x['actor'] ?? '',
      notes: x['notes'] ?? '',
      at: (x['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class TraceabilityRepository {
  TraceabilityRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;
  Stream<List<TraceEvent>> watch(String id) => _db
      .collection('inventoryItems')
      .doc(id)
      .collection('traceability')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(TraceEvent.fromDoc).toList());
  Future<InventoryItem?> findByCode(String code) async {
    final q = await _db
        .collection('inventoryItems')
        .where('itemCode', isEqualTo: code)
        .limit(1)
        .get();
    return q.docs.isEmpty ? null : InventoryItem.fromDoc(q.docs.first);
  }

  Future<void> record(
    InventoryItem item, {
    required String type,
    required String destination,
    required String actor,
    required String notes,
    bool updateLocation = true,
  }) async {
    final root = _db.collection('inventoryItems').doc(item.id);
    final batch = _db.batch();
    if (updateLocation) {
      batch.update(root, {
        'currentLocation': destination,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    batch.set(root.collection('traceability').doc(), {
      'type': type,
      'from': item.location,
      'to': destination,
      'actor': actor.trim(),
      'notes': notes.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(root.collection('history').doc(), {
      'action': type,
      'details': '${item.location} → $destination: ${notes.trim()}',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }
}
