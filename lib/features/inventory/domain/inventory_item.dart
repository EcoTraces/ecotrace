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
    required this.barcodeValue,
    required this.qrPayload,
  });
  final String id,
      itemCode,
      deviceType,
      brand,
      model,
      serialNumber,
      source,
      location;
  final String barcodeValue, qrPayload;
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
      barcodeValue:
          d['barcodeValue']?.toString() ?? d['itemCode']?.toString() ?? doc.id,
      qrPayload:
          d['qrPayload']?.toString() ??
          'ecotrace://inventory/${d['itemCode'] ?? doc.id}',
    );
  }
  factory InventoryItem.fromJson(Map<String, dynamic> d) => InventoryItem(
    id: d['id']?.toString() ?? '',
    itemCode: d['itemCode']?.toString() ?? d['id']?.toString() ?? '',
    deviceType: d['deviceType']?.toString() ?? '',
    brand: d['brand']?.toString() ?? '',
    model: d['model']?.toString() ?? '',
    serialNumber: d['serialNumber']?.toString() ?? '',
    condition: ItemCondition.values.byName(
      d['condition']?.toString() ?? ItemCondition.working.name,
    ),
    weight: (d['weight'] as num? ?? 0).toDouble(),
    source: d['source']?.toString() ?? '',
    location: d['currentLocation']?.toString() ?? '',
    status: ProcessingStatus.values.byName(
      d['processingStatus']?.toString() ?? ProcessingStatus.registered.name,
    ),
    batchId: d['batchId']?.toString(),
    imageUrls: List<String>.from(d['imageUrls'] ?? const []),
    barcodeValue:
        d['barcodeValue']?.toString() ?? d['itemCode']?.toString() ?? '',
    qrPayload:
        d['qrPayload']?.toString() ??
        'ecotrace://inventory/${d['itemCode'] ?? d['id'] ?? ''}',
  );
}

class InventoryBatch {
  const InventoryBatch({
    required this.id,
    required this.code,
    required this.name,
    required this.location,
    required this.status,
    required this.itemCount,
    required this.totalWeight,
    required this.closed,
  });
  final String id, code, name, location;
  final String status;
  final int itemCount;
  final double totalWeight;
  final bool closed;
  factory InventoryBatch.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final x = d.data()!;
    return InventoryBatch(
      id: d.id,
      code: x['batchCode'],
      name: x['name'],
      location: x['currentLocation'],
      status: x['processingStatus'] ?? 'registered',
      itemCount: (x['itemCount'] as num? ?? 0).toInt(),
      totalWeight: (x['totalWeight'] as num? ?? 0).toDouble(),
      closed: x['closed'] as bool? ?? false,
    );
  }
  factory InventoryBatch.fromJson(Map<String, dynamic> x) => InventoryBatch(
    id: x['id']?.toString() ?? '',
    code: x['batchCode']?.toString() ?? '',
    name: x['name']?.toString() ?? '',
    location: x['currentLocation']?.toString() ?? '',
    status: x['processingStatus']?.toString() ?? 'registered',
    itemCount: (x['itemCount'] as num? ?? 0).toInt(),
    totalWeight: (x['totalWeight'] as num? ?? 0).toDouble(),
    closed: x['closed'] as bool? ?? false,
  );
}

class InventorySummary {
  const InventorySummary({
    required this.totalItems,
    required this.totalWeightKg,
    required this.batchedItems,
    required this.batches,
    required this.byCondition,
    required this.byStatus,
  });

  final int totalItems, batchedItems, batches;
  final double totalWeightKg;
  final Map<String, int> byCondition, byStatus;

  factory InventorySummary.fromJson(Map<String, dynamic> data) =>
      InventorySummary(
        totalItems: (data['totalItems'] as num? ?? 0).toInt(),
        totalWeightKg: (data['totalWeightKg'] as num? ?? 0).toDouble(),
        batchedItems: (data['batchedItems'] as num? ?? 0).toInt(),
        batches: (data['batches'] as num? ?? 0).toInt(),
        byCondition: _integerMap(data['byCondition']),
        byStatus: _integerMap(data['byStatus']),
      );

  static Map<String, int> _integerMap(dynamic value) => value is Map
      ? value.map(
          (key, item) => MapEntry(key.toString(), (item as num? ?? 0).toInt()),
        )
      : const {};
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
  factory InventoryEvent.fromJson(Map<String, dynamic> x) => InventoryEvent(
    action: x['action']?.toString() ?? '',
    details: x['details']?.toString() ?? '',
    at: DateTime.tryParse(x['createdAt']?.toString() ?? ''),
  );
}
