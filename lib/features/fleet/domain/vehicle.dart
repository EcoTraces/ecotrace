import 'package:cloud_firestore/cloud_firestore.dart';

enum VehicleType { van, truck, pickupTruck, motorcycle, specializedHazardous }

enum VehicleAvailability {
  available,
  dispatched,
  maintenance,
  breakdown,
  inactive,
}

class Vehicle {
  const Vehicle({
    required this.id,
    required this.registrationNumber,
    required this.type,
    required this.capacityKg,
    required this.driverId,
    required this.availability,
    required this.mileageKm,
    required this.fuelLitres,
    required this.insuranceExpiry,
    required this.licenceExpiry,
    required this.latitude,
    required this.longitude,
  });
  final String id, registrationNumber, driverId;
  final VehicleType type;
  final double capacityKg, mileageKm, fuelLitres;
  final VehicleAvailability availability;
  final DateTime? insuranceExpiry, licenceExpiry;
  final double? latitude, longitude;
  factory Vehicle.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Vehicle(
      id: doc.id,
      registrationNumber: d['registrationNumber'] ?? '',
      type: VehicleType.values.byName(d['type']),
      capacityKg: (d['capacityKg'] as num).toDouble(),
      driverId: d['driverId'] ?? '',
      availability: VehicleAvailability.values.byName(d['availability']),
      mileageKm: (d['mileageKm'] as num? ?? 0).toDouble(),
      fuelLitres: (d['fuelLitres'] as num? ?? 0).toDouble(),
      insuranceExpiry: (d['insuranceExpiry'] as Timestamp?)?.toDate(),
      licenceExpiry: (d['licenceExpiry'] as Timestamp?)?.toDate(),
      latitude: (d['latitude'] as num?)?.toDouble(),
      longitude: (d['longitude'] as num?)?.toDouble(),
    );
  }
  factory Vehicle.fromJson(Map<String, dynamic> data) => Vehicle(
    id: data['id']?.toString() ?? '',
    registrationNumber: data['registrationNumber']?.toString() ?? '',
    type: VehicleType.values.byName(data['type']?.toString() ?? 'van'),
    capacityKg: (data['capacityKg'] as num? ?? 0).toDouble(),
    driverId: data['driverId']?.toString() ?? '',
    availability: VehicleAvailability.values.byName(
      data['availability']?.toString() ?? 'available',
    ),
    mileageKm: (data['mileageKm'] as num? ?? 0).toDouble(),
    fuelLitres: (data['fuelLitres'] as num? ?? 0).toDouble(),
    insuranceExpiry: DateTime.tryParse(
      data['insuranceExpiry']?.toString() ?? '',
    ),
    licenceExpiry: DateTime.tryParse(data['licenceExpiry']?.toString() ?? ''),
    latitude: (data['latitude'] as num?)?.toDouble(),
    longitude: (data['longitude'] as num?)?.toDouble(),
  );
  bool expiresWithin(Duration duration) {
    final cutoff = DateTime.now().add(duration);
    return (insuranceExpiry?.isBefore(cutoff) ?? false) ||
        (licenceExpiry?.isBefore(cutoff) ?? false);
  }
}

class FleetEvent {
  const FleetEvent({
    required this.type,
    required this.details,
    required this.at,
  });
  final String type, details;
  final DateTime? at;
  factory FleetEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final x = d.data()!;
    return FleetEvent(
      type: x['type'] ?? '',
      details: x['details'] ?? '',
      at: (x['createdAt'] as Timestamp?)?.toDate(),
    );
  }
  factory FleetEvent.fromJson(Map<String, dynamic> data) => FleetEvent(
    type: data['type']?.toString() ?? '',
    details: data['details']?.toString() ?? '',
    at: DateTime.tryParse(data['createdAt']?.toString() ?? ''),
  );
}

class FleetTrip {
  const FleetTrip({
    required this.scheduleId,
    required this.pickupCount,
    required this.completedAt,
  });
  final String scheduleId;
  final int pickupCount;
  final DateTime? completedAt;
  factory FleetTrip.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return FleetTrip(
      scheduleId: data['scheduleId'] ?? '',
      pickupCount: data['pickupCount'] ?? 0,
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
    );
  }
  factory FleetTrip.fromJson(Map<String, dynamic> data) => FleetTrip(
    scheduleId: data['scheduleId']?.toString() ?? '',
    pickupCount: (data['pickupCount'] as num? ?? 0).toInt(),
    completedAt: DateTime.tryParse(data['completedAt']?.toString() ?? ''),
  );
}

class FleetAlert {
  const FleetAlert({
    required this.vehicleId,
    required this.registrationNumber,
    required this.type,
    required this.title,
    required this.dueAt,
    required this.critical,
  });
  final String vehicleId, registrationNumber, type, title;
  final DateTime? dueAt;
  final bool critical;
  factory FleetAlert.fromJson(Map<String, dynamic> data) => FleetAlert(
    vehicleId: data['vehicleId']?.toString() ?? '',
    registrationNumber: data['registrationNumber']?.toString() ?? '',
    type: data['type']?.toString() ?? '',
    title: data['title']?.toString() ?? '',
    dueAt: DateTime.tryParse(data['dueAt']?.toString() ?? ''),
    critical: data['critical'] == true,
  );
}

class VehicleUtilization {
  const VehicleUtilization({
    required this.vehicleId,
    required this.registrationNumber,
    required this.trips,
    required this.pickupCount,
    required this.distanceKm,
    required this.utilizationScore,
  });
  final String vehicleId, registrationNumber;
  final int trips, pickupCount;
  final double distanceKm, utilizationScore;
  factory VehicleUtilization.fromJson(Map<String, dynamic> data) =>
      VehicleUtilization(
        vehicleId: data['vehicleId']?.toString() ?? '',
        registrationNumber: data['registrationNumber']?.toString() ?? '',
        trips: (data['trips'] as num? ?? 0).toInt(),
        pickupCount: (data['pickupCount'] as num? ?? 0).toInt(),
        distanceKm: (data['distanceKm'] as num? ?? 0).toDouble(),
        utilizationScore: (data['utilizationScore'] as num? ?? 0).toDouble(),
      );
}

class FleetWorkRecord {
  const FleetWorkRecord({
    required this.id,
    required this.type,
    required this.description,
    required this.status,
    required this.scheduledAt,
    required this.costSLE,
  });

  final String id, type, description, status;
  final DateTime? scheduledAt;
  final double costSLE;

  factory FleetWorkRecord.fromJson(Map<String, dynamic> data) =>
      FleetWorkRecord(
        id: data['id']?.toString() ?? '',
        type: data['type']?.toString() ?? data['severity']?.toString() ?? '',
        description:
            data['description']?.toString() ??
            data['resolution']?.toString() ??
            '',
        status: data['status']?.toString() ?? '',
        scheduledAt: DateTime.tryParse(
          data['scheduledAt']?.toString() ??
              data['occurredAt']?.toString() ??
              '',
        ),
        costSLE: (data['actualCostSLE'] as num? ??
                data['estimatedCostSLE'] as num? ??
                data['repairCostSLE'] as num? ??
                0)
            .toDouble(),
      );
}
