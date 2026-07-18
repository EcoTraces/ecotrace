import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../domain/pickup.dart';

class PickupRepository {
  PickupRepository({FirebaseFirestore? firestore, FirebaseStorage? storage})
    : _db = firestore ?? FirebaseFirestore.instance,
      _storage = storage ?? FirebaseStorage.instance;
  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  Stream<List<PickupRequest>> watchMine(String uid) => _db
      .collection('pickupRequests')
      .where('userId', isEqualTo: uid)
      .snapshots()
      .map(
        (s) =>
            s.docs.map(PickupRequest.fromDoc).toList()
              ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt)),
      );
  Stream<PickupRequest> watchOne(String id) => _db
      .collection('pickupRequests')
      .doc(id)
      .snapshots()
      .where((document) => document.exists)
      .map(PickupRequest.fromDoc);
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

  Future<void> cancel(String id) =>
      _db.collection('pickupRequests').doc(id).update({
        'status': PickupStatus.cancelled.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
  Future<void> reschedule(String id, DateTime date) =>
      _db.collection('pickupRequests').doc(id).update({
        'scheduledAt': Timestamp.fromDate(date),
        'status': PickupStatus.submitted.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
  Future<void> rate(String id, int rating) => _db
      .collection('pickupRequests')
      .doc(id)
      .update({'rating': rating, 'ratedAt': FieldValue.serverTimestamp()});
}
