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
}

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
}
