import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';
import '../../../core/media/cloudinary_upload_service.dart';
import '../domain/managed_document.dart';

class DocumentRepository {
  DocumentRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    FirebaseAuth? auth,
    ApiClient? apiClient,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _api = apiClient ?? ApiClient.instance,
       _useApi =
           apiClient != null ||
           (firestore == null && auth == null && ApiConfig.enabled);
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final FirebaseAuth _auth;
  final ApiClient _api;
  final bool _useApi;
  CollectionReference<Map<String, dynamic>> get _docs =>
      _db.collection('managedDocuments');
  Stream<List<ManagedDocument>> watchDocuments(String userId, bool all) =>
      _useApi
      ? _pollDocuments(userId, all)
      : (all ? _docs : _docs.where('ownerId', isEqualTo: userId))
            .snapshots()
            .map(
              (s) => s.docs.map(ManagedDocument.fromDoc).toList()
                ..sort(
                  (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
                    a.createdAt ?? DateTime(0),
                  ),
                ),
            );
  Stream<List<ManagedDocument>> _pollDocuments(String userId, bool all) async* {
    while (true) {
      final data = await _api.getList('/api/v1/documents');
      final docs = data.map(ManagedDocument.fromJson).toList();
      yield all
          ? docs
          : docs
                .where((d) => d.ownerId == userId || d.ownerId.isEmpty)
                .toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<ManagedDocument> watchDocument(String id) => _useApi
      ? _pollDocument(id)
      : _docs.doc(id).snapshots().map(ManagedDocument.fromDoc);
  Stream<ManagedDocument> _pollDocument(String id) async* {
    while (true) {
      final data = await _api.get('/api/v1/documents/$id');
      yield ManagedDocument.fromJson({'id': id, ...data});
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<List<DocumentVersion>> watchVersions(String id) => _useApi
      ? _pollVersions(id)
      : _docs
            .doc(id)
            .collection('versions')
            .snapshots()
            .map(
              (s) =>
                  s.docs.map(DocumentVersion.fromDoc).toList()
                    ..sort((a, b) => b.version.compareTo(a.version)),
            );

  Stream<List<DocumentVersion>> _pollVersions(String id) async* {
    while (true) {
      final data = await _api.getList('/api/v1/documents/$id/versions');
      yield data.map(DocumentVersion.fromJson).toList()
        ..sort((a, b) => b.version.compareTo(a.version));
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<List<DocumentAuditEvent>> watchAudit(String id) => _useApi
      ? _pollAudit(id)
      : _docs
            .doc(id)
            .collection('auditTrail')
            .snapshots()
            .map((s) => s.docs.map(DocumentAuditEvent.fromDoc).toList());

  Stream<List<DocumentAuditEvent>> _pollAudit(String id) async* {
    while (true) {
      final data = await _api.getList('/api/v1/documents/$id/audit');
      yield data.map(DocumentAuditEvent.fromJson).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Future<void> upload({
    required String ownerId,
    required String ownerName,
    required String title,
    required DocumentCategory category,
    required DocumentAccessLevel access,
    required String reference,
    required DateTime? expiresAt,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
    required String actorId,
  }) async {
    if (bytes.isEmpty || title.trim().isEmpty) {
      throw StateError('Title and file are required.');
    }
    if (_useApi) {
      final fileUrl = await CloudinaryUploadService.instance.uploadImage(
        bytes,
        scope: 'documents',
        fileName: fileName,
      );
      await _api.post('/api/v1/documents', {
        'title': title.trim(),
        'category': category.name,
        'description': '',
        'documentType': category.name,
        'fileUrl': fileUrl,
        'currentVersion': 1,
        'status': 'pendingApproval',
        'ownerId': ownerId,
        'ownerName': ownerName,
        'approverId': '',
        'expiresAt': expiresAt?.toIso8601String(),
        'referenceNumber': reference.trim(),
        'tags': <String>[],
        'secureAccess': true,
      });
      return;
    }
    final ref = _docs.doc(),
        url = await _store(ownerId, ref.id, 1, fileName, mimeType, bytes),
        batch = _db.batch();
    batch.set(ref, {
      'title': title.trim(),
      'category': category.name,
      'ownerId': ownerId,
      'ownerName': ownerName,
      'status': ManagedDocumentStatus.pendingApproval.name,
      'accessLevel': access.name,
      'currentVersion': 1,
      'fileName': fileName,
      'mimeType': mimeType,
      'url': url,
      'referenceNumber': reference.trim(),
      'expiresAt': expiresAt == null ? null : Timestamp.fromDate(expiresAt),
      'createdBy': actorId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(ref.collection('versions').doc('1'), {
      'version': 1,
      'fileName': fileName,
      'mimeType': mimeType,
      'url': url,
      'changeNotes': 'Initial upload',
      'uploadedBy': actorId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    _audit(batch, ref, 'uploaded', actorId, 'Version 1');
    await batch.commit();
  }

  Future<void> newVersion(
    ManagedDocument d, {
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
    required String notes,
    required String actorId,
  }) async {
    final v = d.currentVersion + 1;
    if (_useApi) {
      final fileUrl = await CloudinaryUploadService.instance.uploadImage(
        bytes,
        scope: 'documents',
        fileName: fileName,
      );
      await _api.post('/api/v1/documents/${d.id}/versions', {
        'fileUrl': fileUrl,
        'fileName': fileName,
        'mimeType': mimeType,
        'version': v,
        'changeNotes': notes.trim(),
      });
      return;
    }
    final url = await _store(d.ownerId, d.id, v, fileName, mimeType, bytes),
        ref = _docs.doc(d.id),
        batch = _db.batch();
    batch.update(ref, {
      'currentVersion': v,
      'fileName': fileName,
      'mimeType': mimeType,
      'url': url,
      'status': ManagedDocumentStatus.pendingApproval.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(ref.collection('versions').doc('$v'), {
      'version': v,
      'fileName': fileName,
      'mimeType': mimeType,
      'url': url,
      'changeNotes': notes.trim(),
      'uploadedBy': actorId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    _audit(batch, ref, 'versionAdded', actorId, 'Version $v: $notes');
    await batch.commit();
  }

  Future<void> approve(
    ManagedDocument d,
    bool approved,
    String actor,
    String notes,
  ) async {
    if (_useApi) {
      await _api.patch('/api/v1/documents/${d.id}/approve', {
        'approved': approved,
      });
      return;
    }
    final ref = _docs.doc(d.id), batch = _db.batch();
    batch.update(ref, {
      'status': approved
          ? ManagedDocumentStatus.approved.name
          : ManagedDocumentStatus.rejected.name,
      'approvalNotes': notes.trim(),
      'reviewedBy': actor,
      'reviewedAt': FieldValue.serverTimestamp(),
    });
    _audit(batch, ref, approved ? 'approved' : 'rejected', actor, notes);
    await batch.commit();
  }

  Future<void> archive(ManagedDocument d, String actor) async {
    if (_useApi) {
      await _api.patch('/api/v1/documents/${d.id}/archive', {}).then((_) {});
      return;
    }
    final ref = _docs.doc(d.id), batch = _db.batch();
    batch.update(ref, {
      'status': ManagedDocumentStatus.archived.name,
      'archivedAt': FieldValue.serverTimestamp(),
    });
    _audit(batch, ref, 'archived', actor, 'Document archived');
    await batch.commit();
  }

  Future<Uint8List> download(String url) => _storage
      .refFromURL(url)
      .getData(20 * 1024 * 1024)
      .then((x) => x ?? Uint8List(0));
  Future<String> _store(
    String ownerId,
    String id,
    int v,
    String name,
    String mime,
    Uint8List b,
  ) async {
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_'),
        ref = _storage.ref('managedDocuments/$ownerId/$id/v$v-$safe');
    await ref.putData(b, SettableMetadata(contentType: mime));
    return ref.getDownloadURL();
  }

  void _audit(
    WriteBatch b,
    DocumentReference<Map<String, dynamic>> r,
    String action,
    String actor,
    String details,
  ) => b.set(r.collection('auditTrail').doc(), {
    'action': action,
    'actorId': actor,
    'details': details,
    'createdAt': FieldValue.serverTimestamp(),
  });
}
