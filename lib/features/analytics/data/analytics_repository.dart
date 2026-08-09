import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';
import '../domain/analytics_snapshot.dart';

class AnalyticsRepository {
  AnalyticsRepository({FirebaseFirestore? firestore, ApiClient? apiClient})
    : _db = firestore ?? FirebaseFirestore.instance,
      _api = apiClient ?? ApiClient.instance,
      _useApi = apiClient != null || (firestore == null && ApiConfig.enabled);
  final FirebaseFirestore _db;
  final ApiClient _api;
  final bool _useApi;
  Future<AnalyticsSnapshot> load(DateTime from, DateTime to) async {
    if (_useApi) return _loadApi(from, to);
    Future<List<Map<String, dynamic>>> c(String n) async =>
        (await _db.collection(n).get()).docs
            .map((d) => {'id': d.id, ...d.data()})
            .where((x) {
              final t = x['createdAt'];
              return t is! Timestamp ||
                  (t.toDate().isAfter(
                        from.subtract(const Duration(seconds: 1)),
                      ) &&
                      t.toDate().isBefore(to.add(const Duration(days: 1))));
            })
            .toList();
    final pickups = await c('pickupRequests'),
        inventory = await c('inventoryItems'),
        recycling = await c('recyclingBatches'),
        materials = await c('recoveredMaterialLots'),
        repairs = await c('repairJobs'),
        users = await c('users'),
        partners = await c('servicePartners'),
        billing = await c('billingTransactions'),
        hazard = await c('hazardousWasteRecords');
    double sum(List<Map<String, dynamic>> x, String k) =>
        x.fold(0, (s, e) => s + (e[k] as num? ?? 0).toDouble());
    final categories = <String, double>{};
    for (final x in inventory) {
      categories.update(
        x['deviceType'] ?? 'Other',
        (v) => v + (x['weight'] as num? ?? 0).toDouble(),
        ifAbsent: () => (x['weight'] as num? ?? 0).toDouble(),
      );
    }
    final regions = <String, double>{};
    for (final x in pickups) {
      regions.update(
        x['serviceArea'] ?? x['address'] ?? 'Unknown',
        (v) => v + 1,
        ifAbsent: () => 1,
      );
    }
    final completedPickups = pickups
            .where(
              (x) => x['status'] == 'completed' || x['status'] == 'collected',
            )
            .length,
        completedRecycling = recycling
            .where((x) => x['stage'] == 'completed')
            .toList();
    final rows = <Map<String, Object?>>[
      ...pickups.map(
        (x) => {
          'dataset': 'Pickup',
          'reference': x['id'],
          'status': x['status'],
          'value': x['estimatedWeight'] ?? 0,
        },
      ),
      ...inventory.map(
        (x) => {
          'dataset': 'Inventory',
          'reference': x['itemCode'] ?? x['id'],
          'status': x['processingStatus'],
          'value': x['weight'] ?? 0,
        },
      ),
      ...billing.map(
        (x) => {
          'dataset': 'Financial',
          'reference': x['transactionNumber'] ?? x['id'],
          'status': x['status'],
          'value': x['total'] ?? 0,
        },
      ),
    ];
    return AnalyticsSnapshot(
      from: from,
      to: to,
      metrics: {
        'collections': sum(inventory, 'weight'),
        'pickups': pickups.length.toDouble(),
        'pickupCompletionRate': pickups.isEmpty
            ? 0
            : completedPickups / pickups.length * 100,
        'inventoryItems': inventory.length.toDouble(),
        'recycledKg': sum(completedRecycling, 'inputWeightKg'),
        'recyclingRate': sum(inventory, 'weight') == 0
            ? 0
            : sum(completedRecycling, 'inputWeightKg') /
                  sum(inventory, 'weight') *
                  100,
        'recoveredKg': sum(materials, 'weightKg'),
        'recoveryRate': sum(completedRecycling, 'inputWeightKg') == 0
            ? 0
            : sum(materials, 'weightKg') /
                  sum(completedRecycling, 'inputWeightKg') *
                  100,
        'repairsCompleted': repairs
            .where((x) => x['status'] == 'completed')
            .length
            .toDouble(),
        'users': users.length.toDouble(),
        'partners': partners.length.toDouble(),
        'partnerRating': partners.isEmpty
            ? 0
            : sum(partners, 'performanceRating') / partners.length,
        'revenue': sum(
          billing.where((x) => x['status'] == 'confirmed').toList(),
          'total',
        ),
        'hazardousHandledKg': sum(
          hazard.where((x) => x['status'] == 'certified').toList(),
          'weightKg',
        ),
      },
      categories: categories,
      regions: regions,
      rows: rows,
    );
  }

  Future<AnalyticsSnapshot> _loadApi(DateTime from, DateTime to) async {
    final query = {'from': from.toUtc().toIso8601String(), 'to': to.toUtc().toIso8601String()};
    final results = await Future.wait([
      _api.get('/api/v1/analytics/overview', query: query),
      _api.get('/api/v1/analytics/waste/categories', query: query),
      _api.get('/api/v1/analytics/waste/regions', query: query),
      _api.get('/api/v1/analytics/operations', query: query),
      _api.get('/api/v1/analytics/revenue', query: query),
      _api.get('/api/v1/analytics/environmental', query: query),
    ]);
    final overview = results[0], categoriesData = results[1], regionsData = results[2], operations = results[3], revenue = results[4], impact = results[5];
    double number(Map<String, dynamic> map, String key) => (map[key] as num? ?? 0).toDouble();
    final categories = <String, double>{};
    for (final entry in categoriesData.entries) {
      if (entry.value is Map) categories[entry.key] = ((entry.value as Map)['weightKg'] as num? ?? 0).toDouble();
    }
    final regions = <String, double>{};
    for (final entry in regionsData.entries) {
      if (entry.value is Map) regions[entry.key] = ((entry.value as Map)['requests'] as num? ?? 0).toDouble();
    }
    return AnalyticsSnapshot(
      from: from,
      to: to,
      metrics: {
        'collections': number(overview, 'collectedKg'),
        'pickups': number(overview, 'pickupRequests'),
        'pickupCompletionRate': number(overview, 'pickupCompletionRate'),
        'inventoryItems': 0,
        'recycledKg': number(impact, 'recycledKg'),
        'recyclingRate': number(operations, 'recyclingRate'),
        'recoveredKg': number(impact, 'recoveredKg'),
        'recoveryRate': number(operations, 'resourceRecoveryRate'),
        'repairsCompleted': number(impact, 'reusableDevices'),
        'users': number(overview, 'newUsers'),
        'partners': number(overview, 'newPartners'),
        'partnerRating': 0,
        'revenue': number(revenue, 'combinedRevenue'),
        'hazardousHandledKg': number(impact, 'hazardousKg'),
      },
      categories: categories,
      regions: regions,
      rows: const [],
    );
  }

  Stream<List<ReportSchedule>> watchSchedules() => _useApi ? _pollSchedules() : _db
      .collection('reportSchedules')
      .snapshots()
      .map(
        (s) => s.docs.map((d) {
          final x = d.data();
          return ReportSchedule(
            id: d.id,
            name: x['name'],
            type: ReportType.values.byName(x['type']),
            frequency: x['frequency'],
            recipients: List<String>.from(x['recipients'] ?? []),
            active: x['active'] ?? true,
          );
        }).toList(),
      );
  Stream<List<ReportSchedule>> _pollSchedules() async* {
    while (true) {
      final data = await _api.getList('/api/v1/reports/schedules');
      yield data.map(ReportSchedule.fromJson).toList();
      await Future<void>.delayed(const Duration(seconds: ApiConfig.pollingSeconds));
    }
  }
  Future<void> schedule({
    required String name,
    required ReportType type,
    required String frequency,
    required List<String> recipients,
  }) async {
    if (_useApi) {
      final definition = await _api.post('/api/v1/reports/definitions', {
        'name': name,
        'type': type.name,
        'sourceCollection': type == ReportType.custom ? 'pickupRequests' : '',
        'fields': ['status', 'createdAt'],
        'filters': <Map<String, dynamic>>[],
        'metrics': ['count'],
        'active': true,
      });
      await _api.post('/api/v1/reports/schedules', {
        'definitionId': definition['id'],
        'frequency': frequency,
        'format': 'pdf',
        'recipientEmails': recipients.map((value) => value.contains('@') ? value : '$value@ecotrace.local').toList(),
        'nextRunAt': DateTime.now().add(const Duration(days: 30)).toUtc().toIso8601String(),
        'active': true,
      });
      return;
    }
    await _db.collection('reportSchedules').add({
    'name': name,
    'type': type.name,
    'frequency': frequency,
    'recipients': recipients,
    'active': true,
    'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
