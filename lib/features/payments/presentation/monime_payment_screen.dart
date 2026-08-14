import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../../../core/app_currency.dart';
import '../data/monime_payment_repository.dart';
import '../domain/monime_payment.dart';

/// Collects a mobile-money payment through Monime: pick a provider, enter the
/// phone number, submit, then watch the payment reach a final state in real
/// time via a Firestore listener (populated by the backend's Monime webhook
/// handler) rather than by polling.
class MonimePaymentScreen extends StatefulWidget {
  const MonimePaymentScreen({
    super.key,
    required this.repository,
    this.purpose = 'other',
    this.referenceId,
    this.amount,
    this.currency = 'SLE',
  });

  final MonimePaymentRepository repository;
  final String purpose;
  final String? referenceId;
  final double? amount;
  final String currency;

  @override
  State<MonimePaymentScreen> createState() => _MonimePaymentScreenState();
}

class _MonimePaymentScreenState extends State<MonimePaymentScreen> {
  late final TextEditingController _referenceController;
  late final TextEditingController _amountController;
  final _phoneController = TextEditingController();
  MonimeProvider _provider = MonimeProvider.orangeMoney;
  bool _submitting = false;
  String? _error;
  String? _transactionId;

  @override
  void initState() {
    super.initState();
    _referenceController = TextEditingController(text: widget.referenceId ?? '');
    _amountController = TextEditingController(
      text: widget.amount == null ? '' : widget.amount!.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _referenceController.dispose();
    _amountController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountController.text.trim());
    final reference = _referenceController.text.trim();
    final phone = _phoneController.text.trim();
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }
    if (reference.isEmpty) {
      setState(() => _error = 'A reference is required.');
      return;
    }
    if (!RegExp(r'^\+?[0-9]{8,15}$').hasMatch(phone)) {
      setState(() => _error = 'Enter a valid mobile money phone number.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await widget.repository.initiate(
        purpose: widget.purpose,
        referenceId: reference,
        amount: amount,
        currency: widget.currency,
        provider: _provider,
        phoneNumber: phone,
      );
      setState(() => _transactionId = result.id);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
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
      appBar: AppBar(title: const Text('Pay with mobile money')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _transactionId == null ? _buildForm() : _buildStatus(_transactionId!),
      ),
    );
  }

  Widget _buildForm() {
    return ListView(
      children: [
        SegmentedButton<MonimeProvider>(
          segments: MonimeProvider.values
              .map(
                (provider) => ButtonSegment(
                  value: provider,
                  label: Text(provider.label),
                ),
              )
              .toList(),
          selected: {_provider},
          onSelectionChanged: (selection) =>
              setState(() => _provider = selection.first),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Amount (${widget.currency})',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _referenceController,
          decoration: const InputDecoration(labelText: 'Payment reference'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: '${_provider.label} phone number',
            hintText: '+2327XXXXXXXX',
          ),
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
              : Text('Pay with ${_provider.label}'),
        ),
      ],
    );
  }

  Widget _buildStatus(String transactionId) {
    return StreamBuilder<MonimePayment>(
      stream: widget.repository.watch(transactionId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final payment = snapshot.data!;
        return Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: switch (payment.status) {
                MonimePaymentStatus.confirmed => _success(payment),
                MonimePaymentStatus.failed => _failure(payment),
                _ => _waiting(payment),
              },
            ),
          ),
        );
      },
    );
  }

  List<Widget> _waiting(MonimePayment payment) => [
    const CircularProgressIndicator(),
    const SizedBox(height: 16),
    Text(
      payment.status == MonimePaymentStatus.processing
          ? 'Confirming your payment…'
          : 'Waiting for you to approve the payment…',
      style: Theme.of(context).textTheme.titleMedium,
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 8),
    Text(
      AppCurrency.format(payment.amount, currencyCode: payment.currency),
    ),
    if (payment.ussdCode.isNotEmpty) ...[
      const SizedBox(height: 20),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text(
                "If you don't get a payment prompt automatically, "
                'dial this code to complete the payment:',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              SelectableText(
                payment.ussdCode,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ],
          ),
        ),
      ),
    ],
  ];

  List<Widget> _success(MonimePayment payment) => [
    Icon(Icons.check_circle, color: Colors.green.shade600, size: 64),
    const SizedBox(height: 16),
    Text('Payment successful', style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 8),
    Text(AppCurrency.format(payment.amount, currencyCode: payment.currency)),
    if (payment.providerReference.isNotEmpty)
      Text('Reference: ${payment.providerReference}'),
    const SizedBox(height: 20),
    FilledButton(
      onPressed: () => Navigator.of(context).pop(payment),
      child: const Text('Done'),
    ),
  ];

  List<Widget> _failure(MonimePayment payment) => [
    Icon(
      Icons.error_outline,
      color: Theme.of(context).colorScheme.error,
      size: 64,
    ),
    const SizedBox(height: 16),
    Text('Payment failed', style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 8),
    Text(
      monimeFailureMessage(payment.failureReason),
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 20),
    FilledButton(onPressed: _retry, child: const Text('Try again')),
  ];
}
