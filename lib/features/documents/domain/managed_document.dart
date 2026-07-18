import 'package:cloud_firestore/cloud_firestore.dart';

enum DocumentCategory {
  licence,
  certificate,
  contract,
  inspectionReport,
  userVerification,
  incidentEvidence,
  regulatory,
  financial,
  policy,
  other,
}

enum ManagedDocumentStatus {
  draft,
  pendingApproval,
  approved,
  rejected,
  archived,
  expired,
}

enum DocumentAccessLevel { owner, staff, governance, administrators }

class ManagedDocument {
  const ManagedDocument({
    required this.id,
    required this.title,
    required this.category,
    required this.ownerId,
    required this.ownerName,
    required this.status,
    required this.accessLevel,
    required this.currentVersion,
    required this.fileName,
    required this.mimeType,
    required this.url,
    required this.referenceNumber,
    required this.expiresAt,
    required this.createdAt,
    required this.archivedAt,
  });
  final String id,
      title,
      ownerId,
      ownerName,
      fileName,
      mimeType,
      url,
      referenceNumber;
  final DocumentCategory category;
  final ManagedDocumentStatus status;
  final DocumentAccessLevel accessLevel;
  final int currentVersion;
  final DateTime? expiresAt, createdAt, archivedAt;
  bool get expired => expiresAt != null && expiresAt!.isBefore(DateTime.now());
  bool expiresWithin(Duration d) =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now().add(d));
  factory ManagedDocument.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final x = d.data()!;
    return ManagedDocument(
      id: d.id,
      title: x['title'] ?? '',
      category: DocumentCategory.values.byName(x['category'] ?? 'other'),
      ownerId: x['ownerId'] ?? '',
      ownerName: x['ownerName'] ?? '',
      status: ManagedDocumentStatus.values.byName(x['status'] ?? 'draft'),
      accessLevel: DocumentAccessLevel.values.byName(
        x['accessLevel'] ?? 'owner',
      ),
      currentVersion: x['currentVersion'] ?? 1,
      fileName: x['fileName'] ?? '',
      mimeType: x['mimeType'] ?? '',
      url: x['url'] ?? '',
      referenceNumber: x['referenceNumber'] ?? '',
      expiresAt: (x['expiresAt'] as Timestamp?)?.toDate(),
      createdAt: (x['createdAt'] as Timestamp?)?.toDate(),
      archivedAt: (x['archivedAt'] as Timestamp?)?.toDate(),
    );
  }
}

class DocumentVersion {
  const DocumentVersion({
    required this.version,
    required this.fileName,
    required this.mimeType,
    required this.url,
    required this.changeNotes,
    required this.uploadedBy,
    required this.createdAt,
  });
  final int version;
  final String fileName, mimeType, url, changeNotes, uploadedBy;
  final DateTime? createdAt;
  factory DocumentVersion.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final x = d.data()!;
    return DocumentVersion(
      version: x['version'] ?? 1,
      fileName: x['fileName'] ?? '',
      mimeType: x['mimeType'] ?? '',
      url: x['url'] ?? '',
      changeNotes: x['changeNotes'] ?? '',
      uploadedBy: x['uploadedBy'] ?? '',
      createdAt: (x['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class DocumentAuditEvent {
  const DocumentAuditEvent({
    required this.action,
    required this.actorId,
    required this.details,
    required this.createdAt,
  });
  final String action, actorId, details;
  final DateTime? createdAt;
  factory DocumentAuditEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final x = d.data()!;
    return DocumentAuditEvent(
      action: x['action'] ?? '',
      actorId: x['actorId'] ?? '',
      details: x['details'] ?? '',
      createdAt: (x['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
