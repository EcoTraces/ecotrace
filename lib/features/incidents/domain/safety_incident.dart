import 'package:cloud_firestore/cloud_firestore.dart';

enum SafetyIncidentType {
  accident,
  hazardousExposure,
  injury,
  equipmentDamage,
  nearMiss,
  fire,
  spill,
  security,
  operationalRisk,
  other,
}

enum SafetyIncidentSeverity { low, moderate, high, critical }

enum SafetyIncidentStatus {
  reported,
  immediateResponse,
  investigating,
  correctiveAction,
  followUp,
  closed,
}

class SafetyIncident {
  const SafetyIncident({
    required this.id,
    required this.number,
    required this.type,
    required this.severity,
    required this.status,
    required this.title,
    required this.description,
    required this.location,
    required this.latitude,
    required this.longitude,
    required this.staffInvolved,
    required this.injuryDetails,
    required this.hazardType,
    required this.immediateResponse,
    required this.evidenceUrls,
    required this.investigatorId,
    required this.rootCause,
    required this.correctiveAction,
    required this.correctiveOwner,
    required this.correctiveDueAt,
    required this.closureNotes,
    required this.reportedBy,
    required this.reportedAt,
    required this.closedAt,
  });
  final String id,
      number,
      title,
      description,
      location,
      injuryDetails,
      hazardType,
      immediateResponse,
      investigatorId,
      rootCause,
      correctiveAction,
      correctiveOwner,
      closureNotes,
      reportedBy;
  final SafetyIncidentType type;
  final SafetyIncidentSeverity severity;
  final SafetyIncidentStatus status;
  final double? latitude, longitude;
  final List<String> staffInvolved, evidenceUrls;
  final DateTime? correctiveDueAt, reportedAt, closedAt;
  bool get overdue =>
      correctiveDueAt != null &&
      correctiveDueAt!.isBefore(DateTime.now()) &&
      status != SafetyIncidentStatus.closed;
  factory SafetyIncident.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final x = d.data()!;
    return SafetyIncident(
      id: d.id,
      number: x['incidentNumber'] ?? d.id,
      type: SafetyIncidentType.values.byName(x['type'] ?? 'other'),
      severity: SafetyIncidentSeverity.values.byName(
        x['severity'] ?? 'moderate',
      ),
      status: SafetyIncidentStatus.values.byName(x['status'] ?? 'reported'),
      title: x['title'] ?? '',
      description: x['description'] ?? '',
      location: x['location'] ?? '',
      latitude: (x['latitude'] as num?)?.toDouble(),
      longitude: (x['longitude'] as num?)?.toDouble(),
      staffInvolved: List<String>.from(x['staffInvolved'] ?? []),
      injuryDetails: x['injuryDetails'] ?? '',
      hazardType: x['hazardType'] ?? '',
      immediateResponse: x['immediateResponse'] ?? '',
      evidenceUrls: List<String>.from(x['evidenceUrls'] ?? []),
      investigatorId: x['investigatorId'] ?? '',
      rootCause: x['rootCause'] ?? '',
      correctiveAction: x['correctiveAction'] ?? '',
      correctiveOwner: x['correctiveOwner'] ?? '',
      correctiveDueAt: (x['correctiveDueAt'] as Timestamp?)?.toDate(),
      closureNotes: x['closureNotes'] ?? '',
      reportedBy: x['reportedBy'] ?? '',
      reportedAt: (x['reportedAt'] as Timestamp?)?.toDate(),
      closedAt: (x['closedAt'] as Timestamp?)?.toDate(),
    );
  }
}

class IncidentFollowUp {
  const IncidentFollowUp({
    required this.findings,
    required this.riskRemaining,
    required this.recordedBy,
    required this.recordedAt,
  });
  final String findings, recordedBy;
  final bool riskRemaining;
  final DateTime? recordedAt;
  factory IncidentFollowUp.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final x = d.data()!;
    return IncidentFollowUp(
      findings: x['findings'] ?? '',
      riskRemaining: x['riskRemaining'] ?? false,
      recordedBy: x['recordedBy'] ?? '',
      recordedAt: (x['recordedAt'] as Timestamp?)?.toDate(),
    );
  }
}

class EmergencyContact {
  const EmergencyContact({
    required this.id,
    required this.name,
    required this.role,
    required this.phone,
    required this.email,
    required this.region,
    required this.active,
  });
  final String id, name, role, phone, email, region;
  final bool active;
  factory EmergencyContact.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final x = d.data()!;
    return EmergencyContact(
      id: d.id,
      name: x['name'] ?? '',
      role: x['role'] ?? '',
      phone: x['phone'] ?? '',
      email: x['email'] ?? '',
      region: x['region'] ?? '',
      active: x['active'] ?? true,
    );
  }
}

class SafetyStatistics {
  const SafetyStatistics({
    required this.total,
    required this.open,
    required this.closed,
    required this.critical,
    required this.overdue,
    required this.byType,
  });
  final int total, open, closed, critical, overdue;
  final Map<SafetyIncidentType, int> byType;
  factory SafetyStatistics.fromIncidents(List<SafetyIncident> x) {
    final types = <SafetyIncidentType, int>{};
    for (final i in x) {
      types.update(i.type, (n) => n + 1, ifAbsent: () => 1);
    }
    return SafetyStatistics(
      total: x.length,
      open: x.where((i) => i.status != SafetyIncidentStatus.closed).length,
      closed: x.where((i) => i.status == SafetyIncidentStatus.closed).length,
      critical: x
          .where((i) => i.severity == SafetyIncidentSeverity.critical)
          .length,
      overdue: x.where((i) => i.overdue).length,
      byType: types,
    );
  }
}
