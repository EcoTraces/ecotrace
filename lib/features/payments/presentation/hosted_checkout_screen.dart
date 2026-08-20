import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/app_currency.dart';
import '../../billing/data/billing_repository.dart';
import '../../billing/domain/billing.dart';
import 'payment_status.dart';

enum HostedGateway { stripe, paypal }

extension HostedGatewayLabel on HostedGateway {
  String get label => switch (this) {
    HostedGateway.stripe => 'card',
    HostedGateway.paypal => 'PayPal',
  };

  /// The gateway's own name, for copy that refers to the provider rather
  /// than the payment method (e.g. "processed securely by Stripe").
  String get providerName => switch (this) {
    HostedGateway.stripe => 'Stripe',
    HostedGateway.paypal => 'PayPal',
  };

  IconData get icon => switch (this) {
    HostedGateway.stripe => Icons.credit_card,
    HostedGateway.paypal => Icons.account_balance_wallet_outlined,
  };
}

/// Collects a card (via Stripe Checkout) or PayPal payment by redirecting to
/// a gateway-hosted page, then watching the same paymentTransactions
/// document (populated by the backend's webhook handlers) that
/// MonimePaymentScreen watches, via Firestore rather than polling.
///
/// Unlike Monime -- where paying happens on the phone's own dialer while the
/// app stays open -- this backgrounds the app into an external browser tab
/// on every platform, since neither gateway's hosted checkout is embeddable
/// in-app across Android/iOS/web/Windows (flutter_stripe in particular has
/// no Windows support at all). The waiting screen below says so explicitly.
class HostedCheckoutScreen extends StatefulWidget {
  const HostedCheckoutScreen({
    super.key,
    required this.repository,
    required this.gateway,
    required this.purpose,
    required this.referenceId,
    required this.amount,
    this.currency = 'SLE',
    this.title,
    this.submitLabel,
  });

  final BillingRepository repository;
  final HostedGateway gateway;
  final String purpose;
  final String referenceId;
  final double amount;
  final String currency;
  final String? title;
  final String? submitLabel;

  @override
  State<HostedCheckoutScreen> createState() => _HostedCheckoutScreenState();
}

class _HostedCheckoutScreenState extends State<HostedCheckoutScreen> {
  bool _submitting = false;
  String? _error;
  String? _transactionId;

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = widget.gateway == HostedGateway.stripe
          ? await widget.repository.initiateStripeCheckout(
              purpose: widget.purpose,
              referenceId: widget.referenceId,
            )
          : await widget.repository.initiatePaypalCheckout(
              purpose: widget.purpose,
              referenceId: widget.referenceId,
            );
      if (result.checkoutUrl.isEmpty) {
        setState(() => _error = 'Could not start the payment: no checkout link was returned.');
        return;
      }
      // externalApplication forces a new tab/window on web instead of
      // navigating the current one away — without this, a same-tab
      // navigation would tear down the Flutter web app and its Firestore
      // listener before the payment status can ever be shown.
      final launched = await launchUrl(
        Uri.parse(result.checkoutUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        setState(() => _error = 'Could not open the payment page.');
        return;
      }
      setState(() => _transactionId = result.id);
    } catch (error) {
      setState(() => _error = 'Could not start the payment: $error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _retry() {
    setState(() {
      _transactionId = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'Pay with ${widget.gateway.label}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _transactionId == null ? _buildForm() : _buildStatus(_transactionId!),
      ),
    );
  }

  Widget _buildForm() {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      children: [
        Center(
          child: PaymentMethodIcon(
            icon: widget.gateway.icon,
            color: widget.gateway == HostedGateway.stripe
                ? scheme.tertiary
                : scheme.secondary,
            size: 56,
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Amount to pay'),
                Text(
                  AppCurrency.format(widget.amount, currencyCode: widget.currency),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          "You'll be taken to ${widget.gateway.providerName} to complete "
          'payment in your browser, then return to this screen.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.submitLabel ?? 'Pay with ${widget.gateway.label}'),
        ),
        const SizedBox(height: 12),
        Center(child: PaymentTrustNote(provider: widget.gateway.providerName)),
      ],
    );
  }

  Widget _buildStatus(String transactionId) {
    return StreamBuilder<BillingTransaction>(
      stream: widget.repository.watchTransaction(transactionId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Theme.of(context).colorScheme.error,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Could not load the payment status: ${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final transaction = snapshot.data!;
        return Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: switch (transaction.status) {
                BillingStatus.confirmed => _success(transaction),
                BillingStatus.failed => _failure(transaction),
                _ => _waiting(transaction),
              },
            ),
          ),
        );
      },
    );
  }

  List<Widget> _waiting(BillingTransaction transaction) => [
    const CircularProgressIndicator(),
    const SizedBox(height: 16),
    Text(
      'Waiting for you to complete the payment…',
      style: Theme.of(context).textTheme.titleMedium,
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 8),
    Text(AppCurrency.format(transaction.total, currencyCode: transaction.currency)),
    const SizedBox(height: 16),
    Text(
      "If you've already completed payment in the browser tab, this will "
      'update automatically — no need to refresh.',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall,
    ),
  ];

  List<Widget> _success(BillingTransaction transaction) => [
    Icon(
      Icons.check_circle,
      color: PaymentStatusVisuals.forStatus(
        'confirmed',
        Theme.of(context).colorScheme,
      ).color,
      size: 64,
    ),
    const SizedBox(height: 16),
    Text('Payment successful', style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 8),
    Text(AppCurrency.format(transaction.total, currencyCode: transaction.currency)),
    if (transaction.providerReference.isNotEmpty)
      Text('Reference: ${transaction.providerReference}'),
    const SizedBox(height: 20),
    FilledButton(
      onPressed: () => Navigator.of(context).pop(transaction),
      child: const Text('Done'),
    ),
  ];

  List<Widget> _failure(BillingTransaction transaction) => [
    Icon(
      Icons.error_outline,
      color: Theme.of(context).colorScheme.error,
      size: 64,
    ),
    const SizedBox(height: 16),
    Text('Payment failed', style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 8),
    Text(
      transaction.failureReason.isEmpty
          ? 'The payment could not be completed.'
          : transaction.failureReason,
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 20),
    FilledButton(onPressed: _retry, child: const Text('Try again')),
  ];
}
