import 'package:cloud_firestore/cloud_firestore.dart';

enum BillingPurpose {
  pickupFee,
  marketplaceOrder,
  partnerPayout,
  collectorPayment,
  serviceFee,
  rewardAdjustment,
  refund,
}

enum BillingMethod { mobileMoney, bankTransfer, card, manual }

enum PaymentMethod { mobileMoney, bankTransfer, card, manual }

enum BillingStatus {
  draft,
  pending,
  processing,
  confirmed,
  failed,
  cancelled,
  refundPending,
  refunded,
}

enum InvoiceStatus { issued, partiallyPaid, paid, overdue, cancelled, refunded }

class ChargeBreakdown {
  const ChargeBreakdown({
    required this.subtotal,
    required this.taxRate,
    required this.serviceChargeRate,
  });
  final double subtotal, taxRate, serviceChargeRate;
  double get tax => subtotal * taxRate / 100;
  double get serviceCharge => subtotal * serviceChargeRate / 100;
  double get total => subtotal + tax + serviceCharge;
  factory ChargeBreakdown.pickup({
    required int quantity,
    required double weightKg,
    required bool urgent,
    double taxRate = 0,
    double serviceChargeRate = 5,
  }) => ChargeBreakdown(
    subtotal: 5 + quantity * 1.5 + weightKg * .35 + (urgent ? 10 : 0),
    taxRate: taxRate,
    serviceChargeRate: serviceChargeRate,
  );
}

class BillingTotals {
  const BillingTotals({
    required this.subtotal,
    required this.tax,
    required this.serviceCharge,
  });
  final double subtotal, tax, serviceCharge;
  double get total => subtotal + tax + serviceCharge;
  factory BillingTotals.calculate({
    required double subtotal,
    required double taxRatePercent,
    required double serviceChargePercent,
  }) {
    if (subtotal < 0 || taxRatePercent < 0 || serviceChargePercent < 0) {
      throw ArgumentError('Billing rates cannot be negative.');
    }
    return BillingTotals(
      subtotal: subtotal,
      tax: subtotal * taxRatePercent / 100,
      serviceCharge: subtotal * serviceChargePercent / 100,
    );
  }
  factory BillingTotals.pickup({
    required int quantity,
    required double weight,
    required bool urgent,
    required double taxRatePercent,
    required double serviceChargePercent,
  }) => BillingTotals.calculate(
    subtotal: 10 + quantity * 1.5 + weight * .35 + (urgent ? 10 : 0),
    taxRatePercent: taxRatePercent,
    serviceChargePercent: serviceChargePercent,
  );
}

class BillingTransaction {
  const BillingTransaction({
    required this.id,
    required this.number,
    required this.purpose,
    required this.payerId,
    required this.payeeId,
    required this.referenceId,
    required this.method,
    required this.status,
    required this.subtotal,
    required this.tax,
    required this.serviceCharge,
    required this.total,
    required this.currency,
    required this.providerReference,
    required this.maskedAccount,
    required this.failureReason,
    required this.createdAt,
  });
  final String id,
      number,
      payerId,
      payeeId,
      referenceId,
      currency,
      providerReference,
      maskedAccount,
      failureReason;
  final BillingPurpose purpose;
  final BillingMethod method;
  final BillingStatus status;
  final double subtotal, tax, serviceCharge, total;
  final DateTime? createdAt;
  factory BillingTransaction.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final x = d.data()!;
    return BillingTransaction(
      id: d.id,
      number: x['transactionNumber'] ?? d.id,
      purpose: BillingPurpose.values.byName(x['purpose']),
      payerId: x['payerId'] ?? '',
      payeeId: x['payeeId'] ?? '',
      referenceId: x['referenceId'] ?? '',
      method: BillingMethod.values.byName(x['method'] ?? 'manual'),
      status: BillingStatus.values.byName(x['status'] ?? 'pending'),
      subtotal: (x['subtotal'] as num? ?? 0).toDouble(),
      tax: (x['tax'] as num? ?? 0).toDouble(),
      serviceCharge: (x['serviceCharge'] as num? ?? 0).toDouble(),
      total: (x['total'] as num? ?? 0).toDouble(),
      currency: x['currency'] ?? 'SLE',
      providerReference: x['providerReference'] ?? '',
      maskedAccount: x['maskedAccount'] ?? '',
      failureReason: x['failureReason'] ?? '',
      createdAt: (x['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class BillingInvoice {
  const BillingInvoice({
    required this.id,
    required this.number,
    required this.customerId,
    required this.description,
    required this.amount,
    required this.currency,
    required this.status,
    required this.dueAt,
  });
  final String id, number, customerId, description, currency;
  final double amount;
  final InvoiceStatus status;
  final DateTime? dueAt;
  factory BillingInvoice.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final x = d.data()!;
    return BillingInvoice(
      id: d.id,
      number: x['invoiceNumber'] ?? d.id,
      customerId: x['customerId'] ?? '',
      description: x['description'] ?? '',
      amount: (x['amount'] as num? ?? 0).toDouble(),
      currency: x['currency'] ?? 'SLE',
      status: InvoiceStatus.values.byName(x['status'] ?? 'issued'),
      dueAt: (x['dueAt'] as Timestamp?)?.toDate(),
    );
  }
}

class ReconciliationSummary {
  const ReconciliationSummary({
    required this.expected,
    required this.confirmed,
    required this.failed,
    required this.refunded,
    this.payouts = 0,
  });
  final double expected, confirmed, refunded, failed, payouts;
  double get variance => expected - confirmed - failed;
  double get netCash => confirmed - refunded - payouts;
  factory ReconciliationSummary.from(List<BillingTransaction> x) =>
      ReconciliationSummary(
        expected: x.fold(0, (s, t) => s + t.total),
        confirmed: x
            .where((t) => t.status == BillingStatus.confirmed)
            .fold(0, (s, t) => s + t.total),
        refunded: x
            .where((t) => t.status == BillingStatus.refunded)
            .fold(0, (s, t) => s + t.total),
        failed: x
            .where((t) => t.status == BillingStatus.failed)
            .fold(0, (s, t) => s + t.total),
      );
}
