import 'package:flutter_test/flutter_test.dart';
import 'package:wastemanagementsystem/features/compliance/domain/compliance_record.dart';
import 'package:wastemanagementsystem/features/support/domain/support_ticket.dart';

void main() {
  group('Customer support management', () {
    SupportTicket ticket({
      required String id,
      TicketStatus status = TicketStatus.submitted,
      ComplaintCategory category = ComplaintCategory.pickupService,
      int escalationLevel = 0,
      int rating = 0,
      DateTime? createdAt,
      DateTime? resolvedAt,
    }) => SupportTicket(
      id: id,
      ticketNumber: 'SUP-$id',
      userId: 'user-1',
      userName: 'Customer',
      category: category,
      subject: 'Support request',
      description: 'Description',
      priority: TicketPriority.normal,
      status: status,
      agentId: '',
      agentName: '',
      evidenceUrls: const [],
      escalationLevel: escalationLevel,
      escalationReason: '',
      resolution: status == TicketStatus.resolved ? 'Resolved' : '',
      satisfactionRating: rating,
      satisfactionComment: '',
      createdAt: createdAt,
      updatedAt: null,
      resolvedAt: resolvedAt,
    );

    test('ticket workflow contains tracking and escalation states', () {
      expect(TicketStatus.values, contains(TicketStatus.submitted));
      expect(TicketStatus.values, contains(TicketStatus.waitingForUser));
      expect(TicketStatus.values, contains(TicketStatus.escalated));
      expect(TicketStatus.values, contains(TicketStatus.resolved));
      expect(TicketStatus.values, contains(TicketStatus.reopened));
    });

    test('support analytics calculate service performance', () {
      final created = DateTime(2026, 7, 17, 8);
      final analytics = SupportAnalytics.fromTickets([
        ticket(
          id: '1',
          status: TicketStatus.resolved,
          rating: 4,
          createdAt: created,
          resolvedAt: created.add(const Duration(hours: 4)),
        ),
        ticket(
          id: '2',
          status: TicketStatus.escalated,
          category: ComplaintCategory.repairService,
          escalationLevel: 1,
        ),
      ]);
      expect(analytics.total, 2);
      expect(analytics.open, 1);
      expect(analytics.resolved, 1);
      expect(analytics.escalated, 1);
      expect(analytics.averageResolutionHours, 4);
      expect(analytics.averageSatisfaction, 4);
      expect(analytics.byCategory[ComplaintCategory.repairService], 1);
    });
  });

  group('Compliance and regulatory management', () {
    ComplianceDocument document({
      required String id,
      ComplianceDocumentStatus status = ComplianceDocumentStatus.valid,
      DateTime? expiresAt,
    }) => ComplianceDocument(
      id: id,
      type: ComplianceDocumentType.operationalLicence,
      title: 'Operating licence',
      referenceNumber: 'LIC-$id',
      entityName: 'EcoTrace',
      regulatoryBodyId: 'reg-1',
      regulatoryBodyName: 'Environment Authority',
      status: status,
      documentUrls: const [],
      issuedAt: null,
      expiresAt: expiresAt,
      submittedAt: null,
      notes: '',
    );

    ComplianceInspection inspection(double score) => ComplianceInspection(
      id: 'inspection-$score',
      entityName: 'Facility',
      regulatoryBodyId: 'reg-1',
      inspectorName: 'Inspector',
      scheduledAt: null,
      completedAt: null,
      status: ComplianceInspectionStatus.completed,
      checklist: const {'Storage controls': true},
      score: score,
      findings: '',
      recommendations: '',
      reportUrls: const [],
    );

    ComplianceViolation violation(ComplianceViolationStatus status) =>
        ComplianceViolation(
          id: status.name,
          referenceNumber: 'VIO-1',
          entityName: 'Facility',
          requirement: 'Storage controls',
          description: 'Finding',
          severity: ViolationSeverity.major,
          status: status,
          correctiveActionPlan: '',
          correctiveActionOwner: '',
          correctiveActionDueAt: null,
          resolutionEvidence: '',
          reportedAt: null,
          resolvedAt: null,
        );

    test(
      'document types cover licences, recycler and environmental records',
      () {
        expect(
          ComplianceDocumentType.values,
          contains(ComplianceDocumentType.operationalLicence),
        );
        expect(
          ComplianceDocumentType.values,
          contains(ComplianceDocumentType.recyclerCertification),
        );
        expect(
          ComplianceDocumentType.values,
          contains(ComplianceDocumentType.environmentalCertificate),
        );
        expect(
          ComplianceDocumentType.values,
          contains(ComplianceDocumentType.regulatorySubmission),
        );
      },
    );

    test('expiry alerts distinguish expired and upcoming documents', () {
      final expired = document(
        id: 'expired',
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      final upcoming = document(
        id: 'upcoming',
        expiresAt: DateTime.now().add(const Duration(days: 30)),
      );
      expect(expired.isExpired, isTrue);
      expect(upcoming.isExpired, isFalse);
      expect(upcoming.expiresWithin(const Duration(days: 60)), isTrue);
    });

    test('compliance score combines documents, inspections and violations', () {
      final score = ComplianceScore.calculate(
        documents: [document(id: 'valid')],
        inspections: [inspection(80)],
        violations: [violation(ComplianceViolationStatus.resolved)],
      );
      expect(score.documentScore, 100);
      expect(score.inspectionScore, 80);
      expect(score.violationScore, 100);
      expect(score.overall, 93);
    });
  });
}
