import 'package:flutter/material.dart';

/// Canonical status visuals (icon + semantic color + label) shared by every
/// payment surface (Monime, hosted checkout, billing history) so "confirmed"
/// or "failed" looks and reads the same everywhere, no matter which of the
/// three gateway-specific status enums produced it. Accepts the raw status
/// string (each status enum's `.name` already matches these keys) rather
/// than a shared enum type, since Monime/Billing status sets don't fully
/// overlap and forcing one enum onto both would be the wrong abstraction.
class PaymentStatusVisuals {
  const PaymentStatusVisuals({
    required this.icon,
    required this.label,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color background;

  factory PaymentStatusVisuals.forStatus(String status, ColorScheme scheme) {
    switch (status) {
      case 'confirmed':
      case 'paid':
      case 'partiallyRefunded':
        return PaymentStatusVisuals(
          icon: Icons.check_circle,
          label: switch (status) {
            'paid' => 'Paid',
            'partiallyRefunded' => 'Partially refunded',
            _ => 'Confirmed',
          },
          color: const Color(0xFF2E7D4F),
          background: const Color(0xFFE3F5EA),
        );
      case 'failed':
      case 'cancelled':
      case 'overdue':
        return PaymentStatusVisuals(
          icon: Icons.error,
          label: switch (status) {
            'cancelled' => 'Cancelled',
            'overdue' => 'Overdue',
            _ => 'Failed',
          },
          color: scheme.error,
          background: scheme.errorContainer,
        );
      case 'refunded':
        return PaymentStatusVisuals(
          icon: Icons.replay_circle_filled,
          label: 'Refunded',
          color: scheme.tertiary,
          background: scheme.tertiaryContainer,
        );
      case 'processing':
      case 'partiallyPaid':
        return PaymentStatusVisuals(
          icon: Icons.autorenew,
          label: status == 'partiallyPaid' ? 'Partially paid' : 'Processing',
          color: scheme.secondary,
          background: scheme.secondaryContainer,
        );
      default: // pending, refundPending, draft, issued
        return PaymentStatusVisuals(
          icon: Icons.schedule,
          label: status == 'issued' ? 'Issued' : 'Pending',
          color: scheme.onSurfaceVariant,
          background: scheme.surfaceContainerHighest,
        );
    }
  }
}

/// A compact status pill for list rows (billing history), pairing color with
/// an icon and text label so status is never conveyed by color alone.
class PaymentStatusChip extends StatelessWidget {
  const PaymentStatusChip({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final visuals = PaymentStatusVisuals.forStatus(
      status,
      Theme.of(context).colorScheme,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: visuals.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(visuals.icon, size: 14, color: visuals.color),
          const SizedBox(width: 4),
          Text(
            visuals.label,
            style: TextStyle(
              color: visuals.color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A tonal icon circle used for payment-method affordances (the method
/// picker, billing-history row leading icon) so every method reads as part
/// of one consistent family rather than bare, ungrouped icons.
class PaymentMethodIcon extends StatelessWidget {
  const PaymentMethodIcon({
    super.key,
    required this.icon,
    required this.color,
    this.size = 44,
  });
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

/// A small reassurance line placed near the pay button on every gateway
/// screen -- a standard checkout trust signal that was previously missing
/// entirely. Never claims a specific certification EcoTrace hasn't verified;
/// it only states what's structurally true (the gateway processes it, this
/// app never sees full card/account details).
class PaymentTrustNote extends StatelessWidget {
  const PaymentTrustNote({super.key, required this.provider});
  final String provider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lock_outline, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Payment is processed securely by $provider. EcoTrace never '
            'sees or stores your card or account details.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
