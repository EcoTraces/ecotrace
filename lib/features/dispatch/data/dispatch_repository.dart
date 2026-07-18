import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
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
}

class DispatchRepository {
  DispatchRepository({FirebaseFirestore? firestore, FirebaseStorage? storage})
    : _db = firestore ?? FirebaseFirestore.instance,
      _storage = storage ?? FirebaseStorage.instance;
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  Stream<List<CollectionSchedule>> watchDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day),
        end = start.add(const Duration(days: 1));
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

  Stream<List<PickupRequest>> watchAssignablePickups() => _db
      .collection('pickupRequests')
      .where(
        'status',
        whereIn: [PickupStatus.submitted.name, PickupStatus.approved.name],
      )
      .snapshots()
      .map((s) => s.docs.map(PickupRequest.fromDoc).toList());
  Stream<List<DispatchStaff>> watchStaff() => _db
      .collection('users')
      .where('role', whereIn: ['collector', 'driver'])
      .snapshots()
      .map((s) => s.docs.map(DispatchStaff.fromDoc).toList());
  Stream<List<Vehicle>> watchAvailableVehicles() => _db
      .collection('vehicles')
      .where('availability', isEqualTo: VehicleAvailability.available.name)
      .snapshots()
      .map((s) => s.docs.map(Vehicle.fromDoc).toList());
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
    }
    await batch.commit();
  }

  Future<void> dispatch(CollectionSchedule schedule) async {
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
    for (final userId in [...schedule.collectorIds, schedule.driverId]) {
      batch.set(
        _db.collection('users').doc(userId).collection('notifications').doc(),
        {
          'type': 'dispatchJob',
          'scheduleId': schedule.id,
          'title': 'New collection job',
          'body': 'Collection scheduled for ${schedule.scheduledAt}',
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        },
      );
    }
    await batch.commit();
  }

  Future<void> start(CollectionSchedule schedule) async {
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
    final urls = <String>[];
    for (var i = 0; i < evidence.length; i++) {
      final ref = _storage.ref('collectionEvidence/${schedule.id}/$i.jpg');
      await ref.putData(
        evidence[i],
        SettableMetadata(contentType: 'image/jpeg'),
      );
      urls.add(await ref.getDownloadURL());
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
