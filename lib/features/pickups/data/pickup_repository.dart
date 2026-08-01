import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';
import '../domain/pickup.dart';

class PickupRepository {
  PickupRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    ApiClient? apiClient,
  })
    : _db = firestore ?? FirebaseFirestore.instance,
      _storage = storage ?? FirebaseStorage.instance,
      _api = apiClient ?? ApiClient.instance,
      _useApi = apiClient != null ||
          (firestore == null && storage == null && ApiConfig.enabled);
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final ApiClient _api;
  final bool _useApi;
  Stream<List<PickupRequest>> watchMine(String uid) => _useApi
      ? _pollMine()
      : _db
      .collection('pickupRequests')
      .where('userId', isEqualTo: uid)
      .snapshots()
      .map(
        (s) =>
            s.docs.map(PickupRequest.fromDoc).toList()
              ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt)),
      );
  Stream<PickupRequest> watchOne(String id) => _useApi
      ? _pollMine().map((items) => items.firstWhere((item) => item.id == id))
      : _db
      .collection('pickupRequests')
      .doc(id)
      .snapshots()
      .where((document) => document.exists)
      .map(PickupRequest.fromDoc);

  Stream<List<PickupRequest>> _pollMine() async* {
    while (true) {
      final data = await _api.getList('/api/v1/pickup-requests');
      yield data.map(PickupRequest.fromJson).toList()
        ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }
  Future<void> create({
    required String uid,
    required WasteCategory category,
    required int quantity,
    required double weight,
    required String condition,
    required String location,
    required DateTime scheduledAt,
    required bool urgent,
    required String instructions,
    required List<PickupPhoto> photos,
    required double? latitude,
    required double? longitude,
  }) async {
    if (_useApi) {
      if (photos.isNotEmpty) {
        throw StateError(
          'Photo upload through the API is not enabled yet. Submit without photos.',
        );
      }
      await _api.post('/api/v1/pickup-requests', {
        'category': category.name,
        'quantity': quantity,
        'estimatedWeight': weight,
        'condition': condition.trim(),
        'location': location.trim(),
        'scheduledAt': scheduledAt.toUtc().toIso8601String(),
        'urgent': urgent,
        'instructions': instructions.trim(),
        'latitude': latitude,
        'longitude': longitude,
      });
      return;
    }
    final document = _db.collection('pickupRequests').doc();
    final photoUrls = <String>[];
    for (var index = 0; index < photos.length; index++) {
      final photo = photos[index];
      final reference = _storage.ref(
        'pickupImages/$uid/${document.id}/$index.jpg',
      );
      await reference.putData(
        Uint8List.fromList(photo.bytes),
        SettableMetadata(contentType: 'image/jpeg'),
      );
      photoUrls.add(await reference.getDownloadURL());
    }
    await document.set({
      'userId': uid,
      'category': category.name,
      'quantity': quantity,
      'estimatedWeight': weight,
      'condition': condition.trim(),
      'location': location.trim(),
      'scheduledAt': Timestamp.fromDate(scheduledAt),
      'urgent': urgent,
      'instructions': instructions.trim(),
      'estimatedFee': estimatePickupFee(
        quantity: quantity,
        weight: weight,
        urgent: urgent,
      ),
      'status': PickupStatus.submitted.name,
      'photoUrls': photoUrls,
      'latitude': latitude,
      'longitude': longitude,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'rating': null,
    });
  }

  Future<void> cancel(String id) => _useApi
      ? _api.patch('/api/v1/pickup-requests/$id/cancel', {}).then((_) {})
      : _db.collection('pickupRequests').doc(id).update({
        'status': PickupStatus.cancelled.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
  Future<void> reschedule(String id, DateTime date) => _useApi
      ? _api.patch('/api/v1/pickup-requests/$id/reschedule', {
          'scheduledAt': date.toUtc().toIso8601String(),
        }).then((_) {})
      : _db.collection('pickupRequests').doc(id).update({
        'scheduledAt': Timestamp.fromDate(date),
        'status': PickupStatus.submitted.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
  Future<void> rate(String id, int rating) => _useApi
      ? _api.patch('/api/v1/pickup-requests/$id/rating', {
          'rating': rating,
        }).then((_) {})
      : _db.collection('pickupRequests').doc(id).update({
          'rating': rating,
          'ratedAt': FieldValue.serverTimestamp(),
        });
}
