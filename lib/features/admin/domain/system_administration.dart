import 'package:cloud_firestore/cloud_firestore.dart';

import '../../auth/domain/app_role.dart';

class RoleDefinition {
  const RoleDefinition({
    required this.role,
    required this.permissions,
    this.description = '',
  });

  final AppRole role;
  final Set<String> permissions;
  final String description;

  bool allows(String permission) => permissions.contains(permission);

  factory RoleDefinition.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return RoleDefinition(
      role: AppRole.fromValue(doc.id),
      permissions: Set<String>.from(data['permissions'] as List? ?? const []),
      description: data['description'] as String? ?? '',
    );
  }
}

class SystemConfiguration {
  const SystemConfiguration({
    required this.wasteCategories,
    required this.itemConditions,
    required this.serviceAreas,
    required this.supportedLanguages,
    required this.integrationNames,
    required this.notificationTemplateNames,
    required this.pickupFees,
    required this.rewardRules,
    required this.environmentalFormulas,
    required this.settings,
    this.updatedAt,
  });

  final List<String> wasteCategories;
  final List<String> itemConditions;
  final List<String> serviceAreas;
  final List<String> supportedLanguages;
  final List<String> integrationNames;
  final List<String> notificationTemplateNames;
  final Map<String, double> pickupFees;
  final Map<String, double> rewardRules;
  final Map<String, double> environmentalFormulas;
  final Map<String, String> settings;
  final DateTime? updatedAt;

  static const defaults = SystemConfiguration(
    wasteCategories: ['Computers', 'Phones', 'Appliances', 'Batteries'],
    itemConditions: ['Working', 'Repairable', 'Damaged', 'Hazardous'],
    serviceAreas: [],
    supportedLanguages: ['English'],
    integrationNames: ['Mobile money', 'Bank', 'Card', 'SMS', 'Email'],
    notificationTemplateNames: [
      'Pickup reminder',
      'Status update',
      'Payment alert',
      'Emergency alert',
    ],
    pickupFees: {
      'base': 5,
      'perItem': 1.5,
      'perKg': .35,
      'urgent': 10,
      'taxPercent': 0,
      'servicePercent': 5,
    },
    rewardRules: {'pickupPoints': 20, 'referralPoints': 50},
    environmentalFormulas: {
      'reuseCarbonKg': 50,
      'reuseEnergyKwh': 200,
      'treeCarbonKg': 21,
      'waterProtectedLitresPerHazardousKg': 1000,
    },
    settings: {
      'currency': 'USD',
      'timezone': 'UTC',
      'supportEmail': '',
      'maintenanceMode': 'false',
    },
  );

  factory SystemConfiguration.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) return defaults;
    return SystemConfiguration(
      wasteCategories: _strings(data['wasteCategories']),
      itemConditions: _strings(data['itemConditions']),
      serviceAreas: _strings(data['serviceAreas']),
      supportedLanguages: _strings(data['supportedLanguages']),
      integrationNames: _strings(data['integrationNames']),
      notificationTemplateNames: _strings(data['notificationTemplateNames']),
      pickupFees: _numbers(data['pickupFees']),
      rewardRules: _numbers(data['rewardRules']),
      environmentalFormulas: _numbers(data['environmentalFormulas']),
      settings: Map<String, String>.from(data['settings'] as Map? ?? const {}),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
    'wasteCategories': wasteCategories,
    'itemConditions': itemConditions,
    'serviceAreas': serviceAreas,
    'supportedLanguages': supportedLanguages,
    'integrationNames': integrationNames,
    'notificationTemplateNames': notificationTemplateNames,
    'pickupFees': pickupFees,
    'rewardRules': rewardRules,
    'environmentalFormulas': environmentalFormulas,
    'settings': settings,
  };

  double pickupTotal({
    required int quantity,
    required double weightKg,
    required bool urgent,
  }) {
    if (quantity < 0 || weightKg < 0) {
      throw ArgumentError('Quantity and weight cannot be negative.');
    }
    final subtotal =
        (pickupFees['base'] ?? 0) +
        quantity * (pickupFees['perItem'] ?? 0) +
        weightKg * (pickupFees['perKg'] ?? 0) +
        (urgent ? pickupFees['urgent'] ?? 0 : 0);
    return subtotal *
        (1 +
            (pickupFees['taxPercent'] ?? 0) / 100 +
            (pickupFees['servicePercent'] ?? 0) / 100);
  }

  static List<String> _strings(dynamic value) =>
      List<String>.from(value as List? ?? const []);
  static Map<String, double> _numbers(dynamic value) =>
      Map<String, dynamic>.from(
        value as Map? ?? const {},
      ).map((key, value) => MapEntry(key, (value as num).toDouble()));
}

enum PlatformServiceStatus { operational, degraded, unavailable }

class PlatformHealthSnapshot {
  const PlatformHealthSnapshot({
    required this.services,
    required this.userCount,
    required this.pendingRoleChanges,
    required this.checkedAt,
  });

  final Map<String, PlatformServiceStatus> services;
  final int userCount;
  final int pendingRoleChanges;
  final DateTime checkedAt;

  bool get healthy => services.values.every(
    (status) => status == PlatformServiceStatus.operational,
  );
}

const administrationPermissions = <String>[
  'users.view',
  'users.manage',
  'roles.manage',
  'configuration.manage',
  'audit.view',
  'reports.export',
  'billing.manage',
  'inventory.manage',
  'compliance.manage',
];
