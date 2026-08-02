import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value);
  return null;
}

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
    return ManagedDocument.fromJson({...x, 'id': d.id});
  }

  factory ManagedDocument.fromJson(Map<String, dynamic> json) {
    final categoryName = json['category']?.toString() ?? 'other';
    final statusName = json['status']?.toString() ?? 'draft';
    final accessName = json['accessLevel']?.toString() ?? 'owner';
    return ManagedDocument(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      category: DocumentCategory.values.byName(categoryName),
      ownerId: json['ownerId']?.toString() ?? '',
      ownerName: json['ownerName']?.toString() ?? '',
      status: ManagedDocumentStatus.values.byName(statusName),
      accessLevel: DocumentAccessLevel.values.byName(accessName),
      currentVersion: json['currentVersion'] is int
          ? json['currentVersion'] as int
          : int.tryParse(json['currentVersion']?.toString() ?? '1') ?? 1,
      fileName: json['fileName']?.toString() ?? '',
      mimeType: json['mimeType']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      referenceNumber:
          json['referenceNumber']?.toString() ??
          json['reference']?.toString() ??
          '',
      expiresAt: _parseDateTime(json['expiresAt']),
      createdAt: _parseDateTime(json['createdAt']),
      archivedAt: _parseDateTime(json['archivedAt']),
    );
  }

  factory ManagedDocument.fromJson(Map<String, dynamic> json) {
    final categoryName =
        json['category']?.toString() ??
        json['documentType']?.toString() ??
        'other';
    final statusName = json['status']?.toString() ?? 'draft';
    final accessName =
        json['accessLevel']?.toString() ??
        (json['secureAccess'] == false ? 'owner' : 'governance');
    final fileUrl =
        json['url']?.toString() ?? json['fileUrl']?.toString() ?? '';
    final fileName =
        json['fileName']?.toString() ?? _extractFileName(fileUrl) ?? '';
    return ManagedDocument(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      category: DocumentCategory.values.byName(categoryName),
      ownerId: json['ownerId']?.toString() ?? '',
      ownerName:
          json['ownerName']?.toString() ?? json['ownerId']?.toString() ?? '',
      status: ManagedDocumentStatus.values.byName(statusName),
      accessLevel: DocumentAccessLevel.values.byName(accessName),
      currentVersion: json['currentVersion'] is int
          ? json['currentVersion'] as int
          : int.tryParse(
                  json['currentVersion']?.toString() ??
                      json['version']?.toString() ??
                      '1',
                ) ??
                1,
      fileName: fileName,
      mimeType: json['mimeType']?.toString() ?? '',
      url: fileUrl,
      referenceNumber:
          json['referenceNumber']?.toString() ??
          json['reference']?.toString() ??
          '',
      expiresAt: _parseDateTime(json['expiresAt']),
      createdAt: _parseDateTime(json['createdAt']),
      archivedAt: _parseDateTime(json['archivedAt']),
    );
  }
}

String? _extractFileName(String? url) {
  if (url == null || url.isEmpty) return null;
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  return uri.pathSegments.isNotEmpty ? uri.pathSegments.last : null;
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
    return DocumentVersion.fromJson({...x, 'createdAt': x['createdAt']});
  }

  factory DocumentVersion.fromJson(Map<String, dynamic> json) {
    return DocumentVersion(
      version: json['version'] ?? 1,
      fileName: json['fileName']?.toString() ?? '',
      mimeType: json['mimeType']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      changeNotes: json['changeNotes']?.toString() ?? '',
      uploadedBy: json['uploadedBy']?.toString() ?? '',
      createdAt: _parseDateTime(json['createdAt']),
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
    return DocumentAuditEvent.fromJson({...x, 'createdAt': x['createdAt']});
  }

  factory DocumentAuditEvent.fromJson(Map<String, dynamic> json) {
    return DocumentAuditEvent(
      action: json['action']?.toString() ?? '',
      actorId: json['actorId']?.toString() ?? '',
      details: json['details']?.toString() ?? '',
      createdAt: _parseDateTime(json['createdAt']),
    );
  }
}
