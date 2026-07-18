import 'package:cloud_firestore/cloud_firestore.dart';

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
    final data = doc.data()!;
    return RegulatoryBody(
      id: doc.id,
      name: data['name'] ?? '',
      jurisdiction: data['jurisdiction'] ?? '',
      contactName: data['contactName'] ?? '',
      contactEmail: data['contactEmail'] ?? '',
      contactPhone: data['contactPhone'] ?? '',
      active: data['active'] as bool? ?? true,
    );
  }
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
    final data = doc.data()!;
    return ComplianceDocument(
      id: doc.id,
      type: ComplianceDocumentType.values.byName(
        data['type'] ?? ComplianceDocumentType.other.name,
      ),
      title: data['title'] ?? '',
      referenceNumber: data['referenceNumber'] ?? '',
      entityName: data['entityName'] ?? '',
      regulatoryBodyId: data['regulatoryBodyId'] ?? '',
      regulatoryBodyName: data['regulatoryBodyName'] ?? '',
      status: ComplianceDocumentStatus.values.byName(
        data['status'] ?? ComplianceDocumentStatus.draft.name,
      ),
      documentUrls: List<String>.from(
        data['documentUrls'] as List? ?? const [],
      ),
      issuedAt: (data['issuedAt'] as Timestamp?)?.toDate(),
      expiresAt: (data['expiresAt'] as Timestamp?)?.toDate(),
      submittedAt: (data['submittedAt'] as Timestamp?)?.toDate(),
      notes: data['notes'] ?? '',
    );
  }
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
    final data = doc.data()!;
    return ComplianceRequirement(
      id: doc.id,
      category: data['category'] ?? 'General',
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      mandatory: data['mandatory'] as bool? ?? true,
      active: data['active'] as bool? ?? true,
    );
  }
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
    final data = doc.data()!;
    return ComplianceInspection(
      id: doc.id,
      entityName: data['entityName'] ?? '',
      regulatoryBodyId: data['regulatoryBodyId'] ?? '',
      inspectorName: data['inspectorName'] ?? '',
      scheduledAt: (data['scheduledAt'] as Timestamp?)?.toDate(),
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
      status: ComplianceInspectionStatus.values.byName(
        data['status'] ?? ComplianceInspectionStatus.scheduled.name,
      ),
      checklist: Map<String, bool>.from(data['checklist'] as Map? ?? const {}),
      score: (data['score'] as num? ?? 0).toDouble(),
      findings: data['findings'] ?? '',
      recommendations: data['recommendations'] ?? '',
      reportUrls: List<String>.from(data['reportUrls'] as List? ?? const []),
    );
  }
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
    final data = doc.data()!;
    return ComplianceViolation(
      id: doc.id,
      referenceNumber: data['referenceNumber'] ?? doc.id,
      entityName: data['entityName'] ?? '',
      requirement: data['requirement'] ?? '',
      description: data['description'] ?? '',
      severity: ViolationSeverity.values.byName(
        data['severity'] ?? ViolationSeverity.minor.name,
      ),
      status: ComplianceViolationStatus.values.byName(
        data['status'] ?? ComplianceViolationStatus.open.name,
      ),
      correctiveActionPlan: data['correctiveActionPlan'] ?? '',
      correctiveActionOwner: data['correctiveActionOwner'] ?? '',
      correctiveActionDueAt: (data['correctiveActionDueAt'] as Timestamp?)
          ?.toDate(),
      resolutionEvidence: data['resolutionEvidence'] ?? '',
      reportedAt: (data['reportedAt'] as Timestamp?)?.toDate(),
      resolvedAt: (data['resolvedAt'] as Timestamp?)?.toDate(),
    );
  }
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
    final data = doc.data()!;
    return PenaltyRecord(
      id: doc.id,
      violationId: data['violationId'] ?? '',
      referenceNumber: data['referenceNumber'] ?? '',
      amount: (data['amount'] as num? ?? 0).toDouble(),
      currency: data['currency'] ?? 'USD',
      status: PenaltyStatus.values.byName(
        data['status'] ?? PenaltyStatus.issued.name,
      ),
      dueAt: (data['dueAt'] as Timestamp?)?.toDate(),
      notes: data['notes'] ?? '',
    );
  }
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
