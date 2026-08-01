import 'package:cloud_firestore/cloud_firestore.dart';

enum PickupStatus {
  draft,
  submitted,
  approved,
  assigned,
  scheduled,
  inProgress,
  collected,
  cancelled,
  failed,
  completed,
}

enum WasteCategory {
  computers,
  phones,
  televisions,
  appliances,
  batteries,
  accessories,
  other,
}

class PickupRequest {
  const PickupRequest({
    required this.id,
    required this.userId,
    required this.category,
    required this.quantity,
    required this.weight,
    required this.condition,
    required this.location,
    required this.scheduledAt,
    required this.urgent,
    required this.instructions,
    required this.fee,
    required this.status,
    required this.rating,
    required this.photoUrls,
    required this.latitude,
    required this.longitude,
  });
  final String id, userId, condition, location, instructions;
  final WasteCategory category;
  final int quantity;
  final double weight, fee;
  final DateTime scheduledAt;
  final bool urgent;
  final PickupStatus status;
  final int? rating;
  final List<String> photoUrls;
  final double? latitude, longitude;
  factory PickupRequest.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final x = d.data()!;
    return PickupRequest(
      id: d.id,
      userId: x['userId'],
      category: WasteCategory.values.byName(x['category']),
      quantity: x['quantity'],
      weight: (x['estimatedWeight'] as num).toDouble(),
      condition: x['condition'],
      location: x['location'],
      scheduledAt: (x['scheduledAt'] as Timestamp).toDate(),
      urgent: x['urgent'],
      instructions: x['instructions'] ?? '',
      fee: (x['estimatedFee'] as num).toDouble(),
      status: PickupStatus.values.byName(x['status']),
      rating: x['rating'],
      photoUrls: List<String>.from(x['photoUrls'] as List? ?? const []),
      latitude: (x['latitude'] as num?)?.toDouble(),
      longitude: (x['longitude'] as num?)?.toDouble(),
    );
  }
  factory PickupRequest.fromJson(Map<String, dynamic> data) => PickupRequest(
    id: data['id']?.toString() ?? '',
    userId: data['userId']?.toString() ?? '',
    category: WasteCategory.values.byName(
      data['category']?.toString() ?? 'other',
    ),
    quantity: (data['quantity'] as num? ?? 0).toInt(),
    weight: (data['estimatedWeight'] as num? ?? 0).toDouble(),
    condition: data['condition']?.toString() ?? '',
    location: data['location']?.toString() ?? '',
    scheduledAt:
        DateTime.tryParse(data['scheduledAt']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    urgent: data['urgent'] as bool? ?? false,
    instructions: data['instructions']?.toString() ?? '',
    fee: (data['estimatedFee'] as num? ?? 0).toDouble(),
    status: PickupStatus.values.byName(
      data['status']?.toString() ?? 'submitted',
    ),
    rating: (data['rating'] as num?)?.toInt(),
    photoUrls: List<String>.from(data['photoUrls'] as List? ?? const []),
    latitude: (data['latitude'] as num?)?.toDouble(),
    longitude: (data['longitude'] as num?)?.toDouble(),
  );
}

class PickupPhoto {
  const PickupPhoto({required this.name, required this.bytes});
  final String name;
  final List<int> bytes;
}

double estimatePickupFee({
  required int quantity,
  required double weight,
  required bool urgent,
}) => ((quantity * 2) + (weight * 0.75) + (urgent ? 15 : 0));
