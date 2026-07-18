import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../domain/organization.dart';

class OrganizationRepository {
  OrganizationRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  Stream<List<Organization>> watchForUser(String uid) => _firestore
      .collection('organizations')
      .where('memberIds', arrayContains: uid)
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.docs.map(Organization.fromSnapshot).toList()
              ..sort((a, b) => a.name.compareTo(b.name)),
      );

  Stream<Organization?> watchOrganization(String organizationId) => _firestore
      .collection('organizations')
      .doc(organizationId)
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.exists ? Organization.fromSnapshot(snapshot) : null,
      );

  Stream<List<Organization>> watchPendingVerification() => _firestore
      .collection('organizations')
      .where('status', isEqualTo: OrganizationStatus.pendingVerification.name)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(Organization.fromSnapshot).toList());

  Future<void> review({
    required String organizationId,
    required bool approved,
    String? reason,
  }) => _firestore.collection('organizations').doc(organizationId).update({
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
  }) => _firestore
      .collection('organizations')
      .doc(organizationId)
      .collection('branches')
      .add({
        'name': name.trim(),
        'address': address.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });

  Stream<List<OrganizationBranch>> watchBranches(String organizationId) =>
      _firestore
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

  Future<void> inviteStaff(
    String organizationId, {
    required String email,
    required String role,
  }) => _firestore.collection('organizationInvitations').add({
    'organizationId': organizationId,
    'email': email.trim().toLowerCase(),
    'organizationRole': role,
    'status': 'pending',
    'createdAt': FieldValue.serverTimestamp(),
  });

  Future<void> uploadDocument(
    String organizationId, {
    required String fileName,
    required Uint8List bytes,
  }) async {
    final document = _firestore
        .collection('organizations')
        .doc(organizationId)
        .collection('documents')
        .doc();
    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final reference = _storage.ref(
      'organizationDocuments/$organizationId/${document.id}_$safeName',
    );
    await reference.putData(
      bytes,
      SettableMetadata(contentType: _contentType(fileName)),
    );
    final downloadUrl = await reference.getDownloadURL();
    await document.set({
      'name': fileName,
      'storagePath': reference.fullPath,
      'downloadUrl': downloadUrl,
      'uploadedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<OrganizationDocument>> watchDocuments(String organizationId) =>
      _firestore
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
