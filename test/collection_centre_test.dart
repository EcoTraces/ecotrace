import 'package:flutter_test/flutter_test.dart';
import 'package:wastemanagementsystem/features/centres/domain/collection_centre.dart';
import 'package:wastemanagementsystem/features/pickups/domain/pickup.dart';

void main() {
  CollectionCentre centre({
    double capacity = 1000,
    double stock = 0,
    double alert = 80,
  }) => CollectionCentre(
    id: 'centre-1',
    name: 'Central depot',
    address: '1 Circular Way',
    contactName: 'Operator',
    contactEmail: 'operator@example.com',
    contactPhone: '123',
    latitude: null,
    longitude: null,
    operatingHours: const {'Monday–Friday': '08:00–17:00'},
    supportedCategories: const [WasteCategory.computers],
    capacityKg: capacity,
    currentStockKg: stock,
    capacityAlertPercent: alert,
    staffIds: const [],
    active: true,
  );

  test('capacity monitoring reports occupancy and available storage', () {
    final subject = centre(stock: 250);
    expect(subject.occupancyPercent, 25);
    expect(subject.availableCapacityKg, 750);
    expect(subject.hasCapacityAlert, isFalse);
  });

  test('capacity alert activates at configured threshold', () {
    expect(centre(stock: 800).hasCapacityAlert, isTrue);
    expect(centre(stock: 799).hasCapacityAlert, isFalse);
  });

  test('available capacity never becomes negative', () {
    expect(centre(stock: 1200).availableCapacityKg, 0);
  });
}
