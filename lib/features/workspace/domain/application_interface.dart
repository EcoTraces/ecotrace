import '../../auth/domain/app_role.dart';

enum ApplicationInterface {
  citizen,
  fieldOperations,
  processing,
  administration,
}

enum WorkspaceDestination {
  dashboard,
  requestPickup,
  myPickups,
  trackWaste,
  collectionCentres,
  rewards,
  marketplace,
  notifications,
  support,
  profile,
  assignedPickups,
  routeNavigation,
  pickupDetails,
  scanQrCode,
  recordWeight,
  uploadProof,
  updatePickupStatus,
  reportFailedPickup,
  collectionHistory,
  vehicleInformation,
  receivedItems,
  assessment,
  repairJobs,
  recyclingBatches,
  resourceRecovery,
  hazardousItems,
  inventory,
  certificates,
  reports,
  pickupRequests,
  collections,
  classification,
  recyclingAndRecovery,
  reverseLogistics,
  usersAndOrganizations,
  partners,
  payments,
  analytics,
  compliance,
  auditLogs,
  settings,
}

class WorkspaceCatalog {
  const WorkspaceCatalog._();

  static ApplicationInterface interfaceFor(AppRole role) => switch (role) {
    AppRole.household ||
    AppRole.business ||
    AppRole.institution => ApplicationInterface.citizen,
    AppRole.collector || AppRole.driver => ApplicationInterface.fieldOperations,
    AppRole.collectionCentreOperator ||
    AppRole.repairTechnician ||
    AppRole.recycler => ApplicationInterface.processing,
    AppRole.administrator ||
    AppRole.environmentalOfficer ||
    AppRole.superAdministrator => ApplicationInterface.administration,
  };

  static List<WorkspaceDestination> destinationsFor(AppRole role) =>
      switch (interfaceFor(role)) {
        ApplicationInterface.citizen => const [
          WorkspaceDestination.dashboard,
          WorkspaceDestination.requestPickup,
          WorkspaceDestination.myPickups,
          WorkspaceDestination.trackWaste,
          WorkspaceDestination.collectionCentres,
          WorkspaceDestination.rewards,
          WorkspaceDestination.marketplace,
          WorkspaceDestination.notifications,
          WorkspaceDestination.support,
          WorkspaceDestination.profile,
        ],
        ApplicationInterface.fieldOperations => const [
          WorkspaceDestination.dashboard,
          WorkspaceDestination.assignedPickups,
          WorkspaceDestination.routeNavigation,
          WorkspaceDestination.pickupDetails,
          WorkspaceDestination.scanQrCode,
          WorkspaceDestination.recordWeight,
          WorkspaceDestination.uploadProof,
          WorkspaceDestination.updatePickupStatus,
          WorkspaceDestination.reportFailedPickup,
          WorkspaceDestination.collectionHistory,
          WorkspaceDestination.vehicleInformation,
          WorkspaceDestination.notifications,
          WorkspaceDestination.profile,
        ],
        ApplicationInterface.processing => _processingDestinations(role),
        ApplicationInterface.administration => _administrationDestinations(
          role,
        ),
      };

  static List<WorkspaceDestination> _processingDestinations(AppRole role) {
    final destinations = <WorkspaceDestination>[
      WorkspaceDestination.dashboard,
      WorkspaceDestination.receivedItems,
      WorkspaceDestination.assessment,
      WorkspaceDestination.inventory,
    ];
    if (role == AppRole.repairTechnician) {
      destinations.add(WorkspaceDestination.repairJobs);
    }
    if (role == AppRole.recycler) {
      destinations.addAll(const [
        WorkspaceDestination.recyclingBatches,
        WorkspaceDestination.resourceRecovery,
        WorkspaceDestination.hazardousItems,
      ]);
    }
    if (role == AppRole.collectionCentreOperator) {
      destinations.addAll(const [
        WorkspaceDestination.collectionCentres,
        WorkspaceDestination.reverseLogistics,
      ]);
    }
    destinations.addAll(const [
      WorkspaceDestination.certificates,
      WorkspaceDestination.reports,
      WorkspaceDestination.notifications,
      WorkspaceDestination.profile,
    ]);
    return destinations;
  }

  static List<WorkspaceDestination> _administrationDestinations(AppRole role) {
    final destinations = <WorkspaceDestination>[
      WorkspaceDestination.dashboard,
      WorkspaceDestination.pickupRequests,
      WorkspaceDestination.collections,
      WorkspaceDestination.vehicleInformation,
      WorkspaceDestination.inventory,
      WorkspaceDestination.classification,
      WorkspaceDestination.repairJobs,
      WorkspaceDestination.recyclingAndRecovery,
      WorkspaceDestination.reverseLogistics,
      WorkspaceDestination.partners,
      WorkspaceDestination.analytics,
      WorkspaceDestination.reports,
      WorkspaceDestination.compliance,
    ];
    if (role == AppRole.administrator || role == AppRole.superAdministrator) {
      destinations.addAll(const [
        WorkspaceDestination.collectionCentres,
        WorkspaceDestination.usersAndOrganizations,
        WorkspaceDestination.payments,
        WorkspaceDestination.auditLogs,
        WorkspaceDestination.settings,
      ]);
    }
    destinations.addAll(const [
      WorkspaceDestination.notifications,
      WorkspaceDestination.profile,
    ]);
    return destinations;
  }
}

extension ApplicationInterfaceLabel on ApplicationInterface {
  String get title => switch (this) {
    ApplicationInterface.citizen => 'Citizen application',
    ApplicationInterface.fieldOperations => 'Collector and driver application',
    ApplicationInterface.processing => 'Technician and recycler application',
    ApplicationInterface.administration => 'Administration dashboard',
  };
}

extension WorkspaceDestinationLabel on WorkspaceDestination {
  String get label => switch (this) {
    WorkspaceDestination.dashboard => 'Dashboard',
    WorkspaceDestination.requestPickup => 'Request pickup',
    WorkspaceDestination.myPickups => 'My pickups',
    WorkspaceDestination.trackWaste => 'Track e-waste',
    WorkspaceDestination.collectionCentres => 'Collection centres',
    WorkspaceDestination.rewards => 'Rewards',
    WorkspaceDestination.marketplace => 'Marketplace',
    WorkspaceDestination.notifications => 'Notifications',
    WorkspaceDestination.support => 'Support',
    WorkspaceDestination.profile => 'Profile',
    WorkspaceDestination.assignedPickups => 'Assigned pickups',
    WorkspaceDestination.routeNavigation => 'Route navigation',
    WorkspaceDestination.pickupDetails => 'Pickup details',
    WorkspaceDestination.scanQrCode => 'Scan QR code',
    WorkspaceDestination.recordWeight => 'Record weight',
    WorkspaceDestination.uploadProof => 'Upload proof',
    WorkspaceDestination.updatePickupStatus => 'Update pickup status',
    WorkspaceDestination.reportFailedPickup => 'Report failed pickup',
    WorkspaceDestination.collectionHistory => 'Collection history',
    WorkspaceDestination.vehicleInformation => 'Fleet & vehicles',
    WorkspaceDestination.receivedItems => 'Received items',
    WorkspaceDestination.assessment => 'Assessment',
    WorkspaceDestination.repairJobs => 'Repair jobs',
    WorkspaceDestination.recyclingBatches => 'Recycling batches',
    WorkspaceDestination.resourceRecovery => 'Resource recovery',
    WorkspaceDestination.hazardousItems => 'Hazardous items',
    WorkspaceDestination.inventory => 'E-waste inventory',
    WorkspaceDestination.certificates => 'Certificates',
    WorkspaceDestination.reports => 'Reports',
    WorkspaceDestination.pickupRequests => 'Pickup requests',
    WorkspaceDestination.collections => 'Collections',
    WorkspaceDestination.classification => 'Classification',
    WorkspaceDestination.recyclingAndRecovery => 'Recycling and recovery',
    WorkspaceDestination.reverseLogistics => 'Reverse logistics',
    WorkspaceDestination.usersAndOrganizations => 'Users and organizations',
    WorkspaceDestination.partners => 'Partners',
    WorkspaceDestination.payments => 'Payments',
    WorkspaceDestination.analytics => 'Analytics',
    WorkspaceDestination.compliance => 'Compliance',
    WorkspaceDestination.auditLogs => 'Audit logs',
    WorkspaceDestination.settings => 'Settings',
  };
}
