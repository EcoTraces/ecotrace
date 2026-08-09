import 'package:cloud_firestore/cloud_firestore.dart';

enum HazardousMaterialCategory {
  lithiumBattery,
  leadAcidBattery,
  mercury,
  lead,
  cadmium,
  toxicChemicals,
  crtGlass,
  contaminatedCircuitBoards,
  other,
}

extension HazardousMaterialLabel on HazardousMaterialCategory {
  String get label => switch (this) {
    HazardousMaterialCategory.lithiumBattery => 'Lithium battery',
    HazardousMaterialCategory.leadAcidBattery => 'Lead-acid battery',
    HazardousMaterialCategory.mercury => 'Mercury',
    HazardousMaterialCategory.lead => 'Lead',
    HazardousMaterialCategory.cadmium => 'Cadmium',
    HazardousMaterialCategory.toxicChemicals => 'Toxic chemicals',
    HazardousMaterialCategory.crtGlass => 'CRT glass',
    HazardousMaterialCategory.contaminatedCircuitBoards =>
      'Contaminated circuit boards',
    HazardousMaterialCategory.other => 'Other hazardous material',
  };
}

enum HazardousWasteStatus {
  identified,
  secured,
  stored,
  incidentHold,
  transferApproved,
  transferred,
  disposed,
  certified,
}

enum IncidentSeverity { minor, moderate, serious, critical }

enum IncidentStatus { reported, responding, contained, investigating, closed }

class HazardousWasteRecord {
  const HazardousWasteRecord({
    required this.id,
    required this.code,
    required this.sourceBatchId,
    required this.sourceReference,
    required this.category,
    required this.classification,
    required this.weightKg,
    required this.quantity,
    required this.storageLocation,
    required this.safetyInstructions,
    required this.ppeChecklist,
    required this.disposalFacility,
    required this.status,
    required this.certificateNumber,
    required this.createdAt,
  });
  final String id,
      code,
      sourceBatchId,
      sourceReference,
      classification,
      storageLocation,
      safetyInstructions,
      disposalFacility,
      certificateNumber;
  final HazardousMaterialCategory category;
  final double weightKg;
  final int quantity;
  final Map<String, bool> ppeChecklist;
  final HazardousWasteStatus status;
  final DateTime? createdAt;
  bool get ppeComplete =>
      ppeChecklist.isNotEmpty && ppeChecklist.values.every((value) => value);

  factory HazardousWasteRecord.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return HazardousWasteRecord(
      id: doc.id,
      code: data['wasteCode'] ?? doc.id,
      sourceBatchId: data['sourceBatchId'] ?? '',
      sourceReference: data['sourceReference'] ?? '',
      category: HazardousMaterialCategory.values.byName(
        data['category'] ?? HazardousMaterialCategory.other.name,
      ),
      classification: data['classification'] ?? '',
      weightKg: (data['weightKg'] as num? ?? 0).toDouble(),
      quantity: data['quantity'] as int? ?? 0,
      storageLocation: data['storageLocation'] ?? '',
      safetyInstructions: data['safetyInstructions'] ?? '',
      ppeChecklist: Map<String, bool>.from(
        data['ppeChecklist'] as Map? ?? const {},
      ),
      disposalFacility: data['disposalFacility'] ?? '',
      status: HazardousWasteStatus.values.byName(
        data['status'] ?? HazardousWasteStatus.identified.name,
      ),
      certificateNumber: data['certificateNumber'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  factory HazardousWasteRecord.fromJson(Map<String, dynamic> data) {
    final classification = data['classification']?.toString() ?? 'other';
    return HazardousWasteRecord(
      id: data['id']?.toString() ?? '',
      code:
          data['recordCode']?.toString() ??
          data['wasteCode']?.toString() ??
          data['id']?.toString() ??
          '',
      sourceBatchId: data['sourceType'] == 'recyclingBatch'
          ? data['sourceId']?.toString() ?? ''
          : data['sourceBatchId']?.toString() ?? '',
      sourceReference:
          data['sourceId']?.toString() ??
          data['sourceReference']?.toString() ??
          '',
      category: _categoryFromApi(classification),
      classification: classification,
      weightKg: (data['weightKg'] as num? ?? 0).toDouble(),
      quantity: (data['quantity'] as num? ?? 0).toInt(),
      storageLocation: data['storageLocation']?.toString() ?? '',
      safetyInstructions: data['safetyInstructions'] is List
          ? (data['safetyInstructions'] as List).join('\n')
          : data['safetyInstructions']?.toString() ?? '',
      ppeChecklist: Map<String, bool>.from(
        data['ppeChecklist'] as Map? ?? const {},
      ),
      disposalFacility:
          data['disposalFacility']?.toString() ??
          data['facilityName']?.toString() ??
          '',
      status: _statusFromApi(data['status']?.toString()),
      certificateNumber: data['certificateNumber']?.toString() ?? '',
      createdAt: DateTime.tryParse(data['createdAt']?.toString() ?? ''),
    );
  }
}

HazardousMaterialCategory _categoryFromApi(String value) => switch (value) {
  'battery' || 'lithium' => HazardousMaterialCategory.lithiumBattery,
  'mercury' => HazardousMaterialCategory.mercury,
  'lead' => HazardousMaterialCategory.lead,
  'cadmium' => HazardousMaterialCategory.cadmium,
  'circuitBoards' => HazardousMaterialCategory.contaminatedCircuitBoards,
  _ => HazardousMaterialCategory.other,
};

HazardousWasteStatus _statusFromApi(String? value) => switch (value) {
  'inTransfer' => HazardousWasteStatus.transferred,
  'incidentHold' => HazardousWasteStatus.incidentHold,
  'transferApproved' => HazardousWasteStatus.transferApproved,
  'certified' => HazardousWasteStatus.certified,
  'disposed' => HazardousWasteStatus.disposed,
  'stored' => HazardousWasteStatus.stored,
  'secured' => HazardousWasteStatus.secured,
  _ => HazardousWasteStatus.identified,
};

class HazardousIncident {
  const HazardousIncident({
    required this.id,
    required this.severity,
    required this.description,
    required this.emergencyActions,
    required this.status,
    required this.reportedBy,
    required this.reportedAt,
  });
  final String id, description, emergencyActions, reportedBy;
  final IncidentSeverity severity;
  final IncidentStatus status;
  final DateTime? reportedAt;
  factory HazardousIncident.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return HazardousIncident(
      id: doc.id,
      severity: IncidentSeverity.values.byName(
        data['severity'] ?? IncidentSeverity.minor.name,
      ),
      description: data['description'] ?? '',
      emergencyActions: data['emergencyActions'] ?? '',
      status: IncidentStatus.values.byName(
        data['status'] ?? IncidentStatus.reported.name,
      ),
      reportedBy: data['reportedBy'] ?? '',
      reportedAt: (data['reportedAt'] as Timestamp?)?.toDate(),
    );
  }

  factory HazardousIncident.fromJson(Map<String, dynamic> data) =>
      HazardousIncident(
        id: data['id']?.toString() ?? '',
        severity: switch (data['severity']?.toString()) {
          'critical' => IncidentSeverity.critical,
          'high' => IncidentSeverity.serious,
          'medium' => IncidentSeverity.moderate,
          _ => IncidentSeverity.minor,
        },
        description: data['description']?.toString() ?? '',
        emergencyActions: data['actions'] is List
            ? (data['actions'] as List).join('\n')
            : data['immediateActions'] is List
            ? (data['immediateActions'] as List).join('\n')
            : data['emergencyActions']?.toString() ?? '',
        status: IncidentStatus.values.byName(
          data['status']?.toString() ?? IncidentStatus.reported.name,
        ),
        reportedBy: data['reportedBy']?.toString() ?? '',
        reportedAt: DateTime.tryParse(data['reportedAt']?.toString() ?? ''),
      );
}

class SafetyTrainingRecord {
  const SafetyTrainingRecord({
    required this.id,
    required this.staffId,
    required this.course,
    required this.completedAt,
    required this.expiresAt,
  });
  final String id, staffId, course;
  final DateTime? completedAt, expiresAt;
  bool get valid => expiresAt == null || expiresAt!.isAfter(DateTime.now());
  factory SafetyTrainingRecord.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return SafetyTrainingRecord(
      id: doc.id,
      staffId: data['staffId'] ?? '',
      course: data['course'] ?? '',
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
      expiresAt: (data['expiresAt'] as Timestamp?)?.toDate(),
    );
  }

  factory SafetyTrainingRecord.fromJson(Map<String, dynamic> data) =>
      SafetyTrainingRecord(
        id: data['id']?.toString() ?? '',
        staffId: data['staffId']?.toString() ?? '',
        course:
            data['courseName']?.toString() ?? data['course']?.toString() ?? '',
        completedAt: DateTime.tryParse(data['completedAt']?.toString() ?? ''),
        expiresAt: DateTime.tryParse(data['expiresAt']?.toString() ?? ''),
      );
}

class HazardousTransferRecord {
  const HazardousTransferRecord({
    required this.from,
    required this.to,
    required this.carrier,
    required this.manifestNumber,
    required this.at,
  });
  final String from, to, carrier, manifestNumber;
  final DateTime? at;
  factory HazardousTransferRecord.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return HazardousTransferRecord(
      from: data['from'] ?? '',
      to: data['to'] ?? '',
      carrier: data['carrier'] ?? '',
      manifestNumber: data['manifestNumber'] ?? '',
      at: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  factory HazardousTransferRecord.fromJson(Map<String, dynamic> data) =>
      HazardousTransferRecord(
        from: data['from']?.toString() ?? '',
        to:
            data['to']?.toString() ??
            data['destinationFacilityName']?.toString() ??
            '',
        carrier: data['carrier']?.toString() ?? '',
        manifestNumber: data['manifestNumber']?.toString() ?? '',
        at: DateTime.tryParse(
          data['createdAt']?.toString() ??
              data['dispatchedAt']?.toString() ??
              '',
        ),
      );
}
