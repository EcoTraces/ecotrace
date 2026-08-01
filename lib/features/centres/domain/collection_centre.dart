import 'package:cloud_firestore/cloud_firestore.dart';

import '../../pickups/domain/pickup.dart';

enum StockMovementType { checkIn, checkOut, transferIn, transferOut, adjustment }

enum SafetyInspectionStatus { passed, actionRequired, failed }

extension WasteCategoryLabel on WasteCategory {
  String get label => switch (this) {
    WasteCategory.computers => 'Computers',
    WasteCategory.phones => 'Phones',
    WasteCategory.televisions => 'Televisions',
    WasteCategory.appliances => 'Appliances',
    WasteCategory.batteries => 'Batteries',
    WasteCategory.accessories => 'Accessories',
    WasteCategory.other => 'Other',
  };
}

class CollectionCentre {
  const CollectionCentre({
    required this.id,
    required this.name,
    required this.address,
    required this.contactName,
    required this.contactEmail,
    required this.contactPhone,
    required this.latitude,
    required this.longitude,
    required this.operatingHours,
    required this.supportedCategories,
    required this.capacityKg,
    required this.currentStockKg,
    required this.capacityAlertPercent,
    required this.staffIds,
    required this.active,
  });

  final String id, name, address, contactName, contactEmail, contactPhone;
  final double? latitude, longitude;
  final Map<String, String> operatingHours;
  final List<WasteCategory> supportedCategories;
  final double capacityKg, currentStockKg, capacityAlertPercent;
  final List<String> staffIds;
  final bool active;

  double get occupancyPercent =>
      capacityKg <= 0 ? 0 : currentStockKg / capacityKg * 100;
  double get availableCapacityKg =>
      (capacityKg - currentStockKg).clamp(0, double.infinity);
  bool get hasCapacityAlert => occupancyPercent >= capacityAlertPercent;

  factory CollectionCentre.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return CollectionCentre(
      id: doc.id,
      name: data['name'] ?? '',
      address: data['address'] ?? '',
      contactName: data['contactName'] ?? '',
      contactEmail: data['contactEmail'] ?? '',
      contactPhone: data['contactPhone'] ?? '',
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      operatingHours: Map<String, String>.from(
        data['operatingHours'] as Map? ?? const {},
      ),
      supportedCategories: List<String>.from(
        data['supportedCategories'] as List? ?? const [],
      ).map(WasteCategory.values.byName).toList(),
      capacityKg: (data['capacityKg'] as num? ?? 0).toDouble(),
      currentStockKg: (data['currentStockKg'] as num? ?? 0).toDouble(),
      capacityAlertPercent: (data['capacityAlertPercent'] as num? ?? 80)
          .toDouble(),
      staffIds: List<String>.from(data['staffIds'] as List? ?? const []),
      active: data['active'] as bool? ?? true,
    );
  }

  factory CollectionCentre.fromJson(Map<String, dynamic> data) =>
      CollectionCentre(
        id: data['id']?.toString() ?? '',
        name: data['name']?.toString() ?? '',
        address: data['address']?.toString() ?? '',
        contactName: data['contactName']?.toString() ?? '',
        contactEmail: data['contactEmail']?.toString() ?? '',
        contactPhone: data['contactPhone']?.toString() ?? '',
        latitude: (data['latitude'] as num?)?.toDouble(),
        longitude: (data['longitude'] as num?)?.toDouble(),
        operatingHours: Map<String, String>.from(
          data['operatingHours'] as Map? ?? const {},
        ),
        supportedCategories: List<String>.from(
          data['supportedCategories'] as List? ?? const [],
        ).map(WasteCategory.values.byName).toList(),
        capacityKg: (data['capacityKg'] as num? ?? 0).toDouble(),
        currentStockKg: (data['currentStockKg'] as num? ?? 0).toDouble(),
        capacityAlertPercent:
            (data['capacityAlertPercent'] as num? ?? 80).toDouble(),
        staffIds: List<String>.from(data['staffIds'] as List? ?? const []),
        active: data['active'] as bool? ?? true,
      );
}

class StorageSection {
  const StorageSection({
    required this.id,
    required this.name,
    required this.category,
    required this.capacityKg,
    required this.currentStockKg,
    required this.restricted,
  });
  final String id, name;
  final WasteCategory category;
  final double capacityKg, currentStockKg;
  final bool restricted;
  double get occupancyPercent =>
      capacityKg <= 0 ? 0 : currentStockKg / capacityKg * 100;

  factory StorageSection.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return StorageSection(
      id: doc.id,
      name: data['name'] ?? '',
      category: WasteCategory.values.byName(data['category'] ?? 'other'),
      capacityKg: (data['capacityKg'] as num? ?? 0).toDouble(),
      currentStockKg: (data['currentStockKg'] as num? ?? 0).toDouble(),
      restricted: data['restricted'] as bool? ?? false,
    );
  }

  factory StorageSection.fromJson(Map<String, dynamic> data) => StorageSection(
    id: data['id']?.toString() ?? '',
    name: data['name']?.toString() ?? '',
    category: WasteCategory.values.byName(
      data['category']?.toString() ?? 'other',
    ),
    capacityKg: (data['capacityKg'] as num? ?? 0).toDouble(),
    currentStockKg: (data['currentStockKg'] as num? ?? 0).toDouble(),
    restricted: data['restricted'] as bool? ?? false,
  );
}

class ReceivingRecord {
  const ReceivingRecord({
    required this.id,
    required this.reference,
    required this.category,
    required this.itemCount,
    required this.recordedWeightKg,
    required this.verifiedWeightKg,
    required this.verified,
    required this.sectionId,
    required this.staffId,
    required this.notes,
    required this.receivedAt,
  });
  final String id, reference, sectionId, staffId, notes;
  final WasteCategory category;
  final int itemCount;
  final double recordedWeightKg;
  final double? verifiedWeightKg;
  final bool verified;
  final DateTime? receivedAt;
  double get stockWeightKg => verifiedWeightKg ?? recordedWeightKg;

  factory ReceivingRecord.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return ReceivingRecord(
      id: doc.id,
      reference: data['reference'] ?? doc.id,
      category: WasteCategory.values.byName(data['category'] ?? 'other'),
      itemCount: data['itemCount'] as int? ?? 0,
      recordedWeightKg: (data['recordedWeightKg'] as num? ?? 0).toDouble(),
      verifiedWeightKg: (data['verifiedWeightKg'] as num?)?.toDouble(),
      verified: data['verified'] as bool? ?? false,
      sectionId: data['sectionId'] ?? '',
      staffId: data['staffId'] ?? '',
      notes: data['notes'] ?? '',
      receivedAt: (data['receivedAt'] as Timestamp?)?.toDate(),
    );
  }

  factory ReceivingRecord.fromJson(Map<String, dynamic> data) =>
      ReceivingRecord(
        id: data['id']?.toString() ?? '',
        reference: data['reference']?.toString() ?? '',
        category: WasteCategory.values.byName(
          data['category']?.toString() ?? 'other',
        ),
        itemCount: (data['itemCount'] as num? ?? 0).toInt(),
        recordedWeightKg:
            (data['recordedWeightKg'] as num? ?? 0).toDouble(),
        verifiedWeightKg: (data['verifiedWeightKg'] as num?)?.toDouble(),
        verified: data['verified'] as bool? ?? false,
        sectionId: data['sectionId']?.toString() ?? '',
        staffId: data['staffId']?.toString() ?? '',
        notes: data['notes']?.toString() ?? '',
        receivedAt: DateTime.tryParse(data['receivedAt']?.toString() ?? ''),
      );
}

class StockMovement {
  const StockMovement({
    required this.id,
    required this.type,
    required this.weightKg,
    required this.sectionId,
    required this.destination,
    required this.staffId,
    required this.notes,
    required this.at,
  });
  final String id, sectionId, destination, staffId, notes;
  final StockMovementType type;
  final double weightKg;
  final DateTime? at;

  factory StockMovement.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return StockMovement(
      id: doc.id,
      type: StockMovementType.values.byName(data['type'] ?? 'adjustment'),
      weightKg: (data['weightKg'] as num? ?? 0).toDouble(),
      sectionId: data['sectionId'] ?? '',
      destination: data['destination'] ?? '',
      staffId: data['staffId'] ?? '',
      notes: data['notes'] ?? '',
      at: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  factory StockMovement.fromJson(Map<String, dynamic> data) => StockMovement(
    id: data['id']?.toString() ?? '',
    type: StockMovementType.values.byName(
      data['type']?.toString() ?? 'adjustment',
    ),
    weightKg: (data['weightKg'] as num? ?? 0).toDouble(),
    sectionId: data['sectionId']?.toString() ?? '',
    destination: data['destination']?.toString() ?? '',
    staffId: data['staffId']?.toString() ?? '',
    notes: data['notes']?.toString() ?? '',
    at: DateTime.tryParse(data['createdAt']?.toString() ?? ''),
  );
}

class CentreStaffAssignment {
  const CentreStaffAssignment({
    required this.id,
    required this.userId,
    required this.role,
    required this.active,
  });
  final String id, userId, role;
  final bool active;
  factory CentreStaffAssignment.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return CentreStaffAssignment(
      id: doc.id,
      userId: data['userId'] ?? '',
      role: data['role'] ?? 'staff',
      active: data['active'] as bool? ?? true,
    );
  }

  factory CentreStaffAssignment.fromJson(Map<String, dynamic> data) =>
      CentreStaffAssignment(
        id: data['id']?.toString() ?? '',
        userId: data['userId']?.toString() ?? '',
        role: data['role']?.toString() ?? 'staff',
        active: data['active'] as bool? ?? true,
      );
}

class SafetyInspection {
  const SafetyInspection({
    required this.id,
    required this.inspectorId,
    required this.status,
    required this.score,
    required this.notes,
    required this.inspectedAt,
  });
  final String id, inspectorId, notes;
  final SafetyInspectionStatus status;
  final int score;
  final DateTime? inspectedAt;
  factory SafetyInspection.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return SafetyInspection(
      id: doc.id,
      inspectorId: data['inspectorId'] ?? '',
      status: SafetyInspectionStatus.values.byName(
        data['status'] ?? 'actionRequired',
      ),
      score: data['score'] as int? ?? 0,
      notes: data['notes'] ?? '',
      inspectedAt: (data['inspectedAt'] as Timestamp?)?.toDate(),
    );
  }

  factory SafetyInspection.fromJson(Map<String, dynamic> data) =>
      SafetyInspection(
        id: data['id']?.toString() ?? '',
        inspectorId: data['inspectorId']?.toString() ?? '',
        status: SafetyInspectionStatus.values.byName(
          data['status']?.toString() ?? 'actionRequired',
        ),
        score: (data['score'] as num? ?? 0).toInt(),
        notes: data['notes']?.toString() ?? '',
        inspectedAt: DateTime.tryParse(
          data['inspectedAt']?.toString() ?? '',
        ),
      );
}
