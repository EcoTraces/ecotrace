import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';
import '../../audit/data/audit_repository.dart';
import '../../audit/domain/audit_event.dart';
import '../domain/billing.dart';

class BillingRepository {
  BillingRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    AuditRepository? auditRepository,
    ApiClient? apiClient,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _api = apiClient ?? ApiClient.instance,
       _useApi = apiClient != null || (firestore == null && ApiConfig.enabled) {
    _audit = auditRepository ?? AuditRepository(firestore: _db, auth: _auth);
  }
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final ApiClient _api;
  final bool _useApi;
  late final AuditRepository _audit;

  Stream<List<BillingTransaction>> watchTransactions(String userId, bool all) =>
      _useApi
      ? _pollList('/api/v1/payments/transactions', BillingTransaction.fromJson)
      : (all
                ? _db.collection('paymentTransactions')
                : _db
                      .collection('paymentTransactions')
                      .where('participantIds', arrayContains: userId))
            .snapshots()
            .map((s) => s.docs.map(BillingTransaction.fromDoc).toList());
  Stream<List<BillingInvoice>> watchInvoices(String userId, bool all) =>
      _useApi
      ? _pollList('/api/v1/payments/invoices', BillingInvoice.fromJson)
      : (all
                ? _db.collection('invoices')
                : _db
                      .collection('invoices')
                      .where('customerId', isEqualTo: userId))
            .snapshots()
            .map((s) => s.docs.map(BillingInvoice.fromDoc).toList());

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

  Future<void> createPayment({
    required BillingPurpose purpose,
    required String payerId,
    required String payeeId,
    required String referenceId,
    required BillingMethod method,
    required ChargeBreakdown charge,
    required String currency,
    required String provider,
    required String maskedAccount,
  }) async {
    if (referenceId.isEmpty || charge.total < 0) {
      throw StateError('Invalid billing transaction.');
    }
    if (_useApi) {
      await _api.post('/api/v1/payments/intents', {
        'purpose': _apiPurpose(purpose),
        'referenceId': referenceId.trim(),
        'amount': charge.total,
        'currency': currency.trim().isEmpty ? 'SLE' : currency.trim(),
        'method': _apiMethod(method),
        'provider': provider.trim(),
        'payerPhoneOrReference': maskedAccount.trim(),
      });
      return;
    }
    final duplicate = await _db
        .collection('paymentTransactions')
        .where('referenceId', isEqualTo: referenceId)
        .where('purpose', isEqualTo: purpose.name)
        .limit(1)
        .get();
    if (duplicate.docs.isNotEmpty) {
      throw StateError('This reference has already been billed.');
    }
    final document = await _db.collection('paymentTransactions').add({
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
      'providerReference': '',
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

  static String _apiPurpose(BillingPurpose purpose) => switch (purpose) {
    BillingPurpose.pickupFee => 'pickupFee',
    BillingPurpose.marketplaceOrder => 'marketplaceOrder',
    BillingPurpose.serviceFee => 'partnerService',
    _ => 'other',
  };

  static String _apiMethod(BillingMethod method) => switch (method) {
    BillingMethod.bankTransfer => 'bank',
    BillingMethod.card => 'card',
    _ => 'mobileMoney',
  };

  Future<void> confirm(
    BillingTransaction t,
    String actor, {
    String providerReference = '',
  }) async {
    if (_useApi) {
      if (providerReference.trim().length < 2) {
        throw StateError('A provider reference is required to confirm a payment.');
      }
      await _api.patch('/api/v1/payments/transactions/${t.id}/confirm', {
        'providerReference': providerReference.trim(),
        'providerStatus': 'successful',
        'failureReason': '',
      });
      return;
    }
    await _db.collection('paymentTransactions').doc(t.id).update({
      'status': BillingStatus.confirmed.name,
      'confirmedBy': actor,
      'confirmedAt': FieldValue.serverTimestamp(),
    });
    await _recordStatus(t, BillingStatus.confirmed);
  }

  Future<void> fail(
    BillingTransaction t,
    String reason, {
    String providerReference = '',
  }) async {
    if (_useApi) {
      if (providerReference.trim().length < 2) {
        throw StateError('A provider reference is required to mark a payment failed.');
      }
      await _api.patch('/api/v1/payments/transactions/${t.id}/confirm', {
        'providerReference': providerReference.trim(),
        'providerStatus': 'failed',
        'failureReason': reason.trim().isEmpty
            ? 'Provider declined transaction'
            : reason.trim(),
      });
      return;
    }
    await _db.collection('paymentTransactions').doc(t.id).update({
      'status': BillingStatus.failed.name,
      'failureReason': reason.trim(),
      'failedAt': FieldValue.serverTimestamp(),
    });
    await _recordStatus(t, BillingStatus.failed, reason: reason);
  }

  Future<void> refund(
    BillingTransaction t,
    String actor, {
    double? amount,
    String reason = '',
  }) async {
    if (_useApi) {
      final refundAmount = amount ?? t.total;
      if (refundAmount <= 0) {
        throw StateError('The refund amount must be greater than zero.');
      }
      if (reason.trim().length < 2) {
        throw StateError('A refund reason is required.');
      }
      await _api.post('/api/v1/payments/transactions/${t.id}/refunds', {
        'amount': refundAmount,
        'reason': reason.trim(),
      });
      return;
    }
    await _db.collection('paymentTransactions').doc(t.id).update({
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
  }) async {
    if (_useApi) {
      await _api.post('/api/v1/payments/invoices', {
        'referenceType': 'other',
        'referenceId': 'invoice-${DateTime.now().millisecondsSinceEpoch}',
        'customerId': customerId.trim(),
        'lineItems': [
          {
            'description': description.trim(),
            'quantity': 1,
            'unitPrice': amount,
          },
        ],
        'currency': currency.trim().isEmpty ? 'SLE' : currency.trim(),
        'taxRate': 0.15,
        'dueAt': dueAt.toUtc().toIso8601String(),
      });
      return;
    }
    await _db.collection('invoices').add({
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
}
