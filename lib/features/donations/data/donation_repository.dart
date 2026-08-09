import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';
import '../../../core/media/cloudinary_upload_service.dart';
import '../../repairs/domain/repair_job.dart';
import '../domain/donation.dart';

class DonationRepository {
  DonationRepository({FirebaseFirestore? firestore, ApiClient? apiClient})
    : _db = firestore ?? FirebaseFirestore.instance,
      _api = apiClient ?? ApiClient.instance,
      _useApi = apiClient != null || (firestore == null && ApiConfig.enabled);
  final FirebaseFirestore _db;
  final ApiClient _api;
  final bool _useApi;
  Stream<List<Beneficiary>> watchBeneficiaries() => _useApi
      ? _pollBeneficiaries()
      : _db
            .collection('donationBeneficiaries')
            .snapshots()
            .map((s) => s.docs.map(Beneficiary.fromDoc).toList());
  Stream<List<Beneficiary>> _pollBeneficiaries() async* {
    while (true) {
      final data = await _api.getList('/api/v1/donations/beneficiaries');
      yield data.map(Beneficiary.fromJson).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<List<DonationRequest>> watchRequests({String? requesterId}) => _useApi
      ? _pollRequests()
      : (requesterId == null
                ? _db.collection('donationRequests')
                : _db
                      .collection('donationRequests')
                      .where('requesterId', isEqualTo: requesterId))
            .snapshots()
            .map((s) => s.docs.map(DonationRequest.fromDoc).toList());
  Stream<List<DonationRequest>> _pollRequests() async* {
    while (true) {
      final data = await _api.getList('/api/v1/donations/requests');
      yield data.map(DonationRequest.fromJson).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<List<SocialImpactRecord>> watchImpact(String id) => _useApi
      ? _pollImpact(id)
      : _db
            .collection('donationRequests')
            .doc(id)
            .collection('impactRecords')
            .snapshots()
            .map((s) => s.docs.map(SocialImpactRecord.fromDoc).toList());
  Stream<List<SocialImpactRecord>> _pollImpact(String id) async* {
    while (true) {
      final data = await _api.getList(
        '/api/v1/donations/requests/$id/follow-ups',
      );
      yield data.map(SocialImpactRecord.fromJson).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<List<RepairJob>> watchEligibleDevices() => _useApi
      ? _pollEligibleDevices()
      : _db
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
  Stream<List<RepairJob>> _pollEligibleDevices() async* {
    while (true) {
      final data = await _api.getList('/api/v1/donations/eligible-devices');
      yield data.map(RepairJob.fromJson).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Future<void> registerBeneficiary({
    required String name,
    required BeneficiaryType type,
    required String contactName,
    required String contact,
    required String address,
    required int peopleServed,
    required String actorId,
  }) => _useApi
      ? _api
            .post('/api/v1/donations/beneficiaries', {
              'type': _beneficiaryType(type),
              'name': name,
              'registrationNumber': '',
              'contactName': contactName,
              'contactEmail': contact.contains('@')
                  ? contact
                  : 'contact@ecotrace.invalid',
              'contactPhone': contact.contains('@') ? '00000000' : contact,
              'address': address,
              'district': address,
              'beneficiariesServed': peopleServed,
              'mission': 'Community technology access and digital inclusion',
              'verificationDocumentUrls': <String>[],
            })
            .then((_) {})
      : _db.collection('donationBeneficiaries').add({
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
  }) => _useApi
      ? _api
            .patch('/api/v1/donations/beneficiaries/${b.id}/eligibility', {
              'decision': status.name,
              'score': score,
              'criteria': {'communityBenefit': true},
              'notes': notes,
            })
            .then((_) {})
      : _db.collection('donationBeneficiaries').doc(b.id).update({
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
  }) => _useApi
      ? _api
            .post('/api/v1/donations/requests', {
              'beneficiaryId': beneficiary.id,
              'deviceCategory': deviceTypes
                  .map((value) => value.trim())
                  .where((value) => value.isNotEmpty)
                  .join(', '),
              'quantity': quantity,
              'purpose': purpose,
              'urgency': 'normal',
              'requestedDeliveryDate': DateTime.now()
                  .add(const Duration(days: 30))
                  .toUtc()
                  .toIso8601String(),
              'supportingDocumentUrls': <String>[],
            })
            .then((_) {})
      : _db.collection('donationRequests').add({
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
      _useApi
      ? _api
            .patch('/api/v1/donations/requests/${r.id}/review', {
              'decision': approved ? 'approved' : 'rejected',
              'notes': '',
            })
            .then((_) {})
      : _db.collection('donationRequests').doc(r.id).update({
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
    if (_useApi) {
      await _api.patch('/api/v1/donations/requests/${r.id}/allocation', {
        'deviceIds': jobs.map((job) => job.id).toList(),
      });
      return;
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
      _useApi
      ? _api
            .patch('/api/v1/donations/requests/${r.id}/delivery', {
              'status': 'scheduled',
              'scheduledAt': date.toUtc().toIso8601String(),
              'carrier': 'EcoTrace delivery team',
              'trackingReference': 'DON-${r.id}',
              'proofOfDeliveryUrls': <String>[],
              'recipientName': '',
            })
            .then((_) {})
      : _db.collection('donationRequests').doc(r.id).update({
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
    if (_useApi) {
      await _api.patch('/api/v1/donations/requests/${r.id}/delivery', {
        'status': 'delivered',
        'scheduledAt': (r.deliveryAt ?? DateTime.now())
            .toUtc()
            .toIso8601String(),
        'carrier': 'EcoTrace delivery team',
        'trackingReference': 'DON-${r.id}',
        'proofOfDeliveryUrls': <String>[proofUrl],
        'recipientName': 'Beneficiary representative',
      });
      return;
    }
    await _db.collection('donationRequests').doc(r.id).update({
      'status': DonationStatus.delivered.name,
      'proofUrl': proofUrl,
      'deliveredBy': actorId,
      'deliveredAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> confirm(DonationRequest r, String name) => _useApi
      ? _api
            .patch('/api/v1/donations/requests/${r.id}/confirm', {
              'confirmed': true,
              'condition': 'good',
              'comments': name,
            })
            .then((_) {})
      : _db.collection('donationRequests').doc(r.id).update({
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
    if (_useApi) {
      await _api.post('/api/v1/donations/requests/${r.id}/follow-ups', {
        'devicesInUse': r.allocatedJobIds.length,
        'devicesFunctional': activeDevices,
        'peopleReached': peopleReached,
        'usageSummary': notes.isEmpty ? 'Devices remain in active use.' : notes,
        'issues': <String>[],
        'evidenceUrls': <String>[],
      });
      return;
    }
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

  Future<Map<String, dynamic>> certificate(DonationRequest request) => _useApi
      ? _api.get('/api/v1/donations/requests/${request.id}/certificate')
      : Future.value({
          'certificateNumber': request.requestNumber,
          'beneficiaryName': request.beneficiaryName,
          'donatedQuantity': request.allocatedJobIds.length,
          'issuedAt': request.deliveryAt?.toIso8601String(),
        });
}

String _beneficiaryType(BeneficiaryType type) =>
    type == BeneficiaryType.publicInstitution
    ? 'governmentInstitution'
    : type.name;
