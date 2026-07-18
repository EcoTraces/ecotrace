import 'package:cloud_firestore/cloud_firestore.dart';

enum AuditAction {
  login,
  logout,
  create,
  update,
  delete,
  approve,
  reject,
  payment,
  itemMovement,
  roleChange,
  permissionChange,
  configurationChange,
  security,
  system,
}

enum AuditSeverity { information, notice, warning, critical }

class AuditEvent {
  const AuditEvent({
    required this.id,
    required this.actorId,
    required this.actorName,
    required this.actorRole,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.description,
    required this.changes,
    required this.ipAddress,
    required this.deviceInformation,
    required this.success,
    required this.severity,
    required this.source,
    required this.createdAt,
  });

  final String id;
  final String actorId;
  final String actorName;
  final String actorRole;
  final AuditAction action;
  final String entityType;
  final String entityId;
  final String description;
  final Map<String, dynamic> changes;
  final String ipAddress;
  final String deviceInformation;
  final bool success;
  final AuditSeverity severity;
  final String source;
  final DateTime? createdAt;

  factory AuditEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return AuditEvent(
      id: doc.id,
      actorId: data['actorId'] as String? ?? '',
      actorName: data['actorName'] as String? ?? '',
      actorRole: data['actorRole'] as String? ?? '',
      action: AuditAction.values.byName(
        data['action'] as String? ?? AuditAction.system.name,
      ),
      entityType: data['entityType'] as String? ?? '',
      entityId: data['entityId'] as String? ?? '',
      description: data['description'] as String? ?? '',
      changes: Map<String, dynamic>.from(data['changes'] as Map? ?? const {}),
      ipAddress: data['ipAddress'] as String? ?? '',
      deviceInformation: data['deviceInformation'] as String? ?? '',
      success: data['success'] as bool? ?? true,
      severity: AuditSeverity.values.byName(
        data['severity'] as String? ?? AuditSeverity.information.name,
      ),
      source: data['source'] as String? ?? 'client',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  bool matches(AuditFilter filter) {
    if (filter.action != null && action != filter.action) return false;
    if (filter.from != null &&
        (createdAt == null || createdAt!.isBefore(filter.from!))) {
      return false;
    }
    if (filter.to != null &&
        (createdAt == null || createdAt!.isAfter(filter.to!))) {
      return false;
    }
    final query = filter.query.trim().toLowerCase();
    if (query.isEmpty) return true;
    return [
      actorName,
      actorId,
      actorRole,
      action.name,
      entityType,
      entityId,
      description,
      ipAddress,
      deviceInformation,
    ].any((value) => value.toLowerCase().contains(query));
  }
}

class AuditFilter {
  const AuditFilter({this.query = '', this.action, this.from, this.to});

  final String query;
  final AuditAction? action;
  final DateTime? from;
  final DateTime? to;
}
