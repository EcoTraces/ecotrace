import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';
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
  factory TraceEvent.fromJson(Map<String, dynamic> x) => TraceEvent(
    type: x['type']?.toString() ?? '',
    from: x['from']?.toString() ?? '',
    to: x['to']?.toString() ?? '',
    actor: x['actor']?.toString() ?? '',
    notes: x['notes']?.toString() ?? '',
    at: DateTime.tryParse(x['createdAt']?.toString() ?? ''),
  );
}

class TraceabilityRepository {
  TraceabilityRepository({FirebaseFirestore? firestore, ApiClient? apiClient})
    : _db = firestore ?? FirebaseFirestore.instance,
      _api = apiClient ?? ApiClient.instance,
      _useApi = apiClient != null || (firestore == null && ApiConfig.enabled);
  final FirebaseFirestore _db;
  final ApiClient _api;
  final bool _useApi;
  Stream<List<TraceEvent>> watch(String id) => _useApi
      ? _poll(id)
      : _db
            .collection('inventoryItems')
            .doc(id)
            .collection('traceability')
            .orderBy('createdAt', descending: true)
            .snapshots()
            .map((s) => s.docs.map(TraceEvent.fromDoc).toList());
  Stream<List<TraceEvent>> _poll(String id) async* {
    while (true) {
      final data = await _api.getList(
        '/api/v1/inventory/items/$id/traceability',
      );
      yield data.map(TraceEvent.fromJson).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Future<InventoryItem?> findByCode(String code) async {
    if (_useApi) {
      try {
        return InventoryItem.fromJson(
          await _api.get(
            '/api/v1/inventory/items/by-code/${Uri.encodeComponent(code)}',
          ),
        );
      } on ApiException catch (error) {
        if (error.statusCode == 404) return null;
        rethrow;
      }
    }
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
    if (_useApi) {
      await _api.post('/api/v1/inventory/items/${item.id}/traceability', {
        'type': type,
        'destination': destination,
        'actor': actor.trim(),
        'notes': notes.trim(),
        'updateLocation': updateLocation,
      });
      return;
    }
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
