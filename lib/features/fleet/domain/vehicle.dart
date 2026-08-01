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
}
