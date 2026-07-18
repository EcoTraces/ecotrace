import 'package:flutter_test/flutter_test.dart';
import 'package:wastemanagementsystem/features/admin/domain/system_administration.dart';
import 'package:wastemanagementsystem/features/audit/domain/audit_event.dart';
import 'package:wastemanagementsystem/features/auth/domain/app_role.dart';

void main() {
  group('Audit trail', () {
    test('supports all required governance event categories', () {
      expect(
        AuditAction.values,
        containsAll([
          AuditAction.login,
          AuditAction.create,
          AuditAction.update,
          AuditAction.delete,
          AuditAction.approve,
          AuditAction.reject,
          AuditAction.payment,
          AuditAction.itemMovement,
          AuditAction.roleChange,
          AuditAction.permissionChange,
        ]),
      );
    });

    test('search filter matches actor, entity and description', () {
      final event = AuditEvent(
        id: 'log-1',
        actorId: 'admin-1',
        actorName: 'Amina Admin',
        actorRole: 'administrator',
        action: AuditAction.roleChange,
        entityType: 'user',
        entityId: 'user-7',
        description: 'Role changed to recycler',
        changes: const {},
        ipAddress: '',
        deviceInformation: 'android / Flutter',
        success: true,
        severity: AuditSeverity.warning,
        source: 'client',
        createdAt: DateTime(2026, 7, 17),
      );
      expect(event.matches(const AuditFilter(query: 'amina')), isTrue);
      expect(event.matches(const AuditFilter(query: 'recycler')), isTrue);
      expect(
        event.matches(const AuditFilter(action: AuditAction.payment)),
        isFalse,
      );
    });
  });

  group('System administration', () {
    test('role definitions enforce explicit permissions', () {
      const role = RoleDefinition(
        role: AppRole.administrator,
        permissions: {'users.view', 'audit.view'},
      );
      expect(role.allows('audit.view'), isTrue);
      expect(role.allows('billing.manage'), isFalse);
    });

    test('configured pickup fees include rates and urgent surcharge', () {
      final total = SystemConfiguration.defaults.pickupTotal(
        quantity: 2,
        weightKg: 10,
        urgent: true,
      );
      expect(total, closeTo(22.575, .001));
    });

    test('platform health reports degraded services', () {
      final health = PlatformHealthSnapshot(
        services: const {
          'Authentication': PlatformServiceStatus.operational,
          'Configuration': PlatformServiceStatus.degraded,
        },
        userCount: 5,
        pendingRoleChanges: 1,
        checkedAt: DateTime(2026),
      );
      expect(health.healthy, isFalse);
    });
  });
}
