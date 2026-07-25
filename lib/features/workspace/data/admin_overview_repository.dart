import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../environmental_impact/domain/environmental_impact.dart';

class AdminOverviewRepository {
  AdminOverviewRepository({
    FirebaseFirestore? firestore,
    EnvironmentalImpactCalculator? impactCalculator,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _impactCalculator =
           impactCalculator ?? const EnvironmentalImpactCalculator();

  final FirebaseFirestore _db;
  final EnvironmentalImpactCalculator _impactCalculator;

  Stream<AdminOverviewSnapshot> watchOverview() {
    late StreamController<AdminOverviewSnapshot> controller;
    final subscriptions = <StreamSubscription<dynamic>>[];
    final records = <String, List<Map<String, dynamic>>>{};
    final loadedSources = <String>{};
    final failedSources = <String>{};
    final collections = <String, String>{
      'pickups': 'pickupRequests',
      'inventory': 'inventoryItems',
      'recycling': 'recyclingBatches',
      'materials': 'recoveredMaterialLots',
      'hazardous': 'hazardousWasteRecords',
      'repairs': 'repairJobs',
      'users': 'users',
      'partners': 'servicePartners',
      'centres': 'collectionCentres',
    };

    void emit() {
      if (controller.isClosed) return;
      controller.add(
        AdminOverviewSnapshot.fromRecords(
          records,
          impactCalculator: _impactCalculator,
          loadedSources: loadedSources,
          failedSources: failedSources,
          sourceCount: collections.length,
        ),
      );
    }

    controller = StreamController<AdminOverviewSnapshot>.broadcast(
      onListen: () {
        for (final entry in collections.entries) {
          records[entry.key] = const [];
          subscriptions.add(
            _db
                .collection(entry.value)
                .snapshots()
                .listen(
                  (snapshot) {
                    records[entry.key] = snapshot.docs
                        .map(
                          (doc) => <String, dynamic>{
                            'id': doc.id,
                            ...doc.data(),
                          },
                        )
                        .toList();
                    loadedSources.add(entry.key);
                    failedSources.remove(entry.key);
                    emit();
                  },
                  onError: (_) {
                    failedSources.add(entry.key);
                    emit();
                  },
                ),
          );
        }
        scheduleMicrotask(emit);
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }
}

class AdminOverviewSnapshot {
  const AdminOverviewSnapshot({
    required this.totalCollections,
    required this.collectedKg,
    required this.recycledKg,
    required this.activeUsers,
    required this.totalUsers,
    required this.totalPartners,
    required this.collectionCentres,
    required this.trackedItems,
    required this.categoryWeights,
    required this.collectionTrend,
    required this.pickupStatuses,
    required this.recentCollections,
    required this.collectionLocations,
    required this.impact,
    this.loadedSources = const {},
    this.failedSources = const {},
    this.sourceCount = 0,
  });

  final int totalCollections;
  final double collectedKg;
  final double recycledKg;
  final int activeUsers;
  final int totalUsers;
  final int totalPartners;
  final int collectionCentres;
  final int trackedItems;
  final Map<String, double> categoryWeights;
  final List<double> collectionTrend;
  final Map<String, int> pickupStatuses;
  final List<RecentCollectionSummary> recentCollections;
  final List<CollectionLocationSummary> collectionLocations;
  final EnvironmentalImpactSnapshot impact;
  final Set<String> loadedSources;
  final Set<String> failedSources;
  final int sourceCount;

  bool get isLoading =>
      loadedSources.length + failedSources.length < sourceCount;

  int get completedPickups => pickupStatuses['Completed'] ?? 0;
  int get allPickups => pickupStatuses.values.fold(0, (a, b) => a + b);
  double get pickupCompletionRate =>
      allPickups == 0 ? 0 : (completedPickups / allPickups * 100).clamp(0, 100);

  factory AdminOverviewSnapshot.fromRecords(
    Map<String, List<Map<String, dynamic>>> records, {
    EnvironmentalImpactCalculator impactCalculator =
        const EnvironmentalImpactCalculator(),
    DateTime? now,
    Set<String> loadedSources = const {},
    Set<String> failedSources = const {},
    int sourceCount = 0,
  }) {
    final generatedAt = now ?? DateTime.now();
    final pickups = records['pickups'] ?? const [];
    final inventory = records['inventory'] ?? const [];
    final recycling = records['recycling'] ?? const [];
    final materials = records['materials'] ?? const [];
    final hazardous = records['hazardous'] ?? const [];
    final repairs = records['repairs'] ?? const [];
    final users = records['users'] ?? const [];
    final partners = records['partners'] ?? const [];
    final centres = records['centres'] ?? const [];

    final completedStatuses = {'collected', 'completed'};
    final completed = pickups
        .where((item) => completedStatuses.contains(item['status']))
        .toList();
    final categories = <String, double>{};
    for (final item in inventory) {
      final category = _displayCategory(item['deviceType']?.toString());
      categories.update(
        category,
        (value) => value + _number(item['weight']),
        ifAbsent: () => _number(item['weight']),
      );
    }

    final trend = List<double>.filled(8, 0);
    final startOfCurrentWeek = DateTime(
      generatedAt.year,
      generatedAt.month,
      generatedAt.day,
    ).subtract(Duration(days: generatedAt.weekday - 1));
    for (final item in inventory) {
      final date = _date(item['createdAt']);
      if (date == null) continue;
      final weeksAgo = startOfCurrentWeek.difference(date).inDays ~/ 7;
      if (weeksAgo >= 0 && weeksAgo < trend.length) {
        trend[trend.length - 1 - weeksAgo] += _number(item['weight']);
      }
    }

    final statuses = <String, int>{
      'New Requests': 0,
      'Scheduled': 0,
      'In Progress': 0,
      'Completed': 0,
    };
    for (final pickup in pickups) {
      final status = pickup['status']?.toString() ?? '';
      final bucket = switch (status) {
        'scheduled' || 'assigned' => 'Scheduled',
        'inProgress' => 'In Progress',
        'collected' || 'completed' => 'Completed',
        _ => 'New Requests',
      };
      statuses[bucket] = (statuses[bucket] ?? 0) + 1;
    }

    final recent = completed.isEmpty ? List.of(pickups) : List.of(completed);
    recent.sort(
      (a, b) =>
          (_date(b['updatedAt']) ?? _date(b['scheduledAt']) ?? DateTime(2000))
              .compareTo(
                _date(a['updatedAt']) ??
                    _date(a['scheduledAt']) ??
                    DateTime(2000),
              ),
    );

    final impact = impactCalculator.calculate(
      EnvironmentalImpactInput(
        collected: inventory
            .map(
              (item) => WeightedImpactEvent(
                weightKg: _number(item['weight']),
                occurredAt: _date(item['createdAt']),
              ),
            )
            .toList(),
        recycled: recycling
            .where(
              (item) =>
                  item['stage'] == 'completed' ||
                  item['completionVerified'] == true,
            )
            .map(
              (item) => WeightedImpactEvent(
                weightKg: _number(item['inputWeightKg']),
                occurredAt:
                    _date(item['completedAt']) ?? _date(item['updatedAt']),
              ),
            )
            .toList(),
        recoveredMaterials: materials
            .map(
              (item) => WeightedImpactEvent(
                weightKg: _number(item['weightKg']),
                material: item['material']?.toString() ?? 'other',
                occurredAt: _date(item['createdAt']),
              ),
            )
            .toList(),
        hazardousHandled: hazardous
            .where(
              (item) =>
                  item['status'] == 'disposed' || item['status'] == 'certified',
            )
            .map(
              (item) => WeightedImpactEvent(
                weightKg: _number(item['weightKg']),
                occurredAt:
                    _date(item['certifiedAt']) ??
                    _date(item['disposedAt']) ??
                    _date(item['updatedAt']),
              ),
            )
            .toList(),
        reusableDeviceDates: repairs
            .where((item) => item['status'] == 'completed')
            .map(
              (item) => _date(item['completedAt']) ?? _date(item['updatedAt']),
            )
            .toList(),
      ),
      now: generatedAt,
    );

    return AdminOverviewSnapshot(
      totalCollections: completed.length,
      collectedKg: inventory.fold(
        0,
        (total, item) => total + _number(item['weight']),
      ),
      recycledKg: impact.totalRecycledKg,
      activeUsers: users
          .where(
            (user) =>
                user['accountStatus'] == null ||
                user['accountStatus'] == 'active',
          )
          .length,
      totalUsers: users.length,
      totalPartners: partners.length,
      collectionCentres: centres
          .where(
            (centre) =>
                centre['status'] == null || centre['status'] == 'active',
          )
          .length,
      trackedItems: inventory.length,
      categoryWeights: categories,
      collectionTrend: trend,
      pickupStatuses: statuses,
      recentCollections: recent
          .take(4)
          .map(RecentCollectionSummary.fromRecord)
          .toList(),
      collectionLocations: pickups
          .where((item) => item['latitude'] is num && item['longitude'] is num)
          .take(8)
          .map(CollectionLocationSummary.fromRecord)
          .toList(),
      impact: impact,
      loadedSources: Set.unmodifiable(loadedSources),
      failedSources: Set.unmodifiable(failedSources),
      sourceCount: sourceCount,
    );
  }

  static double _number(Object? value) => (value as num? ?? 0).toDouble();
  static DateTime? _date(Object? value) => switch (value) {
    Timestamp timestamp => timestamp.toDate(),
    DateTime date => date,
    _ => null,
  };
  static String _displayCategory(String? value) {
    final raw = (value == null || value.trim().isEmpty) ? 'Other' : value;
    return raw
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (match) => '${match.group(1)} ${match.group(2)}',
        )
        .split(' ')
        .map(
          (word) => word.isEmpty
              ? word
              : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }
}

class RecentCollectionSummary {
  const RecentCollectionSummary({
    required this.id,
    required this.category,
    required this.location,
    required this.status,
    required this.occurredAt,
  });

  final String id;
  final String category;
  final String location;
  final String status;
  final DateTime? occurredAt;

  factory RecentCollectionSummary.fromRecord(Map<String, dynamic> record) =>
      RecentCollectionSummary(
        id: record['id']?.toString() ?? '',
        category: AdminOverviewSnapshot._displayCategory(
          record['category']?.toString(),
        ),
        location: record['location']?.toString() ?? 'Location not recorded',
        status: record['status']?.toString() ?? 'submitted',
        occurredAt:
            AdminOverviewSnapshot._date(record['updatedAt']) ??
            AdminOverviewSnapshot._date(record['scheduledAt']),
      );
}

class CollectionLocationSummary {
  const CollectionLocationSummary({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;

  factory CollectionLocationSummary.fromRecord(Map<String, dynamic> record) =>
      CollectionLocationSummary(
        latitude: (record['latitude'] as num).toDouble(),
        longitude: (record['longitude'] as num).toDouble(),
      );
}
