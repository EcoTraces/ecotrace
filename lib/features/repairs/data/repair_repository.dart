import 'package:cloud_firestore/cloud_firestore.dart';

import '../../inventory/domain/inventory_item.dart';
import '../domain/repair_job.dart';

class RepairRepository {
  RepairRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _jobs =>
      _db.collection('repairJobs');

  Stream<List<RepairJob>> watchJobs() => _jobs.snapshots().map(
    (snapshot) => snapshot.docs.map(RepairJob.fromDoc).toList()
      ..sort((a, b) => b.createdAt?.compareTo(a.createdAt ?? DateTime(0)) ?? 0),
  );

  Stream<RepairJob> watchJob(String jobId) => _jobs
      .doc(jobId)
      .snapshots()
      .where((document) => document.exists)
      .map(RepairJob.fromDoc);

  Stream<List<SparePartUsage>> watchParts(String jobId) => _jobs
      .doc(jobId)
      .collection('parts')
      .orderBy('recordedAt', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(SparePartUsage.fromDoc).toList());

  Stream<List<RepairProgressEvent>> watchProgress(String jobId) => _jobs
      .doc(jobId)
      .collection('progress')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs.map(RepairProgressEvent.fromDoc).toList(),
      );

  Future<void> createAssessment({
    required InventoryItem item,
    required String assessmentNotes,
    required String createdBy,
    required String technicianId,
  }) async {
    final existing = await _jobs.where('itemId', isEqualTo: item.id).get();
    final hasActiveJob = existing.docs
        .map(RepairJob.fromDoc)
        .any(
          (job) => ![
            RepairStatus.completed,
            RepairStatus.rejected,
            RepairStatus.unrepairable,
          ].contains(job.status),
        );
    if (hasActiveJob) {
      throw StateError('This item already has an active repair job.');
    }
    final job = _jobs.doc();
    final itemRef = _db.collection('inventoryItems').doc(item.id);
    final batch = _db.batch();
    batch.set(job, {
      'itemId': item.id,
      'itemCode': item.itemCode,
      'deviceName': '${item.brand} ${item.model}'.trim(),
      'status': RepairStatus.awaitingAssessment.name,
      'assessmentNotes': assessmentNotes.trim(),
      'diagnosis': '',
      'faults': <String>[],
      'technicianId': technicianId.trim(),
      'estimatedRepairCost': 0,
      'actualPartsCost': 0,
      'progressPercent': 0,
      'qualityChecks': <String, bool>{},
      'qualityNotes': '',
      'refurbishmentGrade': null,
      'warrantyStart': null,
      'warrantyEnd': null,
      'disposition': RefurbishedDisposition.pending.name,
      'dispositionApproved': false,
      'resalePrice': null,
      'donationRecipient': '',
      'createdBy': createdBy,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(itemRef, {
      'processingStatus': ProcessingStatus.inspecting.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(itemRef.collection('history').doc(), {
      'action': 'repairAssessmentCreated',
      'details': 'Repair job ${job.id} created',
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(job.collection('progress').doc(), {
      'type': 'assessmentCreated',
      'details': assessmentNotes.trim(),
      'progressPercent': 0,
      'actorId': createdBy,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> assignTechnician(
    RepairJob job, {
    required String technicianId,
    required String actorId,
  }) => _updateWithProgress(
    job,
    updates: {'technicianId': technicianId.trim()},
    type: 'technicianAssigned',
    details: 'Assigned to ${technicianId.trim()}',
    actorId: actorId,
  );

  Future<void> diagnose(
    RepairJob job, {
    required String diagnosis,
    required List<String> faults,
    required double estimatedRepairCost,
    required String actorId,
  }) => _updateWithProgress(
    job,
    updates: {
      'status': RepairStatus.diagnosed.name,
      'diagnosis': diagnosis.trim(),
      'faults': faults,
      'estimatedRepairCost': estimatedRepairCost,
      'diagnosedAt': FieldValue.serverTimestamp(),
    },
    type: 'diagnosed',
    details: '${faults.length} fault(s); estimate $estimatedRepairCost',
    actorId: actorId,
  );

  Future<void> reviewRepair(
    RepairJob job, {
    required bool approved,
    required String actorId,
    required String notes,
  }) async {
    final status = approved ? RepairStatus.approved : RepairStatus.rejected;
    final jobRef = _jobs.doc(job.id);
    final itemRef = _db.collection('inventoryItems').doc(job.itemId);
    final batch = _db.batch();
    batch.update(jobRef, {
      'status': status.name,
      'repairApproved': approved,
      'repairApprovedBy': actorId,
      'repairApprovalNotes': notes.trim(),
      'repairApprovedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(itemRef, {
      'processingStatus': approved
          ? ProcessingStatus.assignedForRepair.name
          : ProcessingStatus.inspecting.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(jobRef.collection('progress').doc(), {
      'type': approved ? 'repairApproved' : 'repairRejected',
      'details': notes.trim(),
      'progressPercent': job.progressPercent,
      'actorId': actorId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> startRepair(RepairJob job, String actorId) async {
    final jobRef = _jobs.doc(job.id);
    final itemRef = _db.collection('inventoryItems').doc(job.itemId);
    final batch = _db.batch();
    batch.update(jobRef, {
      'status': RepairStatus.repairInProgress.name,
      'progressPercent': 10,
      'repairStartedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(itemRef, {
      'processingStatus': ProcessingStatus.repairing.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(jobRef.collection('progress').doc(), {
      'type': 'repairStarted',
      'details': 'Repair work started',
      'progressPercent': 10,
      'actorId': actorId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> addPart(
    RepairJob job, {
    required String name,
    required String partNumber,
    required int quantity,
    required double unitCost,
    required String actorId,
  }) async {
    if (quantity <= 0 || unitCost < 0 || name.trim().isEmpty) {
      throw ArgumentError('Enter a part name, quantity, and valid cost.');
    }
    final jobRef = _jobs.doc(job.id);
    await _db.runTransaction((transaction) async {
      transaction.set(jobRef.collection('parts').doc(), {
        'name': name.trim(),
        'partNumber': partNumber.trim(),
        'quantity': quantity,
        'unitCost': unitCost,
        'recordedBy': actorId,
        'recordedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(jobRef, {
        'actualPartsCost': FieldValue.increment(quantity * unitCost),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> recordProgress(
    RepairJob job, {
    required int progressPercent,
    required String details,
    required String actorId,
  }) {
    if (progressPercent < job.progressPercent || progressPercent > 95) {
      throw ArgumentError('Progress must increase and remain at or below 95%.');
    }
    return _updateWithProgress(
      job,
      updates: {'progressPercent': progressPercent},
      type: 'progressUpdated',
      details: details.trim(),
      actorId: actorId,
      progressPercent: progressPercent,
    );
  }

  Future<void> beginQualityTesting(RepairJob job, String actorId) =>
      _updateWithProgress(
        job,
        updates: {
          'status': RepairStatus.qualityTesting.name,
          'progressPercent': 95,
          'qualityTestingStartedAt': FieldValue.serverTimestamp(),
        },
        type: 'qualityTestingStarted',
        details: 'Repair submitted for quality control',
        actorId: actorId,
        progressPercent: 95,
      );

  Future<void> performQualityControl(
    RepairJob job, {
    required Map<String, bool> checks,
    required String notes,
    required RefurbishmentGrade grade,
    required int warrantyMonths,
    required String actorId,
  }) async {
    final passed = checks.isNotEmpty && checks.values.every((value) => value);
    final jobRef = _jobs.doc(job.id);
    final itemRef = _db.collection('inventoryItems').doc(job.itemId);
    final start = DateTime.now();
    final end = DateTime(start.year, start.month + warrantyMonths, start.day);
    final batch = _db.batch();
    batch.update(jobRef, {
      'status': passed
          ? RepairStatus.completed.name
          : RepairStatus.repairInProgress.name,
      'progressPercent': passed ? 100 : 80,
      'qualityChecks': checks,
      'qualityNotes': notes.trim(),
      'qualityTestedBy': actorId,
      'qualityTestedAt': FieldValue.serverTimestamp(),
      if (passed) 'refurbishmentGrade': grade.name,
      if (passed) 'warrantyStart': Timestamp.fromDate(start),
      if (passed) 'warrantyEnd': Timestamp.fromDate(end),
      if (passed) 'completedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(itemRef, {
      'processingStatus': passed
          ? ProcessingStatus.refurbished.name
          : ProcessingStatus.repairing.name,
      if (passed) 'condition': ItemCondition.working.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(jobRef.collection('progress').doc(), {
      'type': passed ? 'qualityPassed' : 'qualityFailed',
      'details': notes.trim(),
      'progressPercent': passed ? 100 : 80,
      'actorId': actorId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> markUnrepairable(
    RepairJob job, {
    required String reason,
    required String actorId,
  }) async {
    final jobRef = _jobs.doc(job.id);
    final itemRef = _db.collection('inventoryItems').doc(job.itemId);
    final batch = _db.batch();
    batch.update(jobRef, {
      'status': RepairStatus.unrepairable.name,
      'unrepairableReason': reason.trim(),
      'unrepairableBy': actorId,
      'closedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(itemRef, {
      'processingStatus': ProcessingStatus.assignedForRecycling.name,
      'condition': ItemCondition.recyclable.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(jobRef.collection('progress').doc(), {
      'type': 'markedUnrepairable',
      'details': reason.trim(),
      'progressPercent': job.progressPercent,
      'actorId': actorId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> updateWarranty(
    RepairJob job, {
    required DateTime warrantyEnd,
    required String actorId,
  }) => _updateWithProgress(
    job,
    updates: {'warrantyEnd': Timestamp.fromDate(warrantyEnd)},
    type: 'warrantyUpdated',
    details: 'Warranty valid until ${warrantyEnd.toIso8601String()}',
    actorId: actorId,
  );

  Future<void> approveDisposition(
    RepairJob job, {
    required RefurbishedDisposition disposition,
    required double? resalePrice,
    required String donationRecipient,
    required String actorId,
    required String notes,
  }) => _updateWithProgress(
    job,
    updates: {
      'disposition': disposition.name,
      'dispositionApproved': true,
      'dispositionApprovedBy': actorId,
      'dispositionApprovedAt': FieldValue.serverTimestamp(),
      'dispositionNotes': notes.trim(),
      'resalePrice': disposition == RefurbishedDisposition.resale
          ? resalePrice
          : null,
      'donationRecipient': disposition == RefurbishedDisposition.donation
          ? donationRecipient.trim()
          : '',
    },
    type: 'dispositionApproved',
    details: '${disposition.name}: ${notes.trim()}',
    actorId: actorId,
    progressPercent: 100,
  );

  Future<void> _updateWithProgress(
    RepairJob job, {
    required Map<String, dynamic> updates,
    required String type,
    required String details,
    required String actorId,
    int? progressPercent,
  }) async {
    final jobRef = _jobs.doc(job.id);
    final batch = _db.batch();
    batch.update(jobRef, {
      ...updates,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(jobRef.collection('progress').doc(), {
      'type': type,
      'details': details,
      'progressPercent': progressPercent ?? job.progressPercent,
      'actorId': actorId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }
}
