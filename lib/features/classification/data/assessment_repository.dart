import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';
import '../../inventory/domain/inventory_item.dart';
import '../domain/assessment.dart';

class AssessmentRepository {
  AssessmentRepository({FirebaseFirestore? firestore, ApiClient? apiClient})
    : _db = firestore ?? FirebaseFirestore.instance,
      _api = apiClient ?? ApiClient.instance,
      _useApi = apiClient != null || (firestore == null && ApiConfig.enabled);
  final FirebaseFirestore _db;
  final ApiClient _api;
  final bool _useApi;
  Stream<List<ItemAssessment>> watch(String itemId) => _useApi
      ? _poll(itemId)
      : _db
            .collection('inventoryItems')
            .doc(itemId)
            .collection('assessments')
            .orderBy('createdAt', descending: true)
            .snapshots()
            .map((s) => s.docs.map(ItemAssessment.fromDoc).toList());
  Stream<List<ItemAssessment>> _poll(String itemId) async* {
    while (true) {
      final data = await _api.getList(
        '/api/v1/inventory/items/$itemId/assessments',
      );
      yield data.map(ItemAssessment.fromJson).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Map<String, dynamic> assistedSuggestion(InventoryItem item) {
    final text = '${item.deviceType} ${item.brand} ${item.model}'.toLowerCase();
    final category = text.contains('phone')
        ? DeviceCategory.mobilePhones
        : text.contains('laptop')
        ? DeviceCategory.laptops
        : text.contains('tv') || text.contains('television')
        ? DeviceCategory.televisions
        : text.contains('printer')
        ? DeviceCategory.printers
        : text.contains('battery')
        ? DeviceCategory.batteries
        : DeviceCategory.accessories;
    final hazardous =
        item.condition == ItemCondition.hazardous ||
        category == DeviceCategory.batteries;
    return {
      'category': category,
      'materials': <String, double>{
        'metals': 45,
        'plastics': 30,
        'glass': 15,
        'other': 10,
      },
      'hazards': hazardous
          ? <String>['Battery or hazardous chemical component']
          : <String>[],
      'confidence': item.imageUrls.isEmpty ? 0.55 : 0.72,
    };
  }

  Future<void> submit({
    required InventoryItem item,
    required DeviceCategory category,
    required Map<String, double> materials,
    required List<String> hazards,
    required int reusability,
    required int repairability,
    required TreatmentRecommendation recommendation,
    required double recoveryValue,
    required double confidence,
    required String notes,
  }) async {
    if (_useApi) {
      await _api.post('/api/v1/inventory/items/${item.id}/assessments', {
        'category': category.name,
        'materials': materials,
        'hazards': hazards,
        'reusability': reusability,
        'repairability': repairability,
        'recommendation': recommendation.name,
        'recoveryValue': recoveryValue,
        'confidence': confidence,
        'notes': notes.trim(),
      });
      return;
    }
    final root = _db.collection('inventoryItems').doc(item.id);
    final assessment = root.collection('assessments').doc();
    final batch = _db.batch();
    batch.set(assessment, {
      'category': category.name,
      'materials': materials,
      'hazards': hazards,
      'reusability': reusability,
      'repairability': repairability,
      'recommendation': recommendation.name,
      'recoveryValue': recoveryValue,
      'confidence': confidence,
      'status': AssessmentStatus.pendingSupervisor.name,
      'notes': notes.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(root.collection('history').doc(), {
      'action': 'assessmentSubmitted',
      'details': '${category.name}: ${recommendation.name}',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> review(
    String itemId,
    String assessmentId, {
    required bool approved,
    String? reason,
  }) {
    if (_useApi) {
      return _api
          .patch(
            '/api/v1/inventory/items/$itemId/assessments/$assessmentId/review',
            {'approved': approved, 'reason': reason},
          )
          .then((_) {});
    }
    return _db
        .collection('inventoryItems')
        .doc(itemId)
        .collection('assessments')
        .doc(assessmentId)
        .update({
          'status': approved
              ? AssessmentStatus.approved.name
              : AssessmentStatus.rejected.name,
          'reviewReason': reason,
          'reviewedAt': FieldValue.serverTimestamp(),
        });
  }
}
