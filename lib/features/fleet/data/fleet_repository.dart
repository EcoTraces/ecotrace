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
  Stream<List<FleetEvent>> watchEvents(String vehicleId) => _useApi
      ? _pollList('/api/v1/vehicles/$vehicleId/events', FleetEvent.fromJson)
      : _db
      .collection('vehicles')
      .doc(vehicleId)
      .collection('events')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(FleetEvent.fromDoc).toList());
  Stream<List<FleetTrip>> watchTrips(String vehicleId) => _useApi
      ? _pollList('/api/v1/vehicles/$vehicleId/trips', FleetTrip.fromJson)
      : _db
      .collection('vehicles')
      .doc(vehicleId)
      .collection('trips')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(FleetTrip.fromDoc).toList());

  Stream<List<T>> _pollList<T>(
    String path,
    T Function(Map<String, dynamic>) decode,
  ) async* {
    while (true) {
      final data = await _api.getList(path);
      yield data.map(decode).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }
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
    if (_useApi) {
      switch (type) {
        case 'inspection':
          await _api.post('/api/v1/vehicles/${vehicle.id}/inspections', {
            'result': 'passedWithIssues',
            'odometerKm': mileage ?? vehicle.mileageKm,
            'checklist': {'generalCondition': true},
            'defects': details.trim().isEmpty ? <String>[] : [details.trim()],
            'evidenceUrls': <String>[],
            'nextInspectionAt': (nextMaintenanceAt ?? DateTime.now().add(const Duration(days: 90))).toUtc().toIso8601String(),
            'notes': details.trim(),
          });
          return;
        case 'fuel':
          await _api.post('/api/v1/vehicles/${vehicle.id}/fuel-records', {
            'litres': fuel,
            'costSLE': 0,
            'odometerKm': mileage ?? vehicle.mileageKm,
            'station': details.trim().isEmpty ? 'Not recorded' : details.trim(),
            'receiptUrl': null,
          });
          return;
        case 'mileage':
          await _api.post('/api/v1/vehicles/${vehicle.id}/mileage-records', {
            'odometerKm': mileage,
            'purpose': details.trim().isEmpty ? 'Odometer update' : details.trim(),
          });
          return;
        case 'location':
          await _api.post('/api/v1/vehicles/${vehicle.id}/location', {
            'latitude': latitude,
            'longitude': longitude,
            'accuracyMetres': null,
          });
          return;
        case 'maintenance':
          await _api.post('/api/v1/vehicles/${vehicle.id}/maintenance', {
            'type': 'preventive',
            'description': details.trim().isEmpty ? 'Scheduled vehicle maintenance' : details.trim(),
            'scheduledAt': (nextMaintenanceAt ?? DateTime.now().add(const Duration(days: 7))).toUtc().toIso8601String(),
            'estimatedCostSLE': 0,
            'provider': '',
          });
          return;
        case 'breakdown':
          await _api.post('/api/v1/vehicles/${vehicle.id}/breakdowns', {
            'location': '${vehicle.latitude ?? 0}, ${vehicle.longitude ?? 0}',
            'description': details.trim().isEmpty ? 'Vehicle breakdown reported' : details.trim(),
            'severity': 'medium',
            'evidenceUrls': <String>[],
          });
          return;
      }
    }
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

  Future<void> assignDriver(String vehicleId, String driverId) {
    if (_useApi) {
      return _api.patch('/api/v1/vehicles/$vehicleId/driver', {
        'driverId': driverId.trim(),
      }).then((_) {});
    }
    return _db.collection('vehicles').doc(vehicleId).update({
        'driverId': driverId.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
  }

  Future<List<FleetAlert>> getAlerts({int days = 30}) async {
    if (!_useApi) return const [];
    final data = await _api.getList(
      '/api/v1/fleet/alerts',
      query: {'days': '$days'},
    );
    return data.map(FleetAlert.fromJson).toList();
  }

  Future<List<VehicleUtilization>> getUtilization({
    required DateTime from,
    required DateTime to,
  }) async {
    if (!_useApi) return const [];
    final data = await _api.getList(
      '/api/v1/fleet/utilization',
      query: {
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
      },
    );
    return data.map(VehicleUtilization.fromJson).toList();
  }
}
