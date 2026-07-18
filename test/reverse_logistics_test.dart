import 'package:flutter_test/flutter_test.dart';
import 'package:wastemanagementsystem/features/reverse_logistics/domain/reverse_logistics_transfer.dart';

void main() {
  ReverseLogisticsTransfer transfer({
    ReverseTransferStatus status = ReverseTransferStatus.approved,
    String vehicleId = 'vehicle-1',
    String driverId = 'driver-1',
    String documentNumber = 'MAN-001',
    int exceptions = 0,
    DateTime? dispatchedAt,
    DateTime? receivedAt,
  }) => ReverseLogisticsTransfer(
    id: 'transfer-1',
    transferNumber: 'RLT-001',
    type: ReverseTransferType.centreToRecycler,
    status: status,
    originId: 'centre-1',
    originName: 'Central Collection Centre',
    destinationId: 'recycler-1',
    destinationName: 'Green Recycling Facility',
    assetReferences: const ['EW-001', 'EW-002'],
    itemCount: 2,
    weightKg: 40,
    vehicleId: vehicleId,
    vehicleRegistration: 'ABC-123',
    driverId: driverId,
    driverName: 'Driver One',
    transportDocumentNumber: documentNumber,
    transportDocumentUrls: const [],
    approvalNotes: '',
    deliveryProofUrl: '',
    receivedBy: '',
    receiptNotes: '',
    openExceptionCount: exceptions,
    createdBy: 'operator-1',
    approvedBy: 'supervisor-1',
    createdAt: null,
    approvedAt: null,
    dispatchedAt: dispatchedAt,
    deliveredAt: null,
    receivedAt: receivedAt,
  );

  test('all required reverse movement types are represented', () {
    expect(ReverseTransferType.values.map((type) => type.label), [
      'Pickup to centre',
      'Centre to repair',
      'Centre to recycler',
      'Inter-facility transfer',
    ]);
  });

  test('dispatch requires approval, assignments, documents, and no holds', () {
    expect(transfer().canDispatch, isTrue);
    expect(transfer(vehicleId: '').canDispatch, isFalse);
    expect(transfer(driverId: '').canDispatch, isFalse);
    expect(transfer(documentNumber: '').canDispatch, isFalse);
    expect(transfer(exceptions: 1).canDispatch, isFalse);
    expect(
      transfer(status: ReverseTransferStatus.pendingApproval).canDispatch,
      isFalse,
    );
  });

  test('received transfers expose completed transit duration', () {
    final dispatched = DateTime(2026, 7, 17, 8);
    final received = DateTime(2026, 7, 17, 13, 30);
    final completed = transfer(
      status: ReverseTransferStatus.received,
      dispatchedAt: dispatched,
      receivedAt: received,
    );
    expect(completed.isComplete, isTrue);
    expect(completed.transitDuration, const Duration(hours: 5, minutes: 30));
  });

  test('exception classifications cover operational failures', () {
    expect(TransferExceptionType.values, contains(TransferExceptionType.delay));
    expect(
      TransferExceptionType.values,
      contains(TransferExceptionType.damage),
    );
    expect(
      TransferExceptionType.values,
      contains(TransferExceptionType.quantityMismatch),
    );
    expect(
      TransferExceptionType.values,
      contains(TransferExceptionType.vehicleBreakdown),
    );
    expect(
      TransferExceptionType.values,
      contains(TransferExceptionType.refusedDelivery),
    );
  });
}
