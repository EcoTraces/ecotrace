import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';
import '../../../core/media/cloudinary_upload_service.dart';

import '../../auth/domain/user_profile.dart';
import '../../centres/domain/collection_centre.dart';
import '../../fleet/domain/vehicle.dart';
import '../domain/reverse_logistics_transfer.dart';

class ReverseLogisticsRepository {
  ReverseLogisticsRepository({
    FirebaseFirestore? firestore,
    ApiClient? apiClient,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _api = apiClient ?? ApiClient.instance,
       _useApi = apiClient != null || (firestore == null && ApiConfig.enabled);

  final FirebaseFirestore _db;
  final ApiClient _api;
  final bool _useApi;
  CollectionReference<Map<String, dynamic>> get _transfers =>
      _db.collection('logisticsTransfers');

  Stream<List<ReverseLogisticsTransfer>> watchTransfers() => _useApi
      ? _pollTransfers()
      : _transfers.snapshots().map(
          (snapshot) =>
              snapshot.docs.map(ReverseLogisticsTransfer.fromDoc).toList()
                ..sort(
                  (a, b) => (b.createdAt ?? DateTime(2000)).compareTo(
                    a.createdAt ?? DateTime(2000),
                  ),
                ),
        );
  Stream<List<ReverseLogisticsTransfer>> _pollTransfers() async* {
    while (true) {
      final data = await _api.getList('/api/v1/logistics/transfers');
      yield data.map(ReverseLogisticsTransfer.fromJson).toList()..sort(
        (a, b) => (b.createdAt ?? DateTime(2000)).compareTo(
          a.createdAt ?? DateTime(2000),
        ),
      );
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<ReverseLogisticsTransfer> watchTransfer(String id) => _useApi
      ? _pollTransfer(id)
      : _transfers.doc(id).snapshots().map(ReverseLogisticsTransfer.fromDoc);
  Stream<ReverseLogisticsTransfer> _pollTransfer(String id) async* {
    while (true) {
      yield ReverseLogisticsTransfer.fromJson(
        await _api.get('/api/v1/logistics/transfers/$id'),
      );
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<List<CustodyEvent>> watchCustody(String id) => _useApi
      ? _pollCustody(id)
      : _transfers
            .doc(id)
            .collection('custodyEvents')
            .snapshots()
            .map(
              (snapshot) => snapshot.docs.map(CustodyEvent.fromDoc).toList()
                ..sort(
                  (a, b) => (b.at ?? DateTime(2000)).compareTo(
                    a.at ?? DateTime(2000),
                  ),
                ),
            );
  Stream<List<CustodyEvent>> _pollCustody(String id) async* {
    while (true) {
      final data = await _api.getList(
        '/api/v1/logistics/transfers/$id/custody-events',
      );
      yield data.map(CustodyEvent.fromJson).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<List<TransferException>> watchExceptions(String id) => _useApi
      ? _pollExceptions(id)
      : _transfers
            .doc(id)
            .collection('exceptions')
            .snapshots()
            .map(
              (snapshot) =>
                  snapshot.docs.map(TransferException.fromDoc).toList()..sort(
                    (a, b) => (b.reportedAt ?? DateTime(2000)).compareTo(
                      a.reportedAt ?? DateTime(2000),
                    ),
                  ),
            );
  Stream<List<TransferException>> _pollExceptions(String id) async* {
    while (true) {
      final data = await _api.getList(
        '/api/v1/logistics/transfers/$id/exceptions',
      );
      yield data.map(TransferException.fromJson).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<List<Vehicle>> watchVehicles() => _useApi
      ? _pollVehicles()
      : _db
            .collection('vehicles')
            .snapshots()
            .map((snapshot) => snapshot.docs.map(Vehicle.fromDoc).toList());
  Stream<List<Vehicle>> _pollVehicles() async* {
    while (true) {
      final data = await _api.getList('/api/v1/vehicles');
      yield data.map(Vehicle.fromJson).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<List<UserProfile>> watchDrivers() => _useApi
      ? _pollDrivers()
      : _db
            .collection('users')
            .where('role', isEqualTo: 'driver')
            .snapshots()
            .map(
              (snapshot) =>
                  snapshot.docs.map(UserProfile.fromSnapshot).toList(),
            );
  Stream<List<UserProfile>> _pollDrivers() async* {
    while (true) {
      final data = await _api.getList('/api/v1/logistics/drivers');
      yield data.map(UserProfile.fromJson).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<List<CollectionCentre>> watchCentres() => _useApi
      ? _pollCentres()
      : _db
            .collection('collectionCentres')
            .where('active', isEqualTo: true)
            .snapshots()
            .map(
              (snapshot) =>
                  snapshot.docs.map(CollectionCentre.fromDoc).toList(),
            );
  Stream<List<CollectionCentre>> _pollCentres() async* {
    while (true) {
      final data = await _api.getList('/api/v1/logistics/centres');
      yield data.map(CollectionCentre.fromJson).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Future<void> create({
    required ReverseTransferType type,
    required String originId,
    required String originName,
    required String destinationId,
    required String destinationName,
    required List<String> assetReferences,
    required int itemCount,
    required double weightKg,
    required String actorId,
  }) async {
    if (originName.trim().isEmpty || destinationName.trim().isEmpty) {
      throw StateError('Origin and destination are required.');
    }
    if (originId == destinationId && originId.isNotEmpty) {
      throw StateError('Origin and destination must be different.');
    }
    if (assetReferences.isEmpty || itemCount <= 0 || weightKg <= 0) {
      throw StateError('Add references, item count, and a positive weight.');
    }
    if (_useApi) {
      await _api.post('/api/v1/logistics/transfers/drafts', {
        'type': type.name,
        'originId': originId.trim(),
        'originName': originName.trim(),
        'destinationId': destinationId.trim(),
        'destinationName': destinationName.trim(),
        'assetReferences': assetReferences,
        'itemCount': itemCount,
        'weightKg': weightKg,
      });
      return;
    }
    final ref = _transfers.doc();
    final number = 'RLT-${DateTime.now().millisecondsSinceEpoch}';
    final write = _db.batch();
    write.set(ref, {
      'transferNumber': number,
      'type': type.name,
      'status': ReverseTransferStatus.draft.name,
      'originId': originId.trim(),
      'originName': originName.trim(),
      'destinationId': destinationId.trim(),
      'destinationName': destinationName.trim(),
      'assetReferences': assetReferences,
      'itemCount': itemCount,
      'weightKg': weightKg,
      'vehicleId': '',
      'vehicleRegistration': '',
      'driverId': '',
      'driverName': '',
      'transportDocumentNumber': '',
      'transportDocumentUrls': [],
      'approvalNotes': '',
      'deliveryProofUrl': '',
      'receivedBy': '',
      'receiptNotes': '',
      'openExceptionCount': 0,
      'createdBy': actorId,
      'approvedBy': '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _custody(
      write,
      ref,
      action: 'Transfer created',
      custodianId: actorId,
      custodianName: actorId,
      location: originName,
      notes: '$itemCount items, $weightKg kg',
    );
    await write.commit();
  }

  Future<void> assignTransport(
    ReverseLogisticsTransfer transfer, {
    required Vehicle vehicle,
    required UserProfile driver,
    required String documentNumber,
    required String actorId,
  }) async {
    if (transfer.status != ReverseTransferStatus.draft &&
        transfer.status != ReverseTransferStatus.pendingApproval) {
      throw StateError('Transport can no longer be changed.');
    }
    if (transfer.weightKg > vehicle.capacityKg) {
      throw StateError('Transfer weight exceeds vehicle capacity.');
    }
    if (vehicle.availability != VehicleAvailability.available) {
      throw StateError('Select an available vehicle.');
    }
    if (_useApi) {
      await _api.patch('/api/v1/logistics/transfers/${transfer.id}/transport', {
        'vehicleId': vehicle.id,
        'driverId': driver.uid,
        'documentNumber': documentNumber.trim(),
        'documentUrls': transfer.transportDocumentUrls,
      });
      return;
    }
    final ref = _transfers.doc(transfer.id);
    final write = _db.batch();
    write.update(ref, {
      'vehicleId': vehicle.id,
      'vehicleRegistration': vehicle.registrationNumber,
      'driverId': driver.uid,
      'driverName': driver.displayName,
      'transportDocumentNumber': documentNumber.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _custody(
      write,
      ref,
      action: 'Transport assigned',
      custodianId: actorId,
      custodianName: actorId,
      location: transfer.originName,
      notes: '${vehicle.registrationNumber}; ${driver.displayName}',
    );
    await write.commit();
  }

  Future<String> uploadTransportDocument(
    ReverseLogisticsTransfer transfer,
    Uint8List bytes,
  ) async {
    final url = await CloudinaryUploadService.instance.uploadImage(
      bytes,
      scope: 'reverse-logistics',
      fileName: 'transport-document.jpg',
    );
    if (_useApi) {
      await _api.patch('/api/v1/logistics/transfers/${transfer.id}/documents', {
        'documentUrl': url,
      });
      return url;
    }
    await _transfers.doc(transfer.id).update({
      'transportDocumentUrls': FieldValue.arrayUnion([url]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return url;
  }

  Future<void> submitForApproval(
    ReverseLogisticsTransfer transfer,
    String actorId,
  ) async {
    if (!transfer.transportAssigned || !transfer.hasTransportDocument) {
      throw StateError('Assign a vehicle, driver, and document number first.');
    }
    if (_useApi) {
      await _api.patch('/api/v1/logistics/transfers/${transfer.id}/submit', {});
      return;
    }
    await _changeStatus(
      transfer,
      ReverseTransferStatus.pendingApproval,
      actorId,
      'Submitted for approval',
    );
  }

  Future<void> approve(
    ReverseLogisticsTransfer transfer, {
    required String actorId,
    required String notes,
  }) async {
    if (transfer.status != ReverseTransferStatus.pendingApproval) {
      throw StateError('Only pending transfers can be approved.');
    }
    if (_useApi) {
      await _api.patch('/api/v1/logistics/transfers/${transfer.id}/review', {
        'decision': 'approved',
        'reason': notes.trim(),
      });
      return;
    }
    final ref = _transfers.doc(transfer.id);
    final write = _db.batch();
    write.update(ref, {
      'status': ReverseTransferStatus.approved.name,
      'approvedBy': actorId,
      'approvalNotes': notes.trim(),
      'approvedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _custody(
      write,
      ref,
      action: 'Transfer approved',
      custodianId: actorId,
      custodianName: actorId,
      location: transfer.originName,
      notes: notes,
    );
    await write.commit();
  }

  Future<void> reject(
    ReverseLogisticsTransfer transfer, {
    required String actorId,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) throw StateError('Enter a rejection reason.');
    if (_useApi) {
      await _api.patch('/api/v1/logistics/transfers/${transfer.id}/review', {
        'decision': 'rejected',
        'reason': reason.trim(),
      });
      return;
    }
    await _changeStatus(
      transfer,
      ReverseTransferStatus.rejected,
      actorId,
      'Rejected: $reason',
      extra: {'approvalNotes': reason.trim()},
    );
  }

  Future<void> dispatch(
    ReverseLogisticsTransfer transfer,
    String actorId,
  ) async {
    if (!transfer.canDispatch) {
      throw StateError(
        'Approval, transport documents, and assignments are required.',
      );
    }
    if (_useApi) {
      final vehicle =
          (await _api.getList(
                '/api/v1/vehicles',
                query: {'driverId': transfer.driverId},
              ))
              .map(Vehicle.fromJson)
              .where((item) => item.id == transfer.vehicleId)
              .firstOrNull;
      await _api.patch('/api/v1/logistics/transfers/${transfer.id}/dispatch', {
        'odometerKm': vehicle?.mileageKm ?? 0,
        'sealNumber': '',
        'documentUrls': transfer.transportDocumentUrls,
      });
      return;
    }
    final ref = _transfers.doc(transfer.id);
    final write = _db.batch();
    write.update(ref, {
      'status': ReverseTransferStatus.dispatched.name,
      'dispatchedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    write.update(_db.collection('vehicles').doc(transfer.vehicleId), {
      'availability': VehicleAvailability.dispatched.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _custody(
      write,
      ref,
      action: 'Dispatched to driver',
      custodianId: transfer.driverId,
      custodianName: transfer.driverName,
      location: transfer.originName,
      notes: transfer.transportDocumentNumber,
    );
    await write.commit();
  }

  Future<void> startTransit(ReverseLogisticsTransfer transfer, String actorId) {
    if (_useApi) {
      return _api
          .patch('/api/v1/logistics/transfers/${transfer.id}/start', {})
          .then((_) {});
    }
    return _changeStatus(
      transfer,
      ReverseTransferStatus.inTransit,
      actorId,
      'Departed ${transfer.originName}',
    );
  }

  Future<void> confirmDelivery(
    ReverseLogisticsTransfer transfer, {
    required String actorId,
    required Uint8List proof,
    required String notes,
  }) async {
    if (transfer.status != ReverseTransferStatus.inTransit &&
        transfer.status != ReverseTransferStatus.dispatched) {
      throw StateError('The transfer is not in transit.');
    }
    if (proof.isEmpty) throw StateError('Delivery proof is required.');
    final url = await CloudinaryUploadService.instance.uploadImage(
      proof,
      scope: 'reverse-logistics',
      fileName: 'delivery-proof.jpg',
    );
    if (_useApi) {
      await _api.patch('/api/v1/logistics/transfers/${transfer.id}/deliver', {
        'deliveryProofUrl': url,
        'notes': notes.trim(),
      });
      return;
    }
    final ref = _transfers.doc(transfer.id);
    final write = _db.batch();
    write.update(ref, {
      'status': ReverseTransferStatus.delivered.name,
      'deliveryProofUrl': url,
      'deliveryNotes': notes.trim(),
      'deliveredAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _custody(
      write,
      ref,
      action: 'Delivery confirmed',
      custodianId: actorId,
      custodianName: transfer.driverName,
      location: transfer.destinationName,
      notes: notes,
    );
    await write.commit();
  }

  Future<void> confirmReceipt(
    ReverseLogisticsTransfer transfer, {
    required String actorId,
    required String receiverName,
    required String notes,
  }) async {
    if (transfer.status != ReverseTransferStatus.delivered) {
      throw StateError('Delivery must be confirmed before receipt.');
    }
    if (receiverName.trim().isEmpty) throw StateError('Receiver is required.');
    if (_useApi) {
      if (transfer.deliveryProofUrl.isEmpty) {
        throw StateError('Delivery proof is required before receipt.');
      }
      await _api.patch('/api/v1/logistics/transfers/${transfer.id}/receive', {
        'receivedWeightKg': transfer.weightKg,
        'receivedItemIds': transfer.assetReferences,
        'condition': 'intact',
        'deliveryProofUrls': [transfer.deliveryProofUrl],
        'receiverName': receiverName.trim(),
        'notes': notes.trim(),
      });
      return;
    }
    final ref = _transfers.doc(transfer.id);
    final vehicle = _db.collection('vehicles').doc(transfer.vehicleId);
    final write = _db.batch();
    write.update(ref, {
      'status': ReverseTransferStatus.received.name,
      'receivedBy': receiverName.trim(),
      'receiptNotes': notes.trim(),
      'receivedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    write.update(vehicle, {
      'availability': VehicleAvailability.available.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    write.set(vehicle.collection('trips').doc(), {
      'transferId': transfer.id,
      'transferNumber': transfer.transferNumber,
      'startedAt': transfer.dispatchedAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(transfer.dispatchedAt!),
      'completedAt': FieldValue.serverTimestamp(),
      'pickupCount': transfer.itemCount,
      'createdAt': FieldValue.serverTimestamp(),
    });
    _custody(
      write,
      ref,
      action: 'Receipt confirmed',
      custodianId: actorId,
      custodianName: receiverName,
      location: transfer.destinationName,
      notes: notes,
    );
    await write.commit();
  }

  Future<void> reportException(
    ReverseLogisticsTransfer transfer, {
    required TransferExceptionType type,
    required String description,
    required String actorId,
  }) async {
    if (description.trim().isEmpty) throw StateError('Describe the exception.');
    if (_useApi) {
      await _api.post('/api/v1/logistics/transfers/${transfer.id}/exceptions', {
        'type': _apiExceptionType(type),
        'severity': 'medium',
        'description': description.trim(),
        'location': transfer.destinationName.isEmpty
            ? transfer.originName
            : transfer.destinationName,
        'evidenceUrls': <String>[],
        'immediateAction': 'Transfer paused and reported for review',
      });
      return;
    }
    final ref = _transfers.doc(transfer.id);
    final write = _db.batch();
    write.update(ref, {
      'status': ReverseTransferStatus.exceptionHold.name,
      'resumeStatus': transfer.status.name,
      'openExceptionCount': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    write.set(ref.collection('exceptions').doc(), {
      'type': type.name,
      'description': description.trim(),
      'reportedBy': actorId,
      'resolved': false,
      'resolution': '',
      'reportedAt': FieldValue.serverTimestamp(),
    });
    _custody(
      write,
      ref,
      action: 'Transfer exception reported',
      custodianId: actorId,
      custodianName: actorId,
      location: transfer.destinationName,
      notes: '${type.name}: $description',
    );
    await write.commit();
  }

  Future<void> resolveException(
    ReverseLogisticsTransfer transfer,
    TransferException exception, {
    required String resolution,
    required String actorId,
  }) async {
    if (resolution.trim().isEmpty) throw StateError('Enter a resolution.');
    if (_useApi) {
      await _api.patch(
        '/api/v1/logistics/transfers/${transfer.id}/exceptions/${exception.id}/resolve',
        {'resolution': resolution.trim()},
      );
      return;
    }
    final ref = _transfers.doc(transfer.id);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data()!;
      final openCount = (data['openExceptionCount'] as int? ?? 1) - 1;
      final resume = ReverseTransferStatus.values.byName(
        data['resumeStatus'] ?? ReverseTransferStatus.inTransit.name,
      );
      transaction.update(ref.collection('exceptions').doc(exception.id), {
        'resolved': true,
        'resolution': resolution.trim(),
        'resolvedBy': actorId,
        'resolvedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(ref, {
        'openExceptionCount': openCount.clamp(0, 999),
        if (openCount <= 0) 'status': resume.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(ref.collection('custodyEvents').doc(), {
        'action': 'Transfer exception resolved',
        'custodianId': actorId,
        'custodianName': actorId,
        'location': transfer.destinationName,
        'notes': resolution.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> _changeStatus(
    ReverseLogisticsTransfer transfer,
    ReverseTransferStatus status,
    String actorId,
    String action, {
    Map<String, Object?> extra = const {},
  }) async {
    final ref = _transfers.doc(transfer.id);
    final write = _db.batch();
    write.update(ref, {
      'status': status.name,
      ...extra,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _custody(
      write,
      ref,
      action: action,
      custodianId: actorId,
      custodianName: actorId,
      location: status == ReverseTransferStatus.inTransit
          ? transfer.originName
          : transfer.destinationName,
      notes: '',
    );
    await write.commit();
  }

  void _custody(
    WriteBatch write,
    DocumentReference<Map<String, dynamic>> transferRef, {
    required String action,
    required String custodianId,
    required String custodianName,
    required String location,
    required String notes,
  }) {
    write.set(transferRef.collection('custodyEvents').doc(), {
      'action': action,
      'custodianId': custodianId,
      'custodianName': custodianName,
      'location': location,
      'notes': notes,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

String _apiExceptionType(TransferExceptionType type) => switch (type) {
  TransferExceptionType.delay => 'delay',
  TransferExceptionType.damage => 'damagedLoad',
  TransferExceptionType.quantityMismatch => 'missingItem',
  TransferExceptionType.weightMismatch => 'missingItem',
  TransferExceptionType.documentation => 'other',
  TransferExceptionType.routeDeviation => 'routeDeviation',
  TransferExceptionType.vehicleBreakdown => 'breakdown',
  TransferExceptionType.refusedDelivery => 'other',
  TransferExceptionType.other => 'other',
};
