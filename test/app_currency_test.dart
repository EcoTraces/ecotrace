import 'package:flutter_test/flutter_test.dart';
import 'package:wastemanagementsystem/core/app_currency.dart';

void main() {
  test('formats Sierra Leone leones with the legal Le prefix', () {
    expect(AppCurrency.code, 'SLE');
    expect(AppCurrency.format(1250), 'Le 1250.00');
    expect(AppCurrency.inputLabel('Amount'), 'Amount (Le)');
  });

  test('preserves explicit legacy currency codes when reading old records', () {
    expect(AppCurrency.format(10, currencyCode: 'USD'), 'USD 10.00');
  });
}
