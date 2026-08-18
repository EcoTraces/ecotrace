final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Returns an error message if [value] isn't a plausible email address,
/// or null if it's fine.
String? emailError(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'Enter your email.';
  if (!_emailPattern.hasMatch(trimmed)) return 'Enter a valid email address.';
  return null;
}

/// Strips everything but digits (and a leading +) so phone numbers typed
/// with dashes, spaces, or parentheses all normalize to the same format
/// before they reach the backend.
String normalizePhone(String raw) {
  final trimmed = raw.trim();
  final hasPlus = trimmed.startsWith('+');
  final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  return hasPlus ? '+$digits' : digits;
}

/// Returns an error message if [raw], once normalized, isn't a plausible
/// phone number, or null if it's fine.
String? phoneError(String raw) {
  final digitCount = normalizePhone(raw).replaceAll('+', '').length;
  if (digitCount == 0) return 'Enter a contact phone number.';
  if (digitCount < 8 || digitCount > 15) return 'Enter a valid phone number.';
  return null;
}

class PasswordRequirement {
  const PasswordRequirement(this.label, this.met);
  final String label;
  final bool Function(String value) met;
}

final passwordRequirements = <PasswordRequirement>[
  PasswordRequirement('At least 8 characters', (v) => v.length >= 8),
  PasswordRequirement(
    'An uppercase letter',
    (v) => v.contains(RegExp(r'[A-Z]')),
  ),
  PasswordRequirement(
    'A lowercase letter',
    (v) => v.contains(RegExp(r'[a-z]')),
  ),
  PasswordRequirement('A number', (v) => v.contains(RegExp(r'[0-9]'))),
];

bool passwordMeetsRequirements(String value) =>
    passwordRequirements.every((requirement) => requirement.met(value));
