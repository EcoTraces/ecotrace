import 'package:flutter_test/flutter_test.dart';
import 'package:wastemanagementsystem/features/documents/domain/managed_document.dart';
import 'package:wastemanagementsystem/features/incidents/domain/safety_incident.dart';

void main() {
  group('API response mapping', () {
    test('parses incident payloads into the existing UI model', () {
      final incident = SafetyIncident.fromJson({
        'id': 'inc-1',
        'incidentNumber': 'INC-100',
        'type': 'accident',
        'severity': 'critical',
        'status': 'investigating',
        'title': 'Forklift collision',
        'description': 'A forklift struck a pallet rack.',
        'location': 'North bay',
        'staffInvolved': ['Asha', 'Jules'],
        'injuryDetails': 'Minor bruise',
        'hazardType': 'Machinery',
        'immediateResponse': 'Area secured',
        'evidenceUrls': ['https://example.com/a.png'],
        'investigatorId': 'user-1',
        'rootCause': 'Poor visibility',
        'correctiveAction': 'Add mirrors',
        'correctiveOwner': 'Ops lead',
        'correctiveDueAt': '2026-08-10T00:00:00.000Z',
        'closureNotes': '',
        'reportedBy': 'user-2',
        'reportedAt': '2026-08-01T10:00:00.000Z',
        'closedAt': null,
      });

      expect(incident.id, 'inc-1');
      expect(incident.number, 'INC-100');
      expect(incident.title, 'Forklift collision');
      expect(incident.status, SafetyIncidentStatus.investigating);
      expect(incident.staffInvolved, ['Asha', 'Jules']);
    });

    test('parses document payloads into the existing UI model', () {
      final document = ManagedDocument.fromJson({
        'id': 'doc-1',
        'title': 'Operating licence',
        'category': 'licence',
        'ownerId': 'user-1',
        'ownerName': 'Asha',
        'status': 'approved',
        'accessLevel': 'governance',
        'currentVersion': 2,
        'fileName': 'licence.pdf',
        'mimeType': 'application/pdf',
        'url': 'https://example.com/licence.pdf',
        'referenceNumber': 'LIC-001',
        'expiresAt': '2026-12-01T00:00:00.000Z',
        'createdAt': '2026-07-01T00:00:00.000Z',
        'archivedAt': null,
      });

      expect(document.id, 'doc-1');
      expect(document.title, 'Operating licence');
      expect(document.category, DocumentCategory.licence);
      expect(document.status, ManagedDocumentStatus.approved);
      expect(document.currentVersion, 2);
    });
  });
}
