import 'package:cloud_firestore/cloud_firestore.dart';

enum RepairStatus {
  awaitingAssessment,
  diagnosed,
  approved,
  repairInProgress,
  qualityTesting,
  completed,
  rejected,
  unrepairable,
}

extension RepairStatusLabel on RepairStatus {
  String get label => switch (this) {
    RepairStatus.awaitingAssessment => 'Awaiting assessment',
    RepairStatus.diagnosed => 'Diagnosed',
    RepairStatus.approved => 'Approved',
    RepairStatus.repairInProgress => 'Repair in progress',
    RepairStatus.qualityTesting => 'Quality testing',
    RepairStatus.completed => 'Completed',
    RepairStatus.rejected => 'Rejected',
    RepairStatus.unrepairable => 'Unrepairable',
  };
}

enum RefurbishmentGrade { gradeA, gradeB, gradeC, partsOnly }

extension RefurbishmentGradeLabel on RefurbishmentGrade {
  String get label => switch (this) {
    RefurbishmentGrade.gradeA => 'Grade A',
    RefurbishmentGrade.gradeB => 'Grade B',
    RefurbishmentGrade.gradeC => 'Grade C',
    RefurbishmentGrade.partsOnly => 'Parts only',
  };
}

enum RefurbishedDisposition { pending, donation, resale }

class RepairJob {
  const RepairJob({
    required this.id,
    required this.itemId,
    required this.itemCode,
    required this.deviceName,
    required this.status,
    required this.assessmentNotes,
    required this.diagnosis,
    required this.faults,
    required this.technicianId,
    required this.estimatedRepairCost,
    required this.actualPartsCost,
    required this.progressPercent,
    required this.qualityChecks,
    required this.qualityNotes,
    required this.grade,
    required this.warrantyStart,
    required this.warrantyEnd,
    required this.disposition,
    required this.dispositionApproved,
    required this.resalePrice,
    required this.donationRecipient,
    required this.createdAt,
    required this.completedAt,
  });

  final String id, itemId, itemCode, deviceName;
  final RepairStatus status;
  final String assessmentNotes, diagnosis, technicianId, qualityNotes;
  final List<String> faults;
  final double estimatedRepairCost, actualPartsCost;
  final int progressPercent;
  final Map<String, bool> qualityChecks;
  final RefurbishmentGrade? grade;
  final DateTime? warrantyStart, warrantyEnd;
  final RefurbishedDisposition disposition;
  final bool dispositionApproved;
  final double? resalePrice;
  final String donationRecipient;
  final DateTime? createdAt, completedAt;

  bool get warrantyActive {
    final end = warrantyEnd;
    return end != null && end.isAfter(DateTime.now());
  }

  double get projectedTotalCost => estimatedRepairCost + actualPartsCost;

  factory RepairJob.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return RepairJob(
      id: doc.id,
      itemId: data['itemId'] ?? '',
      itemCode: data['itemCode'] ?? '',
      deviceName: data['deviceName'] ?? '',
      status: RepairStatus.values.byName(
        data['status'] ?? RepairStatus.awaitingAssessment.name,
      ),
      assessmentNotes: data['assessmentNotes'] ?? '',
      diagnosis: data['diagnosis'] ?? '',
      faults: List<String>.from(data['faults'] as List? ?? const []),
      technicianId: data['technicianId'] ?? '',
      estimatedRepairCost: (data['estimatedRepairCost'] as num? ?? 0)
          .toDouble(),
      actualPartsCost: (data['actualPartsCost'] as num? ?? 0).toDouble(),
      progressPercent: data['progressPercent'] as int? ?? 0,
      qualityChecks: Map<String, bool>.from(
        data['qualityChecks'] as Map? ?? const {},
      ),
      qualityNotes: data['qualityNotes'] ?? '',
      grade: data['refurbishmentGrade'] == null
          ? null
          : RefurbishmentGrade.values.byName(data['refurbishmentGrade']),
      warrantyStart: (data['warrantyStart'] as Timestamp?)?.toDate(),
      warrantyEnd: (data['warrantyEnd'] as Timestamp?)?.toDate(),
      disposition: RefurbishedDisposition.values.byName(
        data['disposition'] ?? RefurbishedDisposition.pending.name,
      ),
      dispositionApproved: data['dispositionApproved'] as bool? ?? false,
      resalePrice: (data['resalePrice'] as num?)?.toDouble(),
      donationRecipient: data['donationRecipient'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
    );
  }

  factory RepairJob.fromJson(Map<String, dynamic> data) => RepairJob(
    id: data['id']?.toString() ?? '',
    itemId: data['itemId']?.toString() ?? '',
    itemCode: data['itemCode']?.toString() ?? '',
    deviceName: data['deviceName']?.toString() ?? '',
    status: RepairStatus.values.byName(
      data['status']?.toString() ?? RepairStatus.awaitingAssessment.name,
    ),
    assessmentNotes: data['assessmentNotes']?.toString() ?? '',
    diagnosis: data['diagnosis']?.toString() ?? '',
    faults: List<String>.from(data['faults'] as List? ?? const []),
    technicianId: data['technicianId']?.toString() ?? '',
    estimatedRepairCost: (data['estimatedRepairCost'] as num? ?? 0).toDouble(),
    actualPartsCost: (data['actualPartsCost'] as num? ?? 0).toDouble(),
    progressPercent: (data['progressPercent'] as num? ?? 0).toInt(),
    qualityChecks: Map<String, bool>.from(
      data['qualityChecks'] as Map? ?? const {},
    ),
    qualityNotes: data['qualityNotes']?.toString() ?? '',
    grade: data['refurbishmentGrade'] == null
        ? null
        : RefurbishmentGrade.values.byName(
            data['refurbishmentGrade'].toString(),
          ),
    warrantyStart: _apiDate(data['warrantyStart']),
    warrantyEnd: _apiDate(data['warrantyEnd']),
    disposition: RefurbishedDisposition.values.byName(
      data['disposition']?.toString() ?? RefurbishedDisposition.pending.name,
    ),
    dispositionApproved: data['dispositionApproved'] as bool? ?? false,
    resalePrice: (data['resalePrice'] as num?)?.toDouble(),
    donationRecipient: data['donationRecipient']?.toString() ?? '',
    createdAt: _apiDate(data['createdAt']),
    completedAt: _apiDate(data['completedAt']),
  );
}

class SparePartUsage {
  const SparePartUsage({
    required this.id,
    required this.name,
    required this.partNumber,
    required this.quantity,
    required this.unitCost,
    required this.recordedBy,
    required this.recordedAt,
  });
  final String id, name, partNumber, recordedBy;
  final int quantity;
  final double unitCost;
  final DateTime? recordedAt;
  double get totalCost => quantity * unitCost;

  factory SparePartUsage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return SparePartUsage(
      id: doc.id,
      name: data['name'] ?? '',
      partNumber: data['partNumber'] ?? '',
      quantity: data['quantity'] as int? ?? 0,
      unitCost: (data['unitCost'] as num? ?? 0).toDouble(),
      recordedBy: data['recordedBy'] ?? '',
      recordedAt: (data['recordedAt'] as Timestamp?)?.toDate(),
    );
  }
  factory SparePartUsage.fromJson(Map<String, dynamic> data) => SparePartUsage(
    id: data['id']?.toString() ?? '',
    name: data['name']?.toString() ?? '',
    partNumber: data['partNumber']?.toString() ?? '',
    quantity: (data['quantity'] as num? ?? 0).toInt(),
    unitCost: (data['unitCost'] as num? ?? 0).toDouble(),
    recordedBy: data['recordedBy']?.toString() ?? '',
    recordedAt: _apiDate(data['recordedAt']),
  );
}

class RepairProgressEvent {
  const RepairProgressEvent({
    required this.type,
    required this.details,
    required this.progressPercent,
    required this.actorId,
    required this.at,
  });
  final String type, details, actorId;
  final int progressPercent;
  final DateTime? at;

  factory RepairProgressEvent.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return RepairProgressEvent(
      type: data['type'] ?? '',
      details: data['details'] ?? '',
      progressPercent: data['progressPercent'] as int? ?? 0,
      actorId: data['actorId'] ?? '',
      at: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
  factory RepairProgressEvent.fromJson(Map<String, dynamic> data) =>
      RepairProgressEvent(
        type: data['type']?.toString() ?? '',
        details: data['details']?.toString() ?? '',
        progressPercent: (data['progressPercent'] as num? ?? 0).toInt(),
        actorId: data['actorId']?.toString() ?? '',
        at: _apiDate(data['createdAt']),
      );
}

DateTime? _apiDate(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
