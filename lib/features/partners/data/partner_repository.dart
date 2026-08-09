import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';
import '../../../core/media/cloudinary_upload_service.dart';

import '../domain/partner.dart';

class PartnerRepository {
  PartnerRepository({FirebaseFirestore? firestore, ApiClient? apiClient})
    : _db = firestore ?? FirebaseFirestore.instance,
      _api = apiClient ?? ApiClient.instance,
      _useApi = apiClient != null || (firestore == null && ApiConfig.enabled);
  final FirebaseFirestore _db;
  final ApiClient _api;
  final bool _useApi;
  CollectionReference<Map<String, dynamic>> get _partners =>
      _db.collection('servicePartners');

  Stream<List<Partner>> watchPartners() => _useApi
      ? _pollPartners()
      : _partners.snapshots().map(
          (snapshot) =>
              snapshot.docs.map(Partner.fromDoc).toList()
                ..sort((a, b) => a.name.compareTo(b.name)),
        );
  Stream<List<Partner>> _pollPartners() async* {
    while (true) {
      final data = await _api.getList('/api/v1/partners');
      yield data.map(Partner.fromJson).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<Partner> watchPartner(String id) => _useApi
      ? _pollPartner(id)
      : _partners.doc(id).snapshots().map(Partner.fromDoc);
  Stream<Partner> _pollPartner(String id) async* {
    while (true) {
      yield Partner.fromJson(await _api.get('/api/v1/partners/$id'));
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<List<PartnerDocument>> watchDocuments(String id) => _useApi
      ? _pollDocuments(id)
      : _partners
            .doc(id)
            .collection('documents')
            .snapshots()
            .map(
              (snapshot) => snapshot.docs.map(PartnerDocument.fromDoc).toList(),
            );
  Stream<List<PartnerDocument>> _pollDocuments(String id) async* {
    while (true) {
      final data = await _api.getList('/api/v1/partners/$id/documents');
      yield data.map(PartnerDocument.fromJson).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<List<PartnerContract>> watchContracts(String id) => _useApi
      ? _pollContracts(id)
      : _partners
            .doc(id)
            .collection('contracts')
            .snapshots()
            .map(
              (snapshot) => snapshot.docs.map(PartnerContract.fromDoc).toList(),
            );
  Stream<List<PartnerContract>> _pollContracts(String id) async* {
    while (true) {
      final data = await _api.getList('/api/v1/partners/$id/contracts');
      yield data.map(PartnerContract.fromJson).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<List<PartnerServiceRecord>> watchServices(String id) => _useApi
      ? _pollServices(id)
      : _partners
            .doc(id)
            .collection('serviceRecords')
            .snapshots()
            .map(
              (snapshot) =>
                  snapshot.docs.map(PartnerServiceRecord.fromDoc).toList(),
            );
  Stream<List<PartnerServiceRecord>> _pollServices(String id) async* {
    while (true) {
      final data = await _api.getList('/api/v1/partners/$id/service-records');
      yield data.map(PartnerServiceRecord.fromJson).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<List<PartnerComplianceRecord>> watchCompliance(String id) => _useApi
      ? _pollCompliance(id)
      : _partners
            .doc(id)
            .collection('complianceRecords')
            .snapshots()
            .map(
              (snapshot) =>
                  snapshot.docs.map(PartnerComplianceRecord.fromDoc).toList(),
            );
  Stream<List<PartnerComplianceRecord>> _pollCompliance(String id) async* {
    while (true) {
      final data = await _api.getList(
        '/api/v1/partners/$id/compliance-records',
      );
      yield data.map(PartnerComplianceRecord.fromJson).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Future<void> register({
    required String name,
    required PartnerType type,
    required String contactName,
    required String contactEmail,
    required String contactPhone,
    required String address,
    required List<PartnerServiceCategory> serviceCategories,
    required List<String> serviceAreas,
    required String pricingInformation,
    required String currency,
    required double facilityCapacityKg,
    required String paymentMethod,
    required String payeeName,
    required String paymentTerms,
    required String actorId,
  }) async {
    if (name.trim().isEmpty || serviceCategories.isEmpty) {
      throw StateError('Partner name and service category are required.');
    }
    if (facilityCapacityKg < 0) {
      throw StateError('Capacity cannot be negative.');
    }
    if (_useApi) {
      await _api.post('/api/v1/partners', {
        'name': name,
        'type': type.name,
        'contactName': contactName,
        'contactEmail': contactEmail,
        'contactPhone': contactPhone,
        'address': address,
        'serviceCategories': serviceCategories.map(_apiCategory).toList(),
        'serviceAreas': serviceAreas,
        'pricingInformation': pricingInformation,
        'paymentCurrency': currency,
        'facilityCapacityKg': facilityCapacityKg,
        'paymentMethod': paymentMethod,
        'payeeName': payeeName,
        'paymentTerms': paymentTerms,
      });
      return;
    }
    final ref = _partners.doc();
    await ref.set({
      'partnerCode': 'PTN-${ref.id.substring(0, 8).toUpperCase()}',
      'name': name.trim(),
      'type': type.name,
      'contactName': contactName.trim(),
      'contactEmail': contactEmail.trim(),
      'contactPhone': contactPhone.trim(),
      'address': address.trim(),
      'serviceCategories': serviceCategories
          .map((value) => value.name)
          .toList(),
      'serviceAreas': serviceAreas,
      'pricingInformation': pricingInformation.trim(),
      'currency': currency.trim(),
      'facilityCapacityKg': facilityCapacityKg,
      'paymentMethod': paymentMethod.trim(),
      'payeeName': payeeName.trim(),
      'paymentTerms': paymentTerms.trim(),
      'status': PartnerStatus.pendingVerification.name,
      'licenceStatus': LicenceVerificationStatus.pending.name,
      'suspensionReason': '',
      'performanceRating': 0,
      'complianceScore': 0,
      'completedServiceCount': 0,
      'onTimeServiceCount': 0,
      'totalSpend': 0,
      'createdBy': actorId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addDocument(
    Partner partner, {
    required String documentType,
    required String referenceNumber,
    required DateTime issuedAt,
    required DateTime expiresAt,
    required Uint8List file,
    required String actorId,
  }) async {
    if (file.isEmpty) throw StateError('Select a document image.');
    final doc = _partners.doc(partner.id).collection('documents').doc();
    final url = await CloudinaryUploadService.instance.uploadImage(
      file,
      scope: 'partners',
      fileName: 'partner-document.jpg',
    );
    if (_useApi) {
      await _api.post('/api/v1/partners/${partner.id}/documents', {
        'type': _documentType(documentType),
        'number': referenceNumber,
        'issuedAt': issuedAt.toUtc().toIso8601String(),
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'documentUrl': url,
      });
      return;
    }
    await doc.set({
      'documentType': documentType.trim(),
      'referenceNumber': referenceNumber.trim(),
      'url': url,
      'verified': false,
      'issuedAt': Timestamp.fromDate(issuedAt),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'uploadedBy': actorId,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> verifyDocument(Partner partner, PartnerDocument document) =>
      _useApi
      ? _api
            .patch(
              '/api/v1/partners/${partner.id}/documents/${document.id}/verify',
              {'decision': 'verified', 'notes': ''},
            )
            .then((_) {})
      : _partners
            .doc(partner.id)
            .collection('documents')
            .doc(document.id)
            .update({
              'verified': true,
              'verifiedAt': FieldValue.serverTimestamp(),
            });

  Future<void> verifyLicence(
    Partner partner, {
    required bool approved,
    required String notes,
    required String actorId,
  }) async {
    if (_useApi) {
      await _api.patch('/api/v1/partners/${partner.id}/licence', {
        'approved': approved,
        'notes': notes,
      });
      return;
    }
    if (approved) {
      final documents = await _partners
          .doc(partner.id)
          .collection('documents')
          .where('verified', isEqualTo: true)
          .get();
      final hasValidDocument = documents.docs
          .map(PartnerDocument.fromDoc)
          .any((document) => !document.expired);
      if (!hasValidDocument) {
        throw StateError(
          'Verify at least one unexpired licence document first.',
        );
      }
    }
    await _partners.doc(partner.id).update({
      'licenceStatus': approved
          ? LicenceVerificationStatus.verified.name
          : LicenceVerificationStatus.rejected.name,
      'status': approved
          ? PartnerStatus.active.name
          : PartnerStatus.pendingVerification.name,
      'licenceVerificationNotes': notes.trim(),
      'licenceVerifiedBy': actorId,
      'licenceVerifiedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> suspend(Partner partner, String reason, String actorId) {
    if (reason.trim().isEmpty) {
      throw StateError('Suspension reason is required.');
    }
    if (_useApi) {
      return _api
          .patch('/api/v1/partners/${partner.id}/status', {
            'status': 'suspended',
            'reason': reason,
          })
          .then((_) {});
    }
    return _partners.doc(partner.id).update({
      'status': PartnerStatus.suspended.name,
      'suspensionReason': reason.trim(),
      'suspendedBy': actorId,
      'suspendedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> reactivate(Partner partner, String actorId) => _useApi
      ? _api
            .patch('/api/v1/partners/${partner.id}/status', {
              'status': 'active',
              'reason': 'Partner reactivated',
            })
            .then((_) {})
      : _partners.doc(partner.id).update({
          'status': PartnerStatus.active.name,
          'suspensionReason': '',
          'reactivatedBy': actorId,
          'reactivatedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

  Future<void> addContract(
    Partner partner, {
    required String contractNumber,
    required String title,
    required DateTime startAt,
    required DateTime endAt,
    required double contractValue,
    required String currency,
    required double slaTargetHours,
    required double minimumQualityRating,
    required String terms,
  }) {
    if (endAt.isBefore(startAt) || slaTargetHours < 0 || contractValue < 0) {
      throw StateError('Contract dates, value, or SLA target are invalid.');
    }
    if (_useApi) {
      return _api
          .post('/api/v1/partners/${partner.id}/contracts', {
            'contractNumber': contractNumber,
            'title': title,
            'serviceCategories': partner.serviceCategories
                .map(_apiCategory)
                .toList(),
            'startsAt': startAt.toUtc().toIso8601String(),
            'endsAt': endAt.toUtc().toIso8601String(),
            'value': contractValue,
            'currency': currency,
            'documentUrl': 'https://ecotrace.invalid/contracts/$contractNumber',
            'paymentTerms': terms,
            'slaTargetHours': slaTargetHours,
            'minimumQualityRating': minimumQualityRating,
          })
          .then((_) {});
    }
    return _partners.doc(partner.id).collection('contracts').add({
      'contractNumber': contractNumber.trim(),
      'title': title.trim(),
      'status': ContractStatus.active.name,
      'startAt': Timestamp.fromDate(startAt),
      'endAt': Timestamp.fromDate(endAt),
      'contractValue': contractValue,
      'currency': currency.trim(),
      'slaTargetHours': slaTargetHours,
      'minimumQualityRating': minimumQualityRating,
      'terms': terms.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> recordService(
    Partner partner, {
    required String reference,
    required PartnerServiceCategory serviceCategory,
    required double targetHours,
    required double actualHours,
    required double qualityRating,
    required double serviceCost,
    required String notes,
  }) async {
    if (qualityRating < 1 ||
        qualityRating > 5 ||
        actualHours < 0 ||
        serviceCost < 0) {
      throw StateError('Service hours, rating, or cost are invalid.');
    }
    if (_useApi) {
      await _api.post('/api/v1/partners/${partner.id}/service-records', {
        'reference': reference,
        'serviceCategory': _apiCategory(serviceCategory),
        'targetHours': targetHours,
        'actualHours': actualHours,
        'qualityRating': qualityRating,
        'serviceCost': serviceCost,
        'notes': notes,
      });
      return;
    }
    final ref = _partners.doc(partner.id);
    await _db.runTransaction((transaction) async {
      final current = Partner.fromDoc(await transaction.get(ref));
      final count = current.completedServiceCount + 1;
      final rating =
          (current.performanceRating * current.completedServiceCount +
              qualityRating) /
          count;
      transaction.set(ref.collection('serviceRecords').doc(), {
        'reference': reference.trim(),
        'serviceCategory': serviceCategory.name,
        'targetHours': targetHours,
        'actualHours': actualHours,
        'qualityRating': qualityRating,
        'serviceCost': serviceCost,
        'notes': notes.trim(),
        'metSla': targetHours <= 0 || actualHours <= targetHours,
        'completedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(ref, {
        'performanceRating': rating,
        'completedServiceCount': count,
        if (targetHours <= 0 || actualHours <= targetHours)
          'onTimeServiceCount': FieldValue.increment(1),
        'totalSpend': FieldValue.increment(serviceCost),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> recordCompliance(
    Partner partner, {
    required String type,
    required double score,
    required String outcome,
    required String findings,
    required DateTime nextReviewAt,
    required String actorId,
  }) async {
    if (score < 0 || score > 100) throw StateError('Score must be 0 to 100.');
    if (_useApi) {
      final total = 100;
      final passed = score.round().clamp(0, total);
      await _api.post('/api/v1/partners/${partner.id}/compliance-records', {
        'checklistName': type,
        'passedItems': passed,
        'totalItems': total,
        'violations': outcome.toLowerCase().contains('pass')
            ? <String>[]
            : <String>[findings.isEmpty ? outcome : findings],
        'correctiveActionDueAt': nextReviewAt.toUtc().toIso8601String(),
        'notes': findings,
      });
      return;
    }
    final ref = _partners.doc(partner.id);
    final write = _db.batch();
    write.set(ref.collection('complianceRecords').doc(), {
      'type': type.trim(),
      'score': score,
      'outcome': outcome.trim(),
      'findings': findings.trim(),
      'reviewedBy': actorId,
      'reviewedAt': FieldValue.serverTimestamp(),
      'nextReviewAt': Timestamp.fromDate(nextReviewAt),
    });
    write.update(ref, {
      'complianceScore': score,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await write.commit();
  }

  Future<void> updateCommercialDetails(
    Partner partner, {
    required String pricingInformation,
    required String currency,
    required double capacityKg,
    required String paymentMethod,
    required String payeeName,
    required String paymentTerms,
  }) {
    if (capacityKg < 0) throw StateError('Capacity cannot be negative.');
    if (_useApi) {
      return _api
          .patch('/api/v1/partners/${partner.id}/commercial', {
            'pricing': <String, double>{},
            'pricingInformation': pricingInformation,
            'currency': currency,
            'facilityCapacityKg': capacityKg,
            'paymentMethod': paymentMethod,
            'payeeName': payeeName,
            'paymentTerms': paymentTerms,
            'paymentInformation': {
              'accountName': payeeName.isEmpty ? 'Not supplied' : payeeName,
              'bankName': paymentMethod.isEmpty
                  ? 'Not supplied'
                  : paymentMethod,
              'accountReference': payeeName.isEmpty
                  ? partner.partnerCode
                  : payeeName,
              'mobileMoneyProvider': '',
              'mobileMoneyNumber': '',
            },
          })
          .then((_) {});
    }
    return _partners.doc(partner.id).update({
      'pricingInformation': pricingInformation.trim(),
      'currency': currency.trim(),
      'facilityCapacityKg': capacityKg,
      'paymentMethod': paymentMethod.trim(),
      'payeeName': payeeName.trim(),
      'paymentTerms': paymentTerms.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

String _apiCategory(PartnerServiceCategory category) => switch (category) {
  PartnerServiceCategory.electronicsRecycling => 'recycling',
  PartnerServiceCategory.deviceRepair => 'repair',
  PartnerServiceCategory.refurbishment => 'refurbishment',
  PartnerServiceCategory.materialPurchase => 'materialBuyer',
  PartnerServiceCategory.hazardousDisposal => 'hazardousDisposal',
  PartnerServiceCategory.transport => 'transport',
  PartnerServiceCategory.collection => 'collectionCentre',
  PartnerServiceCategory.dataDestruction ||
  PartnerServiceCategory.other => 'other',
};

String _documentType(String value) {
  final normalized = value.toLowerCase();
  if (normalized.contains('operating') || normalized.contains('licence')) {
    return 'operatingLicence';
  }
  if (normalized.contains('recycler')) return 'recyclerCertificate';
  if (normalized.contains('tax')) return 'taxCertificate';
  if (normalized.contains('insurance')) return 'insurance';
  if (normalized.contains('environment')) return 'environmentalPermit';
  return 'other';
}
