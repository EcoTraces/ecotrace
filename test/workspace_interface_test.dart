import 'package:flutter_test/flutter_test.dart';
import 'package:wastemanagementsystem/features/auth/domain/app_role.dart';
import 'package:wastemanagementsystem/features/workspace/domain/application_interface.dart';

void main() {
  group('Recommended application interfaces', () {
    test('citizen roles receive the complete citizen workspace', () {
      for (final role in [
        AppRole.household,
        AppRole.business,
        AppRole.institution,
      ]) {
        expect(
          WorkspaceCatalog.interfaceFor(role),
          ApplicationInterface.citizen,
        );
        expect(
          WorkspaceCatalog.destinationsFor(role),
          containsAll(const [
            WorkspaceDestination.requestPickup,
            WorkspaceDestination.myPickups,
            WorkspaceDestination.trackWaste,
            WorkspaceDestination.collectionCentres,
            WorkspaceDestination.rewards,
            WorkspaceDestination.marketplace,
            WorkspaceDestination.notifications,
            WorkspaceDestination.support,
            WorkspaceDestination.profile,
          ]),
        );
      }
    });

    test('collector and driver receive every field collection shortcut', () {
      for (final role in [AppRole.collector, AppRole.driver]) {
        expect(
          WorkspaceCatalog.interfaceFor(role),
          ApplicationInterface.fieldOperations,
        );
        expect(
          WorkspaceCatalog.destinationsFor(role),
          containsAll(const [
            WorkspaceDestination.assignedPickups,
            WorkspaceDestination.routeNavigation,
            WorkspaceDestination.scanQrCode,
            WorkspaceDestination.recordWeight,
            WorkspaceDestination.uploadProof,
            WorkspaceDestination.updatePickupStatus,
            WorkspaceDestination.reportFailedPickup,
            WorkspaceDestination.collectionHistory,
            WorkspaceDestination.vehicleInformation,
          ]),
        );
      }
    });

    test('processing workspace specializes technician and recycler tools', () {
      final technician = WorkspaceCatalog.destinationsFor(
        AppRole.repairTechnician,
      );
      final recycler = WorkspaceCatalog.destinationsFor(AppRole.recycler);
      expect(technician, contains(WorkspaceDestination.repairJobs));
      expect(
        technician,
        isNot(contains(WorkspaceDestination.recyclingBatches)),
      );
      expect(
        recycler,
        containsAll(const [
          WorkspaceDestination.recyclingBatches,
          WorkspaceDestination.resourceRecovery,
          WorkspaceDestination.hazardousItems,
        ]),
      );
    });

    test('administrators receive every requested web governance section', () {
      final destinations = WorkspaceCatalog.destinationsFor(
        AppRole.administrator,
      );
      expect(
        destinations,
        containsAll(const [
          WorkspaceDestination.pickupRequests,
          WorkspaceDestination.collections,
          WorkspaceDestination.inventory,
          WorkspaceDestination.classification,
          WorkspaceDestination.repairJobs,
          WorkspaceDestination.recyclingAndRecovery,
          WorkspaceDestination.reverseLogistics,
          WorkspaceDestination.collectionCentres,
          WorkspaceDestination.usersAndOrganizations,
          WorkspaceDestination.partners,
          WorkspaceDestination.payments,
          WorkspaceDestination.analytics,
          WorkspaceDestination.reports,
          WorkspaceDestination.compliance,
          WorkspaceDestination.auditLogs,
          WorkspaceDestination.settings,
        ]),
      );
    });

    test('regulators do not receive administrator-only security controls', () {
      final destinations = WorkspaceCatalog.destinationsFor(
        AppRole.environmentalOfficer,
      );
      expect(
        WorkspaceCatalog.interfaceFor(AppRole.environmentalOfficer),
        ApplicationInterface.administration,
      );
      expect(destinations, contains(WorkspaceDestination.compliance));
      expect(destinations, isNot(contains(WorkspaceDestination.settings)));
      expect(destinations, isNot(contains(WorkspaceDestination.auditLogs)));
    });
  });
}
