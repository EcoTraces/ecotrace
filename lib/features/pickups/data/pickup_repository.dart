import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';
import '../../../core/media/cloudinary_upload_service.dart';
import '../domain/pickup.dart';

class PickupRepository {
  PickupRepository({FirebaseFirestore? firestore, ApiClient? apiClient})
    : _db = firestore ?? FirebaseFirestore.instance,
      _api = apiClient ?? ApiClient.instance,
      _useApi = apiClient != null || (firestore == null && ApiConfig.enabled);
  final FirebaseFirestore _db;
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
      ? _pollOne(id)
      : _db
            .collection('pickupRequests')
            .doc(id)
            .snapshots()
            .where((document) => document.exists)
            .map(PickupRequest.fromDoc);

  Stream<PickupRequest> _pollOne(String id) async* {
    while (true) {
      yield PickupRequest.fromJson(
        await _api.get('/api/v1/pickup-requests/$id'),
      );
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<List<PickupRequest>> _pollMine() async* {
    while (true) {
      try {
        final data = await _api.getList('/api/v1/pickup-requests');
        yield data.map(PickupRequest.fromJson).toList()
          ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
      } catch (_) {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) return;
        final snapshot = await _db
            .collection('pickupRequests')
            .where('userId', isEqualTo: user.uid)
            .get();
        yield snapshot.docs.map(PickupRequest.fromDoc).toList()
          ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
      }
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Future<PickupFeeEstimate> estimateFee({
    required int quantity,
    required double weight,
    required bool urgent,
  }) async {
    if (_useApi) {
      return PickupFeeEstimate.fromJson(
        await _api.post('/api/v1/pickup-requests/estimate-fee', {
          'quantity': quantity,
          'estimatedWeight': weight,
          'urgent': urgent,
        }),
      );
    }
    final total = estimatePickupFee(
      quantity: quantity,
      weight: weight,
      urgent: urgent,
    );
    return PickupFeeEstimate(
      total: total,
      currency: 'SLE',
      baseFee: quantity * 2,
      weightFee: weight * .75,
      urgentFee: urgent ? 15 : 0,
    );
  }

  Future<String> create({
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
    bool submit = true,
  }) async {
    if (photos.isEmpty) {
      throw ArgumentError('At least one pickup photo is required.');
    }
    final photoUrls = await CloudinaryUploadService.instance.uploadImages(
      photos.map((photo) => Uint8List.fromList(photo.bytes)).toList(),
      scope: 'pickups',
    );
    if (_useApi) {
      final result = await _api.post('/api/v1/pickup-requests', {
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
        'photoUrls': photoUrls,
        'status': submit ? 'submitted' : 'draft',
      });
      return result['id']?.toString() ?? '';
    }
    final document = _db.collection('pickupRequests').doc();
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
      'status': submit ? PickupStatus.submitted.name : PickupStatus.draft.name,
      'photoUrls': photoUrls,
      'latitude': latitude,
      'longitude': longitude,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'rating': null,
    });
    return document.id;
  }

  Future<void> confirm(String id) => _useApi
      ? _api.post('/api/v1/pickup-requests/$id/confirm', {}).then((_) {})
      : _db.collection('pickupRequests').doc(id).update({
          'status': PickupStatus.submitted.name,
          'updatedAt': FieldValue.serverTimestamp(),
        });

  Future<List<PickupEvent>> history(String id) async {
    if (_useApi) {
      final result = await _api.get('/api/v1/pickup-requests/$id/history');
      return (result['events'] as List? ?? const [])
          .map(
            (item) =>
                PickupEvent.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList();
    }
    final snapshot = await _db
        .collection('pickupRequests')
        .doc(id)
        .collection('events')
        .orderBy('createdAt')
        .get();
    return snapshot.docs
        .map((doc) => PickupEvent.fromJson({'id': doc.id, ...doc.data()}))
        .toList();
  }

  Future<void> cancel(String id, {String reason = ''}) => _useApi
      ? _api
            .patch('/api/v1/pickup-requests/$id/cancel', {'reason': reason})
            .then((_) {})
      : _db.collection('pickupRequests').doc(id).update({
          'status': PickupStatus.cancelled.name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  Future<void> reschedule(String id, DateTime date, {String reason = ''}) =>
      _useApi
      ? _api
            .patch('/api/v1/pickup-requests/$id/reschedule', {
              'scheduledAt': date.toUtc().toIso8601String(),
              'reason': reason,
            })
            .then((_) {})
      : _db.collection('pickupRequests').doc(id).update({
          'scheduledAt': Timestamp.fromDate(date),
          'status': PickupStatus.submitted.name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  Future<void> rate(String id, int rating, {String comment = ''}) => _useApi
      ? _api
            .patch('/api/v1/pickup-requests/$id/rating', {
              'rating': rating,
              'comment': comment,
            })
            .then((_) {})
      : _db.collection('pickupRequests').doc(id).update({
          'rating': rating,
          'ratedAt': FieldValue.serverTimestamp(),
        });
}
