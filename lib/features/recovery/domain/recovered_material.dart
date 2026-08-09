import 'package:cloud_firestore/cloud_firestore.dart';

enum RecoverableMaterial {
  copper,
  aluminium,
  steel,
  plastic,
  glass,
  gold,
  silver,
  lithium,
  cobalt,
  circuitBoards,
}

extension RecoverableMaterialLabel on RecoverableMaterial {
  String get label => switch (this) {
    RecoverableMaterial.copper => 'Copper',
    RecoverableMaterial.aluminium => 'Aluminium',
    RecoverableMaterial.steel => 'Steel',
    RecoverableMaterial.plastic => 'Plastic',
    RecoverableMaterial.glass => 'Glass',
    RecoverableMaterial.gold => 'Gold',
    RecoverableMaterial.silver => 'Silver',
    RecoverableMaterial.lithium => 'Lithium',
    RecoverableMaterial.cobalt => 'Cobalt',
    RecoverableMaterial.circuitBoards => 'Circuit boards',
  };
}

enum MaterialQualityGrade { premium, gradeA, gradeB, gradeC, mixed }

enum MaterialLotStatus { stored, salesReady, reserved, transferred, sold }

class RecoveredMaterialLot {
  const RecoveredMaterialLot({
    required this.id,
    required this.lotCode,
    required this.recyclingBatchId,
    required this.recyclingBatchCode,
    required this.material,
    required this.weightKg,
    required this.quantity,
    required this.qualityGrade,
    required this.storageLocation,
    required this.unitMarketValue,
    required this.buyerId,
    required this.status,
    required this.saleRevenue,
    required this.createdAt,
  });
  final String id,
      lotCode,
      recyclingBatchId,
      recyclingBatchCode,
      storageLocation,
      buyerId;
  final RecoverableMaterial material;
  final double weightKg, unitMarketValue, saleRevenue;
  final int quantity;
  final MaterialQualityGrade qualityGrade;
  final MaterialLotStatus status;
  final DateTime? createdAt;
  double get estimatedMarketValue => weightKg * unitMarketValue;

  factory RecoveredMaterialLot.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return RecoveredMaterialLot(
      id: doc.id,
      lotCode: data['lotCode'] ?? doc.id,
      recyclingBatchId: data['recyclingBatchId'] ?? '',
      recyclingBatchCode: data['recyclingBatchCode'] ?? '',
      material: RecoverableMaterial.values.byName(
        data['material'] ?? RecoverableMaterial.circuitBoards.name,
      ),
      weightKg: (data['weightKg'] as num? ?? 0).toDouble(),
      quantity: data['quantity'] as int? ?? 0,
      qualityGrade: MaterialQualityGrade.values.byName(
        data['qualityGrade'] ?? MaterialQualityGrade.mixed.name,
      ),
      storageLocation: data['storageLocation'] ?? '',
      unitMarketValue: (data['unitMarketValue'] as num? ?? 0).toDouble(),
      buyerId: data['buyerId'] ?? '',
      status: MaterialLotStatus.values.byName(
        data['status'] ?? MaterialLotStatus.stored.name,
      ),
      saleRevenue: (data['saleRevenue'] as num? ?? 0).toDouble(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  factory RecoveredMaterialLot.fromJson(Map<String, dynamic> data) =>
      RecoveredMaterialLot(
        id: data['id']?.toString() ?? '',
        lotCode: data['lotCode']?.toString() ?? data['id']?.toString() ?? '',
        recyclingBatchId: data['recyclingBatchId']?.toString() ?? '',
        recyclingBatchCode: data['recyclingBatchCode']?.toString() ?? '',
        material: RecoverableMaterial.values.byName(
          data['material']?.toString() ??
              RecoverableMaterial.circuitBoards.name,
        ),
        weightKg: (data['weightKg'] as num? ?? 0).toDouble(),
        quantity: (data['quantity'] as num? ?? 0).toInt(),
        qualityGrade: MaterialQualityGrade.values.byName(
          data['qualityGrade']?.toString() ?? MaterialQualityGrade.mixed.name,
        ),
        storageLocation: data['storageLocation']?.toString() ?? '',
        unitMarketValue: (data['unitMarketValue'] as num? ?? 0).toDouble(),
        buyerId: data['buyerId']?.toString() ?? '',
        status: MaterialLotStatus.values.byName(
          data['status']?.toString() ?? MaterialLotStatus.stored.name,
        ),
        saleRevenue: (data['saleRevenue'] as num? ?? 0).toDouble(),
        createdAt: DateTime.tryParse(data['createdAt']?.toString() ?? ''),
      );
}

class MaterialCategoryDefinition {
  const MaterialCategoryDefinition({
    required this.id,
    required this.material,
    required this.defaultUnitValue,
    required this.active,
  });
  final String id;
  final RecoverableMaterial material;
  final double defaultUnitValue;
  final bool active;
  factory MaterialCategoryDefinition.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return MaterialCategoryDefinition(
      id: doc.id,
      material: RecoverableMaterial.values.byName(data['material'] ?? doc.id),
      defaultUnitValue: (data['defaultUnitValue'] as num? ?? 0).toDouble(),
      active: data['active'] as bool? ?? true,
    );
  }

  factory MaterialCategoryDefinition.fromJson(Map<String, dynamic> data) =>
      MaterialCategoryDefinition(
        id: data['id']?.toString() ?? '',
        material: RecoverableMaterial.values.byName(
          data['material']?.toString() ?? data['id']?.toString() ?? '',
        ),
        defaultUnitValue: (data['defaultUnitValue'] as num? ?? 0).toDouble(),
        active: data['active'] as bool? ?? true,
      );
}

class MaterialBuyer {
  const MaterialBuyer({
    required this.id,
    required this.name,
    required this.contact,
    required this.materials,
    required this.active,
  });
  final String id, name, contact;
  final List<RecoverableMaterial> materials;
  final bool active;
  factory MaterialBuyer.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return MaterialBuyer(
      id: doc.id,
      name: data['name'] ?? '',
      contact: data['contact'] ?? '',
      materials: List<String>.from(
        data['materials'] as List? ?? const [],
      ).map(RecoverableMaterial.values.byName).toList(),
      active: data['active'] as bool? ?? true,
    );
  }

  factory MaterialBuyer.fromJson(Map<String, dynamic> data) => MaterialBuyer(
    id: data['id']?.toString() ?? '',
    name: data['name']?.toString() ?? '',
    contact: data['contact']?.toString() ?? '',
    materials: List<String>.from(
      data['materials'] as List? ?? const [],
    ).map(RecoverableMaterial.values.byName).toList(),
    active: data['active'] as bool? ?? true,
  );
}

class MaterialTransferRecord {
  const MaterialTransferRecord({
    required this.from,
    required this.to,
    required this.weightKg,
    required this.carrier,
    required this.reference,
    required this.at,
  });
  final String from, to, carrier, reference;
  final double weightKg;
  final DateTime? at;
  factory MaterialTransferRecord.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return MaterialTransferRecord(
      from: data['from'] ?? '',
      to: data['to'] ?? '',
      weightKg: (data['weightKg'] as num? ?? 0).toDouble(),
      carrier: data['carrier'] ?? '',
      reference: data['reference'] ?? '',
      at: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  factory MaterialTransferRecord.fromJson(Map<String, dynamic> data) =>
      MaterialTransferRecord(
        from: data['from']?.toString() ?? '',
        to: data['to']?.toString() ?? '',
        weightKg: (data['weightKg'] as num? ?? 0).toDouble(),
        carrier: data['carrier']?.toString() ?? '',
        reference: data['reference']?.toString() ?? '',
        at: DateTime.tryParse(data['createdAt']?.toString() ?? ''),
      );
}
