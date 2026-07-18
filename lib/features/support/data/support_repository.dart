import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../auth/domain/user_profile.dart';
import '../domain/support_ticket.dart';

class SupportRepository {
  SupportRepository({FirebaseFirestore? firestore, FirebaseStorage? storage})
    : _db = firestore ?? FirebaseFirestore.instance,
      _storage = storage ?? FirebaseStorage.instance;
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  CollectionReference<Map<String, dynamic>> get _tickets =>
      _db.collection('supportTickets');

  Stream<List<SupportTicket>> watchTickets({String? userId}) =>
      (userId == null ? _tickets : _tickets.where('userId', isEqualTo: userId))
          .snapshots()
          .map(
            (snapshot) =>
                snapshot.docs.map(SupportTicket.fromDoc).toList()..sort(
                  (a, b) => (b.updatedAt ?? b.createdAt ?? DateTime(2000))
                      .compareTo(a.updatedAt ?? a.createdAt ?? DateTime(2000)),
                ),
          );

  Stream<SupportTicket> watchTicket(String id) =>
      _tickets.doc(id).snapshots().map(SupportTicket.fromDoc);

  Stream<List<TicketMessage>> watchMessages(
    String ticketId, {
    required bool includeInternal,
  }) =>
      (includeInternal
              ? _tickets.doc(ticketId).collection('messages')
              : _tickets
                    .doc(ticketId)
                    .collection('messages')
                    .where('internal', isEqualTo: false))
          .snapshots()
          .map(
            (snapshot) =>
                snapshot.docs.map(TicketMessage.fromDoc).toList()..sort(
                  (a, b) => (a.createdAt ?? DateTime(2000)).compareTo(
                    b.createdAt ?? DateTime(2000),
                  ),
                ),
          );

  Stream<List<KnowledgeArticle>> watchKnowledge({
    required bool includeDrafts,
  }) =>
      (includeDrafts
              ? _db.collection('supportKnowledgeBase')
              : _db
                    .collection('supportKnowledgeBase')
                    .where('published', isEqualTo: true))
          .snapshots()
          .map(
            (snapshot) =>
                snapshot.docs.map(KnowledgeArticle.fromDoc).toList()
                  ..sort((a, b) => a.title.compareTo(b.title)),
          );

  Stream<List<UserProfile>> watchAgents() => _db
      .collection('users')
      .where('role', whereIn: ['administrator', 'superAdministrator'])
      .snapshots()
      .map((snapshot) => snapshot.docs.map(UserProfile.fromSnapshot).toList());

  Future<void> submitTicket({
    required String userId,
    required String userName,
    required ComplaintCategory category,
    required String subject,
    required String description,
    required TicketPriority priority,
    required List<Uint8List> evidence,
  }) async {
    if (subject.trim().isEmpty || description.trim().isEmpty) {
      throw StateError('Subject and description are required.');
    }
    final ref = _tickets.doc();
    final urls = await _upload(userId, ref.id, evidence, 'evidence');
    await ref.set({
      'ticketNumber': 'SUP-${DateTime.now().millisecondsSinceEpoch}',
      'userId': userId,
      'userName': userName.trim(),
      'category': category.name,
      'subject': subject.trim(),
      'description': description.trim(),
      'priority': priority.name,
      'status': TicketStatus.submitted.name,
      'agentId': '',
      'agentName': '',
      'evidenceUrls': urls,
      'escalationLevel': 0,
      'escalationReason': '',
      'resolution': '',
      'satisfactionRating': 0,
      'satisfactionComment': '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> assignAgent(
    SupportTicket ticket,
    UserProfile agent,
    String actorId,
  ) async {
    final ref = _tickets.doc(ticket.id);
    final write = _db.batch();
    write.update(ref, {
      'agentId': agent.uid,
      'agentName': agent.displayName,
      'status': TicketStatus.assigned.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _message(
      write,
      ref,
      senderId: actorId,
      senderName: 'Support team',
      body: 'Ticket assigned to ${agent.displayName}.',
      internal: true,
    );
    await write.commit();
  }

  Future<void> updatePriority(SupportTicket ticket, TicketPriority priority) =>
      _tickets.doc(ticket.id).update({
        'priority': priority.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> updateStatus(SupportTicket ticket, TicketStatus status) =>
      _tickets.doc(ticket.id).update({
        'status': status.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> addMessage(
    SupportTicket ticket, {
    required String senderId,
    required String senderName,
    required String body,
    required bool internal,
    required List<Uint8List> attachments,
  }) async {
    if (body.trim().isEmpty && attachments.isEmpty) {
      throw StateError('Enter a message or attach evidence.');
    }
    final urls = await _upload(
      ticket.userId,
      ticket.id,
      attachments,
      'messages',
    );
    final ref = _tickets.doc(ticket.id);
    final write = _db.batch();
    write.set(ref.collection('messages').doc(), {
      'senderId': senderId,
      'senderName': senderName.trim(),
      'body': body.trim(),
      'internal': internal,
      'attachmentUrls': urls,
      'createdAt': FieldValue.serverTimestamp(),
    });
    write.update(ref, {
      if (!internal && ticket.status == TicketStatus.waitingForUser)
        'status': TicketStatus.inProgress.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await write.commit();
  }

  Future<void> escalate(
    SupportTicket ticket, {
    required String reason,
    required String actorId,
  }) async {
    if (reason.trim().isEmpty) {
      throw StateError('Escalation reason is required.');
    }
    final ref = _tickets.doc(ticket.id);
    final write = _db.batch();
    write.update(ref, {
      'status': TicketStatus.escalated.name,
      'escalationLevel': FieldValue.increment(1),
      'escalationReason': reason.trim(),
      'escalatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _message(
      write,
      ref,
      senderId: actorId,
      senderName: 'Support team',
      body: 'Escalated: ${reason.trim()}',
      internal: true,
    );
    await write.commit();
  }

  Future<void> resolve(
    SupportTicket ticket, {
    required String resolution,
    required String actorId,
  }) async {
    if (resolution.trim().isEmpty) throw StateError('Resolution is required.');
    final ref = _tickets.doc(ticket.id);
    final write = _db.batch();
    write.update(ref, {
      'status': TicketStatus.resolved.name,
      'resolution': resolution.trim(),
      'resolvedBy': actorId,
      'resolvedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _message(
      write,
      ref,
      senderId: actorId,
      senderName: 'Support team',
      body: 'Resolution: ${resolution.trim()}',
      internal: false,
    );
    await write.commit();
  }

  Future<void> reopen(SupportTicket ticket, String userId) =>
      _tickets.doc(ticket.id).update({
        'status': TicketStatus.reopened.name,
        'reopenedBy': userId,
        'reopenedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> rate(
    SupportTicket ticket, {
    required int rating,
    required String comment,
  }) {
    if (rating < 1 || rating > 5) throw StateError('Rating must be 1 to 5.');
    return _tickets.doc(ticket.id).update({
      'satisfactionRating': rating,
      'satisfactionComment': comment.trim(),
      'status': TicketStatus.closed.name,
      'ratedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveArticle({
    String? id,
    required KnowledgeArticleType type,
    required String category,
    required String title,
    required String content,
    required List<String> tags,
    required bool published,
    required String actorId,
  }) {
    if (title.trim().isEmpty || content.trim().isEmpty) {
      throw StateError('Article title and content are required.');
    }
    final ref = id == null
        ? _db.collection('supportKnowledgeBase').doc()
        : _db.collection('supportKnowledgeBase').doc(id);
    return ref.set({
      'type': type.name,
      'category': category.trim(),
      'title': title.trim(),
      'content': content.trim(),
      'tags': tags,
      'published': published,
      'viewCount': 0,
      'updatedBy': actorId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> recordArticleView(String id) => _db
      .collection('supportKnowledgeBase')
      .doc(id)
      .update({'viewCount': FieldValue.increment(1)});

  Future<List<String>> _upload(
    String userId,
    String ticketId,
    List<Uint8List> files,
    String folder,
  ) async {
    final urls = <String>[];
    for (var index = 0; index < files.length; index++) {
      final ref = _storage.ref(
        'supportTickets/$userId/$ticketId/$folder/${DateTime.now().millisecondsSinceEpoch}-$index.jpg',
      );
      await ref.putData(
        files[index],
        SettableMetadata(contentType: 'image/jpeg'),
      );
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  }

  void _message(
    WriteBatch write,
    DocumentReference<Map<String, dynamic>> ref, {
    required String senderId,
    required String senderName,
    required String body,
    required bool internal,
  }) => write.set(ref.collection('messages').doc(), {
    'senderId': senderId,
    'senderName': senderName,
    'body': body,
    'internal': internal,
    'attachmentUrls': [],
    'createdAt': FieldValue.serverTimestamp(),
  });
}
