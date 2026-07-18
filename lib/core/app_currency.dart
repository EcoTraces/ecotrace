abstract final class AppCurrency {
  static const code = 'SLE';
  static const symbol = 'Le';
  static const name = 'Sierra Leone leone';

  static String format(
    num amount, {
    String currencyCode = code,
    int fractionDigits = 2,
  }) {
    final normalized = currencyCode.trim().toUpperCase();
    final prefix = normalized == code ? symbol : normalized;
    return '$prefix ${amount.toStringAsFixed(fractionDigits)}';
  }

  static String inputLabel(String label) => '$label ($symbol)';
}
