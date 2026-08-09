import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _complianceDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

T _enumValue<T extends Enum>(List<T> values, dynamic value, T fallback) {
  final name = value?.toString();
  return values.where((item) => item.name == name).firstOrNull ?? fallback;
}

enum ComplianceDocumentType {
  operationalLicence,
  recyclerCertification,
  environmentalCertificate,
  transportPermit,
  insurance,
  regulatorySubmission,
  other,
}

extension ComplianceDocumentTypeLabel on ComplianceDocumentType {
  String get label => switch (this) {
    ComplianceDocumentType.operationalLicence => 'Operational licence',
    ComplianceDocumentType.recyclerCertification => 'Recycler certification',
    ComplianceDocumentType.environmentalCertificate =>
      'Environmental certificate',
    ComplianceDocumentType.transportPermit => 'Transport permit',
    ComplianceDocumentType.insurance => 'Insurance',
    ComplianceDocumentType.regulatorySubmission => 'Regulatory submission',
    ComplianceDocumentType.other => 'Other compliance document',
  };
}

enum ComplianceDocumentStatus {
  draft,
  pendingReview,
  valid,
  expired,
  suspended,
  revoked,
  rejected,
}

enum ComplianceInspectionStatus {
  scheduled,
  inProgress,
  completed,
  followUpRequired,
  cancelled,
}

enum ViolationSeverity { minor, major, critical }

enum ComplianceViolationStatus {
  open,
  correctiveAction,
  underReview,
  resolved,
  penalized,
}

enum PenaltyStatus { issued, appealed, due, paid, waived }

class RegulatoryBody {
  const RegulatoryBody({
    required this.id,
    required this.name,
    required this.jurisdiction,
    required this.contactName,
    required this.contactEmail,
    required this.contactPhone,
    required this.active,
  });
  final String id, name, jurisdiction, contactName, contactEmail, contactPhone;
  final bool active;
  factory RegulatoryBody.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return RegulatoryBody.fromJson({'id': doc.id, ...doc.data()!});
  }
  factory RegulatoryBody.fromJson(Map<String, dynamic> data) => RegulatoryBody(
      id: data['id']?.toString() ?? '',
      name: data['name'] ?? '',
      jurisdiction: data['jurisdiction'] ?? '',
      contactName: data['contactName'] ?? '',
      contactEmail: data['contactEmail'] ?? '',
      contactPhone: data['contactPhone'] ?? '',
      active: data['active'] as bool? ?? true,
    );
}

class ComplianceDocument {
  const ComplianceDocument({
    required this.id,
    required this.type,
    required this.title,
    required this.referenceNumber,
    required this.entityName,
    required this.regulatoryBodyId,
    required this.regulatoryBodyName,
    required this.status,
    required this.documentUrls,
    required this.issuedAt,
    required this.expiresAt,
    required this.submittedAt,
    required this.notes,
  });
  final String id,
      title,
      referenceNumber,
      entityName,
      regulatoryBodyId,
      regulatoryBodyName,
      notes;
  final ComplianceDocumentType type;
  final ComplianceDocumentStatus status;
  final List<String> documentUrls;
  final DateTime? issuedAt, expiresAt, submittedAt;

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());
  bool expiresWithin(Duration duration) =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now().add(duration));

  factory ComplianceDocument.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return ComplianceDocument.fromJson({'id': doc.id, ...doc.data()!});
  }
  factory ComplianceDocument.fromJson(Map<String, dynamic> data) => ComplianceDocument(
      id: data['id']?.toString() ?? '',
      type: _enumValue(ComplianceDocumentType.values, data['type'], ComplianceDocumentType.other),
      title: data['title'] ?? '',
      referenceNumber: data['referenceNumber'] ?? '',
      entityName: data['entityName'] ?? '',
      regulatoryBodyId: data['regulatoryBodyId'] ?? '',
      regulatoryBodyName: data['regulatoryBodyName'] ?? '',
      status: _enumValue(ComplianceDocumentStatus.values, data['status'], ComplianceDocumentStatus.draft),
      documentUrls: List<String>.from(
        data['documentUrls'] as List? ?? const [],
      ),
      issuedAt: _complianceDate(data['issuedAt']),
      expiresAt: _complianceDate(data['expiresAt']),
      submittedAt: _complianceDate(data['submittedAt']),
      notes: data['notes'] ?? '',
    );
}

class ComplianceRequirement {
  const ComplianceRequirement({
    required this.id,
    required this.category,
    required this.title,
    required this.description,
    required this.mandatory,
    required this.active,
  });
  final String id, category, title, description;
  final bool mandatory, active;
  factory ComplianceRequirement.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return ComplianceRequirement.fromJson({'id': doc.id, ...doc.data()!});
  }
  factory ComplianceRequirement.fromJson(Map<String, dynamic> data) => ComplianceRequirement(
      id: data['id']?.toString() ?? '',
      category: data['category'] ?? 'General',
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      mandatory: data['mandatory'] as bool? ?? true,
      active: data['active'] as bool? ?? true,
    );
}

class ComplianceInspection {
  const ComplianceInspection({
    required this.id,
    required this.entityName,
    required this.regulatoryBodyId,
    required this.inspectorName,
    required this.scheduledAt,
    required this.completedAt,
    required this.status,
    required this.checklist,
    required this.score,
    required this.findings,
    required this.recommendations,
    required this.reportUrls,
  });
  final String id,
      entityName,
      regulatoryBodyId,
      inspectorName,
      findings,
      recommendations;
  final DateTime? scheduledAt, completedAt;
  final ComplianceInspectionStatus status;
  final Map<String, bool> checklist;
  final double score;
  final List<String> reportUrls;
  factory ComplianceInspection.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return ComplianceInspection.fromJson({'id': doc.id, ...doc.data()!});
  }
  factory ComplianceInspection.fromJson(Map<String, dynamic> data) => ComplianceInspection(
      id: data['id']?.toString() ?? '',
      entityName: data['entityName'] ?? '',
      regulatoryBodyId: data['regulatoryBodyId'] ?? '',
      inspectorName: data['inspectorName'] ?? '',
      scheduledAt: _complianceDate(data['scheduledAt']),
      completedAt: _complianceDate(data['completedAt']),
      status: _enumValue(ComplianceInspectionStatus.values, data['status'], ComplianceInspectionStatus.scheduled),
      checklist: Map<String, bool>.from(data['checklist'] as Map? ?? const {}),
      score: (data['score'] as num? ?? 0).toDouble(),
      findings: data['findings'] ?? '',
      recommendations: data['recommendations'] ?? '',
      reportUrls: List<String>.from(data['reportUrls'] as List? ?? const []),
    );
}

class ComplianceViolation {
  const ComplianceViolation({
    required this.id,
    required this.referenceNumber,
    required this.entityName,
    required this.requirement,
    required this.description,
    required this.severity,
    required this.status,
    required this.correctiveActionPlan,
    required this.correctiveActionOwner,
    required this.correctiveActionDueAt,
    required this.resolutionEvidence,
    required this.reportedAt,
    required this.resolvedAt,
  });
  final String id,
      referenceNumber,
      entityName,
      requirement,
      description,
      correctiveActionPlan,
      correctiveActionOwner,
      resolutionEvidence;
  final ViolationSeverity severity;
  final ComplianceViolationStatus status;
  final DateTime? correctiveActionDueAt, reportedAt, resolvedAt;
  bool get overdue =>
      correctiveActionDueAt != null &&
      correctiveActionDueAt!.isBefore(DateTime.now()) &&
      status != ComplianceViolationStatus.resolved;
  factory ComplianceViolation.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return ComplianceViolation.fromJson({'id': doc.id, ...doc.data()!});
  }
  factory ComplianceViolation.fromJson(Map<String, dynamic> data) => ComplianceViolation(
      id: data['id']?.toString() ?? '',
      referenceNumber: data['referenceNumber'] ?? data['id']?.toString() ?? '',
      entityName: data['entityName'] ?? '',
      requirement: data['requirement'] ?? '',
      description: data['description'] ?? '',
      severity: _enumValue(ViolationSeverity.values, data['severity'], ViolationSeverity.minor),
      status: _enumValue(ComplianceViolationStatus.values, data['status'], ComplianceViolationStatus.open),
      correctiveActionPlan: data['correctiveActionPlan'] ?? '',
      correctiveActionOwner: data['correctiveActionOwner'] ?? '',
      correctiveActionDueAt: _complianceDate(data['correctiveActionDueAt']),
      resolutionEvidence: data['resolutionEvidence'] ?? '',
      reportedAt: _complianceDate(data['reportedAt']),
      resolvedAt: _complianceDate(data['resolvedAt']),
    );
}

class PenaltyRecord {
  const PenaltyRecord({
    required this.id,
    required this.violationId,
    required this.referenceNumber,
    required this.amount,
    required this.currency,
    required this.status,
    required this.dueAt,
    required this.notes,
  });
  final String id, violationId, referenceNumber, currency, notes;
  final double amount;
  final PenaltyStatus status;
  final DateTime? dueAt;
  factory PenaltyRecord.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return PenaltyRecord.fromJson({'id': doc.id, ...doc.data()!});
  }
  factory PenaltyRecord.fromJson(Map<String, dynamic> data) => PenaltyRecord(
      id: data['id']?.toString() ?? '',
      violationId: data['violationId'] ?? '',
      referenceNumber: data['referenceNumber'] ?? '',
      amount: (data['amount'] as num? ?? 0).toDouble(),
      currency: data['currency'] ?? 'SLE',
      status: _enumValue(PenaltyStatus.values, data['status'], PenaltyStatus.issued),
      dueAt: _complianceDate(data['dueAt']),
      notes: data['notes'] ?? '',
    );
}

class ComplianceScore {
  const ComplianceScore({
    required this.overall,
    required this.documentScore,
    required this.inspectionScore,
    required this.violationScore,
  });
  final double overall, documentScore, inspectionScore, violationScore;

  factory ComplianceScore.calculate({
    required List<ComplianceDocument> documents,
    required List<ComplianceInspection> inspections,
    required List<ComplianceViolation> violations,
  }) {
    final documentScore = documents.isEmpty
        ? 100.0
        : documents
                  .where(
                    (document) =>
                        document.status == ComplianceDocumentStatus.valid &&
                        !document.isExpired,
                  )
                  .length /
              documents.length *
              100;
    final completed = inspections
        .where(
          (inspection) =>
              inspection.status == ComplianceInspectionStatus.completed ||
              inspection.status == ComplianceInspectionStatus.followUpRequired,
        )
        .toList();
    final inspectionScore = completed.isEmpty
        ? 100.0
        : completed
                  .map((inspection) => inspection.score)
                  .reduce((a, b) => a + b) /
              completed.length;
    final violationScore = violations.isEmpty
        ? 100.0
        : violations
                  .where(
                    (violation) =>
                        violation.status == ComplianceViolationStatus.resolved,
                  )
                  .length /
              violations.length *
              100;
    return ComplianceScore(
      overall:
          documentScore * .4 + inspectionScore * .35 + violationScore * .25,
      documentScore: documentScore,
      inspectionScore: inspectionScore,
      violationScore: violationScore,
    );
  }
}
