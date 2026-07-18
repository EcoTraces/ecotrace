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
    final data = doc.data()!;
    return Partner(
      id: doc.id,
      partnerCode: data['partnerCode'] ?? doc.id,
      name: data['name'] ?? '',
      type: PartnerType.values.byName(
        data['type'] ?? PartnerType.serviceProvider.name,
      ),
      contactName: data['contactName'] ?? '',
      contactEmail: data['contactEmail'] ?? '',
      contactPhone: data['contactPhone'] ?? '',
      address: data['address'] ?? '',
      serviceCategories: List<String>.from(
        data['serviceCategories'] as List? ?? const [],
      ).map(PartnerServiceCategory.values.byName).toList(),
      serviceAreas: List<String>.from(
        data['serviceAreas'] as List? ?? const [],
      ),
      pricingInformation: data['pricingInformation'] ?? '',
      currency: data['currency'] ?? 'SLE',
      facilityCapacityKg: (data['facilityCapacityKg'] as num? ?? 0).toDouble(),
      paymentMethod: data['paymentMethod'] ?? '',
      payeeName: data['payeeName'] ?? '',
      paymentTerms: data['paymentTerms'] ?? '',
      status: PartnerStatus.values.byName(
        data['status'] ?? PartnerStatus.pendingVerification.name,
      ),
      licenceStatus: LicenceVerificationStatus.values.byName(
        data['licenceStatus'] ?? LicenceVerificationStatus.pending.name,
      ),
      suspensionReason: data['suspensionReason'] ?? '',
      performanceRating: (data['performanceRating'] as num? ?? 0).toDouble(),
      complianceScore: (data['complianceScore'] as num? ?? 0).toDouble(),
      completedServiceCount: data['completedServiceCount'] as int? ?? 0,
      onTimeServiceCount: data['onTimeServiceCount'] as int? ?? 0,
      totalSpend: (data['totalSpend'] as num? ?? 0).toDouble(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
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
    final data = doc.data()!;
    return PartnerDocument(
      id: doc.id,
      documentType: data['documentType'] ?? '',
      referenceNumber: data['referenceNumber'] ?? '',
      url: data['url'] ?? '',
      verified: data['verified'] as bool? ?? false,
      issuedAt: (data['issuedAt'] as Timestamp?)?.toDate(),
      expiresAt: (data['expiresAt'] as Timestamp?)?.toDate(),
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
    final data = doc.data()!;
    return PartnerContract(
      id: doc.id,
      contractNumber: data['contractNumber'] ?? '',
      title: data['title'] ?? '',
      status: ContractStatus.values.byName(
        data['status'] ?? ContractStatus.draft.name,
      ),
      startAt: (data['startAt'] as Timestamp?)?.toDate(),
      endAt: (data['endAt'] as Timestamp?)?.toDate(),
      contractValue: (data['contractValue'] as num? ?? 0).toDouble(),
      currency: data['currency'] ?? 'SLE',
      slaTargetHours: (data['slaTargetHours'] as num? ?? 0).toDouble(),
      minimumQualityRating: (data['minimumQualityRating'] as num? ?? 0)
          .toDouble(),
      terms: data['terms'] ?? '',
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
    final data = doc.data()!;
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
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
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
    final data = doc.data()!;
    return PartnerComplianceRecord(
      type: data['type'] ?? '',
      score: (data['score'] as num? ?? 0).toDouble(),
      outcome: data['outcome'] ?? '',
      findings: data['findings'] ?? '',
      reviewedAt: (data['reviewedAt'] as Timestamp?)?.toDate(),
      nextReviewAt: (data['nextReviewAt'] as Timestamp?)?.toDate(),
    );
  }
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
