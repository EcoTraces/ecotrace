import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/media/cloudinary_upload_service.dart';
import '../../repairs/domain/repair_job.dart';
import '../domain/donation.dart';

class DonationRepository {
  DonationRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;
  Stream<List<Beneficiary>> watchBeneficiaries() => _db
      .collection('donationBeneficiaries')
      .snapshots()
      .map((s) => s.docs.map(Beneficiary.fromDoc).toList());
  Stream<List<DonationRequest>> watchRequests({String? requesterId}) =>
      (requesterId == null
              ? _db.collection('donationRequests')
              : _db
                    .collection('donationRequests')
                    .where('requesterId', isEqualTo: requesterId))
          .snapshots()
          .map((s) => s.docs.map(DonationRequest.fromDoc).toList());
  Stream<List<SocialImpactRecord>> watchImpact(String id) => _db
      .collection('donationRequests')
      .doc(id)
      .collection('impactRecords')
      .snapshots()
      .map((s) => s.docs.map(SocialImpactRecord.fromDoc).toList());
  Stream<List<RepairJob>> watchEligibleDevices() => _db
      .collection('repairJobs')
      .where('status', isEqualTo: RepairStatus.completed.name)
      .snapshots()
      .map(
        (s) => s.docs
            .map(RepairJob.fromDoc)
            .where(
              (j) =>
                  j.dispositionApproved &&
                  j.disposition == RefurbishedDisposition.donation,
            )
            .toList(),
      );
  Future<void> registerBeneficiary({
    required String name,
    required BeneficiaryType type,
    required String contactName,
    required String contact,
    required String address,
    required int peopleServed,
    required String actorId,
  }) => _db.collection('donationBeneficiaries').add({
    'name': name.trim(),
    'type': type.name,
    'contactName': contactName.trim(),
    'contact': contact.trim(),
    'address': address.trim(),
    'peopleServed': peopleServed,
    'eligibilityStatus': EligibilityStatus.pending.name,
    'eligibilityScore': 0,
    'assessmentNotes': '',
    'registeredBy': actorId,
    'createdAt': FieldValue.serverTimestamp(),
  });
  Future<void> assess(
    Beneficiary b, {
    required EligibilityStatus status,
    required double score,
    required String notes,
    required String actorId,
  }) => _db.collection('donationBeneficiaries').doc(b.id).update({
    'eligibilityStatus': status.name,
    'eligibilityScore': score,
    'assessmentNotes': notes.trim(),
    'assessedBy': actorId,
    'assessedAt': FieldValue.serverTimestamp(),
  });
  Future<void> submitRequest({
    required String requesterId,
    required Beneficiary beneficiary,
    required List<String> deviceTypes,
    required int quantity,
    required String purpose,
  }) => _db.collection('donationRequests').add({
    'requestNumber': 'DON-${DateTime.now().millisecondsSinceEpoch}',
    'requesterId': requesterId,
    'beneficiaryId': beneficiary.id,
    'beneficiaryName': beneficiary.name,
    'deviceTypes': deviceTypes,
    'quantity': quantity,
    'purpose': purpose.trim(),
    'status': DonationStatus.requested.name,
    'allocatedJobIds': [],
    'proofUrl': '',
    'confirmedBy': '',
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });
  Future<void> approve(DonationRequest r, bool approved, String actorId) =>
      _db.collection('donationRequests').doc(r.id).update({
        'status': approved
            ? DonationStatus.approved.name
            : DonationStatus.rejected.name,
        'approvedBy': actorId,
        'approvedAt': FieldValue.serverTimestamp(),
      });
  Future<void> allocate(
    DonationRequest r,
    List<RepairJob> jobs,
    String actorId,
  ) async {
    if (jobs.isEmpty || jobs.length > r.quantity) {
      throw StateError('Select an eligible device allocation.');
    }
    final ref = _db.collection('donationRequests').doc(r.id),
        batch = _db.batch();
    batch.update(ref, {
      'status': DonationStatus.allocated.name,
      'allocatedJobIds': jobs.map((j) => j.id).toList(),
      'allocatedBy': actorId,
      'allocatedAt': FieldValue.serverTimestamp(),
    });
    for (final job in jobs) {
      batch.update(_db.collection('repairJobs').doc(job.id), {
        'donationRequestId': r.id,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> schedule(DonationRequest r, DateTime date, String actorId) =>
      _db.collection('donationRequests').doc(r.id).update({
        'status': DonationStatus.scheduled.name,
        'deliveryAt': Timestamp.fromDate(date),
        'scheduledBy': actorId,
      });
  Future<void> deliver(
    DonationRequest r,
    Uint8List proof,
    String actorId,
  ) async {
    if (proof.isEmpty) throw StateError('Proof of delivery is required.');
    final proofUrl = await CloudinaryUploadService.instance.uploadImage(
      proof,
      scope: 'donations',
      fileName: 'delivery-proof.jpg',
    );
    await _db.collection('donationRequests').doc(r.id).update({
      'status': DonationStatus.delivered.name,
      'proofUrl': proofUrl,
      'deliveredBy': actorId,
      'deliveredAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> confirm(DonationRequest r, String name) =>
      _db.collection('donationRequests').doc(r.id).update({
        'status': DonationStatus.confirmed.name,
        'confirmedBy': name.trim(),
        'confirmedAt': FieldValue.serverTimestamp(),
      });
  Future<void> followUp(
    DonationRequest r, {
    required int peopleReached,
    required int activeDevices,
    required String notes,
    required String actorId,
  }) async {
    final ref = _db.collection('donationRequests').doc(r.id),
        batch = _db.batch();
    batch.set(ref.collection('impactRecords').doc(), {
      'devicesDelivered': r.allocatedJobIds.length,
      'peopleReached': peopleReached,
      'activeDevices': activeDevices,
      'usageNotes': notes.trim(),
      'recordedBy': actorId,
      'recordedAt': FieldValue.serverTimestamp(),
    });
    batch.update(ref, {
      'status': DonationStatus.completed.name,
      'completedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }
}
