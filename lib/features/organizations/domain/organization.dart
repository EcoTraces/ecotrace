import 'package:cloud_firestore/cloud_firestore.dart';

enum OrganizationType {
  business('business', 'Business'),
  institution('institution', 'School or institution'),
  recycler('recycler', 'Recycler'),
  collectionCompany('collectionCompany', 'Collection company'),
  repairProvider('repairProvider', 'Repair service provider');

  const OrganizationType(this.value, this.label);
  final String value;
  final String label;

  static OrganizationType fromValue(String? value) =>
      values.firstWhere((type) => type.value == value, orElse: () => business);
}

enum OrganizationStatus {
  draft,
  pendingVerification,
  approved,
  rejected,
  suspended;

  static OrganizationStatus fromValue(String? value) =>
      values.firstWhere((status) => status.name == value, orElse: () => draft);
}

class Organization {
  const Organization({
    required this.id,
    required this.name,
    required this.type,
    required this.registrationNumber,
    required this.contactEmail,
    required this.contactPhone,
    required this.address,
    required this.serviceAreas,
    required this.status,
    required this.ownerId,
    required this.rejectionReason,
  });

  final String id;
  final String name;
  final OrganizationType type;
  final String registrationNumber;
  final String contactEmail;
  final String contactPhone;
  final String address;
  final List<String> serviceAreas;
  final OrganizationStatus status;
  final String ownerId;
  final String? rejectionReason;

  factory Organization.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return Organization(
      id: snapshot.id,
      name: data['name'] as String? ?? '',
      type: OrganizationType.fromValue(data['type'] as String?),
      registrationNumber: data['registrationNumber'] as String? ?? '',
      contactEmail: data['contactEmail'] as String? ?? '',
      contactPhone: data['contactPhone'] as String? ?? '',
      address: data['address'] as String? ?? '',
      serviceAreas: List<String>.from(
        data['serviceAreas'] as List? ?? const [],
      ),
      status: OrganizationStatus.fromValue(data['status'] as String?),
      ownerId: data['ownerId'] as String? ?? '',
      rejectionReason: data['rejectionReason'] as String?,
    );
  }
}

class OrganizationBranch {
  const OrganizationBranch({
    required this.id,
    required this.name,
    required this.address,
  });
  final String id;
  final String name;
  final String address;
}

class OrganizationDocument {
  const OrganizationDocument({
    required this.id,
    required this.name,
    required this.downloadUrl,
  });
  final String id;
  final String name;
  final String downloadUrl;
}
