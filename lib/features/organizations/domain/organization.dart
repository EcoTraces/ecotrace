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

  factory Organization.fromJson(Map<String, dynamic> data) => Organization(
    id: data['id']?.toString() ?? '',
    name: data['name']?.toString() ?? '',
    type: OrganizationType.fromValue(data['type']?.toString()),
    registrationNumber: data['registrationNumber']?.toString() ?? '',
    contactEmail: data['contactEmail']?.toString() ?? '',
    contactPhone: data['contactPhone']?.toString() ?? '',
    address: data['address']?.toString() ?? '',
    serviceAreas: List<String>.from(data['serviceAreas'] as List? ?? const []),
    status: OrganizationStatus.fromValue(data['status']?.toString()),
    ownerId: data['ownerId']?.toString() ?? '',
    rejectionReason: data['rejectionReason']?.toString(),
  );
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
  factory OrganizationBranch.fromJson(Map<String, dynamic> data) =>
      OrganizationBranch(
        id: data['id']?.toString() ?? '',
        name: data['name']?.toString() ?? '',
        address: data['address']?.toString() ?? '',
      );
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
  factory OrganizationDocument.fromJson(Map<String, dynamic> data) =>
      OrganizationDocument(
        id: data['id']?.toString() ?? '',
        name: data['name']?.toString() ?? '',
        downloadUrl:
            data['fileUrl']?.toString() ??
            data['downloadUrl']?.toString() ??
            '',
      );
}

class OrganizationMember {
  const OrganizationMember({
    required this.userId,
    required this.role,
    required this.status,
    required this.branchId,
  });
  final String userId, role, status, branchId;
  factory OrganizationMember.fromJson(Map<String, dynamic> data) =>
      OrganizationMember(
        userId: data['userId']?.toString() ?? data['id']?.toString() ?? '',
        role: data['organizationRole']?.toString() ?? 'staff',
        status: data['status']?.toString() ?? 'active',
        branchId: data['branchId']?.toString() ?? '',
      );
}

class OrganizationInvitation {
  const OrganizationInvitation({
    required this.id,
    required this.organizationName,
    required this.role,
    required this.status,
  });
  final String id, organizationName, role, status;
  factory OrganizationInvitation.fromJson(Map<String, dynamic> data) =>
      OrganizationInvitation(
        id: data['id']?.toString() ?? '',
        organizationName: data['organizationName']?.toString() ?? '',
        role: data['organizationRole']?.toString() ?? 'staff',
        status: data['status']?.toString() ?? 'pending',
      );
}
