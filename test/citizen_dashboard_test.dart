import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wastemanagementsystem/features/auth/domain/app_role.dart';
import 'package:wastemanagementsystem/features/pickups/domain/pickup.dart';
import 'package:wastemanagementsystem/features/rewards/domain/rewards.dart';
import 'package:wastemanagementsystem/features/workspace/presentation/citizen_dashboard.dart';

void main() {
  final pickup = PickupRequest(
    id: 'pickup-1',
    userId: 'user-1',
    category: WasteCategory.appliances,
    quantity: 2,
    weight: 32.5,
    condition: 'Repairable',
    location: 'Freetown',
    scheduledAt: DateTime(2026, 7, 25, 9),
    urgent: false,
    instructions: '',
    fee: 0,
    status: PickupStatus.scheduled,
    rating: null,
    photoUrls: const [],
    latitude: 8.4928,
    longitude: -13.2351,
  );
  const wallet = RewardWallet(
    userId: 'user-1',
    balance: 850,
    lifetimePoints: 950,
    level: RewardLevel.greenAdvocate,
    referralCode: 'ECO-USER1',
    businessSustainabilityScore: 72,
  );

  Widget dashboard({required bool mobile, required AppRole role}) =>
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF167D57)),
          useMaterial3: true,
        ),
        home: Scaffold(
          body: CitizenDashboard(
            userId: 'user-1',
            displayName: role == AppRole.business
                ? 'GreenTech Solutions Ltd.'
                : 'Sarah',
            role: role,
            pickupsStream: Stream.value([pickup]),
            walletStream: Stream.value(wallet),
            onOpen: (_) {},
            onOpenMenu: () {},
            footer: const SizedBox.shrink(),
            mobileLayout: mobile,
          ),
        ),
      );

  testWidgets('mobile household dashboard shows impact and action sections', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(dashboard(mobile: true, role: AppRole.household));
    await tester.pumpAndSettle();

    expect(find.text('Hello, Sarah 👋'), findsOneWidget);
    expect(find.text('My Impact This Month'), findsOneWidget);
    expect(find.text('What would you like to do?'), findsOneWidget);
    expect(find.text('Recent Request'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop business dashboard shows analytics and quick actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(dashboard(mobile: false, role: AppRole.business));
    await tester.pumpAndSettle();

    expect(find.text('Pickup Trends'), findsOneWidget);
    expect(find.text('E-Waste by Category'), findsOneWidget);
    expect(find.text('Recent Pickup Requests'), findsOneWidget);
    expect(find.text('Quick Actions'), findsOneWidget);
    expect(find.text('Business Rewards'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
