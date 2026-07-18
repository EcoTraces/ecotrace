import 'package:flutter_test/flutter_test.dart';
import 'package:wastemanagementsystem/features/workspace/data/admin_overview_repository.dart';

void main() {
  group('AdminOverviewSnapshot', () {
    test('summarizes live module records for the administrator dashboard', () {
      final now = DateTime(2026, 7, 18, 12);
      final snapshot = AdminOverviewSnapshot.fromRecords({
        'pickups': [
          {
            'id': 'pickup-one',
            'status': 'completed',
            'category': 'phones',
            'location': 'Freetown',
            'scheduledAt': now,
            'latitude': 8.4657,
            'longitude': -13.2317,
          },
          {
            'id': 'pickup-two',
            'status': 'scheduled',
            'category': 'computers',
            'location': 'Bo',
            'scheduledAt': now.subtract(const Duration(days: 1)),
          },
          {
            'id': 'pickup-three',
            'status': 'inProgress',
            'category': 'appliances',
            'location': 'Kenema',
            'scheduledAt': now.subtract(const Duration(days: 2)),
          },
        ],
        'inventory': [
          {'deviceType': 'mobilePhones', 'weight': 10, 'createdAt': now},
          {
            'deviceType': 'laptops',
            'weight': 15.5,
            'createdAt': now.subtract(const Duration(days: 8)),
          },
        ],
        'recycling': [
          {'stage': 'completed', 'inputWeightKg': 12, 'completedAt': now},
        ],
        'materials': [
          {'material': 'copper', 'weightKg': 4, 'createdAt': now},
        ],
        'hazardous': [
          {'status': 'certified', 'weightKg': 2, 'certifiedAt': now},
        ],
        'repairs': [
          {'status': 'completed', 'completedAt': now},
        ],
        'users': [
          {'accountStatus': 'active'},
          {'accountStatus': 'suspended'},
        ],
        'partners': [
          {'status': 'active'},
        ],
        'centres': [
          {'status': 'active'},
          {'status': 'inactive'},
        ],
      }, now: now);

      expect(snapshot.totalCollections, 1);
      expect(snapshot.collectedKg, 25.5);
      expect(snapshot.recycledKg, 12);
      expect(snapshot.activeUsers, 1);
      expect(snapshot.totalUsers, 2);
      expect(snapshot.totalPartners, 1);
      expect(snapshot.collectionCentres, 1);
      expect(snapshot.trackedItems, 2);
      expect(snapshot.categoryWeights['Mobile Phones'], 10);
      expect(snapshot.categoryWeights['Laptops'], 15.5);
      expect(snapshot.pickupStatuses['Completed'], 1);
      expect(snapshot.pickupStatuses['Scheduled'], 1);
      expect(snapshot.pickupStatuses['In Progress'], 1);
      expect(snapshot.pickupCompletionRate, closeTo(100 / 3, .001));
      expect(snapshot.recentCollections.single.id, 'pickup-one');
      expect(snapshot.collectionLocations, hasLength(1));
      expect(snapshot.impact.materialsRecoveredKg, 4);
      expect(snapshot.impact.reusableDevices, 1);
      expect(snapshot.impact.hazardousSafelyHandledKg, 2);
      expect(snapshot.collectionTrend.reduce((a, b) => a + b), 25.5);
    });

    test('returns zero-safe metrics when Firestore collections are empty', () {
      final snapshot = AdminOverviewSnapshot.fromRecords(const {});

      expect(snapshot.totalCollections, 0);
      expect(snapshot.collectedKg, 0);
      expect(snapshot.pickupCompletionRate, 0);
      expect(snapshot.categoryWeights, isEmpty);
      expect(snapshot.recentCollections, isEmpty);
      expect(snapshot.collectionTrend, hasLength(8));
    });
  });
}
