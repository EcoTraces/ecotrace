import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/api/api_client.dart';
import '../domain/monime_payment.dart';

class MonimeInitiateResult {
  const MonimeInitiateResult({required this.id, required this.ussdCode});
  final String id, ussdCode;
}

class MonimePaymentRepository {
  MonimePaymentRepository({FirebaseFirestore? firestore, ApiClient? apiClient})
    : _db = firestore ?? FirebaseFirestore.instance,
      _api = apiClient ?? ApiClient.instance;

  final FirebaseFirestore _db;
  final ApiClient _api;

  /// Initiates a Monime mobile-money payment. Monime credentials are
  /// server-only, so unlike other repositories in this app there is no
  /// direct-Firestore fallback here — this always calls the backend.
  Future<MonimeInitiateResult> initiate({
    required String purpose,
    required String referenceId,
    required double amount,
    required String currency,
    required MonimeProvider provider,
    required String phoneNumber,
  }) async {
    final data = await _api.post('/api/v1/payments/monime/initiate', {
      'purpose': purpose,
      'referenceId': referenceId,
      'amount': amount,
      'currency': currency,
      'provider': provider.apiValue,
      'phoneNumber': phoneNumber.trim(),
    });
    return MonimeInitiateResult(
      id: (data['id'] ?? '').toString(),
      ussdCode: (data['ussdCode'] ?? '').toString(),
    );
  }

  /// Real-time status via a direct Firestore listener, not polling — Monime's
  /// webhook (verified against Monime's own API before it writes anything)
  /// updates this document as the payment progresses.
  Stream<MonimePayment> watch(String transactionId) => _db
      .collection('paymentTransactions')
      .doc(transactionId)
      .snapshots()
      .map(MonimePayment.fromDoc);
}
