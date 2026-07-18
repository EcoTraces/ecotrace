import 'package:flutter_test/flutter_test.dart';
import 'package:wastemanagementsystem/features/partners/domain/partner.dart';

void main() {
  Partner partner({
    required String id,
    PartnerStatus status = PartnerStatus.active,
    LicenceVerificationStatus licenceStatus =
        LicenceVerificationStatus.verified,
    double rating = 4,
    double compliance = 90,
    int services = 10,
    int onTime = 8,
    double capacity = 1000,
    double spend = 500,
  }) => Partner(
    id: id,
    partnerCode: 'PTN-$id',
    name: 'Partner $id',
    type: PartnerType.recycler,
    contactName: 'Contact',
    contactEmail: 'contact@example.com',
    contactPhone: '123',
    address: 'Facility',
    serviceCategories: const [PartnerServiceCategory.electronicsRecycling],
    serviceAreas: const ['North'],
    pricingInformation: 'Per kilogram',
    currency: 'USD',
    facilityCapacityKg: capacity,
    paymentMethod: 'Transfer',
    payeeName: 'Partner',
    paymentTerms: 'Net 30',
    status: status,
    licenceStatus: licenceStatus,
    suspensionReason: '',
    performanceRating: rating,
    complianceScore: compliance,
    completedServiceCount: services,
    onTimeServiceCount: onTime,
    totalSpend: spend,
    createdAt: null,
  );

  test('partner types cover the required external providers', () {
    expect(PartnerType.values, contains(PartnerType.recycler));
    expect(PartnerType.values, contains(PartnerType.repairCentre));
    expect(PartnerType.values, contains(PartnerType.materialBuyer));
    expect(PartnerType.values, contains(PartnerType.transporter));
    expect(PartnerType.values, contains(PartnerType.disposalFacility));
  });

  test('partner can receive work only after activation and verification', () {
    expect(partner(id: 'active').canReceiveWork, isTrue);
    expect(
      partner(
        id: 'pending',
        status: PartnerStatus.pendingVerification,
      ).canReceiveWork,
      isFalse,
    );
    expect(
      partner(
        id: 'unverified',
        licenceStatus: LicenceVerificationStatus.pending,
      ).canReceiveWork,
      isFalse,
    );
  });

  test('SLA compliance and partner analytics use completed services', () {
    final first = partner(id: 'one');
    final second = partner(
      id: 'two',
      rating: 5,
      compliance: 100,
      services: 10,
      onTime: 10,
      capacity: 500,
      spend: 250,
    );
    final analytics = PartnerAnalytics.fromPartners([first, second]);
    expect(first.slaCompliancePercent, 80);
    expect(analytics.slaCompliancePercent, 90);
    expect(analytics.averageRating, 4.5);
    expect(analytics.averageCompliance, 95);
    expect(analytics.totalCapacityKg, 1500);
    expect(analytics.totalSpend, 750);
  });

  test('service records evaluate SLA targets', () {
    const onTime = PartnerServiceRecord(
      reference: 'JOB-1',
      serviceCategory: PartnerServiceCategory.transport,
      targetHours: 48,
      actualHours: 36,
      qualityRating: 5,
      serviceCost: 100,
      notes: '',
      completedAt: null,
    );
    const late = PartnerServiceRecord(
      reference: 'JOB-2',
      serviceCategory: PartnerServiceCategory.transport,
      targetHours: 48,
      actualHours: 60,
      qualityRating: 3,
      serviceCost: 100,
      notes: '',
      completedAt: null,
    );
    expect(onTime.metSla, isTrue);
    expect(late.metSla, isFalse);
  });
}
