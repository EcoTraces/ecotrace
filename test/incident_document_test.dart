import 'package:flutter_test/flutter_test.dart';
import 'package:wastemanagementsystem/features/incidents/domain/safety_incident.dart';
import 'package:wastemanagementsystem/features/documents/domain/managed_document.dart';

void main() {
  SafetyIncident i(
    String id,
    SafetyIncidentSeverity sev,
    SafetyIncidentStatus st,
  ) => SafetyIncident(
    id: id,
    number: id,
    type: SafetyIncidentType.accident,
    severity: sev,
    status: st,
    title: 'Incident',
    description: '',
    location: 'Centre',
    latitude: null,
    longitude: null,
    staffInvolved: const [],
    injuryDetails: '',
    hazardType: '',
    immediateResponse: '',
    evidenceUrls: const [],
    investigatorId: '',
    rootCause: '',
    correctiveAction: '',
    correctiveOwner: '',
    correctiveDueAt: null,
    closureNotes: '',
    reportedBy: 'u',
    reportedAt: null,
    closedAt: null,
  );
  test('safety statistics calculate open critical and closed incidents', () {
    final s = SafetyStatistics.fromIncidents([
      i('1', SafetyIncidentSeverity.critical, SafetyIncidentStatus.reported),
      i('2', SafetyIncidentSeverity.low, SafetyIncidentStatus.closed),
    ]);
    expect(s.total, 2);
    expect(s.open, 1);
    expect(s.closed, 1);
    expect(s.critical, 1);
  });
  test(
    'incident workflow contains investigation corrective follow-up and closure',
    () {
      expect(
        SafetyIncidentStatus.values,
        containsAll([
          SafetyIncidentStatus.investigating,
          SafetyIncidentStatus.correctiveAction,
          SafetyIncidentStatus.followUp,
          SafetyIncidentStatus.closed,
        ]),
      );
    },
  );
  test('document categories cover governed records', () {
    expect(
      DocumentCategory.values,
      containsAll([
        DocumentCategory.licence,
        DocumentCategory.certificate,
        DocumentCategory.contract,
        DocumentCategory.inspectionReport,
        DocumentCategory.userVerification,
        DocumentCategory.incidentEvidence,
      ]),
    );
  });
}
