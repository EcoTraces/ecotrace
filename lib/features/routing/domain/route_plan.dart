import 'package:cloud_firestore/cloud_firestore.dart';

enum RoutePlanStatus { planned, active, completed, cancelled }

class RouteStop {
  const RouteStop({
    required this.pickupId,
    required this.userId,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.sequence,
    required this.arrived,
  });
  final String pickupId, userId, address;
  final double latitude, longitude;
  final int sequence;
  final bool arrived;
  factory RouteStop.fromMap(Map<String, dynamic> x) => RouteStop(
    pickupId: x['pickupId'],
    userId: x['userId'] ?? '',
    address: x['address'] ?? '',
    latitude: (x['latitude'] as num).toDouble(),
    longitude: (x['longitude'] as num).toDouble(),
    sequence: x['sequence'],
    arrived: x['arrived'] ?? false,
  );
  Map<String, dynamic> toMap() => {
    'pickupId': pickupId,
    'userId': userId,
    'address': address,
    'latitude': latitude,
    'longitude': longitude,
    'sequence': sequence,
    'arrived': arrived,
  };
}

class RoutePlan {
  const RoutePlan({
    required this.id,
    required this.scheduleId,
    required this.driverId,
    required this.vehicleId,
    required this.stops,
    required this.distanceKm,
    required this.estimatedMinutes,
    required this.status,
    required this.currentLatitude,
    required this.currentLongitude,
    required this.deviationCount,
    required this.startedAt,
    required this.completedAt,
  });
  final String id, scheduleId, driverId, vehicleId;
  final List<RouteStop> stops;
  final double distanceKm, estimatedMinutes;
  final RoutePlanStatus status;
  final double? currentLatitude, currentLongitude;
  final int deviationCount;
  final DateTime? startedAt, completedAt;
  factory RoutePlan.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final x = d.data()!;
    return RoutePlan(
      id: d.id,
      scheduleId: x['scheduleId'],
      driverId: x['driverId'],
      vehicleId: x['vehicleId'],
      stops: (x['stops'] as List)
          .map((s) => RouteStop.fromMap(Map<String, dynamic>.from(s)))
          .toList(),
      distanceKm: (x['distanceKm'] as num).toDouble(),
      estimatedMinutes: (x['estimatedMinutes'] as num).toDouble(),
      status: RoutePlanStatus.values.byName(x['status']),
      currentLatitude: (x['currentLatitude'] as num?)?.toDouble(),
      currentLongitude: (x['currentLongitude'] as num?)?.toDouble(),
      deviationCount: x['deviationCount'] ?? 0,
      startedAt: (x['startedAt'] as Timestamp?)?.toDate(),
      completedAt: (x['completedAt'] as Timestamp?)?.toDate(),
    );
  }

  factory RoutePlan.fromJson(Map<String, dynamic> data) => RoutePlan(
    id: data['id']?.toString() ?? '',
    scheduleId: data['scheduleId']?.toString() ?? '',
    driverId: data['driverId']?.toString() ?? '',
    vehicleId: data['vehicleId']?.toString() ?? '',
    stops: (data['stops'] as List? ?? const [])
        .map(
          (stop) =>
              RouteStop.fromMap(Map<String, dynamic>.from(stop as Map)),
        )
        .toList(),
    distanceKm: (data['distanceKm'] as num? ?? 0).toDouble(),
    estimatedMinutes: (data['estimatedMinutes'] as num? ?? 0).toDouble(),
    status: RoutePlanStatus.values.byName(
      data['status']?.toString() ?? 'planned',
    ),
    currentLatitude: (data['currentLatitude'] as num?)?.toDouble(),
    currentLongitude: (data['currentLongitude'] as num?)?.toDouble(),
    deviationCount: (data['deviationCount'] as num? ?? 0).toInt(),
    startedAt: DateTime.tryParse(data['startedAt']?.toString() ?? ''),
    completedAt: DateTime.tryParse(data['completedAt']?.toString() ?? ''),
  );
}
