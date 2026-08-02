import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value);
  return null;
}

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
    return SafetyIncident.fromJson({
      ...x,
      'id': d.id,
      'incidentNumber': x['incidentNumber'] ?? d.id,
    });
  }

  factory SafetyIncident.fromJson(Map<String, dynamic> json) {
    final typeName = json['type']?.toString() ??
        json['incidentType']?.toString() ?? 'other';
    final severityName = json['severity']?.toString() ?? 'moderate';
    final statusName = json['status']?.toString() ??
        json['investigationStatus']?.toString() ?? 'reported';
    return SafetyIncident(
      id: json['id']?.toString() ?? '',
      number:
          json['incidentNumber']?.toString() ?? json['id']?.toString() ?? '',
      type: SafetyIncidentType.values.byName(typeName),
      severity: SafetyIncidentSeverity.values.byName(severityName),
      status: SafetyIncidentStatus.values.byName(statusName),
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      location: json['location']?.toString() ?? '',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      staffInvolved: List<String>.from(json['staffInvolved'] ?? []),
      injuryDetails: json['injuryDetails']?.toString() ?? '',
      hazardType: json['hazardType']?.toString() ?? '',
      immediateResponse:
          json['immediateResponse']?.toString() ??
          json['immediateResponseAction']?.toString() ??
          '',
      evidenceUrls: List<String>.from(
        json['evidenceUrls'] ?? json['photoUrls'] ?? [],
      ),
      investigatorId: json['investigatorId']?.toString() ?? '',
      rootCause: json['rootCause']?.toString() ?? '',
      correctiveAction: json['correctiveAction']?.toString() ?? '',
      correctiveOwner: json['correctiveOwner']?.toString() ?? '',
      correctiveDueAt: _parseDateTime(json['correctiveDueAt']),
      closureNotes: json['closureNotes']?.toString() ?? '',
      reportedBy: json['reportedBy']?.toString() ?? '',
      reportedAt: _parseDateTime(json['reportedAt'] ?? json['createdAt']),
      closedAt: _parseDateTime(json['closedAt']),
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
    return IncidentFollowUp.fromJson({...x, 'recordedAt': x['recordedAt']});
  }
  factory IncidentFollowUp.fromJson(Map<String, dynamic> json) {
    return IncidentFollowUp(
      findings: json['findings']?.toString() ?? '',
      riskRemaining: json['riskRemaining'] ?? false,
      recordedBy: json['recordedBy']?.toString() ?? '',
      recordedAt: _parseDateTime(json['recordedAt']),
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
