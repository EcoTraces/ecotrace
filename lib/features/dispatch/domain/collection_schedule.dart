import 'package:cloud_firestore/cloud_firestore.dart';

enum DispatchPriority { normal, high, urgent }

enum DispatchStatus {
  planned,
  dispatched,
  inProgress,
  completed,
  missed,
  cancelled,
}

class CollectionSchedule {
  const CollectionSchedule({
    required this.id,
    required this.scheduledAt,
    required this.pickupIds,
    required this.collectorIds,
    required this.driverId,
    required this.vehicleId,
    required this.priority,
    required this.status,
    required this.serviceArea,
    required this.evidenceUrls,
  });
  final String id, driverId, vehicleId, serviceArea;
  final DateTime scheduledAt;
  final List<String> pickupIds, collectorIds, evidenceUrls;
  final DispatchPriority priority;
  final DispatchStatus status;
  factory CollectionSchedule.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final x = d.data()!;
    return CollectionSchedule(
      id: d.id,
      scheduledAt: (x['scheduledAt'] as Timestamp).toDate(),
      pickupIds: List<String>.from(x['pickupIds'] ?? []),
      collectorIds: List<String>.from(x['collectorIds'] ?? []),
      driverId: x['driverId'] ?? '',
      vehicleId: x['vehicleId'] ?? '',
      priority: DispatchPriority.values.byName(x['priority']),
      status: DispatchStatus.values.byName(x['status']),
      serviceArea: x['serviceArea'] ?? '',
      evidenceUrls: List<String>.from(x['evidenceUrls'] ?? []),
    );
  }
}
