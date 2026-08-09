import 'package:cloud_firestore/cloud_firestore.dart';

enum ReverseTransferType {
  pickupToCentre,
  centreToRepair,
  centreToRecycler,
  interFacility,
}

extension ReverseTransferTypeLabel on ReverseTransferType {
  String get label => switch (this) {
    ReverseTransferType.pickupToCentre => 'Pickup to centre',
    ReverseTransferType.centreToRepair => 'Centre to repair',
    ReverseTransferType.centreToRecycler => 'Centre to recycler',
    ReverseTransferType.interFacility => 'Inter-facility transfer',
  };
}

enum ReverseTransferStatus {
  draft,
  pendingApproval,
  approved,
  rejected,
  dispatched,
  inTransit,
  delivered,
  received,
  exceptionHold,
  cancelled,
}

extension ReverseTransferStatusLabel on ReverseTransferStatus {
  String get label => switch (this) {
    ReverseTransferStatus.draft => 'Draft',
    ReverseTransferStatus.pendingApproval => 'Pending approval',
    ReverseTransferStatus.approved => 'Approved',
    ReverseTransferStatus.rejected => 'Rejected',
    ReverseTransferStatus.dispatched => 'Dispatched',
    ReverseTransferStatus.inTransit => 'In transit',
    ReverseTransferStatus.delivered => 'Delivery confirmed',
    ReverseTransferStatus.received => 'Received',
    ReverseTransferStatus.exceptionHold => 'Exception hold',
    ReverseTransferStatus.cancelled => 'Cancelled',
  };
}

enum TransferExceptionType {
  delay,
  damage,
  quantityMismatch,
  weightMismatch,
  documentation,
  routeDeviation,
  vehicleBreakdown,
  refusedDelivery,
  other,
}

class ReverseLogisticsTransfer {
  const ReverseLogisticsTransfer({
    required this.id,
    required this.transferNumber,
    required this.type,
    required this.status,
    required this.originId,
    required this.originName,
    required this.destinationId,
    required this.destinationName,
    required this.assetReferences,
    required this.itemCount,
    required this.weightKg,
    required this.vehicleId,
    required this.vehicleRegistration,
    required this.driverId,
    required this.driverName,
    required this.transportDocumentNumber,
    required this.transportDocumentUrls,
    required this.approvalNotes,
    required this.deliveryProofUrl,
    required this.receivedBy,
    required this.receiptNotes,
    required this.openExceptionCount,
    required this.createdBy,
    required this.approvedBy,
    required this.createdAt,
    required this.approvedAt,
    required this.dispatchedAt,
    required this.deliveredAt,
    required this.receivedAt,
  });

  final String id,
      transferNumber,
      originId,
      originName,
      destinationId,
      destinationName,
      vehicleId,
      vehicleRegistration,
      driverId,
      driverName,
      transportDocumentNumber,
      approvalNotes,
      deliveryProofUrl,
      receivedBy,
      receiptNotes,
      createdBy,
      approvedBy;
  final ReverseTransferType type;
  final ReverseTransferStatus status;
  final List<String> assetReferences, transportDocumentUrls;
  final int itemCount, openExceptionCount;
  final double weightKg;
  final DateTime? createdAt, approvedAt, dispatchedAt, deliveredAt, receivedAt;

  bool get transportAssigned => vehicleId.isNotEmpty && driverId.isNotEmpty;
  bool get hasTransportDocument => transportDocumentNumber.isNotEmpty;
  bool get canDispatch =>
      status == ReverseTransferStatus.approved &&
      transportAssigned &&
      hasTransportDocument &&
      openExceptionCount == 0;
  bool get isComplete => status == ReverseTransferStatus.received;
  Duration? get transitDuration => dispatchedAt == null
      ? null
      : (receivedAt ?? DateTime.now()).difference(dispatchedAt!);

  factory ReverseLogisticsTransfer.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return ReverseLogisticsTransfer(
      id: doc.id,
      transferNumber: data['transferNumber'] ?? doc.id,
      type: ReverseTransferType.values.byName(
        data['type'] ?? ReverseTransferType.interFacility.name,
      ),
      status: ReverseTransferStatus.values.byName(
        data['status'] ?? ReverseTransferStatus.draft.name,
      ),
      originId: data['originId'] ?? '',
      originName: data['originName'] ?? '',
      destinationId: data['destinationId'] ?? '',
      destinationName: data['destinationName'] ?? '',
      assetReferences: List<String>.from(
        data['assetReferences'] as List? ?? const [],
      ),
      itemCount: data['itemCount'] as int? ?? 0,
      weightKg: (data['weightKg'] as num? ?? 0).toDouble(),
      vehicleId: data['vehicleId'] ?? '',
      vehicleRegistration: data['vehicleRegistration'] ?? '',
      driverId: data['driverId'] ?? '',
      driverName: data['driverName'] ?? '',
      transportDocumentNumber: data['transportDocumentNumber'] ?? '',
      transportDocumentUrls: List<String>.from(
        data['transportDocumentUrls'] as List? ?? const [],
      ),
      approvalNotes: data['approvalNotes'] ?? '',
      deliveryProofUrl: data['deliveryProofUrl'] ?? '',
      receivedBy: data['receivedBy'] ?? '',
      receiptNotes: data['receiptNotes'] ?? '',
      openExceptionCount: data['openExceptionCount'] as int? ?? 0,
      createdBy: data['createdBy'] ?? '',
      approvedBy: data['approvedBy'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      approvedAt: (data['approvedAt'] as Timestamp?)?.toDate(),
      dispatchedAt: (data['dispatchedAt'] as Timestamp?)?.toDate(),
      deliveredAt: (data['deliveredAt'] as Timestamp?)?.toDate(),
      receivedAt: (data['receivedAt'] as Timestamp?)?.toDate(),
    );
  }

  factory ReverseLogisticsTransfer.fromJson(Map<String, dynamic> data) {
    final source = Map<String, dynamic>.from(
      data['source'] as Map? ?? const {},
    );
    final destination = Map<String, dynamic>.from(
      data['destination'] as Map? ?? const {},
    );
    return ReverseLogisticsTransfer(
      id: data['id']?.toString() ?? '',
      transferNumber:
          data['transferNumber']?.toString() ??
          data['transferCode']?.toString() ??
          data['id']?.toString() ??
          '',
      type: ReverseTransferType.values.byName(
        data['type']?.toString() ?? ReverseTransferType.interFacility.name,
      ),
      status: _statusFromApi(data['status']?.toString()),
      originId:
          data['originId']?.toString() ??
          source['facilityId']?.toString() ??
          '',
      originName:
          data['originName']?.toString() ?? source['name']?.toString() ?? '',
      destinationId:
          data['destinationId']?.toString() ??
          destination['facilityId']?.toString() ??
          '',
      destinationName:
          data['destinationName']?.toString() ??
          destination['name']?.toString() ??
          '',
      assetReferences: List<String>.from(
        data['assetReferences'] as List? ??
            data['itemIds'] as List? ??
            const [],
      ),
      itemCount:
          (data['itemCount'] as num? ?? (data['itemIds'] as List?)?.length ?? 0)
              .toInt(),
      weightKg: (data['weightKg'] as num? ?? data['totalWeightKg'] as num? ?? 0)
          .toDouble(),
      vehicleId: data['vehicleId']?.toString() ?? '',
      vehicleRegistration: data['vehicleRegistration']?.toString() ?? '',
      driverId: data['driverId']?.toString() ?? '',
      driverName: data['driverName']?.toString() ?? '',
      transportDocumentNumber:
          data['transportDocumentNumber']?.toString() ?? '',
      transportDocumentUrls: List<String>.from(
        data['transportDocumentUrls'] as List? ??
            data['documentUrls'] as List? ??
            const [],
      ),
      approvalNotes:
          data['approvalNotes']?.toString() ??
          data['reviewReason']?.toString() ??
          '',
      deliveryProofUrl:
          data['deliveryProofUrl']?.toString() ??
          ((data['deliveryProofUrls'] as List?)?.firstOrNull?.toString() ?? ''),
      receivedBy:
          data['receiverName']?.toString() ??
          data['receivedBy']?.toString() ??
          '',
      receiptNotes:
          data['notes']?.toString() ?? data['receiptNotes']?.toString() ?? '',
      openExceptionCount:
          (data['openExceptionCount'] as num? ??
                  data['exceptionCount'] as num? ??
                  0)
              .toInt(),
      createdBy: data['createdBy']?.toString() ?? '',
      approvedBy:
          data['approvedBy']?.toString() ??
          data['reviewedBy']?.toString() ??
          '',
      createdAt: DateTime.tryParse(data['createdAt']?.toString() ?? ''),
      approvedAt: DateTime.tryParse(
        data['approvedAt']?.toString() ?? data['reviewedAt']?.toString() ?? '',
      ),
      dispatchedAt: DateTime.tryParse(data['dispatchedAt']?.toString() ?? ''),
      deliveredAt: DateTime.tryParse(data['deliveredAt']?.toString() ?? ''),
      receivedAt: DateTime.tryParse(data['receivedAt']?.toString() ?? ''),
    );
  }
}

ReverseTransferStatus _statusFromApi(String? status) => switch (status) {
  'requested' => ReverseTransferStatus.pendingApproval,
  'exception' => ReverseTransferStatus.exceptionHold,
  'pendingApproval' => ReverseTransferStatus.pendingApproval,
  'approved' => ReverseTransferStatus.approved,
  'rejected' => ReverseTransferStatus.rejected,
  'dispatched' => ReverseTransferStatus.dispatched,
  'inTransit' => ReverseTransferStatus.inTransit,
  'delivered' => ReverseTransferStatus.delivered,
  'received' => ReverseTransferStatus.received,
  'cancelled' => ReverseTransferStatus.cancelled,
  _ => ReverseTransferStatus.draft,
};

class CustodyEvent {
  const CustodyEvent({
    required this.action,
    required this.custodianId,
    required this.custodianName,
    required this.location,
    required this.notes,
    required this.at,
  });
  final String action, custodianId, custodianName, location, notes;
  final DateTime? at;
  factory CustodyEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return CustodyEvent(
      action: data['action'] ?? '',
      custodianId: data['custodianId'] ?? '',
      custodianName: data['custodianName'] ?? '',
      location: data['location'] ?? '',
      notes: data['notes'] ?? '',
      at: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  factory CustodyEvent.fromJson(Map<String, dynamic> data) => CustodyEvent(
    action: data['action']?.toString() ?? data['type']?.toString() ?? '',
    custodianId: data['custodianId']?.toString() ?? '',
    custodianName: data['custodianName']?.toString() ?? '',
    location: data['location']?.toString() ?? '',
    notes: data['notes']?.toString() ?? '',
    at: DateTime.tryParse(data['createdAt']?.toString() ?? ''),
  );
}

class TransferException {
  const TransferException({
    required this.id,
    required this.type,
    required this.description,
    required this.reportedBy,
    required this.resolution,
    required this.resolved,
    required this.reportedAt,
    required this.resolvedAt,
  });
  final String id, description, reportedBy, resolution;
  final TransferExceptionType type;
  final bool resolved;
  final DateTime? reportedAt, resolvedAt;
  factory TransferException.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return TransferException(
      id: doc.id,
      type: TransferExceptionType.values.byName(
        data['type'] ?? TransferExceptionType.other.name,
      ),
      description: data['description'] ?? '',
      reportedBy: data['reportedBy'] ?? '',
      resolution: data['resolution'] ?? '',
      resolved: data['resolved'] as bool? ?? false,
      reportedAt: (data['reportedAt'] as Timestamp?)?.toDate(),
      resolvedAt: (data['resolvedAt'] as Timestamp?)?.toDate(),
    );
  }

  factory TransferException.fromJson(Map<String, dynamic> data) =>
      TransferException(
        id: data['id']?.toString() ?? '',
        type: _exceptionTypeFromApi(data['type']?.toString()),
        description: data['description']?.toString() ?? '',
        reportedBy: data['reportedBy']?.toString() ?? '',
        resolution: data['resolution']?.toString() ?? '',
        resolved:
            data['resolved'] as bool? ??
            data['status']?.toString() == 'resolved',
        reportedAt: DateTime.tryParse(
          data['reportedAt']?.toString() ?? data['createdAt']?.toString() ?? '',
        ),
        resolvedAt: DateTime.tryParse(data['resolvedAt']?.toString() ?? ''),
      );
}

TransferExceptionType _exceptionTypeFromApi(String? type) => switch (type) {
  'damagedLoad' => TransferExceptionType.damage,
  'missingItem' => TransferExceptionType.quantityMismatch,
  'breakdown' => TransferExceptionType.vehicleBreakdown,
  'routeDeviation' => TransferExceptionType.routeDeviation,
  'delay' => TransferExceptionType.delay,
  _ => TransferExceptionType.other,
};
