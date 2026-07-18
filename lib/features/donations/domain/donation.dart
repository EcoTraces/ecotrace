import 'package:cloud_firestore/cloud_firestore.dart';

enum BeneficiaryType { school, community, nonprofit, publicInstitution, other }

enum EligibilityStatus { pending, eligible, ineligible, needsInformation }

enum DonationStatus {
  requested,
  assessed,
  approved,
  allocated,
  scheduled,
  delivered,
  confirmed,
  followUp,
  completed,
  rejected,
  cancelled,
}

class Beneficiary {
  const Beneficiary({
    required this.id,
    required this.name,
    required this.type,
    required this.contactName,
    required this.contact,
    required this.address,
    required this.peopleServed,
    required this.eligibilityStatus,
    required this.eligibilityScore,
    required this.assessmentNotes,
  });
  final String id, name, contactName, contact, address, assessmentNotes;
  final BeneficiaryType type;
  final int peopleServed;
  final EligibilityStatus eligibilityStatus;
  final double eligibilityScore;
  factory Beneficiary.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final x = d.data()!;
    return Beneficiary(
      id: d.id,
      name: x['name'] ?? '',
      type: BeneficiaryType.values.byName(x['type'] ?? 'other'),
      contactName: x['contactName'] ?? '',
      contact: x['contact'] ?? '',
      address: x['address'] ?? '',
      peopleServed: x['peopleServed'] ?? 0,
      eligibilityStatus: EligibilityStatus.values.byName(
        x['eligibilityStatus'] ?? 'pending',
      ),
      eligibilityScore: (x['eligibilityScore'] as num? ?? 0).toDouble(),
      assessmentNotes: x['assessmentNotes'] ?? '',
    );
  }
}

class DonationRequest {
  const DonationRequest({
    required this.id,
    required this.requestNumber,
    required this.requesterId,
    required this.beneficiaryId,
    required this.beneficiaryName,
    required this.deviceTypes,
    required this.quantity,
    required this.purpose,
    required this.status,
    required this.allocatedJobIds,
    required this.deliveryAt,
    required this.proofUrl,
    required this.confirmedBy,
    required this.createdAt,
  });
  final String id,
      requestNumber,
      requesterId,
      beneficiaryId,
      beneficiaryName,
      purpose,
      proofUrl,
      confirmedBy;
  final List<String> deviceTypes, allocatedJobIds;
  final int quantity;
  final DonationStatus status;
  final DateTime? deliveryAt, createdAt;
  factory DonationRequest.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final x = d.data()!;
    return DonationRequest(
      id: d.id,
      requestNumber: x['requestNumber'] ?? d.id,
      requesterId: x['requesterId'] ?? '',
      beneficiaryId: x['beneficiaryId'] ?? '',
      beneficiaryName: x['beneficiaryName'] ?? '',
      deviceTypes: List<String>.from(x['deviceTypes'] ?? []),
      quantity: x['quantity'] ?? 0,
      purpose: x['purpose'] ?? '',
      status: DonationStatus.values.byName(x['status'] ?? 'requested'),
      allocatedJobIds: List<String>.from(x['allocatedJobIds'] ?? []),
      deliveryAt: (x['deliveryAt'] as Timestamp?)?.toDate(),
      proofUrl: x['proofUrl'] ?? '',
      confirmedBy: x['confirmedBy'] ?? '',
      createdAt: (x['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class SocialImpactRecord {
  const SocialImpactRecord({
    required this.devicesDelivered,
    required this.peopleReached,
    required this.activeDevices,
    required this.usageNotes,
    required this.recordedAt,
  });
  final int devicesDelivered, peopleReached, activeDevices;
  final String usageNotes;
  final DateTime? recordedAt;
  factory SocialImpactRecord.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final x = d.data()!;
    return SocialImpactRecord(
      devicesDelivered: x['devicesDelivered'] ?? 0,
      peopleReached: x['peopleReached'] ?? 0,
      activeDevices: x['activeDevices'] ?? 0,
      usageNotes: x['usageNotes'] ?? '',
      recordedAt: (x['recordedAt'] as Timestamp?)?.toDate(),
    );
  }
}

class DonationImpact {
  const DonationImpact(
    this.requests,
    this.delivered,
    this.devices,
    this.peopleReached,
  );
  final int requests, delivered, devices, peopleReached;
  double get completionRate => requests == 0 ? 0 : delivered / requests * 100;
}
