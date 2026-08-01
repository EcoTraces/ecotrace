import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';
import '../../../core/media/cloudinary_upload_service.dart';
import '../../pickups/domain/pickup.dart';
import '../../fleet/domain/vehicle.dart';
import '../domain/collection_schedule.dart';

class DispatchStaff {
  const DispatchStaff({
    required this.id,
    required this.name,
    required this.role,
    required this.available,
  });
  final String id, name, role;
  final bool available;
  factory DispatchStaff.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final x = d.data()!;
    return DispatchStaff(
      id: d.id,
      name: x['displayName'] ?? x['email'] ?? d.id,
      role: x['role'] ?? '',
      available: x['dispatchAvailable'] ?? true,
    );
  }

  factory DispatchStaff.fromJson(Map<String, dynamic> data) => DispatchStaff(
    id: data['id']?.toString() ?? '',
    name:
        data['displayName']?.toString() ??
        data['email']?.toString() ??
        data['id']?.toString() ??
        '',
    role: data['role']?.toString() ?? '',
    available: data['dispatchAvailable'] as bool? ?? true,
  );
}

class DispatchRepository {
  DispatchRepository({FirebaseFirestore? firestore, ApiClient? apiClient})
    : _db = firestore ?? FirebaseFirestore.instance,
      _api = apiClient ?? ApiClient.instance,
      _useApi = apiClient != null || (firestore == null && ApiConfig.enabled);
  final FirebaseFirestore _db;
  final ApiClient _api;
  final bool _useApi;
  Stream<List<CollectionSchedule>> watchDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day),
        end = start.add(const Duration(days: 1));
    if (_useApi) {
      return _pollList(
        '/api/v1/dispatch/schedules',
        (data) => CollectionSchedule.fromJson(data),
        query: {
          'from': start.toUtc().toIso8601String(),
          'to': end.toUtc().toIso8601String(),
        },
      ).map(
        (items) =>
            items..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt)),
      );
    }
    return _db
        .collection('collectionSchedules')
        .where('scheduledAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('scheduledAt', isLessThan: Timestamp.fromDate(end))
        .snapshots()
        .map(
          (s) =>
              s.docs.map(CollectionSchedule.fromDoc).toList()
                ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt)),
        );
  }

  Stream<List<PickupRequest>> watchAssignablePickups() => _useApi
      ? _pollList('/api/v1/dispatch/assignable-pickups', PickupRequest.fromJson)
      : _db
            .collection('pickupRequests')
            .where(
              'status',
              whereIn: [
                PickupStatus.submitted.name,
                PickupStatus.approved.name,
              ],
            )
            .snapshots()
            .map((s) => s.docs.map(PickupRequest.fromDoc).toList());
  Stream<List<DispatchStaff>> watchStaff() => _useApi
      ? _pollList('/api/v1/dispatch/staff', DispatchStaff.fromJson)
      : _db
            .collection('users')
            .where('role', whereIn: ['collector', 'driver'])
            .snapshots()
            .map((s) => s.docs.map(DispatchStaff.fromDoc).toList());
  Stream<List<Vehicle>> watchAvailableVehicles() => _useApi
      ? _pollList(
          '/api/v1/vehicles',
          Vehicle.fromJson,
          query: {'availability': VehicleAvailability.available.name},
        )
      : _db
            .collection('vehicles')
            .where(
              'availability',
              isEqualTo: VehicleAvailability.available.name,
            )
            .snapshots()
            .map((s) => s.docs.map(Vehicle.fromDoc).toList());

  Stream<List<T>> _pollList<T>(
    String path,
    T Function(Map<String, dynamic>) decode, {
    Map<String, String>? query,
  }) async* {
    while (true) {
      final data = await _api.getList(path, query: query);
      yield data.map(decode).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Future<void> create({
    required DateTime scheduledAt,
    required List<PickupRequest> pickups,
    required List<String> collectorIds,
    required String driverId,
    required Vehicle vehicle,
    required DispatchPriority priority,
    required String serviceArea,
  }) async {
    if (pickups.isEmpty) throw StateError('Select at least one pickup.');
    final weight = pickups.fold<double>(0, (total, p) => total + p.weight);
    if (weight > vehicle.capacityKg) {
      throw StateError('Selected pickups exceed vehicle capacity.');
    }
    if (_useApi) {
      await _api.post('/api/v1/dispatch/schedules', {
        'scheduledAt': scheduledAt.toUtc().toIso8601String(),
        'pickupIds': pickups.map((pickup) => pickup.id).toList(),
        'collectorIds': collectorIds,
        'driverId': driverId,
        'vehicleId': vehicle.id,
        'priority': priority.name,
        'serviceArea': serviceArea.trim(),
      });
      return;
    }
    final ref = _db.collection('collectionSchedules').doc();
    final batch = _db.batch();
    batch.set(ref, {
      'scheduledAt': Timestamp.fromDate(scheduledAt),
      'pickupIds': pickups.map((p) => p.id).toList(),
      'collectorIds': collectorIds,
      'driverId': driverId,
      'vehicleId': vehicle.id,
      'priority': priority.name,
      'status': DispatchStatus.planned.name,
      'serviceArea': serviceArea.trim(),
      'evidenceUrls': [],
      'estimatedWeight': weight,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    for (final pickup in pickups) {
      batch.update(_db.collection('pickupRequests').doc(pickup.id), {
        'status': PickupStatus.assigned.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.set(
        _db
            .collection('users')
            .doc(pickup.userId)
            .collection('notifications')
            .doc('pickup-status-${pickup.id}-assigned'),
        {
          'type': 'statusUpdate',
          'title': 'Pickup assigned',
          'body': 'A collection team has been assigned to your pickup.',
          'read': false,
          'data': {'pickupId': pickup.id, 'status': 'assigned'},
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    for (final userId in {...collectorIds, driverId}) {
      batch.set(
        _db
            .collection('users')
            .doc(userId)
            .collection('notifications')
            .doc('schedule-created-${ref.id}'),
        {
          'type': 'assignment',
          'title': 'New collection assignment',
          'body': 'You have been assigned a collection in $serviceArea.',
          'read': false,
          'data': {'scheduleId': ref.id},
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  Future<void> dispatch(CollectionSchedule schedule) async {
    if (_useApi) {
      await _api.patch(
        '/api/v1/dispatch/schedules/${schedule.id}/dispatch',
        const {},
      );
      return;
    }
    final batch = _db.batch();
    final ref = _db.collection('collectionSchedules').doc(schedule.id);
    batch.update(ref, {
      'status': DispatchStatus.dispatched.name,
      'dispatchedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(_db.collection('vehicles').doc(schedule.vehicleId), {
      'availability': VehicleAvailability.dispatched.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    for (final pickupId in schedule.pickupIds) {
      batch.update(_db.collection('pickupRequests').doc(pickupId), {
        'status': PickupStatus.scheduled.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    for (final userId in {...schedule.collectorIds, schedule.driverId}) {
      batch.set(
        _db
            .collection('users')
            .doc(userId)
            .collection('notifications')
            .doc('schedule-status-${schedule.id}-dispatched'),
        {
          'type': 'assignment',
          'scheduleId': schedule.id,
          'title': 'New collection job',
          'body': 'Collection scheduled for ${schedule.scheduledAt}',
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  Future<void> start(CollectionSchedule schedule) async {
    if (_useApi) {
      await _api.patch(
        '/api/v1/dispatch/schedules/${schedule.id}/start',
        const {},
      );
      return;
    }
    final batch = _db.batch();
    batch.update(_db.collection('collectionSchedules').doc(schedule.id), {
      'status': DispatchStatus.inProgress.name,
      'startedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    for (final id in schedule.pickupIds) {
      batch.update(_db.collection('pickupRequests').doc(id), {
        'status': PickupStatus.inProgress.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> complete(
    CollectionSchedule schedule,
    List<Uint8List> evidence,
  ) async {
    final urls = await CloudinaryUploadService.instance.uploadImages(
      evidence,
      scope: 'collection-evidence',
    );
    if (_useApi) {
      await _api.patch('/api/v1/dispatch/schedules/${schedule.id}/complete', {
        'evidenceUrls': urls,
      });
      return;
    }
    final batch = _db.batch();
    batch.update(_db.collection('collectionSchedules').doc(schedule.id), {
      'status': DispatchStatus.completed.name,
      'completedAt': FieldValue.serverTimestamp(),
      'evidenceUrls': urls,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final vehicle = _db.collection('vehicles').doc(schedule.vehicleId);
    batch.update(vehicle, {
      'availability': VehicleAvailability.available.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(vehicle.collection('trips').doc(), {
      'scheduleId': schedule.id,
      'startedAt': FieldValue.serverTimestamp(),
      'completedAt': FieldValue.serverTimestamp(),
      'pickupCount': schedule.pickupIds.length,
      'createdAt': FieldValue.serverTimestamp(),
    });
    for (final id in schedule.pickupIds) {
      batch.update(_db.collection('pickupRequests').doc(id), {
        'status': PickupStatus.collected.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> markMissedAndReschedule(
    CollectionSchedule schedule,
    DateTime nextDate,
  ) async {
    if (_useApi) {
      await _api.patch('/api/v1/dispatch/schedules/${schedule.id}/reschedule', {
        'scheduledAt': nextDate.toUtc().toIso8601String(),
      });
      return;
    }
    final batch = _db.batch();
    batch.update(_db.collection('collectionSchedules').doc(schedule.id), {
      'status': DispatchStatus.planned.name,
      'scheduledAt': Timestamp.fromDate(nextDate),
      'missedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(_db.collection('vehicles').doc(schedule.vehicleId), {
      'availability': VehicleAvailability.available.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    for (final id in schedule.pickupIds) {
      batch.update(_db.collection('pickupRequests').doc(id), {
        'status': PickupStatus.assigned.name,
        'scheduledAt': Timestamp.fromDate(nextDate),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}
