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
    return Beneficiary.fromJson({...d.data()!, 'id': d.id});
  }
  factory Beneficiary.fromJson(Map<String, dynamic> x) {
    final typeName =
        x['type'] == 'governmentInstitution' || x['type'] == 'healthFacility'
        ? 'publicInstitution'
        : x['type'];
    return Beneficiary(
      id: '${x['id'] ?? ''}',
      name: x['name'] ?? '',
      type:
          BeneficiaryType.values
              .where((value) => value.name == typeName)
              .firstOrNull ??
          BeneficiaryType.other,
      contactName: x['contactName'] ?? '',
      contact: x['contact'] ?? x['contactPhone'] ?? x['contactEmail'] ?? '',
      address: x['address'] ?? '',
      peopleServed:
          (x['peopleServed'] as num? ?? x['beneficiariesServed'] as num? ?? 0)
              .toInt(),
      eligibilityStatus: EligibilityStatus.values.byName(
        x['eligibilityStatus'] ?? 'pending',
      ),
      eligibilityScore: (x['eligibilityScore'] as num? ?? 0).toDouble(),
      assessmentNotes: x['assessmentNotes'] ?? x['eligibilityNotes'] ?? '',
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
    return DonationRequest.fromJson({...d.data()!, 'id': d.id});
  }
  factory DonationRequest.fromJson(Map<String, dynamic> x) {
    final rawStatus = '${x['status'] ?? ''}';
    final status = switch (rawStatus) {
      'submitted' => DonationStatus.requested,
      'deliveryScheduled' => DonationStatus.scheduled,
      _ =>
        DonationStatus.values
                .where((value) => value.name == rawStatus)
                .firstOrNull ??
            DonationStatus.requested,
    };
    return DonationRequest(
      id: '${x['id'] ?? ''}',
      requestNumber:
          x['requestNumber'] ?? x['requestCode'] ?? '${x['id'] ?? ''}',
      requesterId: x['requesterId'] ?? x['requestedBy'] ?? '',
      beneficiaryId: x['beneficiaryId'] ?? '',
      beneficiaryName: x['beneficiaryName'] ?? '',
      deviceTypes: x['deviceTypes'] is List
          ? List<String>.from(x['deviceTypes'])
          : <String>['${x['deviceCategory'] ?? ''}'],
      quantity: (x['quantity'] as num? ?? 0).toInt(),
      purpose: x['purpose'] ?? '',
      status: status,
      allocatedJobIds: List<String>.from(
        x['allocatedJobIds'] ?? x['allocatedDeviceIds'] ?? [],
      ),
      deliveryAt: _date(
        x['deliveryAt'] ?? x['scheduledAt'] ?? x['deliveredAt'],
      ),
      proofUrl:
          x['proofUrl'] ??
          ((x['proofOfDeliveryUrls'] as List?)?.firstOrNull ?? ''),
      confirmedBy: x['confirmedBy'] ?? '',
      createdAt: _date(x['createdAt']),
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
    return SocialImpactRecord.fromJson(d.data()!);
  }
  factory SocialImpactRecord.fromJson(Map<String, dynamic> x) {
    return SocialImpactRecord(
      devicesDelivered:
          (x['devicesDelivered'] as num? ?? x['devicesInUse'] as num? ?? 0)
              .toInt(),
      peopleReached: (x['peopleReached'] as num? ?? 0).toInt(),
      activeDevices:
          (x['activeDevices'] as num? ?? x['devicesFunctional'] as num? ?? 0)
              .toInt(),
      usageNotes: x['usageNotes'] ?? x['usageSummary'] ?? '',
      recordedAt: _date(x['recordedAt'] ?? x['createdAt']),
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
