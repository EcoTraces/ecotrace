import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wastemanagementsystem/features/auth/domain/app_role.dart';
import 'package:wastemanagementsystem/features/dispatch/domain/collection_schedule.dart';
import 'package:wastemanagementsystem/features/fleet/domain/vehicle.dart';
import 'package:wastemanagementsystem/features/workspace/presentation/field_operations_dashboard.dart';

void main() {
  group('responsive field operations dashboard', () {
    testWidgets('collector mobile layout matches the collection workflow', (
      tester,
    ) async {
      await _setSurface(tester, const Size(390, 844));
      await _pumpDashboard(
        tester,
        role: AppRole.collector,
        displayName: 'James Koroma',
      );

      expect(find.text('Hello, James 👋'), findsOneWidget);
      expect(find.text('Collector'), findsOneWidget);
      expect(find.text('Today’s Overview'), findsOneWidget);
      expect(find.text('Today’s Schedule'), findsOneWidget);
      expect(find.text('Scan QR code'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('driver mobile layout focuses on trip and vehicle status', (
      tester,
    ) async {
      await _setSurface(tester, const Size(390, 844));
      await _pumpDashboard(
        tester,
        role: AppRole.driver,
        displayName: 'Michael Kamara',
      );

      expect(find.text('Hello, Michael 👋'), findsOneWidget);
      expect(find.text('Driver'), findsOneWidget);
      expect(find.text('Current Trip'), findsOneWidget);
      expect(find.text('View route'), findsWidgets);
      expect(find.text('Vehicle Status'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('collector web and desktop layout exposes collection metrics', (
      tester,
    ) async {
      await _setSurface(tester, const Size(1440, 900));
      await _pumpDashboard(
        tester,
        role: AppRole.collector,
        displayName: 'James Koroma',
      );

      expect(find.text('Collector Operations'), findsOneWidget);
      expect(find.text('Assigned'), findsOneWidget);
      expect(find.text('Completion Rate'), findsOneWidget);
      expect(find.text('Today’s Schedule'), findsOneWidget);
      expect(find.text('Quick Actions'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('driver web and Windows layout exposes delivery metrics', (
      tester,
    ) async {
      await _setSurface(tester, const Size(1440, 900));
      await _pumpDashboard(
        tester,
        role: AppRole.driver,
        displayName: 'Michael Kamara',
      );

      expect(find.text('Driver Operations'), findsOneWidget);
      expect(find.text('Trips Assigned'), findsOneWidget);
      expect(find.text('In Transit'), findsOneWidget);
      expect(find.text('On-time Delivery'), findsOneWidget);
      expect(find.text('Current Assignment'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required AppRole role,
  required String displayName,
}) async {
  final isDriver = role == AppRole.driver;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: isDriver
              ? const Color(0xFF075AC8)
              : const Color(0xFF087A52),
        ),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: FieldOperationsDashboard(
          userId: isDriver ? 'driver-1' : 'collector-1',
          displayName: displayName,
          role: role,
          schedulesStream: Stream.value(_schedules),
          vehiclesStream: Stream.value([_vehicle]),
          onOpen: (_) {},
          onOpenMenu: () {},
          footer: const SizedBox(height: 60),
          mobileLayout: tester.view.physicalSize.width < 1000,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

final _schedules = [
  CollectionSchedule(
    id: 'trip-024-056',
    scheduledAt: DateTime.now(),
    pickupIds: const ['pickup-1', 'pickup-2'],
    collectorIds: const ['collector-1'],
    driverId: 'driver-1',
    vehicleId: 'vehicle-1',
    priority: DispatchPriority.high,
    status: DispatchStatus.inProgress,
    serviceArea: 'Freetown Central',
    evidenceUrls: const [],
  ),
  CollectionSchedule(
    id: 'trip-024-057',
    scheduledAt: DateTime.now().add(const Duration(hours: 2)),
    pickupIds: const ['pickup-3'],
    collectorIds: const ['collector-1'],
    driverId: 'driver-1',
    vehicleId: 'vehicle-1',
    priority: DispatchPriority.normal,
    status: DispatchStatus.completed,
    serviceArea: 'Waterloo',
    evidenceUrls: const [],
  ),
];

const _vehicle = Vehicle(
  id: 'vehicle-1',
  registrationNumber: 'SL-1234',
  type: VehicleType.truck,
  capacityKg: 1000,
  driverId: 'driver-1',
  availability: VehicleAvailability.dispatched,
  mileageKm: 12450,
  fuelLitres: 78,
  insuranceExpiry: null,
  licenceExpiry: null,
  latitude: 8.4928,
  longitude: -13.2351,
);
