import 'package:cloud_firestore/cloud_firestore.dart';

enum PartnerType {
  recycler,
  repairCentre,
  materialBuyer,
  transporter,
  collectionService,
  disposalFacility,
  serviceProvider,
}

extension PartnerTypeLabel on PartnerType {
  String get label => switch (this) {
    PartnerType.recycler => 'Recycler',
    PartnerType.repairCentre => 'Repair centre',
    PartnerType.materialBuyer => 'Material buyer',
    PartnerType.transporter => 'Transporter',
    PartnerType.collectionService => 'Collection service',
    PartnerType.disposalFacility => 'Disposal facility',
    PartnerType.serviceProvider => 'Service partner',
  };
}

enum PartnerServiceCategory {
  electronicsRecycling,
  deviceRepair,
  refurbishment,
  materialPurchase,
  hazardousDisposal,
  transport,
  dataDestruction,
  collection,
  other,
}

enum PartnerStatus {
  pendingVerification,
  active,
  suspended,
  expired,
  terminated,
}

enum LicenceVerificationStatus { pending, verified, rejected, expired }

enum ContractStatus { draft, active, expired, terminated }

class Partner {
  const Partner({
    required this.id,
    required this.partnerCode,
    required this.name,
    required this.type,
    required this.contactName,
    required this.contactEmail,
    required this.contactPhone,
    required this.address,
    required this.serviceCategories,
    required this.serviceAreas,
    required this.pricingInformation,
    required this.currency,
    required this.facilityCapacityKg,
    required this.paymentMethod,
    required this.payeeName,
    required this.paymentTerms,
    required this.status,
    required this.licenceStatus,
    required this.suspensionReason,
    required this.performanceRating,
    required this.complianceScore,
    required this.completedServiceCount,
    required this.onTimeServiceCount,
    required this.totalSpend,
    required this.createdAt,
  });
  final String id,
      partnerCode,
      name,
      contactName,
      contactEmail,
      contactPhone,
      address,
      pricingInformation,
      currency,
      paymentMethod,
      payeeName,
      paymentTerms,
      suspensionReason;
  final PartnerType type;
  final List<PartnerServiceCategory> serviceCategories;
  final List<String> serviceAreas;
  final double facilityCapacityKg,
      performanceRating,
      complianceScore,
      totalSpend;
  final int completedServiceCount, onTimeServiceCount;
  final PartnerStatus status;
  final LicenceVerificationStatus licenceStatus;
  final DateTime? createdAt;

  double get slaCompliancePercent => completedServiceCount <= 0
      ? 0
      : onTimeServiceCount / completedServiceCount * 100;
  bool get canReceiveWork =>
      status == PartnerStatus.active &&
      licenceStatus == LicenceVerificationStatus.verified;

  factory Partner.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return Partner.fromJson({...doc.data()!, 'id': doc.id});
  }

  factory Partner.fromJson(Map<String, dynamic> data) {
    PartnerType partnerType(String? value) {
      final aliases = {
        'repair': 'repairCentre',
        'materialBuyer': 'materialBuyer',
        'transport': 'transporter',
        'hazardousDisposal': 'disposalFacility',
        'collectionCentre': 'collectionService',
      };
      return PartnerType.values
              .where((item) => item.name == (aliases[value] ?? value))
              .firstOrNull ??
          PartnerType.serviceProvider;
    }

    PartnerServiceCategory category(String value) {
      const aliases = {
        'recycling': 'electronicsRecycling',
        'repair': 'deviceRepair',
        'refurbishment': 'refurbishment',
        'materialBuyer': 'materialPurchase',
        'transport': 'transport',
        'hazardousDisposal': 'hazardousDisposal',
        'collectionCentre': 'collection',
      };
      return PartnerServiceCategory.values
              .where((item) => item.name == (aliases[value] ?? value))
              .firstOrNull ??
          PartnerServiceCategory.other;
    }

    final payment = Map<String, dynamic>.from(
      data['paymentInformation'] as Map? ?? const {},
    );
    return Partner(
      id: '${data['id'] ?? ''}',
      partnerCode: data['partnerCode'] ?? '${data['id'] ?? ''}',
      name: data['name'] ?? '',
      type: partnerType(data['type'] as String?),
      contactName: data['contactName'] ?? '',
      contactEmail: data['contactEmail'] ?? '',
      contactPhone: data['contactPhone'] ?? '',
      address: data['address'] ?? '',
      serviceCategories: List<String>.from(
        data['serviceCategories'] as List? ?? const [],
      ).map(category).toList(),
      serviceAreas: List<String>.from(
        data['serviceAreas'] as List? ?? const [],
      ),
      pricingInformation:
          data['pricingInformation'] ??
          (data['pricing'] is Map
              ? (data['pricing'] as Map).values.join(', ')
              : ''),
      currency: data['currency'] ?? data['paymentCurrency'] ?? 'SLE',
      facilityCapacityKg: (data['facilityCapacityKg'] as num? ?? 0).toDouble(),
      paymentMethod:
          data['paymentMethod'] ??
          payment['bankName'] ??
          payment['mobileMoneyProvider'] ??
          '',
      payeeName: data['payeeName'] ?? payment['accountName'] ?? '',
      paymentTerms: data['paymentTerms'] ?? '',
      status: PartnerStatus.values.byName(
        data['status'] ?? PartnerStatus.pendingVerification.name,
      ),
      licenceStatus: data['licenceVerified'] == true
          ? LicenceVerificationStatus.verified
          : LicenceVerificationStatus.values
                    .where((item) => item.name == data['licenceStatus'])
                    .firstOrNull ??
                LicenceVerificationStatus.pending,
      suspensionReason: data['suspensionReason'] ?? data['statusReason'] ?? '',
      performanceRating: (data['performanceRating'] as num? ?? 0).toDouble(),
      complianceScore: (data['complianceScore'] as num? ?? 0).toDouble(),
      completedServiceCount: data['completedServiceCount'] as int? ?? 0,
      onTimeServiceCount: data['onTimeServiceCount'] as int? ?? 0,
      totalSpend: (data['totalSpend'] as num? ?? 0).toDouble(),
      createdAt: _date(data['createdAt']),
    );
  }
}

class PartnerDocument {
  const PartnerDocument({
    required this.id,
    required this.documentType,
    required this.referenceNumber,
    required this.url,
    required this.verified,
    required this.issuedAt,
    required this.expiresAt,
  });
  final String id, documentType, referenceNumber, url;
  final bool verified;
  final DateTime? issuedAt, expiresAt;
  bool get expired => expiresAt != null && expiresAt!.isBefore(DateTime.now());
  bool expiresWithin(Duration duration) =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now().add(duration));
  factory PartnerDocument.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return PartnerDocument.fromJson({...doc.data()!, 'id': doc.id});
  }
  factory PartnerDocument.fromJson(Map<String, dynamic> data) {
    return PartnerDocument(
      id: '${data['id'] ?? ''}',
      documentType: data['documentType'] ?? data['type'] ?? '',
      referenceNumber: data['referenceNumber'] ?? data['number'] ?? '',
      url: data['url'] ?? data['documentUrl'] ?? '',
      verified:
          data['verified'] as bool? ?? data['verificationStatus'] == 'verified',
      issuedAt: _date(data['issuedAt']),
      expiresAt: _date(data['expiresAt']),
    );
  }
}

class PartnerContract {
  const PartnerContract({
    required this.id,
    required this.contractNumber,
    required this.title,
    required this.status,
    required this.startAt,
    required this.endAt,
    required this.contractValue,
    required this.currency,
    required this.slaTargetHours,
    required this.minimumQualityRating,
    required this.terms,
  });
  final String id, contractNumber, title, currency, terms;
  final ContractStatus status;
  final DateTime? startAt, endAt;
  final double contractValue, slaTargetHours, minimumQualityRating;
  bool get expired => endAt != null && endAt!.isBefore(DateTime.now());
  factory PartnerContract.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return PartnerContract.fromJson({...doc.data()!, 'id': doc.id});
  }
  factory PartnerContract.fromJson(Map<String, dynamic> data) {
    return PartnerContract(
      id: '${data['id'] ?? ''}',
      contractNumber: data['contractNumber'] ?? '${data['id'] ?? ''}',
      title: data['title'] ?? '',
      status: ContractStatus.values.byName(
        data['status'] ?? ContractStatus.draft.name,
      ),
      startAt: _date(data['startAt'] ?? data['startsAt']),
      endAt: _date(data['endAt'] ?? data['endsAt']),
      contractValue:
          (data['contractValue'] as num? ?? data['value'] as num? ?? 0)
              .toDouble(),
      currency: data['currency'] ?? 'SLE',
      slaTargetHours: (data['slaTargetHours'] as num? ?? 0).toDouble(),
      minimumQualityRating: (data['minimumQualityRating'] as num? ?? 0)
          .toDouble(),
      terms: data['terms'] ?? data['paymentTerms'] ?? '',
    );
  }
}

class PartnerServiceRecord {
  const PartnerServiceRecord({
    required this.reference,
    required this.serviceCategory,
    required this.targetHours,
    required this.actualHours,
    required this.qualityRating,
    required this.serviceCost,
    required this.notes,
    required this.completedAt,
  });
  final String reference, notes;
  final PartnerServiceCategory serviceCategory;
  final double targetHours, actualHours, qualityRating, serviceCost;
  final DateTime? completedAt;
  bool get metSla => targetHours <= 0 || actualHours <= targetHours;
  factory PartnerServiceRecord.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return PartnerServiceRecord.fromJson(doc.data()!);
  }
  factory PartnerServiceRecord.fromJson(Map<String, dynamic> data) {
    return PartnerServiceRecord(
      reference: data['reference'] ?? '',
      serviceCategory: PartnerServiceCategory.values.byName(
        data['serviceCategory'] ?? PartnerServiceCategory.other.name,
      ),
      targetHours: (data['targetHours'] as num? ?? 0).toDouble(),
      actualHours: (data['actualHours'] as num? ?? 0).toDouble(),
      qualityRating: (data['qualityRating'] as num? ?? 0).toDouble(),
      serviceCost: (data['serviceCost'] as num? ?? 0).toDouble(),
      notes: data['notes'] ?? '',
      completedAt: _date(data['completedAt']),
    );
  }
}

class PartnerComplianceRecord {
  const PartnerComplianceRecord({
    required this.type,
    required this.score,
    required this.outcome,
    required this.findings,
    required this.reviewedAt,
    required this.nextReviewAt,
  });
  final String type, outcome, findings;
  final double score;
  final DateTime? reviewedAt, nextReviewAt;
  factory PartnerComplianceRecord.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return PartnerComplianceRecord.fromJson(doc.data()!);
  }
  factory PartnerComplianceRecord.fromJson(Map<String, dynamic> data) {
    return PartnerComplianceRecord(
      type: data['type'] ?? data['checklistName'] ?? '',
      score: (data['score'] as num? ?? 0).toDouble(),
      outcome:
          data['outcome'] ??
          ((data['score'] as num? ?? 0) >= 80 ? 'passed' : 'requiresAction'),
      findings:
          data['findings'] ??
          (data['violations'] as List? ?? const []).join(', '),
      reviewedAt: _date(data['reviewedAt'] ?? data['createdAt']),
      nextReviewAt: _date(
        data['nextReviewAt'] ?? data['correctiveActionDueAt'],
      ),
    );
  }
}

DateTime? _date(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value);
  if (value is Map) {
    final seconds = value['_seconds'] ?? value['seconds'];
    if (seconds is num) {
      return DateTime.fromMillisecondsSinceEpoch(
        seconds.toInt() * 1000,
        isUtc: true,
      );
    }
  }
  return null;
}

class PartnerAnalytics {
  const PartnerAnalytics({
    required this.total,
    required this.active,
    required this.pending,
    required this.suspended,
    required this.averageRating,
    required this.averageCompliance,
    required this.totalCapacityKg,
    required this.totalSpend,
    required this.slaCompliancePercent,
  });
  final int total, active, pending, suspended;
  final double averageRating,
      averageCompliance,
      totalCapacityKg,
      totalSpend,
      slaCompliancePercent;
  factory PartnerAnalytics.fromPartners(List<Partner> partners) {
    double average(Iterable<double> values) {
      final list = values.toList();
      return list.isEmpty ? 0 : list.reduce((a, b) => a + b) / list.length;
    }

    final services = partners.fold<int>(
      0,
      (total, partner) => total + partner.completedServiceCount,
    );
    final onTime = partners.fold<int>(
      0,
      (total, partner) => total + partner.onTimeServiceCount,
    );
    return PartnerAnalytics(
      total: partners.length,
      active: partners
          .where((partner) => partner.status == PartnerStatus.active)
          .length,
      pending: partners
          .where(
            (partner) => partner.status == PartnerStatus.pendingVerification,
          )
          .length,
      suspended: partners
          .where((partner) => partner.status == PartnerStatus.suspended)
          .length,
      averageRating: average(
        partners
            .where((partner) => partner.completedServiceCount > 0)
            .map((partner) => partner.performanceRating),
      ),
      averageCompliance: average(
        partners.map((partner) => partner.complianceScore),
      ),
      totalCapacityKg: partners.fold(
        0,
        (total, partner) => total + partner.facilityCapacityKg,
      ),
      totalSpend: partners.fold(
        0,
        (total, partner) => total + partner.totalSpend,
      ),
      slaCompliancePercent: services <= 0 ? 0 : onTime / services * 100,
    );
  }
}
