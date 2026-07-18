import 'package:flutter_test/flutter_test.dart';
import 'package:wastemanagementsystem/features/billing/domain/billing.dart';

void main() {
  test('pickup billing includes base fee tax and service charge', () {
    final x = BillingTotals.pickup(
      quantity: 2,
      weight: 10,
      urgent: true,
      taxRatePercent: 10,
      serviceChargePercent: 5,
    );
    expect(x.subtotal, 26.5);
    expect(x.tax, 2.65);
    expect(x.serviceCharge, 1.325);
    expect(x.total, closeTo(30.475, .001));
  });
  test('billing rejects negative rates', () {
    expect(
      () => BillingTotals.calculate(
        subtotal: 10,
        taxRatePercent: -1,
        serviceChargePercent: 0,
      ),
      throwsArgumentError,
    );
  });
  test('reconciliation calculates variance and net cash', () {
    const s = ReconciliationSummary(
      expected: 100,
      confirmed: 80,
      failed: 10,
      refunded: 5,
      payouts: 20,
    );
    expect(s.variance, 10);
    expect(s.netCash, 55);
  });
  test('payment methods cover integrations', () {
    expect(PaymentMethod.values, contains(PaymentMethod.mobileMoney));
    expect(PaymentMethod.values, contains(PaymentMethod.bankTransfer));
    expect(PaymentMethod.values, contains(PaymentMethod.card));
  });
}
