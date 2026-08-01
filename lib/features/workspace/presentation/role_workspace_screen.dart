import 'dart:async';

import 'package:flutter/material.dart';

import '../../admin/data/admin_repository.dart';
import '../../admin/presentation/admin_dashboard_screen.dart';
import '../../analytics/data/analytics_repository.dart';
import '../../analytics/presentation/analytics_reporting_screen.dart';
import '../../audit/data/audit_repository.dart';
import '../../audit/presentation/audit_trail_screen.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/app_role.dart';
import '../../auth/domain/user_profile.dart';
import '../../billing/data/billing_repository.dart';
import '../../billing/presentation/billing_screen.dart';
import '../../centres/data/collection_centre_repository.dart';
import '../../centres/domain/collection_centre.dart';
import '../../centres/presentation/collection_centre_screens.dart';
import '../../compliance/data/compliance_repository.dart';
import '../../compliance/presentation/compliance_screens.dart';
import '../../dispatch/data/dispatch_repository.dart';
import '../../dispatch/presentation/dispatch_screens.dart';
import '../../documents/data/document_repository.dart';
import '../../documents/presentation/document_screens.dart';
import '../../environmental_impact/data/environmental_impact_repository.dart';
import '../../fleet/data/fleet_repository.dart';
import '../../fleet/presentation/fleet_screens.dart';
import '../../hazardous/data/hazardous_waste_repository.dart';
import '../../hazardous/presentation/hazardous_waste_screens.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/presentation/inventory_screens.dart';
import '../../marketplace/data/marketplace_repository.dart';
import '../../marketplace/presentation/marketplace_screens.dart';
import '../../notifications/data/notification_repository.dart';
import '../../notifications/presentation/notification_badge.dart';
import '../../notifications/presentation/notification_screen.dart';
import '../../organizations/data/organization_repository.dart';
import '../../organizations/presentation/organization_screens.dart';
import '../../partners/data/partner_repository.dart';
import '../../partners/presentation/partner_screens.dart';
import '../../pickups/data/pickup_repository.dart';
import '../../pickups/presentation/pickup_screens.dart';
import '../../recovery/data/resource_recovery_repository.dart';
import '../../recovery/presentation/resource_recovery_screens.dart';
import '../../recycling/data/recycling_repository.dart';
import '../../recycling/presentation/recycling_screens.dart';
import '../../repairs/data/repair_repository.dart';
import '../../repairs/presentation/repair_screens.dart';
import '../../reverse_logistics/data/reverse_logistics_repository.dart';
import '../../reverse_logistics/presentation/reverse_logistics_screens.dart';
import '../../rewards/data/rewards_repository.dart';
import '../../rewards/presentation/rewards_screen.dart';
import '../../routing/data/route_repository.dart';
import '../../routing/presentation/route_screens.dart';
import '../../support/data/support_repository.dart';
import '../../support/presentation/support_screens.dart';
import '../../traceability/data/traceability_repository.dart';
import '../../traceability/presentation/traceability_screens.dart';
import '../data/admin_overview_repository.dart';
import '../domain/application_interface.dart';
import 'administrator_overview_dashboard.dart';
import 'citizen_dashboard.dart';
import 'field_operations_dashboard.dart';
import 'specialist_operations_dashboard.dart';

class RoleWorkspaceScreen extends StatelessWidget {
  const RoleWorkspaceScreen({
    super.key,
    required this.authRepository,
    required this.profile,
  });

  final AuthRepository authRepository;
  final UserProfile profile;

  static const _sideMenuGreen = Color(0xFF003D36);
  static const _activeMenuGreen = Color(0xFF138A4B);

  List<WorkspaceDestination> get destinations =>
      WorkspaceCatalog.destinationsFor(profile.role);
  bool get isAdministrator =>
      profile.role == AppRole.administrator ||
      profile.role == AppRole.superAdministrator;
  bool get isCitizen => AppRole.selfServiceRoles.contains(profile.role);
  bool get isField =>
      profile.role == AppRole.collector || profile.role == AppRole.driver;
  bool get isSpecialist =>
      profile.role == AppRole.environmentalOfficer ||
      profile.role == AppRole.repairTechnician ||
      profile.role == AppRole.recycler;
  Color get sideMenuColor =>
      profile.role == AppRole.driver || profile.role == AppRole.repairTechnician
      ? const Color(0xFF052D67)
      : _sideMenuGreen;
  Color get activeMenuColor =>
      profile.role == AppRole.driver || profile.role == AppRole.repairTechnician
      ? const Color(0xFF075AC8)
      : _activeMenuGreen;

  @override
  Widget build(BuildContext context) {
    final menu = _navigation(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1000;
        return Scaffold(
          appBar: wide || isCitizen || isField || isSpecialist
              ? null
              : AppBar(
                  title: const Text('EcoTrace'),
                  actions: [
                    const _LiveClock(compact: true),
                    IconButton(
                      tooltip: 'Notifications',
                      onPressed: () =>
                          _open(context, WorkspaceDestination.notifications),
                      icon: const NotificationBadgeIcon(),
                    ),
                    IconButton(
                      tooltip: 'Profile',
                      onPressed: () =>
                          _open(context, WorkspaceDestination.profile),
                      icon: const Icon(Icons.account_circle_outlined),
                    ),
                  ],
                ),
          drawer: wide
              ? null
              : Drawer(backgroundColor: sideMenuColor, child: menu),
          bottomNavigationBar: !wide
              ? isCitizen
                    ? _citizenBottomNavigation(context)
                    : isField
                    ? _fieldBottomNavigation(context)
                    : isSpecialist
                    ? _specialistBottomNavigation(context)
                    : null
              : null,
          body: Builder(
            builder: (bodyContext) => Row(
              children: [
                if (wide) SizedBox(width: 280, child: menu),
                Expanded(
                  child: Column(
                    children: [
                      if (wide || (!isCitizen && !isField && !isSpecialist))
                        _dashboardHeader(bodyContext, compact: !wide),
                      if (wide || (!isCitizen && !isField && !isSpecialist))
                        const Divider(height: 1),
                      Expanded(child: _dashboard(bodyContext)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _citizenBottomNavigation(BuildContext context) => NavigationBar(
    selectedIndex: 0,
    height: 68,
    backgroundColor: Colors.white,
    indicatorColor: const Color(0xFFDDF3E6),
    labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    onDestinationSelected: (index) {
      final destination = switch (index) {
        1 => WorkspaceDestination.myPickups,
        2 => WorkspaceDestination.trackWaste,
        3 => WorkspaceDestination.myPickups,
        4 => WorkspaceDestination.profile,
        _ => WorkspaceDestination.dashboard,
      };
      if (destination != WorkspaceDestination.dashboard) {
        _open(context, destination);
      }
    },
    destinations: const [
      NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: 'Home',
      ),
      NavigationDestination(
        icon: Icon(Icons.receipt_long_outlined),
        label: 'Requests',
      ),
      NavigationDestination(icon: Icon(Icons.qr_code_scanner), label: 'Scan'),
      NavigationDestination(icon: Icon(Icons.history), label: 'History'),
      NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
    ],
  );

  Widget _fieldBottomNavigation(BuildContext context) {
    final isDriver = profile.role == AppRole.driver;
    final accent = isDriver ? const Color(0xFF075AC8) : const Color(0xFF087A52);
    return NavigationBarTheme(
      data: NavigationBarThemeData(
        indicatorColor: accent.withValues(alpha: .14),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? accent : null,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected) ? accent : null,
            fontSize: 10,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      child: NavigationBar(
        selectedIndex: 0,
        height: 68,
        backgroundColor: Colors.white,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) {
          final destination = switch (index) {
            1 => WorkspaceDestination.assignedPickups,
            2 =>
              isDriver
                  ? WorkspaceDestination.routeNavigation
                  : WorkspaceDestination.scanQrCode,
            3 => WorkspaceDestination.collectionHistory,
            4 => WorkspaceDestination.profile,
            _ => WorkspaceDestination.dashboard,
          };
          if (destination != WorkspaceDestination.dashboard) {
            _open(context, destination);
          }
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(
              isDriver
                  ? Icons.local_shipping_outlined
                  : Icons.event_note_outlined,
            ),
            label: isDriver ? 'Trips' : 'Schedule',
          ),
          NavigationDestination(
            icon: Icon(
              isDriver ? Icons.navigation_outlined : Icons.qr_code_scanner,
            ),
            label: isDriver ? 'Route' : 'Scan QR',
          ),
          const NavigationDestination(
            icon: Icon(Icons.history),
            label: 'History',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'More',
          ),
        ],
      ),
    );
  }

  Widget _specialistBottomNavigation(BuildContext context) {
    const accent = Color(0xFF087A45);
    final destinations = switch (profile.role) {
      AppRole.environmentalOfficer => const [
        _MobileNavItem(
          destination: WorkspaceDestination.dashboard,
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
          label: 'Dashboard',
        ),
        _MobileNavItem(
          destination: WorkspaceDestination.compliance,
          icon: Icons.fact_check_outlined,
          label: 'Inspections',
        ),
        _MobileNavItem(
          destination: WorkspaceDestination.inventory,
          icon: Icons.add_circle_outline,
          label: 'Add',
        ),
        _MobileNavItem(
          destination: WorkspaceDestination.reports,
          icon: Icons.analytics_outlined,
          label: 'Reports',
        ),
        _MobileNavItem(
          destination: WorkspaceDestination.profile,
          icon: Icons.person_outline,
          label: 'Profile',
        ),
      ],
      AppRole.repairTechnician => const [
        _MobileNavItem(
          destination: WorkspaceDestination.dashboard,
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
          label: 'Home',
        ),
        _MobileNavItem(
          destination: WorkspaceDestination.repairJobs,
          icon: Icons.assignment_outlined,
          label: 'Jobs',
        ),
        _MobileNavItem(
          destination: WorkspaceDestination.scanQrCode,
          icon: Icons.qr_code_scanner,
          label: 'Scan',
        ),
        _MobileNavItem(
          destination: WorkspaceDestination.notifications,
          icon: Icons.notifications_outlined,
          label: 'Alerts',
        ),
        _MobileNavItem(
          destination: WorkspaceDestination.profile,
          icon: Icons.person_outline,
          label: 'Profile',
        ),
      ],
      _ => const [
        _MobileNavItem(
          destination: WorkspaceDestination.dashboard,
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
          label: 'Dashboard',
        ),
        _MobileNavItem(
          destination: WorkspaceDestination.recyclingBatches,
          icon: Icons.local_shipping_outlined,
          label: 'Waste',
        ),
        _MobileNavItem(
          destination: WorkspaceDestination.scanQrCode,
          icon: Icons.qr_code_scanner,
          label: 'Scan',
        ),
        _MobileNavItem(
          destination: WorkspaceDestination.reports,
          icon: Icons.analytics_outlined,
          label: 'Reports',
        ),
        _MobileNavItem(
          destination: WorkspaceDestination.profile,
          icon: Icons.person_outline,
          label: 'Profile',
        ),
      ],
    };
    return NavigationBarTheme(
      data: NavigationBarThemeData(
        indicatorColor: accent.withValues(alpha: .14),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? accent : null,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected) ? accent : null,
            fontSize: 10,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      child: NavigationBar(
        selectedIndex: 0,
        height: 68,
        backgroundColor: Colors.white,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) {
          final destination = destinations[index].destination;
          if (destination != WorkspaceDestination.dashboard) {
            _open(context, destination);
          }
        },
        destinations: [
          for (final item in destinations)
            NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selectedIcon ?? item.icon),
              label: item.label,
            ),
        ],
      ),
    );
  }

  Widget _navigation(BuildContext context) => Builder(
    builder: (menuContext) => ColoredBox(
      color: sideMenuColor,
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.recycling, size: 38, color: Color(0xFF20C45A)),
                      SizedBox(width: 8),
                      Text(
                        'EcoTrace',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.7,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 7),
                  Text(
                    'E-Waste Recovery &\nCircular Economy Platform',
                    style: TextStyle(
                      color: Color(0xCCFFFFFF),
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0x26FFFFFF)),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                itemCount: destinations.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final destination = destinations[index];
                  final selected =
                      destination == WorkspaceDestination.dashboard;
                  return Material(
                    color: selected ? activeMenuColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        if (Scaffold.maybeOf(menuContext)?.isDrawerOpen ??
                            false) {
                          Navigator.pop(menuContext);
                        }
                        if (destination != WorkspaceDestination.dashboard) {
                          _open(context, destination);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _icon(destination),
                              size: 19,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 13),
                            Expanded(
                              child: Text(
                                destination.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(42),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: authRepository.signOut,
                icon: const Icon(Icons.logout, size: 19),
                label: const Text('Sign out'),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 0, 14, 18),
              child: _SustainabilityCard(),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _dashboardHeader(BuildContext context, {required bool compact}) {
    final name = profile.displayName.isEmpty
        ? profile.email.split('@').first
        : profile.displayName;
    final fieldRole = profile.role == AppRole.driver
        ? 'Driver'
        : profile.role == AppRole.collector
        ? 'Collector'
        : null;
    final specialistRole = switch (profile.role) {
      AppRole.environmentalOfficer => 'Environmental Officer',
      AppRole.repairTechnician => 'Technician',
      AppRole.recycler => 'Recycler',
      _ => null,
    };
    final citizenRole = switch (profile.role) {
      AppRole.household => 'Household',
      AppRole.business => 'Business',
      AppRole.institution => 'Institution',
      _ => null,
    };
    final introduction = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          fieldRole != null
              ? '$fieldRole Dashboard'
              : specialistRole != null
              ? '$specialistRole Dashboard'
              : citizenRole != null
              ? '$citizenRole User Dashboard'
              : 'Dashboard Overview',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          fieldRole != null
              ? 'Welcome back, $name! Here are your field operations for today.'
              : specialistRole != null
              ? 'Welcome back, $name! Here is your ${specialistRole.toLowerCase()} operations overview.'
              : citizenRole != null
              ? 'Welcome back, $name! Here is your environmental impact and pickup activity.'
              : "Welcome back, $name! Here's what's happening in EcoTrace today.",
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 18 : 28,
          compact ? 18 : 22,
          compact ? 18 : 28,
          compact ? 16 : 20,
        ),
        child: compact
            ? Align(alignment: Alignment.centerLeft, child: introduction)
            : LayoutBuilder(
                builder: (context, constraints) {
                  final controls = Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(
                        width: 210,
                        height: 42,
                        child: TextField(
                          textInputAction: TextInputAction.search,
                          onSubmitted: (value) =>
                              _searchDestination(context, value),
                          decoration: InputDecoration(
                            hintText: 'Search modules...',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            contentPadding: EdgeInsets.zero,
                            filled: true,
                            fillColor: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerLowest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: Theme.of(
                                  context,
                                ).colorScheme.outlineVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                      IconButton.outlined(
                        tooltip: 'Notifications',
                        onPressed: () =>
                            _open(context, WorkspaceDestination.notifications),
                        icon: const NotificationBadgeIcon(size: 21),
                      ),
                      _HeaderUserMenu(
                        name: name,
                        role: profile.role.label,
                        initials: _profileInitials,
                        onProfile: () =>
                            _open(context, WorkspaceDestination.profile),
                        onSignOut: authRepository.signOut,
                      ),
                      const _LiveClock(),
                    ],
                  );
                  if (constraints.maxWidth >= 1050) {
                    return Row(
                      children: [
                        Expanded(child: introduction),
                        const SizedBox(width: 24),
                        controls,
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      introduction,
                      const SizedBox(height: 18),
                      Align(alignment: Alignment.centerRight, child: controls),
                    ],
                  );
                },
              ),
      ),
    );
  }

  String get _profileInitials {
    final source = profile.displayName.trim().isEmpty
        ? profile.email.split('@').first
        : profile.displayName.trim();
    final parts = source
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'ET';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  void _searchDestination(BuildContext context, String value) {
    final query = value.trim().toLowerCase();
    if (query.isEmpty) return;
    final matches = destinations.where(
      (destination) => destination.label.toLowerCase().contains(query),
    );
    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No dashboard module found for "$value".')),
      );
      return;
    }
    final destination = matches.first;
    if (destination != WorkspaceDestination.dashboard) {
      _open(context, destination);
    }
  }

  Widget _dashboard(BuildContext context) {
    if (isAdministrator) {
      return AdministratorOverviewDashboard(
        repository: AdminOverviewRepository(),
        onOpen: (destination) => _open(context, destination),
        footer: const _ImpactFooter(),
      );
    }
    if (profile.role == AppRole.collector || profile.role == AppRole.driver) {
      final name = profile.displayName.trim().isEmpty
          ? profile.email.split('@').first
          : profile.displayName.trim();
      return FieldOperationsDashboard(
        userId: profile.uid,
        displayName: name,
        role: profile.role,
        dispatchRepository: DispatchRepository(),
        fleetRepository: FleetRepository(),
        onOpen: (destination) => _open(context, destination),
        onOpenMenu: () => Scaffold.maybeOf(context)?.openDrawer(),
        footer: const _ImpactFooter(),
        mobileLayout: MediaQuery.sizeOf(context).width < 1000,
      );
    }
    if (isCitizen) {
      final name = profile.displayName.trim().isEmpty
          ? profile.email.split('@').first
          : profile.displayName.trim();
      return CitizenDashboard(
        userId: profile.uid,
        displayName: name,
        role: profile.role,
        pickupRepository: PickupRepository(),
        rewardsRepository: RewardsRepository(),
        onOpen: (destination) => _open(context, destination),
        onOpenMenu: () => Scaffold.maybeOf(context)?.openDrawer(),
        footer: const _ImpactFooter(),
        mobileLayout: MediaQuery.sizeOf(context).width < 1000,
      );
    }
    if (isSpecialist) {
      final name = profile.displayName.trim().isEmpty
          ? profile.email.split('@').first
          : profile.displayName.trim();
      return SpecialistOperationsDashboard(
        userId: profile.uid,
        displayName: name,
        role: profile.role,
        complianceRepository: profile.role == AppRole.environmentalOfficer
            ? ComplianceRepository()
            : null,
        environmentalImpactRepository:
            profile.role == AppRole.environmentalOfficer
            ? EnvironmentalImpactRepository()
            : null,
        repairRepository: profile.role == AppRole.repairTechnician
            ? RepairRepository()
            : null,
        recyclingRepository: profile.role == AppRole.recycler
            ? RecyclingRepository()
            : null,
        resourceRecoveryRepository: profile.role == AppRole.recycler
            ? ResourceRecoveryRepository()
            : null,
        onOpen: (destination) => _open(context, destination),
        onOpenMenu: () => Scaffold.maybeOf(context)?.openDrawer(),
        footer: const _ImpactFooter(),
        mobileLayout: MediaQuery.sizeOf(context).width < 1000,
      );
    }
    final actions = destinations
        .where((destination) => destination != WorkspaceDestination.dashboard)
        .toList();
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          sliver: SliverGrid.builder(
            itemCount: actions.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 260,
              mainAxisExtent: 132,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemBuilder: (context, index) {
              final destination = actions[index];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _open(context, destination),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_icon(destination), size: 30),
                        const SizedBox(height: 10),
                        Text(
                          destination.label,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 24),
          sliver: SliverToBoxAdapter(child: _ImpactFooter()),
        ),
      ],
    );
  }

  void _open(BuildContext context, WorkspaceDestination destination) {
    final screen = _screen(destination);
    if (screen == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Widget? _screen(WorkspaceDestination destination) => switch (destination) {
    WorkspaceDestination.dashboard => null,
    WorkspaceDestination.requestPickup => CreatePickupScreen(
      uid: profile.uid,
      repository: PickupRepository(),
    ),
    WorkspaceDestination.myPickups => PickupListScreen(
      uid: profile.uid,
      repository: PickupRepository(),
    ),
    WorkspaceDestination.trackWaste || WorkspaceDestination.scanQrCode =>
      TraceScannerScreen(repository: TraceabilityRepository()),
    WorkspaceDestination.collectionCentres =>
      profile.role == AppRole.collectionCentreOperator || isAdministrator
          ? CollectionCentreDashboardScreen(
              repository: CollectionCentreRepository(),
              currentUserId: profile.uid,
              canRegister: true,
            )
          : _CollectionCentreDirectoryScreen(
              repository: CollectionCentreRepository(),
            ),
    WorkspaceDestination.rewards => RewardsScreen(
      repository: RewardsRepository(),
      userId: profile.uid,
      canManage: isAdministrator,
    ),
    WorkspaceDestination.marketplace => MarketplaceScreen(
      repository: MarketplaceRepository(),
      currentUserId: profile.uid,
      currentUserName: profile.displayName,
      currentUserEmail: profile.email,
      canListDevices: profile.role == AppRole.repairTechnician,
      canListMaterials: profile.role == AppRole.recycler,
    ),
    WorkspaceDestination.notifications => NotificationScreen(
      repository: NotificationRepository(),
      uid: profile.uid,
      canManage: isAdministrator,
    ),
    WorkspaceDestination.support => SupportDashboardScreen(
      repository: SupportRepository(),
      currentUserId: profile.uid,
      currentUserName: profile.displayName.isEmpty
          ? profile.email
          : profile.displayName,
      isAgent: isAdministrator,
    ),
    WorkspaceDestination.profile => _ProfileScreen(
      repository: authRepository,
      profile: profile,
    ),
    WorkspaceDestination.assignedPickups ||
    WorkspaceDestination.pickupDetails ||
    WorkspaceDestination.recordWeight ||
    WorkspaceDestination.uploadProof ||
    WorkspaceDestination.updatePickupStatus ||
    WorkspaceDestination.reportFailedPickup ||
    WorkspaceDestination.collectionHistory ||
    WorkspaceDestination.pickupRequests ||
    WorkspaceDestination.collections => DispatchDashboardScreen(
      repository: DispatchRepository(),
      routeRepository: RouteRepository(),
      canGenerateRoutes: isAdministrator,
    ),
    WorkspaceDestination.routeNavigation => RouteDashboardScreen(
      repository: RouteRepository(),
      canOptimize: profile.role != AppRole.driver,
      currentUserId: profile.uid,
    ),
    WorkspaceDestination.vehicleInformation => FleetScreen(
      repository: FleetRepository(),
    ),
    WorkspaceDestination.receivedItems ||
    WorkspaceDestination.assessment ||
    WorkspaceDestination.inventory ||
    WorkspaceDestination.classification => InventoryScreen(
      repository: InventoryRepository(),
      canApprove:
          profile.role == AppRole.environmentalOfficer || isAdministrator,
    ),
    WorkspaceDestination.repairJobs => RepairDashboardScreen(
      repository: RepairRepository(),
      inventoryRepository: InventoryRepository(),
      currentUserId: profile.uid,
      canApprove:
          profile.role == AppRole.environmentalOfficer || isAdministrator,
    ),
    WorkspaceDestination.recyclingBatches => RecyclingDashboardScreen(
      repository: RecyclingRepository(),
      inventoryRepository: InventoryRepository(),
      currentUserId: profile.uid,
      canVerify:
          profile.role == AppRole.environmentalOfficer || isAdministrator,
    ),
    WorkspaceDestination.resourceRecovery => ResourceRecoveryDashboardScreen(
      repository: ResourceRecoveryRepository(),
      currentUserId: profile.uid,
    ),
    WorkspaceDestination.hazardousItems => HazardousWasteDashboardScreen(
      repository: HazardousWasteRepository(),
      currentUserId: profile.uid,
      canCertify:
          profile.role == AppRole.environmentalOfficer || isAdministrator,
    ),
    WorkspaceDestination.certificates => DocumentDashboardScreen(
      repository: DocumentRepository(),
      userId: profile.uid,
      userName: profile.displayName.isEmpty
          ? profile.email
          : profile.displayName,
      canGovern:
          profile.role == AppRole.environmentalOfficer || isAdministrator,
    ),
    WorkspaceDestination.reports || WorkspaceDestination.analytics =>
      AnalyticsReportingScreen(repository: AnalyticsRepository()),
    WorkspaceDestination.recyclingAndRecovery => _FeatureHub(
      title: 'Recycling and recovery',
      features: [
        _FeatureLink(
          label: 'Recycling processes',
          icon: Icons.recycling,
          screen: RecyclingDashboardScreen(
            repository: RecyclingRepository(),
            inventoryRepository: InventoryRepository(),
            currentUserId: profile.uid,
            canVerify:
                profile.role == AppRole.environmentalOfficer || isAdministrator,
          ),
        ),
        _FeatureLink(
          label: 'Resource recovery',
          icon: Icons.precision_manufacturing_outlined,
          screen: ResourceRecoveryDashboardScreen(
            repository: ResourceRecoveryRepository(),
            currentUserId: profile.uid,
          ),
        ),
        _FeatureLink(
          label: 'Hazardous waste',
          icon: Icons.warning_amber_outlined,
          screen: HazardousWasteDashboardScreen(
            repository: HazardousWasteRepository(),
            currentUserId: profile.uid,
            canCertify:
                profile.role == AppRole.environmentalOfficer || isAdministrator,
          ),
        ),
      ],
    ),
    WorkspaceDestination.reverseLogistics => ReverseLogisticsDashboardScreen(
      repository: ReverseLogisticsRepository(),
      currentUserId: profile.uid,
      isDriver: profile.role == AppRole.driver,
      canCreate:
          profile.role == AppRole.collectionCentreOperator ||
          profile.role == AppRole.environmentalOfficer ||
          isAdministrator,
      canApprove:
          profile.role == AppRole.collectionCentreOperator ||
          profile.role == AppRole.environmentalOfficer ||
          isAdministrator,
      canReceive: true,
    ),
    WorkspaceDestination.usersAndOrganizations => _FeatureHub(
      title: 'Users and organizations',
      features: [
        _FeatureLink(
          label: 'User administration',
          icon: Icons.manage_accounts_outlined,
          screen: AdministrationDashboardScreen(
            repository: AdminRepository(),
            auditRepository: AuditRepository(),
            initialTab: 1,
          ),
        ),
        _FeatureLink(
          label: 'Organization reviews',
          icon: Icons.apartment_outlined,
          screen: OrganizationReviewScreen(
            repository: OrganizationRepository(),
          ),
        ),
      ],
    ),
    WorkspaceDestination.partners => PartnerDashboardScreen(
      repository: PartnerRepository(),
      currentUserId: profile.uid,
      canManage: true,
    ),
    WorkspaceDestination.payments => BillingScreen(
      repository: BillingRepository(),
      userId: profile.uid,
      canManage: true,
    ),
    WorkspaceDestination.compliance => ComplianceDashboardScreen(
      repository: ComplianceRepository(),
      currentUserId: profile.uid,
      canManage: true,
    ),
    WorkspaceDestination.auditLogs => AuditTrailScreen(
      repository: AuditRepository(),
    ),
    WorkspaceDestination.settings => AdministrationDashboardScreen(
      repository: AdminRepository(),
      auditRepository: AuditRepository(),
      initialTab: 3,
    ),
  };

  IconData _icon(WorkspaceDestination destination) => switch (destination) {
    WorkspaceDestination.dashboard => Icons.dashboard_outlined,
    WorkspaceDestination.requestPickup => Icons.add_location_alt_outlined,
    WorkspaceDestination.myPickups ||
    WorkspaceDestination.pickupRequests => Icons.local_shipping_outlined,
    WorkspaceDestination.trackWaste => Icons.travel_explore,
    WorkspaceDestination.collectionCentres => Icons.warehouse_outlined,
    WorkspaceDestination.rewards => Icons.emoji_events_outlined,
    WorkspaceDestination.marketplace => Icons.storefront_outlined,
    WorkspaceDestination.notifications => Icons.notifications_outlined,
    WorkspaceDestination.support => Icons.support_agent,
    WorkspaceDestination.profile => Icons.person_outline,
    WorkspaceDestination.routeNavigation => Icons.navigation_outlined,
    WorkspaceDestination.scanQrCode => Icons.qr_code_scanner,
    WorkspaceDestination.vehicleInformation => Icons.local_shipping,
    WorkspaceDestination.receivedItems => Icons.move_to_inbox_outlined,
    WorkspaceDestination.assessment ||
    WorkspaceDestination.classification => Icons.fact_check_outlined,
    WorkspaceDestination.repairJobs => Icons.handyman_outlined,
    WorkspaceDestination.recyclingBatches ||
    WorkspaceDestination.recyclingAndRecovery => Icons.recycling,
    WorkspaceDestination.resourceRecovery =>
      Icons.precision_manufacturing_outlined,
    WorkspaceDestination.hazardousItems => Icons.warning_amber_outlined,
    WorkspaceDestination.inventory => Icons.inventory_2_outlined,
    WorkspaceDestination.certificates => Icons.workspace_premium_outlined,
    WorkspaceDestination.reports => Icons.description_outlined,
    WorkspaceDestination.reverseLogistics => Icons.swap_horiz,
    WorkspaceDestination.usersAndOrganizations => Icons.groups_outlined,
    WorkspaceDestination.partners => Icons.handshake_outlined,
    WorkspaceDestination.payments => Icons.payments_outlined,
    WorkspaceDestination.analytics => Icons.analytics_outlined,
    WorkspaceDestination.compliance => Icons.policy_outlined,
    WorkspaceDestination.auditLogs => Icons.history,
    WorkspaceDestination.settings => Icons.settings_outlined,
    WorkspaceDestination.assignedPickups ||
    WorkspaceDestination.pickupDetails ||
    WorkspaceDestination.recordWeight ||
    WorkspaceDestination.uploadProof ||
    WorkspaceDestination.updatePickupStatus ||
    WorkspaceDestination.reportFailedPickup ||
    WorkspaceDestination.collectionHistory ||
    WorkspaceDestination.collections => Icons.assignment_outlined,
  };
}

class _MobileNavItem {
  const _MobileNavItem({
    required this.destination,
    required this.icon,
    required this.label,
    this.selectedIcon,
  });

  final WorkspaceDestination destination;
  final IconData icon;
  final IconData? selectedIcon;
  final String label;
}

class _ImpactFooter extends StatelessWidget {
  const _ImpactFooter();

  static const _items = [
    _ImpactFooterItem(
      icon: Icons.eco,
      title: 'Environmental Impact',
      description: 'Reduces pollution and conserves natural resources.',
    ),
    _ImpactFooterItem(
      icon: Icons.trending_up,
      title: 'Economic Impact',
      description:
          'Creates green jobs and supports resource recovery industries.',
    ),
    _ImpactFooterItem(
      icon: Icons.groups,
      title: 'Social Impact',
      description: 'Protects public health and promotes community awareness.',
    ),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final footerWidth = constraints.maxWidth < 900
          ? 900.0
          : constraints.maxWidth;
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: ColoredBox(
          color: const Color(0xFF06253F),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: footerWidth,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < _items.length; index++) ...[
                      Expanded(child: _items[index]),
                      if (index < _items.length - 1)
                        const VerticalDivider(
                          width: 1,
                          thickness: 1,
                          indent: 18,
                          endIndent: 18,
                          color: Color(0x33FFFFFF),
                        ),
                    ],
                    const SizedBox(width: 260, child: _CleanerFutureCallout()),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _ImpactFooterItem extends StatelessWidget {
  const _ImpactFooterItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    child: Row(
      children: [
        Icon(icon, size: 38, color: const Color(0xFF9CD66D)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: const TextStyle(
                  color: Color(0xCCFFFFFF),
                  fontSize: 11,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CleanerFutureCallout extends StatelessWidget {
  const _CleanerFutureCallout();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF18763A),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.recycling, size: 40, color: Colors.white),
          const SizedBox(width: 13),
          Flexible(
            child: Text(
              'Together for a\nCleaner Future!',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SustainabilityCard extends StatelessWidget {
  const _SustainabilityCard();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0x1A20C45A),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0x8020C45A)),
    ),
    child: const Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: Color(0xFF86D888),
              child: Icon(Icons.eco, size: 20, color: Color(0xFF075B35)),
            ),
            SizedBox(width: 9),
            Flexible(
              child: Text(
                'Together for a\nCleaner Future',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 10),
        Text(
          'Reduce. Reuse. Recycle.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 10),
        ),
      ],
    ),
  );
}

class _HeaderUserMenu extends StatelessWidget {
  const _HeaderUserMenu({
    required this.name,
    required this.role,
    required this.initials,
    required this.onProfile,
    required this.onSignOut,
  });

  final String name;
  final String role;
  final String initials;
  final VoidCallback onProfile;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Account menu',
    onSelected: (value) {
      if (value == 'profile') onProfile();
      if (value == 'signOut') onSignOut();
    },
    itemBuilder: (context) => const [
      PopupMenuItem(
        value: 'profile',
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.person_outline),
          title: Text('Profile'),
        ),
      ),
      PopupMenuItem(
        value: 'signOut',
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.logout),
          title: Text('Sign out'),
        ),
      ),
    ],
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: const Color(0xFFDBEDE3),
              foregroundColor: const Color(0xFF075B35),
              child: Text(
                initials,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 9),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    role,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, size: 18),
          ],
        ),
      ),
    ),
  );
}

class _LiveClock extends StatefulWidget {
  const _LiveClock({this.compact = false});

  final bool compact;

  @override
  State<_LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<_LiveClock> {
  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _time {
    final hour = _now.hour % 12 == 0 ? 12 : _now.hour % 12;
    final period = _now.hour < 12 ? 'AM' : 'PM';
    return '${_twoDigits(hour)}:${_twoDigits(_now.minute)}:'
        '${_twoDigits(_now.second)} $period';
  }

  String get _date =>
      '${_weekdays[_now.weekday - 1]}, ${_months[_now.month - 1]} '
      '${_now.day}, ${_now.year}';

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final showDate = !widget.compact && MediaQuery.sizeOf(context).width >= 720;
    final textColor = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      label: 'Local date and time: $_date, $_time',
      liveRegion: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? 4 : 11,
          vertical: widget.compact ? 3 : 7,
        ),
        decoration: widget.compact
            ? null
            : BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.compact) ...[
              Icon(Icons.calendar_month_outlined, size: 19, color: textColor),
              const SizedBox(width: 7),
            ],
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  widget.compact
                      ? _time.replaceFirst(RegExp(r'\s[AP]M$'), '')
                      : _time,
                  style: TextStyle(
                    color: textColor,
                    fontSize: widget.compact ? 11 : 12,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (showDate)
                  Text(_date, style: TextStyle(color: textColor, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileScreen extends StatelessWidget {
  const _ProfileScreen({required this.repository, required this.profile});
  final AuthRepository repository;
  final UserProfile profile;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Profile')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const CircleAvatar(radius: 42, child: Icon(Icons.person, size: 42)),
        const SizedBox(height: 16),
        ListTile(
          title: const Text('Name'),
          subtitle: Text(profile.displayName),
        ),
        ListTile(title: const Text('Email'), subtitle: Text(profile.email)),
        ListTile(title: const Text('Role'), subtitle: Text(profile.role.label)),
        ListTile(
          title: const Text('Account status'),
          subtitle: Text(profile.accountStatus.name),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () => _rename(context),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit display name'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: repository.signOut,
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    ),
  );

  Future<void> _rename(BuildContext context) async {
    final controller = TextEditingController(text: profile.displayName);
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit display name'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Display name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (save == true) await repository.updateDisplayName(controller.text);
    controller.dispose();
  }
}

class _FeatureLink {
  const _FeatureLink({
    required this.label,
    required this.icon,
    required this.screen,
  });
  final String label;
  final IconData icon;
  final Widget screen;
}

class _CollectionCentreDirectoryScreen extends StatelessWidget {
  const _CollectionCentreDirectoryScreen({required this.repository});
  final CollectionCentreRepository repository;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Collection centres')),
    body: StreamBuilder<List<CollectionCentre>>(
      stream: repository.watchCentres(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Unable to load centres: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final centres = snapshot.data!
            .where((centre) => centre.active)
            .toList();
        if (centres.isEmpty) {
          return const Center(
            child: Text('No active collection centres found.'),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const Card(
              child: ListTile(
                leading: Icon(Icons.location_on_outlined),
                title: Text('Find a drop-off location'),
                subtitle: Text(
                  'Check the address, contact details, operating hours, and accepted waste categories before travelling.',
                ),
              ),
            ),
            ...centres.map(
              (centre) => Card(
                child: ExpansionTile(
                  leading: const Icon(Icons.warehouse_outlined),
                  title: Text(centre.name),
                  subtitle: Text(centre.address),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    ListTile(
                      leading: const Icon(Icons.call_outlined),
                      title: Text(
                        centre.contactPhone.isEmpty
                            ? 'No phone listed'
                            : centre.contactPhone,
                      ),
                      subtitle: Text(centre.contactEmail),
                    ),
                    ListTile(
                      leading: const Icon(Icons.schedule_outlined),
                      title: const Text('Operating hours'),
                      subtitle: Text(
                        centre.operatingHours.entries
                            .map((entry) => '${entry.key}: ${entry.value}')
                            .join('\n'),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.category_outlined),
                      title: const Text('Accepted categories'),
                      subtitle: Text(
                        centre.supportedCategories
                            .map((category) => category.label)
                            .join(', '),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _FeatureHub extends StatelessWidget {
  const _FeatureHub({required this.title, required this.features});
  final String title;
  final List<_FeatureLink> features;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: features
          .map(
            (feature) => Card(
              child: ListTile(
                leading: Icon(feature.icon),
                title: Text(feature.label),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => feature.screen),
                ),
              ),
            ),
          )
          .toList(),
    ),
  );
}
