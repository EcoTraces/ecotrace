import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';
import '../../dispatch/domain/collection_schedule.dart';
import '../../pickups/domain/pickup.dart';
import '../domain/route_plan.dart';

class RouteRepository {
  RouteRepository({FirebaseFirestore? firestore, ApiClient? apiClient})
    : _db = firestore ?? FirebaseFirestore.instance,
      _api = apiClient ?? ApiClient.instance,
      _useApi = apiClient != null || (firestore == null && ApiConfig.enabled);
  final FirebaseFirestore _db;
  final ApiClient _api;
  final bool _useApi;

  Stream<List<RoutePlan>> watchRoutes() => _useApi
      ? _pollRoutes()
      : _db
      .collection('routePlans')
      .snapshots()
      .map(
        (s) =>
            s.docs.map(RoutePlan.fromDoc).toList()
              ..sort((a, b) => a.status.index.compareTo(b.status.index)),
      );
  Stream<RoutePlan> watchRoute(String id) => _useApi
      ? _pollRoute(id)
      : _db
      .collection('routePlans')
      .doc(id)
      .snapshots()
      .where((d) => d.exists)
      .map(RoutePlan.fromDoc);
  Stream<List<CollectionSchedule>> watchSchedulable() => _useApi
      ? _pollSchedulable()
      : _db
      .collection('collectionSchedules')
      .where('status', whereIn: ['planned', 'dispatched', 'inProgress'])
      .snapshots()
      .map((s) => s.docs.map(CollectionSchedule.fromDoc).toList());

  Stream<List<RoutePlan>> _pollRoutes() async* {
    while (true) {
      final data = await _api.getList('/api/v1/routes');
      yield data.map(RoutePlan.fromJson).toList()
        ..sort((a, b) => a.status.index.compareTo(b.status.index));
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<RoutePlan> _pollRoute(String id) async* {
    while (true) {
      yield RoutePlan.fromJson(await _api.get('/api/v1/routes/$id'));
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<List<CollectionSchedule>> _pollSchedulable() async* {
    while (true) {
      final data = await _api.getList('/api/v1/routes/schedulable');
      yield data.map(CollectionSchedule.fromJson).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }
  Stream<Position> positionStream() {
    final LocationSettings settings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 25,
        intervalDuration: const Duration(seconds: 10),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'EcoTrace route tracking active',
          notificationText:
              'Your location is updating dispatch until you pause or complete the route.',
          notificationChannelName: 'Active route location',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 25,
        activityType: ActivityType.automotiveNavigation,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 25,
      );
    }
    return Geolocator.getPositionStream(locationSettings: settings);
  }

  Future<RoutePlan> optimize(CollectionSchedule schedule) async {
    if (_useApi) {
      return RoutePlan.fromJson(
        await _api.post('/api/v1/routes/optimize', {
          'scheduleId': schedule.id,
          'departureAt': schedule.scheduledAt.toUtc().toIso8601String(),
          'trafficAware': true,
          'arrivalRadiusMetres': 150,
          'deviationRadiusMetres': 2000,
        }),
      );
    }
    final existing = await _db
        .collection('routePlans')
        .where('scheduleId', isEqualTo: schedule.id)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      final route = RoutePlan.fromDoc(existing.docs.first);
      await _db.collection('collectionSchedules').doc(schedule.id).update({
        'routePlanId': route.id,
        'routeDistanceKm': route.distanceKm,
        'estimatedTravelMinutes': route.estimatedMinutes,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return route;
    }

    final pickups = <PickupRequest>[];
    for (final id in schedule.pickupIds) {
      final doc = await _db.collection('pickupRequests').doc(id).get();
      if (doc.exists) pickups.add(PickupRequest.fromDoc(doc));
    }
    if (pickups.isEmpty) {
      throw StateError('This schedule does not contain any available pickups.');
    }
    if (pickups.any((p) => p.latitude == null || p.longitude == null)) {
      throw StateError(
        'Every pickup must have GPS coordinates before route optimization.',
      );
    }
    double? startLat, startLng;
    final vehicle = await _db
        .collection('vehicles')
        .doc(schedule.vehicleId)
        .get();
    if (vehicle.exists) {
      startLat = (vehicle.data()?['latitude'] as num?)?.toDouble();
      startLng = (vehicle.data()?['longitude'] as num?)?.toDouble();
    }
    startLat ??= pickups.first.latitude;
    startLng ??= pickups.first.longitude;
    final remaining = [...pickups], ordered = <PickupRequest>[];
    var lat = startLat!, lng = startLng!;
    while (remaining.isNotEmpty) {
      remaining.sort(
        (a, b) => distanceKm(
          lat,
          lng,
          a.latitude!,
          a.longitude!,
        ).compareTo(distanceKm(lat, lng, b.latitude!, b.longitude!)),
      );
      final next = remaining.removeAt(0);
      ordered.add(next);
      lat = next.latitude!;
      lng = next.longitude!;
    }
    var distance = 0.0;
    lat = startLat;
    lng = startLng;
    final stops = <RouteStop>[];
    for (var i = 0; i < ordered.length; i++) {
      final p = ordered[i];
      distance += distanceKm(lat, lng, p.latitude!, p.longitude!);
      stops.add(
        RouteStop(
          pickupId: p.id,
          userId: p.userId,
          address: p.location,
          latitude: p.latitude!,
          longitude: p.longitude!,
          sequence: i + 1,
          arrived: false,
        ),
      );
      lat = p.latitude!;
      lng = p.longitude!;
    }
    final ref = _db.collection('routePlans').doc();
    await ref.set({
      'scheduleId': schedule.id,
      'driverId': schedule.driverId,
      'vehicleId': schedule.vehicleId,
      'stops': stops.map((s) => s.toMap()).toList(),
      'distanceKm': distance,
      'estimatedMinutes': distance / 30 * 60,
      'status': RoutePlanStatus.planned.name,
      'currentLatitude': startLat,
      'currentLongitude': startLng,
      'deviationCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _db.collection('collectionSchedules').doc(schedule.id).update({
      'routePlanId': ref.id,
      'routeDistanceKm': distance,
      'estimatedTravelMinutes': distance / 30 * 60,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return RoutePlan.fromDoc(await ref.get());
  }

  Future<void> start(String routeId) => _useApi
      ? _api.patch('/api/v1/routes/$routeId/start', const {}).then((_) {})
      : _db.collection('routePlans').doc(routeId).update({
        'status': RoutePlanStatus.active.name,
        'startedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
  Future<void> recordPosition(String routeId, Position position) async {
    if (_useApi) {
      await _api.post('/api/v1/routes/$routeId/positions', {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'speedMps': position.speed,
        'accuracy': position.accuracy,
        'recordedAt': position.timestamp.toUtc().toIso8601String(),
      });
      return;
    }
    final route = RoutePlan.fromDoc(
      await _db.collection('routePlans').doc(routeId).get(),
    );
    final ref = _db.collection('routePlans').doc(route.id);
    final batch = _db.batch();
    final remaining = route.stops.where((s) => !s.arrived).toList();
    final nearest = remaining.isEmpty
        ? null
        : (remaining..sort(
                (a, b) =>
                    distanceKm(
                      position.latitude,
                      position.longitude,
                      a.latitude,
                      a.longitude,
                    ).compareTo(
                      distanceKm(
                        position.latitude,
                        position.longitude,
                        b.latitude,
                        b.longitude,
                      ),
                    ),
              ))
              .first;
    final nearestDistance = nearest == null
        ? 0
        : distanceKm(
            position.latitude,
            position.longitude,
            nearest.latitude,
            nearest.longitude,
          );
    batch.update(ref, {
      'currentLatitude': position.latitude,
      'currentLongitude': position.longitude,
      'lastLocationAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (nearestDistance > 2) 'deviationCount': FieldValue.increment(1),
    });
    batch.set(ref.collection('locationHistory').doc(), {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'speedMps': position.speed,
      'accuracy': position.accuracy,
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (nearestDistance > 2) {
      batch.set(ref.collection('alerts').doc(), {
        'type': 'routeDeviation',
        'distanceKm': nearestDistance,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    if (nearest != null && nearestDistance <= .15) {
      final updated = route.stops
          .map(
            (s) => s.pickupId == nearest.pickupId
                ? RouteStop(
                    pickupId: s.pickupId,
                    userId: s.userId,
                    address: s.address,
                    latitude: s.latitude,
                    longitude: s.longitude,
                    sequence: s.sequence,
                    arrived: true,
                  )
                : s,
          )
          .map((s) => s.toMap())
          .toList();
      batch.update(ref, {'stops': updated});
      batch.set(ref.collection('events').doc(), {
        'type': 'pickupArrival',
        'pickupId': nearest.pickupId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (nearest.userId.isNotEmpty) {
        batch.set(
          _db
              .collection('users')
              .doc(nearest.userId)
              .collection('notifications')
              .doc(),
          {
            'type': 'pickupArrival',
            'title': 'Collector arriving',
            'body': 'Your collection team has arrived.',
            'routeId': route.id,
            'read': false,
            'createdAt': FieldValue.serverTimestamp(),
          },
        );
      }
    }
    await batch.commit();
  }

  Future<void> complete(String routeId) => _useApi
      ? _api.patch('/api/v1/routes/$routeId/complete', const {}).then((_) {})
      : _db.collection('routePlans').doc(routeId).update({
        'status': RoutePlanStatus.completed.name,
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<List<RouteLocation>> locationHistory(String routeId) async {
    if (!_useApi) {
      final snapshot = await _db.collection('routePlans').doc(routeId).collection('locationHistory').orderBy('recordedAt', descending: true).limit(1000).get();
      return snapshot.docs.map((document) {
        final data = document.data();
        return RouteLocation(
          latitude: (data['latitude'] as num? ?? 0).toDouble(),
          longitude: (data['longitude'] as num? ?? 0).toDouble(),
          speedMps: (data['speedMps'] as num? ?? 0).toDouble(),
          recordedAt: (data['recordedAt'] as Timestamp?)?.toDate(),
        );
      }).toList();
    }
    final data = await _api.getList('/api/v1/routes/$routeId/location-history');
    return data.map(RouteLocation.fromJson).toList();
  }

  Future<RoutePerformance> performance({required DateTime from, required DateTime to}) async {
    if (!_useApi) {
      final routes = await watchRoutes().first;
      final completed = routes.where((route) => route.status == RoutePlanStatus.completed).toList();
      return RoutePerformance(
        routes: routes.length,
        completed: completed.length,
        active: routes.where((route) => route.status == RoutePlanStatus.active).length,
        plannedDistanceKm: routes.fold(0, (total, route) => total + route.distanceKm),
        actualDistanceKm: completed.fold(0, (total, route) => total + route.actualDistanceKm),
        deviations: routes.fold(0, (total, route) => total + route.deviationCount),
        averageCompletionRate: completed.isEmpty ? 0 : 100,
      );
    }
    return RoutePerformance.fromJson(await _api.get('/api/v1/routing/reports/performance', query: {
      'from': from.toUtc().toIso8601String(),
      'to': to.toUtc().toIso8601String(),
    }));
  }
  static double distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const earth = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180,
        dLon = (lon2 - lon1) * math.pi / 180;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return earth * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}
