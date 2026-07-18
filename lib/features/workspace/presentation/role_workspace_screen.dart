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
import '../../fleet/data/fleet_repository.dart';
import '../../fleet/presentation/fleet_screens.dart';
import '../../hazardous/data/hazardous_waste_repository.dart';
import '../../hazardous/presentation/hazardous_waste_screens.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/presentation/inventory_screens.dart';
import '../../marketplace/data/marketplace_repository.dart';
import '../../marketplace/presentation/marketplace_screens.dart';
import '../../notifications/data/notification_repository.dart';
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
import '../domain/application_interface.dart';

class RoleWorkspaceScreen extends StatelessWidget {
  const RoleWorkspaceScreen({
    super.key,
    required this.authRepository,
    required this.profile,
  });

  final AuthRepository authRepository;
  final UserProfile profile;

  ApplicationInterface get application =>
      WorkspaceCatalog.interfaceFor(profile.role);
  List<WorkspaceDestination> get destinations =>
      WorkspaceCatalog.destinationsFor(profile.role);
  bool get isAdministrator =>
      profile.role == AppRole.administrator ||
      profile.role == AppRole.superAdministrator;

  @override
  Widget build(BuildContext context) {
    final menu = _navigation(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1000;
        return Scaffold(
          appBar: AppBar(
            title: Text(application.title),
            actions: [
              IconButton(
                tooltip: 'Notifications',
                onPressed: () =>
                    _open(context, WorkspaceDestination.notifications),
                icon: const Icon(Icons.notifications_outlined),
              ),
              IconButton(
                tooltip: 'Profile',
                onPressed: () => _open(context, WorkspaceDestination.profile),
                icon: const Icon(Icons.account_circle_outlined),
              ),
            ],
          ),
          drawer: wide ? null : Drawer(child: menu),
          body: Row(
            children: [
              if (wide) SizedBox(width: 300, child: menu),
              if (wide) const VerticalDivider(width: 1),
              Expanded(child: _dashboard(context)),
            ],
          ),
        );
      },
    );
  }

  Widget _navigation(BuildContext context) => Builder(
    builder: (menuContext) => NavigationDrawer(
      selectedIndex: 0,
      onDestinationSelected: (index) {
        if (Scaffold.maybeOf(menuContext)?.isDrawerOpen ?? false) {
          Navigator.pop(menuContext);
        }
        final destination = destinations[index];
        if (destination != WorkspaceDestination.dashboard) {
          _open(context, destination);
        }
      },
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.recycling, size: 38),
              const SizedBox(height: 8),
              Text(
                profile.displayName.isEmpty
                    ? profile.email
                    : profile.displayName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(profile.role.label),
            ],
          ),
        ),
        ...destinations.map(
          (destination) => NavigationDrawerDestination(
            icon: Icon(_icon(destination)),
            label: Text(destination.label),
          ),
        ),
        const Padding(padding: EdgeInsets.all(12), child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextButton.icon(
            onPressed: authRepository.signOut,
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ),
      ],
    ),
  );

  Widget _dashboard(BuildContext context) {
    final actions = destinations
        .where((destination) => destination != WorkspaceDestination.dashboard)
        .toList();
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
          sliver: SliverToBoxAdapter(
            child: Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome, ${profile.displayName.isEmpty ? profile.email : profile.displayName}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${application.title} • ${profile.role.label}\nSelect a workspace below to continue.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(20),
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
