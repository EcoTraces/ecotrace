import 'package:cloud_firestore/cloud_firestore.dart';

enum ComplaintCategory {
  pickupService,
  collectionCentre,
  damagedItem,
  billingOrFee,
  repairService,
  recyclingService,
  staffConduct,
  dataPrivacy,
  technicalIssue,
  other,
}

extension ComplaintCategoryLabel on ComplaintCategory {
  String get label => switch (this) {
    ComplaintCategory.pickupService => 'Pickup service',
    ComplaintCategory.collectionCentre => 'Collection centre',
    ComplaintCategory.damagedItem => 'Damaged item',
    ComplaintCategory.billingOrFee => 'Billing or fee',
    ComplaintCategory.repairService => 'Repair service',
    ComplaintCategory.recyclingService => 'Recycling service',
    ComplaintCategory.staffConduct => 'Staff conduct',
    ComplaintCategory.dataPrivacy => 'Data privacy',
    ComplaintCategory.technicalIssue => 'Technical issue',
    ComplaintCategory.other => 'Other enquiry',
  };
}

enum TicketPriority { low, normal, high, urgent }

enum TicketStatus {
  submitted,
  assigned,
  inProgress,
  waitingForUser,
  escalated,
  resolved,
  closed,
  reopened,
}

extension TicketStatusLabel on TicketStatus {
  String get label => switch (this) {
    TicketStatus.submitted => 'Submitted',
    TicketStatus.assigned => 'Assigned',
    TicketStatus.inProgress => 'In progress',
    TicketStatus.waitingForUser => 'Waiting for user',
    TicketStatus.escalated => 'Escalated',
    TicketStatus.resolved => 'Resolved',
    TicketStatus.closed => 'Closed',
    TicketStatus.reopened => 'Reopened',
  };
}

class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.ticketNumber,
    required this.userId,
    required this.userName,
    required this.category,
    required this.subject,
    required this.description,
    required this.priority,
    required this.status,
    required this.agentId,
    required this.agentName,
    required this.evidenceUrls,
    required this.escalationLevel,
    required this.escalationReason,
    required this.resolution,
    required this.satisfactionRating,
    required this.satisfactionComment,
    required this.createdAt,
    required this.updatedAt,
    required this.resolvedAt,
  });
  final String id,
      ticketNumber,
      userId,
      userName,
      subject,
      description,
      agentId,
      agentName,
      escalationReason,
      resolution,
      satisfactionComment;
  final ComplaintCategory category;
  final TicketPriority priority;
  final TicketStatus status;
  final List<String> evidenceUrls;
  final int escalationLevel, satisfactionRating;
  final DateTime? createdAt, updatedAt, resolvedAt;

  bool get isOpen =>
      ![TicketStatus.resolved, TicketStatus.closed].contains(status);
  Duration? get resolutionDuration => createdAt == null || resolvedAt == null
      ? null
      : resolvedAt!.difference(createdAt!);

  factory SupportTicket.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return SupportTicket(
      id: doc.id,
      ticketNumber: data['ticketNumber'] ?? doc.id,
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? '',
      category: ComplaintCategory.values.byName(
        data['category'] ?? ComplaintCategory.other.name,
      ),
      subject: data['subject'] ?? '',
      description: data['description'] ?? '',
      priority: TicketPriority.values.byName(
        data['priority'] ?? TicketPriority.normal.name,
      ),
      status: TicketStatus.values.byName(
        data['status'] ?? TicketStatus.submitted.name,
      ),
      agentId: data['agentId'] ?? '',
      agentName: data['agentName'] ?? '',
      evidenceUrls: List<String>.from(
        data['evidenceUrls'] as List? ?? const [],
      ),
      escalationLevel: data['escalationLevel'] as int? ?? 0,
      escalationReason: data['escalationReason'] ?? '',
      resolution: data['resolution'] ?? '',
      satisfactionRating: data['satisfactionRating'] as int? ?? 0,
      satisfactionComment: data['satisfactionComment'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      resolvedAt: (data['resolvedAt'] as Timestamp?)?.toDate(),
    );
  }
  factory SupportTicket.fromJson(Map<String, dynamic> data) => SupportTicket(
    id: data['id']?.toString() ?? '',
    ticketNumber: data['ticketNumber']?.toString() ?? '',
    userId: data['userId']?.toString() ?? '',
    userName: data['userName']?.toString() ?? '',
    category: ComplaintCategory.values.where((value) => value.name == data['category']).firstOrNull ?? ComplaintCategory.other,
    subject: data['subject']?.toString() ?? '',
    description: data['description']?.toString() ?? '',
    priority: TicketPriority.values.where((value) => value.name == data['priority']).firstOrNull ?? TicketPriority.normal,
    status: TicketStatus.values.where((value) => value.name == data['status']).firstOrNull ?? TicketStatus.submitted,
    agentId: data['agentId']?.toString() ?? data['assignedAgentId']?.toString() ?? '',
    agentName: data['agentName']?.toString() ?? '',
    evidenceUrls: List<String>.from(data['evidenceUrls'] as List? ?? const []),
    escalationLevel: (data['escalationLevel'] as num? ?? 0).toInt(),
    escalationReason: data['escalationReason']?.toString() ?? '',
    resolution: data['resolution']?.toString() ?? '',
    satisfactionRating: (data['satisfactionRating'] as num? ?? 0).toInt(),
    satisfactionComment: data['satisfactionComment']?.toString() ?? data['satisfactionComments']?.toString() ?? '',
    createdAt: DateTime.tryParse(data['createdAt']?.toString() ?? ''),
    updatedAt: DateTime.tryParse(data['updatedAt']?.toString() ?? ''),
    resolvedAt: DateTime.tryParse(data['resolvedAt']?.toString() ?? ''),
  );
}

class TicketMessage {
  const TicketMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.body,
    required this.internal,
    required this.attachmentUrls,
    required this.createdAt,
  });
  final String id, senderId, senderName, body;
  final bool internal;
  final List<String> attachmentUrls;
  final DateTime? createdAt;
  factory TicketMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return TicketMessage(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? '',
      body: data['body'] ?? '',
      internal: data['internal'] as bool? ?? false,
      attachmentUrls: List<String>.from(
        data['attachmentUrls'] as List? ?? const [],
      ),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
  factory TicketMessage.fromJson(Map<String, dynamic> data) => TicketMessage(
    id: data['id']?.toString() ?? '',
    senderId: data['senderId']?.toString() ?? data['authorId']?.toString() ?? '',
    senderName: data['senderName']?.toString() ?? (data['internal'] == true ? 'Internal note' : ''),
    body: data['body']?.toString() ?? data['note']?.toString() ?? '',
    internal: data['internal'] == true || data.containsKey('note'),
    attachmentUrls: List<String>.from(data['attachmentUrls'] as List? ?? const []),
    createdAt: DateTime.tryParse(data['createdAt']?.toString() ?? ''),
  );
}

enum KnowledgeArticleType { faq, guide, policy }

class KnowledgeArticle {
  const KnowledgeArticle({
    required this.id,
    required this.type,
    required this.category,
    required this.title,
    required this.content,
    required this.tags,
    required this.published,
    required this.viewCount,
    required this.updatedAt,
  });
  final String id, category, title, content;
  final KnowledgeArticleType type;
  final List<String> tags;
  final bool published;
  final int viewCount;
  final DateTime? updatedAt;
  factory KnowledgeArticle.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return KnowledgeArticle(
      id: doc.id,
      type: KnowledgeArticleType.values.byName(
        data['type'] ?? KnowledgeArticleType.faq.name,
      ),
      category: data['category'] ?? 'General',
      title: data['title'] ?? '',
      content: data['content'] ?? '',
      tags: List<String>.from(data['tags'] as List? ?? const []),
      published: data['published'] as bool? ?? false,
      viewCount: data['viewCount'] as int? ?? 0,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
  factory KnowledgeArticle.fromJson(Map<String, dynamic> data) => KnowledgeArticle(
    id: data['id']?.toString() ?? '',
    type: KnowledgeArticleType.values.where((value) => value.name == data['type']).firstOrNull ?? KnowledgeArticleType.faq,
    category: data['category']?.toString() ?? 'General',
    title: data['title']?.toString() ?? '',
    content: data['content']?.toString() ?? '',
    tags: List<String>.from(data['tags'] as List? ?? data['keywords'] as List? ?? const []),
    published: data['published'] == true,
    viewCount: (data['viewCount'] as num? ?? 0).toInt(),
    updatedAt: DateTime.tryParse(data['updatedAt']?.toString() ?? ''),
  );
}

class SupportAnalytics {
  const SupportAnalytics({
    required this.total,
    required this.open,
    required this.escalated,
    required this.resolved,
    required this.averageResolutionHours,
    required this.averageSatisfaction,
    required this.byCategory,
  });
  final int total, open, escalated, resolved;
  final double averageResolutionHours, averageSatisfaction;
  final Map<ComplaintCategory, int> byCategory;

  factory SupportAnalytics.fromTickets(List<SupportTicket> tickets) {
    final resolved = tickets
        .where((ticket) => ticket.resolvedAt != null)
        .toList();
    final rated = tickets
        .where((ticket) => ticket.satisfactionRating > 0)
        .toList();
    final byCategory = <ComplaintCategory, int>{};
    for (final ticket in tickets) {
      byCategory.update(
        ticket.category,
        (total) => total + 1,
        ifAbsent: () => 1,
      );
    }
    return SupportAnalytics(
      total: tickets.length,
      open: tickets.where((ticket) => ticket.isOpen).length,
      escalated: tickets.where((ticket) => ticket.escalationLevel > 0).length,
      resolved: resolved.length,
      averageResolutionHours: resolved.isEmpty
          ? 0
          : resolved
                    .map((ticket) => ticket.resolutionDuration!.inMinutes / 60)
                    .reduce((a, b) => a + b) /
                resolved.length,
      averageSatisfaction: rated.isEmpty
          ? 0
          : rated
                    .map((ticket) => ticket.satisfactionRating)
                    .reduce((a, b) => a + b) /
                rated.length,
      byCategory: byCategory,
    );
  }
}
