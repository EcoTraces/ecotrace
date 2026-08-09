import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';
import '../../../core/media/cloudinary_upload_service.dart';
import '../../inventory/domain/inventory_item.dart';

class TraceEvent {
  const TraceEvent({
    required this.id,
    required this.type,
    required this.from,
    required this.to,
    required this.actor,
    required this.notes,
    required this.at,
    required this.sequence,
    required this.integrityHash,
    required this.evidenceUrls,
    required this.custodianId,
    required this.facilityId,
    required this.status,
  });
  final String id, type, from, to, actor, notes, integrityHash;
  final String? custodianId, facilityId, status;
  final List<String> evidenceUrls;
  final int sequence;
  final DateTime? at;
  factory TraceEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final x = d.data()!;
    return TraceEvent(
      id: d.id,
      type: x['type'] ?? '',
      from: x['from'] ?? '',
      to: x['to'] ?? '',
      actor: x['actor'] ?? '',
      notes: x['notes'] ?? '',
      at: (x['createdAt'] as Timestamp?)?.toDate(),
      sequence: (x['sequence'] as num? ?? 0).toInt(),
      integrityHash: x['integrityHash']?.toString() ?? '',
      evidenceUrls: List<String>.from(x['evidenceUrls'] as List? ?? const []),
      custodianId: x['custodianId']?.toString(),
      facilityId: x['facilityId']?.toString(),
      status: x['status']?.toString(),
    );
  }
  factory TraceEvent.fromJson(Map<String, dynamic> x) => TraceEvent(
    id: x['id']?.toString() ?? '',
    type: x['type']?.toString() ?? '',
    from: x['from']?.toString() ?? '',
    to: x['to']?.toString() ?? '',
    actor: x['actor']?.toString() ?? '',
    notes: x['notes']?.toString() ?? '',
    at: DateTime.tryParse(x['createdAt']?.toString() ?? ''),
    sequence: (x['sequence'] as num? ?? 0).toInt(),
    integrityHash: x['integrityHash']?.toString() ?? '',
    evidenceUrls: List<String>.from(x['evidenceUrls'] as List? ?? const []),
    custodianId: x['custodianId']?.toString(),
    facilityId: x['facilityId']?.toString(),
    status: x['status']?.toString(),
  );
}

class TraceabilityRepository {
  TraceabilityRepository({FirebaseFirestore? firestore, ApiClient? apiClient})
    : _db = firestore ?? FirebaseFirestore.instance,
      _api = apiClient ?? ApiClient.instance,
      _useApi = apiClient != null || (firestore == null && ApiConfig.enabled);
  final FirebaseFirestore _db;
  final ApiClient _api;
  final bool _useApi;
  Stream<List<TraceEvent>> watch(String id) => _useApi
      ? _poll(id)
      : _db
            .collection('inventoryItems')
            .doc(id)
            .collection('traceability')
            .orderBy('createdAt', descending: true)
            .snapshots()
            .map((s) => s.docs.map(TraceEvent.fromDoc).toList());
  Stream<List<TraceEvent>> _poll(String id) async* {
    while (true) {
      final data = await _api.getList(
        '/api/v1/inventory/items/$id/traceability',
      );
      yield data.map(TraceEvent.fromJson).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Future<InventoryItem?> findByCode(String code) async {
    final normalized = code.trim().startsWith('ecotrace://inventory/')
        ? Uri.decodeComponent(
            code.trim().substring('ecotrace://inventory/'.length),
          )
        : code.trim();
    if (_useApi) {
      try {
        return InventoryItem.fromJson(
          await _api.get(
            '/api/v1/inventory/items/by-code/${Uri.encodeComponent(normalized)}',
          ),
        );
      } on ApiException catch (error) {
        if (error.statusCode == 404) return null;
        rethrow;
      }
    }
    final q = await _db
        .collection('inventoryItems')
        .where('itemCode', isEqualTo: normalized)
        .limit(1)
        .get();
    return q.docs.isEmpty ? null : InventoryItem.fromDoc(q.docs.first);
  }

  Future<void> record(
    InventoryItem item, {
    required String type,
    required String destination,
    required String actor,
    required String notes,
    String? custodianId,
    String? facilityId,
    ProcessingStatus? status,
    List<String> evidenceUrls = const [],
    bool updateLocation = true,
  }) async {
    if (_useApi) {
      await _api.post('/api/v1/inventory/items/${item.id}/traceability', {
        'type': type,
        'destination': destination,
        'actor': actor.trim(),
        'notes': notes.trim(),
        'custodianId': custodianId,
        'facilityId': facilityId,
        if (status != null) 'status': status.name,
        'evidenceUrls': evidenceUrls,
        'updateLocation': updateLocation,
      });
      return;
    }
    final root = _db.collection('inventoryItems').doc(item.id);
    final batch = _db.batch();
    batch.update(root, {
      if (updateLocation) 'currentLocation': destination,
      'currentCustodianId': ?custodianId,
      'assignedFacilityId': ?facilityId,
      if (status != null) 'processingStatus': status.name,
      if (type == 'receiptVerified') ...{
        'receiptVerified': true,
        'receivedAt': FieldValue.serverTimestamp(),
      },
      if (type == 'damaged' || type == 'missing') ...{
        'traceabilityException': type,
        'traceabilityExceptionNotes': notes.trim(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(root.collection('traceability').doc(), {
      'type': type,
      'from': item.location,
      'to': destination,
      'actor': actor.trim(),
      'notes': notes.trim(),
      'custodianId': custodianId,
      'facilityId': facilityId,
      if (status != null) 'status': status.name,
      'evidenceUrls': evidenceUrls,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(root.collection('history').doc(), {
      'action': type,
      'details': '${item.location} → $destination: ${notes.trim()}',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<List<String>> uploadEvidence(List<Uint8List> images) =>
      CloudinaryUploadService.instance.uploadImages(
        images,
        scope: 'traceability',
      );

  Future<void> assign(
    InventoryItem item, {
    required String assignmentType,
    required String assigneeId,
    required String assigneeName,
    required String destination,
    String notes = '',
  }) async {
    if (_useApi) {
      await _api
          .post('/api/v1/inventory/items/${item.id}/traceability/assign', {
            'assignmentType': assignmentType,
            'assigneeId': assigneeId.trim(),
            'assigneeName': assigneeName.trim(),
            'destination': destination.trim(),
            'notes': notes.trim(),
          });
      return;
    }
    await record(
      item,
      type: assignmentType == 'collector'
          ? 'collectorAssigned'
          : 'facilityAssigned',
      destination: destination,
      actor: assigneeName,
      notes: notes,
      custodianId: assignmentType == 'collector' ? assigneeId : null,
      facilityId: assignmentType == 'facility' ? assigneeId : null,
      updateLocation: false,
    );
  }

  Future<Map<String, dynamic>> certificate(InventoryItem item) async {
    if (_useApi) {
      final certificate = await _api.get(
        '/api/v1/inventory/items/${item.id}/traceability/certificate',
      );
      final integrity = await audit(item);
      certificate['integrityVerified'] = integrity['integrityVerified'] == true;
      certificate['integrityIssues'] = integrity['integrityIssues'] ?? const [];
      return certificate;
    }
    final events = await watch(item.id).first;
    return {
      'certificateNumber':
          'TRACE-${(item.id.length > 10 ? item.id.substring(0, 10) : item.id).toUpperCase()}',
      'issuedAt': DateTime.now().toIso8601String(),
      'chainOfCustody': events
          .map(
            (event) => {
              'type': event.type,
              'from': event.from,
              'to': event.to,
              'actor': event.actor,
              'notes': event.notes,
              'createdAt': event.at?.toIso8601String(),
            },
          )
          .toList(),
    };
  }

  Future<Map<String, dynamic>> audit(InventoryItem item) async {
    if (_useApi) {
      return _api.get('/api/v1/inventory/items/${item.id}/traceability/audit');
    }
    return {'integrityVerified': true, 'integrityIssues': const []};
  }
}
