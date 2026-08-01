import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';
import '../domain/vehicle.dart';

class FleetRepository {
  FleetRepository({FirebaseFirestore? firestore, ApiClient? apiClient})
    : _db = firestore ?? FirebaseFirestore.instance,
      _api = apiClient ?? ApiClient.instance,
      _useApi = apiClient != null || (firestore == null && ApiConfig.enabled);
  final FirebaseFirestore _db;
  final ApiClient _api;
  final bool _useApi;
  Stream<List<Vehicle>> watchVehicles() => _useApi
      ? _pollVehicles()
      : _db
      .collection('vehicles')
      .snapshots()
      .map(
        (s) => s.docs.map(Vehicle.fromDoc).toList()
          ..sort(
            (a, b) => a.registrationNumber.compareTo(b.registrationNumber),
          ),
      );
  Stream<List<Vehicle>> watchAvailable() => _useApi
      ? _pollVehicles(availability: VehicleAvailability.available.name)
      : _db
      .collection('vehicles')
      .where('availability', isEqualTo: VehicleAvailability.available.name)
      .snapshots()
      .map((s) => s.docs.map(Vehicle.fromDoc).toList());

  Stream<List<Vehicle>> _pollVehicles({String? availability}) async* {
    while (true) {
      final data = await _api.getList(
        '/api/v1/vehicles',
        query: availability == null ? null : {'availability': availability},
      );
      yield data.map(Vehicle.fromJson).toList()
        ..sort(
          (a, b) => a.registrationNumber.compareTo(b.registrationNumber),
        );
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }
  Stream<List<FleetEvent>> watchEvents(String vehicleId) => _db
      .collection('vehicles')
      .doc(vehicleId)
      .collection('events')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(FleetEvent.fromDoc).toList());
  Stream<List<FleetTrip>> watchTrips(String vehicleId) => _db
      .collection('vehicles')
      .doc(vehicleId)
      .collection('trips')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(FleetTrip.fromDoc).toList());
  Future<void> register({
    required String registrationNumber,
    required VehicleType type,
    required double capacityKg,
    required String driverId,
    required DateTime insuranceExpiry,
    required DateTime licenceExpiry,
  }) async {
    if (_useApi) {
      await _api.post('/api/v1/vehicles', {
        'registrationNumber': registrationNumber.trim().toUpperCase(),
        'type': type.name,
        'capacityKg': capacityKg,
        'driverId': driverId.trim(),
        'insuranceExpiry': insuranceExpiry.toUtc().toIso8601String(),
        'licenceExpiry': licenceExpiry.toUtc().toIso8601String(),
      });
      return;
    }
    final ref = _db.collection('vehicles').doc();
    final batch = _db.batch();
    batch.set(ref, {
      'registrationNumber': registrationNumber.trim().toUpperCase(),
      'type': type.name,
      'capacityKg': capacityKg,
      'driverId': driverId.trim(),
      'availability': VehicleAvailability.available.name,
      'mileageKm': 0,
      'fuelLitres': 0,
      'insuranceExpiry': Timestamp.fromDate(insuranceExpiry),
      'licenceExpiry': Timestamp.fromDate(licenceExpiry),
      'latitude': null,
      'longitude': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(ref.collection('events').doc(), {
      'type': 'registered',
      'details': 'Vehicle registered',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> recordEvent(
    Vehicle vehicle, {
    required String type,
    required String details,
    VehicleAvailability? availability,
    double? mileage,
    double? fuel,
    double? latitude,
    double? longitude,
    DateTime? nextMaintenanceAt,
  }) async {
    final ref = _db.collection('vehicles').doc(vehicle.id);
    final update = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
    if (availability != null) update['availability'] = availability.name;
    if (mileage != null) update['mileageKm'] = mileage;
    if (fuel != null) update['fuelLitres'] = fuel;
    if (latitude != null) update['latitude'] = latitude;
    if (longitude != null) update['longitude'] = longitude;
    if (nextMaintenanceAt != null) {
      update['nextMaintenanceAt'] = Timestamp.fromDate(nextMaintenanceAt);
    }
    final batch = _db.batch();
    batch.update(ref, update);
    batch.set(ref.collection('events').doc(), {
      'type': type,
      'details': details.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> assignDriver(String vehicleId, String driverId) =>
      _db.collection('vehicles').doc(vehicleId).update({
        'driverId': driverId.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
}
