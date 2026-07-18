import 'package:cloud_firestore/cloud_firestore.dart';

enum ItemCondition {
  working,
  repairable,
  reusable,
  refurbishable,
  recyclable,
  hazardous,
  nonRecoverable,
}

enum ProcessingStatus {
  registered,
  received,
  inspecting,
  sorted,
  stored,
  assignedForRepair,
  repairing,
  refurbished,
  assignedForRecycling,
  recycling,
  recovered,
  disposed,
  quarantined,
}

class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.itemCode,
    required this.deviceType,
    required this.brand,
    required this.model,
    required this.serialNumber,
    required this.condition,
    required this.weight,
    required this.source,
    required this.location,
    required this.status,
    required this.batchId,
    required this.imageUrls,
  });
  final String id,
      itemCode,
      deviceType,
      brand,
      model,
      serialNumber,
      source,
      location;
  final ItemCondition condition;
  final double weight;
  final ProcessingStatus status;
  final String? batchId;
  final List<String> imageUrls;
  factory InventoryItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return InventoryItem(
      id: doc.id,
      itemCode: d['itemCode'] ?? doc.id,
      deviceType: d['deviceType'] ?? '',
      brand: d['brand'] ?? '',
      model: d['model'] ?? '',
      serialNumber: d['serialNumber'] ?? '',
      condition: ItemCondition.values.byName(d['condition']),
      weight: (d['weight'] as num).toDouble(),
      source: d['source'] ?? '',
      location: d['currentLocation'] ?? '',
      status: ProcessingStatus.values.byName(d['processingStatus']),
      batchId: d['batchId'],
      imageUrls: List<String>.from(d['imageUrls'] ?? const []),
    );
  }
}

class InventoryBatch {
  const InventoryBatch({
    required this.id,
    required this.code,
    required this.name,
    required this.location,
  });
  final String id, code, name, location;
  factory InventoryBatch.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final x = d.data()!;
    return InventoryBatch(
      id: d.id,
      code: x['batchCode'],
      name: x['name'],
      location: x['currentLocation'],
    );
  }
}

class InventoryEvent {
  const InventoryEvent({
    required this.action,
    required this.details,
    required this.at,
  });
  final String action, details;
  final DateTime? at;
  factory InventoryEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final x = d.data()!;
    return InventoryEvent(
      action: x['action'] ?? '',
      details: x['details'] ?? '',
      at: (x['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
