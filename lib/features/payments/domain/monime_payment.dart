import 'package:cloud_firestore/cloud_firestore.dart';

enum MonimeProvider { orangeMoney, afrimoney }

extension MonimeProviderLabel on MonimeProvider {
  String get label => switch (this) {
    MonimeProvider.orangeMoney => 'Orange Money',
    MonimeProvider.afrimoney => 'Afrimoney',
  };
  String get apiValue => name;
}

enum MonimePaymentStatus { pending, processing, confirmed, failed }

class MonimePayment {
  const MonimePayment({
    required this.id,
    required this.status,
    required this.amount,
    required this.currency,
    required this.provider,
    required this.ussdCode,
    required this.failureReason,
    required this.providerReference,
    this.expireTime,
  });

  final String id,
      currency,
      provider,
      ussdCode,
      failureReason,
      providerReference;
  final MonimePaymentStatus status;
  final double amount;
  final DateTime? expireTime;

  factory MonimePayment.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    final monime = Map<String, dynamic>.from(
      data['monime'] as Map? ?? const {},
    );
    return MonimePayment(
      id: doc.id,
      status: _status(data['status']?.toString()),
      amount: (data['amount'] as num? ?? 0).toDouble(),
      currency: (data['currency'] ?? 'SLE').toString(),
      provider: (data['provider'] ?? '').toString(),
      ussdCode: (monime['ussdCode'] ?? '').toString(),
      failureReason: (data['failureReason'] ?? '').toString(),
      providerReference: (data['providerReference'] ?? '').toString(),
      expireTime: _date(monime['expireTime']),
    );
  }
}

MonimePaymentStatus _status(String? value) {
  switch (value) {
    case 'processing':
      return MonimePaymentStatus.processing;
    case 'confirmed':
      return MonimePaymentStatus.confirmed;
    case 'failed':
      return MonimePaymentStatus.failed;
    default:
      return MonimePaymentStatus.pending;
  }
}

DateTime? _date(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value);
  return null;
}

/// A user-friendly explanation for a failed Monime payment. Monime's Payment
/// Code resource only distinguishes "expired" and "cancelled" as terminal
/// failure states at the API level used here — it does not expose granular
/// reasons like insufficient funds or wrong number, so those cannot be shown.
String monimeFailureMessage(String failureReason) {
  final reason = failureReason.toLowerCase();
  if (reason.contains('expired')) {
    return 'The payment window expired before it was completed. Please try again.';
  }
  if (reason.contains('cancelled')) {
    return 'The payment was cancelled.';
  }
  return failureReason.isEmpty
      ? 'The payment could not be completed.'
      : failureReason;
}
