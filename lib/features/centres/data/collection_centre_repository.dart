import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';
import '../../pickups/domain/pickup.dart';
import '../domain/collection_centre.dart';

class CollectionCentreRepository {
  CollectionCentreRepository({
    FirebaseFirestore? firestore,
    ApiClient? apiClient,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _api = apiClient ?? ApiClient.instance,
       _useApi = apiClient != null ||
           (firestore == null && ApiConfig.enabled);

  final FirebaseFirestore _db;
  final ApiClient _api;
  final bool _useApi;

  CollectionReference<Map<String, dynamic>> get _centres =>
      _db.collection('collectionCentres');

  Stream<List<CollectionCentre>> watchCentres() {
    if (_useApi) {
      return _pollCentres();
    }
    return _centres.snapshots().map(
      (snapshot) => snapshot.docs.map(CollectionCentre.fromDoc).toList()
        ..sort((a, b) => a.name.compareTo(b.name)),
    );
  }

  Stream<List<CollectionCentre>> _pollCentres() async* {
    while (true) {
      final data = await _api.getList(
        '/api/v1/collection-centres',
        authenticated: false,
      );
      yield data.map(CollectionCentre.fromJson).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<CollectionCentre> watchCentre(String centreId) => _useApi
      ? _pollOne(
          '/api/v1/collection-centres/$centreId',
          CollectionCentre.fromJson,
        )
      : _centres
      .doc(centreId)
      .snapshots()
      .where((document) => document.exists)
      .map(CollectionCentre.fromDoc);

  Stream<List<StorageSection>> watchSections(String centreId) => _useApi
      ? _pollList(
          '/api/v1/collection-centres/$centreId/storageSections',
          StorageSection.fromJson,
        ).map((items) => items..sort((a, b) => a.name.compareTo(b.name)))
      : _centres
      .doc(centreId)
      .collection('storageSections')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs.map(StorageSection.fromDoc).toList()
          ..sort((a, b) => a.name.compareTo(b.name)),
      );

  Stream<List<ReceivingRecord>> watchReceivingRecords(String centreId) =>
      _useApi
      ? _pollList(
          '/api/v1/collection-centres/$centreId/receivingRecords',
          ReceivingRecord.fromJson,
        ).map(
          (items) => items
            ..sort(
              (a, b) => (b.receivedAt ?? DateTime(0)).compareTo(
                a.receivedAt ?? DateTime(0),
              ),
            ),
        )
      : _centres
          .doc(centreId)
          .collection('receivingRecords')
          .orderBy('receivedAt', descending: true)
          .limit(100)
          .snapshots()
          .map((snapshot) => snapshot.docs.map(ReceivingRecord.fromDoc).toList());

  Stream<List<StockMovement>> watchMovements(String centreId) => _useApi
      ? _pollList(
          '/api/v1/collection-centres/$centreId/stockMovements',
          StockMovement.fromJson,
        ).map(
          (items) => items
            ..sort(
              (a, b) =>
                  (b.at ?? DateTime(0)).compareTo(a.at ?? DateTime(0)),
            ),
        )
      : _centres
      .doc(centreId)
      .collection('stockMovements')
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(StockMovement.fromDoc).toList());

  Stream<List<CentreStaffAssignment>> watchStaff(String centreId) => _useApi
      ? _pollList(
          '/api/v1/collection-centres/$centreId/staffAssignments',
          CentreStaffAssignment.fromJson,
        )
      : _centres
      .doc(centreId)
      .collection('staffAssignments')
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.docs.map(CentreStaffAssignment.fromDoc).toList(),
      );

  Stream<List<SafetyInspection>> watchInspections(String centreId) => _useApi
      ? _pollList(
          '/api/v1/collection-centres/$centreId/safetyInspections',
          SafetyInspection.fromJson,
        ).map(
          (items) => items
            ..sort(
              (a, b) => (b.inspectedAt ?? DateTime(0)).compareTo(
                a.inspectedAt ?? DateTime(0),
              ),
            ),
        )
      : _centres
      .doc(centreId)
      .collection('safetyInspections')
      .orderBy('inspectedAt', descending: true)
      .limit(50)
          .snapshots()
          .map((snapshot) => snapshot.docs.map(SafetyInspection.fromDoc).toList());

  Stream<T> _pollOne<T>(
    String path,
    T Function(Map<String, dynamic>) decode,
  ) async* {
    while (true) {
      yield decode(await _api.get(path));
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<List<T>> _pollList<T>(
    String path,
    T Function(Map<String, dynamic>) decode,
  ) async* {
    while (true) {
      final data = await _api.getList(path);
      yield data.map(decode).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Future<void> register({
    required String name,
    required String address,
    required String contactName,
    required String contactEmail,
    required String contactPhone,
    required double? latitude,
    required double? longitude,
    required Map<String, String> operatingHours,
    required List<WasteCategory> supportedCategories,
    required double capacityKg,
    required double capacityAlertPercent,
  }) {
    if (_useApi) {
      return _api.post('/api/v1/collection-centres', {
        'name': name.trim(),
        'address': address.trim(),
        'contactName': contactName.trim(),
        'contactEmail': contactEmail.trim(),
        'contactPhone': contactPhone.trim(),
        'latitude': latitude,
        'longitude': longitude,
        'operatingHours': operatingHours,
        'supportedCategories': supportedCategories
            .map((item) => item.name)
            .toList(),
        'capacityKg': capacityKg,
        'capacityAlertPercent': capacityAlertPercent,
      }).then((_) {});
    }
    return _centres.add({
      'name': name.trim(),
      'address': address.trim(),
      'contactName': contactName.trim(),
      'contactEmail': contactEmail.trim(),
      'contactPhone': contactPhone.trim(),
      'latitude': latitude,
      'longitude': longitude,
      'operatingHours': operatingHours,
      'supportedCategories': supportedCategories
          .map((item) => item.name)
          .toList(),
      'capacityKg': capacityKg,
      'currentStockKg': 0,
      'capacityAlertPercent': capacityAlertPercent,
      'staffIds': <String>[],
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addSection(
    String centreId, {
    required String name,
    required WasteCategory category,
    required double capacityKg,
    required bool restricted,
  }) => _useApi
      ? _api.post('/api/v1/collection-centres/$centreId/sections', {
          'name': name.trim(),
          'category': category.name,
          'capacityKg': capacityKg,
          'restricted': restricted,
        }).then((_) {})
      : _centres.doc(centreId).collection('storageSections').add({
    'name': name.trim(),
    'category': category.name,
    'capacityKg': capacityKg,
    'currentStockKg': 0,
    'restricted': restricted,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<void> assignStaff(
    String centreId, {
    required String userId,
    required String role,
  }) async {
    if (_useApi) {
      await _api.post('/api/v1/collection-centres/$centreId/staff', {
        'userId': userId.trim(),
        'role': role.trim(),
      });
      return;
    }
    final centre = _centres.doc(centreId);
    final assignment = centre.collection('staffAssignments').doc(userId.trim());
    final batch = _db.batch();
    batch.set(assignment, {
      'userId': userId.trim(),
      'role': role.trim(),
      'active': true,
      'assignedAt': FieldValue.serverTimestamp(),
    });
    batch.update(centre, {
      'staffIds': FieldValue.arrayUnion([userId.trim()]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> checkIn(
    String centreId, {
    required String reference,
    required WasteCategory category,
    required int itemCount,
    required double weightKg,
    required String sectionId,
    required String staffId,
    required String notes,
  }) async {
    if (itemCount <= 0 || weightKg <= 0) {
      throw ArgumentError('Item count and weight must be greater than zero.');
    }
    if (_useApi) {
      await _api.post('/api/v1/collection-centres/$centreId/check-ins', {
        'reference': reference.trim(),
        'category': category.name,
        'itemCount': itemCount,
        'weightKg': weightKg,
        'sectionId': sectionId,
        'staffId': staffId,
        'notes': notes.trim(),
      });
      return;
    }
    final centreRef = _centres.doc(centreId);
    final sectionRef = centreRef.collection('storageSections').doc(sectionId);
    await _db.runTransaction((transaction) async {
      final centre = CollectionCentre.fromDoc(await transaction.get(centreRef));
      final section = StorageSection.fromDoc(await transaction.get(sectionRef));
      if (centre.currentStockKg + weightKg > centre.capacityKg) {
        throw StateError('This check-in exceeds the centre storage capacity.');
      }
      if (section.currentStockKg + weightKg > section.capacityKg) {
        throw StateError('This check-in exceeds the selected section capacity.');
      }
      final record = centreRef.collection('receivingRecords').doc();
      final movement = centreRef.collection('stockMovements').doc();
      transaction.set(record, {
        'reference': reference.trim().isEmpty ? record.id : reference.trim(),
        'category': category.name,
        'itemCount': itemCount,
        'recordedWeightKg': weightKg,
        'verifiedWeightKg': null,
        'verified': false,
        'sectionId': sectionId,
        'staffId': staffId,
        'notes': notes.trim(),
        'receivedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(movement, {
        'type': StockMovementType.checkIn.name,
        'weightKg': weightKg,
        'sectionId': sectionId,
        'destination': section.name,
        'staffId': staffId,
        'notes': 'Receiving record ${record.id}',
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.update(centreRef, {
        'currentStockKg': FieldValue.increment(weightKg),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(sectionRef, {
        'currentStockKg': FieldValue.increment(weightKg),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> verifyWeight(
    String centreId,
    ReceivingRecord record,
    double verifiedWeightKg,
  ) async {
    if (verifiedWeightKg <= 0) throw ArgumentError('Weight must be positive.');
    if (_useApi) {
      await _api.patch(
        '/api/v1/collection-centres/$centreId/receiving/${record.id}/verify',
        {'verifiedWeightKg': verifiedWeightKg},
      );
      return;
    }
    final centreRef = _centres.doc(centreId);
    final recordRef = centreRef.collection('receivingRecords').doc(record.id);
    final sectionRef = centreRef
        .collection('storageSections')
        .doc(record.sectionId);
    await _db.runTransaction((transaction) async {
      final currentRecord = ReceivingRecord.fromDoc(
        await transaction.get(recordRef),
      );
      final difference = verifiedWeightKg - currentRecord.stockWeightKg;
      final centre = CollectionCentre.fromDoc(await transaction.get(centreRef));
      final section = StorageSection.fromDoc(await transaction.get(sectionRef));
      if (centre.currentStockKg + difference > centre.capacityKg ||
          section.currentStockKg + difference > section.capacityKg) {
        throw StateError('Verified weight exceeds available capacity.');
      }
      if (centre.currentStockKg + difference < 0 ||
          section.currentStockKg + difference < 0) {
        throw StateError('Verified adjustment would create negative stock.');
      }
      transaction.update(recordRef, {
        'verifiedWeightKg': verifiedWeightKg,
        'verified': true,
        'verifiedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(centreRef, {
        'currentStockKg': FieldValue.increment(difference),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(sectionRef, {
        'currentStockKg': FieldValue.increment(difference),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> checkOut(
    String centreId, {
    required StorageSection section,
    required double weightKg,
    required String destination,
    required String staffId,
    required String notes,
  }) async {
    if (weightKg <= 0) throw ArgumentError('Weight must be greater than zero.');
    if (_useApi) {
      await _api.post('/api/v1/collection-centres/$centreId/check-outs', {
        'sectionId': section.id,
        'weightKg': weightKg,
        'destination': destination.trim(),
        'staffId': staffId,
        'notes': notes.trim(),
      });
      return;
    }
    final centreRef = _centres.doc(centreId);
    final sectionRef = centreRef.collection('storageSections').doc(section.id);
    await _db.runTransaction((transaction) async {
      final centre = CollectionCentre.fromDoc(await transaction.get(centreRef));
      final currentSection = StorageSection.fromDoc(
        await transaction.get(sectionRef),
      );
      if (weightKg > centre.currentStockKg ||
          weightKg > currentSection.currentStockKg) {
        throw StateError('Check-out weight exceeds recorded stock.');
      }
      transaction.update(centreRef, {
        'currentStockKg': FieldValue.increment(-weightKg),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(sectionRef, {
        'currentStockKg': FieldValue.increment(-weightKg),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(centreRef.collection('stockMovements').doc(), {
        'type': StockMovementType.checkOut.name,
        'weightKg': weightKg,
        'sectionId': section.id,
        'destination': destination.trim(),
        'staffId': staffId,
        'notes': notes.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> recordInspection(
    String centreId, {
    required String inspectorId,
    required Map<String, bool> checks,
    required String notes,
  }) {
    final passed = checks.values.where((value) => value).length;
    final score = checks.isEmpty ? 0 : (passed / checks.length * 100).round();
    final status = score == 100
        ? SafetyInspectionStatus.passed
        : score >= 70
        ? SafetyInspectionStatus.actionRequired
        : SafetyInspectionStatus.failed;
    if (_useApi) {
      return _api.post('/api/v1/collection-centres/$centreId/inspections', {
        'inspectorId': inspectorId,
        'checks': checks,
        'notes': notes.trim(),
      }).then((_) {});
    }
    return _centres.doc(centreId).collection('safetyInspections').add({
      'inspectorId': inspectorId,
      'checks': checks,
      'score': score,
      'status': status.name,
      'notes': notes.trim(),
      'inspectedAt': FieldValue.serverTimestamp(),
    });
  }
}
