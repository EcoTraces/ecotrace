import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';
import '../../../core/media/cloudinary_upload_service.dart';

import '../domain/organization.dart';

class OrganizationRepository {
  OrganizationRepository({FirebaseFirestore? firestore, ApiClient? apiClient})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _api = apiClient ?? ApiClient.instance,
      _useApi = apiClient != null || (firestore == null && ApiConfig.enabled);

  final FirebaseFirestore _firestore;
  final ApiClient _api;
  final bool _useApi;

  Stream<List<Organization>> watchForUser(String uid) => _useApi
      ? _pollOrganizations()
      : _firestore
            .collection('organizations')
            .where('memberIds', arrayContains: uid)
            .snapshots()
            .map(
              (snapshot) =>
                  snapshot.docs.map(Organization.fromSnapshot).toList()
                    ..sort((a, b) => a.name.compareTo(b.name)),
            );
  Stream<List<Organization>> _pollOrganizations({String? status}) async* {
    while (true) {
      final data = await _api.getList(
        '/api/v1/organizations',
        query: status == null ? null : {'status': status},
      );
      yield data.map(Organization.fromJson).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<Organization?> watchOrganization(String organizationId) => _useApi
      ? _pollOrganization(organizationId)
      : _firestore
            .collection('organizations')
            .doc(organizationId)
            .snapshots()
            .map(
              (snapshot) =>
                  snapshot.exists ? Organization.fromSnapshot(snapshot) : null,
            );
  Stream<Organization?> _pollOrganization(String id) async* {
    while (true) {
      yield Organization.fromJson(await _api.get('/api/v1/organizations/$id'));
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<List<Organization>> watchPendingVerification() => _useApi
      ? _pollOrganizations(status: OrganizationStatus.pendingVerification.name)
      : _firestore
            .collection('organizations')
            .where(
              'status',
              isEqualTo: OrganizationStatus.pendingVerification.name,
            )
            .snapshots()
            .map(
              (snapshot) =>
                  snapshot.docs.map(Organization.fromSnapshot).toList(),
            );

  Future<void> review({
    required String organizationId,
    required bool approved,
    String? reason,
  }) => _useApi
      ? _api
            .patch('/api/v1/organizations/$organizationId/review', {
              'decision': approved ? 'approve' : 'reject',
              'reason': reason?.trim() ?? '',
              'verificationScore': approved ? 100 : 0,
            })
            .then((_) {})
      : _firestore.collection('organizations').doc(organizationId).update({
          'status': approved
              ? OrganizationStatus.approved.name
              : OrganizationStatus.rejected.name,
          'rejectionReason': approved ? null : reason?.trim(),
          'reviewedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

  Future<String> create({
    required String ownerId,
    required String name,
    required OrganizationType type,
    required String registrationNumber,
    required String contactEmail,
    required String contactPhone,
    required String address,
    required List<String> serviceAreas,
  }) async {
    if (_useApi) {
      final data = await _api.post('/api/v1/organizations', {
        'name': name.trim(),
        'type': type.value,
        'registrationNumber': registrationNumber.trim(),
        'contactName': name.trim(),
        'contactEmail': contactEmail.trim().toLowerCase(),
        'contactPhone': contactPhone.trim(),
        'address': address.trim(),
        'website': '',
        'serviceAreas': serviceAreas,
      });
      return data['id'].toString();
    }
    final organization = _firestore.collection('organizations').doc();
    final batch = _firestore.batch();
    batch.set(organization, {
      'name': name.trim(),
      'type': type.value,
      'registrationNumber': registrationNumber.trim(),
      'contactEmail': contactEmail.trim().toLowerCase(),
      'contactPhone': contactPhone.trim(),
      'address': address.trim(),
      'serviceAreas': serviceAreas,
      'status': OrganizationStatus.pendingVerification.name,
      'ownerId': ownerId,
      'memberIds': [ownerId],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'submittedAt': FieldValue.serverTimestamp(),
      'rejectionReason': null,
    });
    batch.set(organization.collection('members').doc(ownerId), {
      'userId': ownerId,
      'organizationRole': 'owner',
      'status': 'active',
      'joinedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return organization.id;
  }

  Future<void> addBranch(
    String organizationId, {
    required String name,
    required String address,
  }) => _useApi
      ? _api
            .post('/api/v1/organizations/$organizationId/branches', {
              'name': name.trim(),
              'address': address.trim(),
              'contactName': '',
              'contactPhone': '',
              'serviceAreas': <String>[],
            })
            .then((_) {})
      : _firestore
            .collection('organizations')
            .doc(organizationId)
            .collection('branches')
            .add({
              'name': name.trim(),
              'address': address.trim(),
              'createdAt': FieldValue.serverTimestamp(),
            });

  Stream<List<OrganizationBranch>> watchBranches(String organizationId) =>
      _useApi
      ? _pollList(
          '/api/v1/organizations/$organizationId/branches',
          OrganizationBranch.fromJson,
        )
      : _firestore
            .collection('organizations')
            .doc(organizationId)
            .collection('branches')
            .orderBy('createdAt')
            .snapshots()
            .map(
              (snapshot) => snapshot.docs
                  .map(
                    (doc) => OrganizationBranch(
                      id: doc.id,
                      name: doc.data()['name'] as String? ?? '',
                      address: doc.data()['address'] as String? ?? '',
                    ),
                  )
                  .toList(),
            );

  Future<void> updateBranch(
    String organizationId,
    String branchId, {
    required String name,
    required String address,
  }) => _useApi
      ? _api
            .patch('/api/v1/organizations/$organizationId/branches/$branchId', {
              'name': name.trim(),
              'address': address.trim(),
            })
            .then((_) {})
      : _firestore
            .collection('organizations')
            .doc(organizationId)
            .collection('branches')
            .doc(branchId)
            .set({
              'name': name.trim(),
              'address': address.trim(),
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));

  Future<void> archiveBranch(String organizationId, String branchId) => _useApi
      ? _api.delete('/api/v1/organizations/$organizationId/branches/$branchId')
      : _firestore
            .collection('organizations')
            .doc(organizationId)
            .collection('branches')
            .doc(branchId)
            .set({
              'active': false,
              'archivedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));

  Future<void> inviteStaff(
    String organizationId, {
    required String email,
    required String role,
  }) => _useApi
      ? _api
            .post('/api/v1/organizations/$organizationId/invitations', {
              'email': email.trim().toLowerCase(),
              'organizationRole': role,
              'branchId': '',
            })
            .then((_) {})
      : _firestore.collection('organizationInvitations').add({
          'organizationId': organizationId,
          'email': email.trim().toLowerCase(),
          'organizationRole': role,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });

  Stream<List<OrganizationMember>> watchMembers(String organizationId) =>
      _useApi
      ? _pollList(
          '/api/v1/organizations/$organizationId/members',
          OrganizationMember.fromJson,
        )
      : _firestore
            .collection('organizations')
            .doc(organizationId)
            .collection('members')
            .snapshots()
            .map(
              (snapshot) => snapshot.docs
                  .map(
                    (doc) => OrganizationMember.fromJson({
                      'id': doc.id,
                      ...doc.data(),
                    }),
                  )
                  .toList(),
            );

  Future<void> updateMember(
    String organizationId,
    String uid, {
    required String role,
    required String status,
    String branchId = '',
  }) => _useApi
      ? _api
            .patch('/api/v1/organizations/$organizationId/members/$uid', {
              'organizationRole': role,
              'status': status,
              'branchId': branchId,
            })
            .then((_) {})
      : _firestore
            .collection('organizations')
            .doc(organizationId)
            .collection('members')
            .doc(uid)
            .set({
              'organizationRole': role,
              'status': status,
              'branchId': branchId,
            }, SetOptions(merge: true));

  Future<void> removeMember(String organizationId, String uid) => _useApi
      ? _api.delete('/api/v1/organizations/$organizationId/members/$uid')
      : _firestore
            .collection('organizations')
            .doc(organizationId)
            .collection('members')
            .doc(uid)
            .delete();

  Future<List<OrganizationInvitation>> invitations() async {
    if (!_useApi) return const [];
    return (await _api.getList(
      '/api/v1/organization-invitations',
    )).map(OrganizationInvitation.fromJson).toList();
  }

  Future<void> respondToInvitation(String invitationId, bool accept) async {
    if (_useApi) {
      await _api.patch(
        '/api/v1/organization-invitations/$invitationId/respond',
        {'decision': accept ? 'accept' : 'decline'},
      );
    }
  }

  Future<void> updateServiceAreas(String organizationId, List<String> areas) =>
      _useApi
      ? _api
            .put('/api/v1/organizations/$organizationId/service-areas', {
              'serviceAreas': areas,
            })
            .then((_) {})
      : _firestore.collection('organizations').doc(organizationId).update({
          'serviceAreas': areas,
        });

  Future<void> uploadDocument(
    String organizationId, {
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (_useApi) {
      final url = await CloudinaryUploadService.instance.uploadImage(
        bytes,
        scope: 'organizations',
        fileName: fileName,
      );
      await _api.post('/api/v1/organizations/$organizationId/documents', {
        'name': fileName,
        'documentType': _documentType(fileName),
        'fileUrl': url,
        'publicId': Uri.parse(url).pathSegments.last,
        'mimeType': _contentType(fileName),
        'expiresAt': null,
      });
      return;
    }
    final document = _firestore
        .collection('organizations')
        .doc(organizationId)
        .collection('documents')
        .doc();
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final downloadUrl = await CloudinaryUploadService.instance.uploadImage(
      bytes,
      scope: 'organizations',
      fileName: safeName,
    );
    await document.set({
      'name': fileName,
      'downloadUrl': downloadUrl,
      'uploadedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<OrganizationDocument>> watchDocuments(String organizationId) =>
      _useApi
      ? _pollList(
          '/api/v1/organizations/$organizationId/documents',
          OrganizationDocument.fromJson,
        )
      : _firestore
            .collection('organizations')
            .doc(organizationId)
            .collection('documents')
            .orderBy('uploadedAt', descending: true)
            .snapshots()
            .map(
              (snapshot) => snapshot.docs
                  .map(
                    (doc) => OrganizationDocument(
                      id: doc.id,
                      name: doc.data()['name'] as String? ?? '',
                      downloadUrl: doc.data()['downloadUrl'] as String? ?? '',
                    ),
                  )
                  .toList(),
            );

  Stream<List<T>> _pollList<T>(
    String path,
    T Function(Map<String, dynamic>) convert,
  ) async* {
    while (true) {
      final data = await _api.getList(path);
      yield data.map(convert).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }
}

String _documentType(String fileName) {
  final name = fileName.toLowerCase();
  if (name.contains('licen')) return 'licence';
  if (name.contains('tax')) return 'tax';
  if (name.contains('certif')) return 'certificate';
  if (name.contains('insur')) return 'insurance';
  if (name.contains('registr')) return 'registration';
  return 'other';
}

String _contentType(String fileName) {
  final extension = fileName.split('.').last.toLowerCase();
  return switch (extension) {
    'pdf' => 'application/pdf',
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    _ => 'application/octet-stream',
  };
}
