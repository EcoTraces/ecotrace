import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../audit/data/audit_repository.dart';
import '../../audit/domain/audit_event.dart';
import '../domain/billing.dart';

class BillingRepository {
  BillingRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    AuditRepository? auditRepository,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance {
    _audit = auditRepository ?? AuditRepository(firestore: _db, auth: _auth);
  }
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  late final AuditRepository _audit;
  Stream<List<BillingTransaction>> watchTransactions(String userId, bool all) =>
      (all
              ? _db.collection('billingTransactions')
              : _db
                    .collection('billingTransactions')
                    .where('participantIds', arrayContains: userId))
          .snapshots()
          .map((s) => s.docs.map(BillingTransaction.fromDoc).toList());
  Stream<List<BillingInvoice>> watchInvoices(String userId, bool all) =>
      (all
              ? _db.collection('billingInvoices')
              : _db
                    .collection('billingInvoices')
                    .where('customerId', isEqualTo: userId))
          .snapshots()
          .map((s) => s.docs.map(BillingInvoice.fromDoc).toList());
  Future<void> createPayment({
    required BillingPurpose purpose,
    required String payerId,
    required String payeeId,
    required String referenceId,
    required BillingMethod method,
    required ChargeBreakdown charge,
    required String currency,
    required String providerReference,
    required String maskedAccount,
  }) async {
    if (referenceId.isEmpty || charge.total < 0) {
      throw StateError('Invalid billing transaction.');
    }
    final duplicate = await _db
        .collection('billingTransactions')
        .where('referenceId', isEqualTo: referenceId)
        .where('purpose', isEqualTo: purpose.name)
        .limit(1)
        .get();
    if (duplicate.docs.isNotEmpty) {
      throw StateError('This reference has already been billed.');
    }
    final document = await _db.collection('billingTransactions').add({
      'transactionNumber': 'PAY-${DateTime.now().millisecondsSinceEpoch}',
      'purpose': purpose.name,
      'payerId': payerId,
      'payeeId': payeeId,
      'participantIds': [payerId, payeeId],
      'referenceId': referenceId,
      'method': method.name,
      'status': BillingStatus.pending.name,
      'subtotal': charge.subtotal,
      'tax': charge.tax,
      'serviceCharge': charge.serviceCharge,
      'total': charge.total,
      'currency': currency,
      'providerReference': providerReference.trim(),
      'maskedAccount': maskedAccount.trim(),
      'failureReason': '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _audit.record(
      action: AuditAction.payment,
      entityType: 'billingTransaction',
      entityId: document.id,
      description: 'Payment initiated for ${purpose.name}.',
      changes: {'status': BillingStatus.pending.name, 'total': charge.total},
    );
  }

  Future<void> confirm(BillingTransaction t, String actor) async {
    await _db.collection('billingTransactions').doc(t.id).update({
      'status': BillingStatus.confirmed.name,
      'confirmedBy': actor,
      'confirmedAt': FieldValue.serverTimestamp(),
    });
    await _recordStatus(t, BillingStatus.confirmed);
  }

  Future<void> fail(BillingTransaction t, String reason) async {
    await _db.collection('billingTransactions').doc(t.id).update({
      'status': BillingStatus.failed.name,
      'failureReason': reason.trim(),
      'failedAt': FieldValue.serverTimestamp(),
    });
    await _recordStatus(t, BillingStatus.failed, reason: reason);
  }

  Future<void> refund(BillingTransaction t, String actor) async {
    await _db.collection('billingTransactions').doc(t.id).update({
      'status': BillingStatus.refunded.name,
      'refundedBy': actor,
      'refundedAt': FieldValue.serverTimestamp(),
    });
    await _recordStatus(t, BillingStatus.refunded);
  }

  Future<void> _recordStatus(
    BillingTransaction transaction,
    BillingStatus status, {
    String reason = '',
  }) => _audit.record(
    action: AuditAction.payment,
    entityType: 'billingTransaction',
    entityId: transaction.id,
    description: 'Payment marked ${status.name}.',
    changes: {
      'status': {'before': transaction.status.name, 'after': status.name},
      if (reason.trim().isNotEmpty) 'reason': reason.trim(),
    },
    severity: status == BillingStatus.failed
        ? AuditSeverity.warning
        : AuditSeverity.notice,
  );
  Future<void> invoice({
    required String customerId,
    required String description,
    required double amount,
    required String currency,
    required DateTime dueAt,
  }) => _db.collection('billingInvoices').add({
    'invoiceNumber': 'INV-${DateTime.now().millisecondsSinceEpoch}',
    'customerId': customerId,
    'description': description,
    'amount': amount,
    'currency': currency,
    'status': InvoiceStatus.issued.name,
    'dueAt': Timestamp.fromDate(dueAt),
    'createdAt': FieldValue.serverTimestamp(),
  });
}
