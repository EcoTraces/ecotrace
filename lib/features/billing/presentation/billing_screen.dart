import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/app_currency.dart';
import '../../payments/data/monime_payment_repository.dart';
import '../../payments/presentation/monime_payment_screen.dart';
import '../data/billing_repository.dart';
import '../domain/billing.dart';

class BillingScreen extends StatelessWidget {
  const BillingScreen({
    super.key,
    required this.repository,
    required this.userId,
    required this.canManage,
  });
  final BillingRepository repository;
  final String userId;
  final bool canManage;
  @override
  Widget build(BuildContext c) => StreamBuilder<List<BillingTransaction>>(
    stream: repository.watchTransactions(userId, canManage),
    builder: (c, t) => StreamBuilder<List<BillingInvoice>>(
      stream: repository.watchInvoices(userId, canManage),
      builder: (c, i) {
        if (!t.hasData || !i.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final rec = ReconciliationSummary.from(t.data!);
        return Scaffold(
          appBar: AppBar(title: const Text('Payments and billing')),
          floatingActionButton: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FloatingActionButton.extended(
                heroTag: 'monimePayment',
                onPressed: () => _monimePayment(c),
                icon: const Icon(Icons.phone_android),
                label: const Text('Pay with mobile money'),
              ),
              const SizedBox(height: 12),
              FloatingActionButton.extended(
                heroTag: 'manualPayment',
                onPressed: () => _payment(c),
                icon: const Icon(Icons.payment),
                label: const Text('New payment'),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (canManage)
                Wrap(
                  spacing: 8,
                  children: [
                    _m('Expected', rec.expected),
                    _m('Confirmed', rec.confirmed),
                    _m('Refunded', rec.refunded),
                    _m('Variance', rec.variance),
                    FilledButton.tonal(
                      onPressed: () => _invoice(c),
                      child: const Text('Generate invoice'),
                    ),
                  ],
                ),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Card, mobile-money and bank credentials are handled by the payment provider. EcoTrace stores only masked account information and provider transaction references.',
                  ),
                ),
              ),
              Text(
                'Transaction history',
                style: Theme.of(c).textTheme.titleLarge,
              ),
              for (final x in t.data!)
                Card(
                  child: ListTile(
                    title: Text('${x.number} • ${x.purpose.name}'),
                    subtitle: Text(
                      '${x.method.name} • ${x.status.name} • ${x.providerReference}${x.failureReason.isEmpty ? '' : '\nFailed: ${x.failureReason}'}',
                    ),
                    trailing: Column(
                      children: [
                        Text(
                          AppCurrency.format(x.total, currencyCode: x.currency),
                        ),
                        if (canManage)
                          PopupMenuButton<String>(
                            onSelected: (a) async {
                              if (a == 'confirm') {
                                final result = await _promptSettlement(
                                  c,
                                  successful: true,
                                );
                                if (result != null) {
                                  await repository.confirm(
                                    x,
                                    userId,
                                    providerReference: result.$1,
                                  );
                                }
                              } else if (a == 'refund') {
                                final result = await _promptRefund(c, x);
                                if (result != null) {
                                  await repository.refund(
                                    x,
                                    userId,
                                    amount: result.$1,
                                    reason: result.$2,
                                  );
                                }
                              } else {
                                final result = await _promptSettlement(
                                  c,
                                  successful: false,
                                );
                                if (result != null) {
                                  await repository.fail(
                                    x,
                                    result.$2,
                                    providerReference: result.$1,
                                  );
                                }
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'confirm',
                                child: Text('Confirm'),
                              ),
                              PopupMenuItem(
                                value: 'fail',
                                child: Text('Mark failed'),
                              ),
                              PopupMenuItem(
                                value: 'refund',
                                child: Text('Refund'),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              Text('Invoices', style: Theme.of(c).textTheme.titleLarge),
              for (final x in i.data!)
                ListTile(
                  leading: const Icon(Icons.receipt_long),
                  title: Text('${x.number} • ${x.description}'),
                  subtitle: Text('${x.status.name} • Due ${x.dueAt}'),
                  trailing: TextButton(
                    onPressed: () => _receipt(x),
                    child: Text(
                      AppCurrency.format(x.amount, currencyCode: x.currency),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
  Future<void> _payment(BuildContext c) async {
    var purpose = BillingPurpose.pickupFee, method = BillingMethod.mobileMoney;
    final payer = TextEditingController(text: userId),
        payee = TextEditingController(),
        ref = TextEditingController(),
        subtotal = TextEditingController(),
        tax = TextEditingController(text: '0'),
        fee = TextEditingController(text: '5'),
        provider = TextEditingController(),
        masked = TextEditingController(),
        currency = TextEditingController(text: 'SLE');
    final ok = await _f(c, 'Create payment', [
      DropdownButtonFormField(
        initialValue: purpose,
        items: BillingPurpose.values
            .map((x) => DropdownMenuItem(value: x, child: Text(x.name)))
            .toList(),
        onChanged: (x) => purpose = x!,
      ),
      DropdownButtonFormField(
        initialValue: method,
        items: BillingMethod.values
            .map((x) => DropdownMenuItem(value: x, child: Text(x.name)))
            .toList(),
        onChanged: (x) => method = x!,
      ),
      TextField(
        controller: payer,
        decoration: const InputDecoration(labelText: 'Payer ID'),
      ),
      TextField(
        controller: payee,
        decoration: const InputDecoration(
          labelText: 'Payee / partner / collector ID',
        ),
      ),
      TextField(
        controller: ref,
        decoration: const InputDecoration(
          labelText: 'Unique service/order reference',
        ),
      ),
      TextField(
        controller: subtotal,
        decoration: const InputDecoration(labelText: 'Subtotal (Le)'),
      ),
      TextField(
        controller: tax,
        decoration: const InputDecoration(labelText: 'Tax %'),
      ),
      TextField(
        controller: fee,
        decoration: const InputDecoration(labelText: 'Service charge %'),
      ),
      TextField(
        controller: provider,
        decoration: const InputDecoration(
          labelText: 'Payment provider (e.g. Orange Money)',
        ),
      ),
      TextField(
        controller: masked,
        decoration: const InputDecoration(
          labelText: 'Masked account (e.g. ****1234)',
        ),
      ),
      TextField(
        controller: currency,
        readOnly: true,
        decoration: const InputDecoration(
          labelText: 'Currency',
          helperText: 'Sierra Leone leone (Le)',
        ),
      ),
    ]);
    if (ok) {
      await repository.createPayment(
        purpose: purpose,
        payerId: payer.text,
        payeeId: payee.text,
        referenceId: ref.text,
        method: method,
        charge: ChargeBreakdown(
          subtotal: double.tryParse(subtotal.text) ?? 0,
          taxRate: double.tryParse(tax.text) ?? 0,
          serviceChargeRate: double.tryParse(fee.text) ?? 0,
        ),
        currency: currency.text,
        provider: provider.text,
        maskedAccount: masked.text,
      );
    }
  }

  Future<void> _monimePayment(BuildContext c) async {
    await Navigator.of(c).push(
      MaterialPageRoute<void>(
        builder: (_) => MonimePaymentScreen(repository: MonimePaymentRepository()),
      ),
    );
  }

  Future<void> _invoice(BuildContext c) async {
    final customer = TextEditingController(),
        desc = TextEditingController(),
        amount = TextEditingController();
    final ok = await _f(c, 'Invoice', [
      TextField(controller: customer),
      TextField(controller: desc),
      TextField(
        controller: amount,
        decoration: const InputDecoration(labelText: 'Amount (Le)'),
      ),
    ]);
    if (ok) {
      await repository.invoice(
        customerId: customer.text,
        description: desc.text,
        amount: double.tryParse(amount.text) ?? 0,
        currency: 'SLE',
        dueAt: DateTime.now().add(const Duration(days: 30)),
      );
    }
  }

  Future<(String, String)?> _promptSettlement(
    BuildContext c, {
    required bool successful,
  }) async {
    final providerReference = TextEditingController();
    final reason = TextEditingController(
      text: successful ? '' : 'Provider declined transaction',
    );
    final ok = await _f(c, successful ? 'Confirm payment' : 'Mark payment failed', [
      TextField(
        controller: providerReference,
        decoration: const InputDecoration(labelText: 'Provider reference'),
      ),
      if (!successful)
        TextField(
          controller: reason,
          decoration: const InputDecoration(labelText: 'Failure reason'),
        ),
    ]);
    if (!ok) return null;
    return (providerReference.text, reason.text);
  }

  Future<(double, String)?> _promptRefund(
    BuildContext c,
    BillingTransaction t,
  ) async {
    final amount = TextEditingController(text: t.total.toStringAsFixed(2));
    final reason = TextEditingController();
    final ok = await _f(c, 'Refund payment', [
      TextField(
        controller: amount,
        decoration: const InputDecoration(labelText: 'Refund amount (Le)'),
      ),
      TextField(
        controller: reason,
        decoration: const InputDecoration(labelText: 'Refund reason'),
      ),
    ]);
    if (!ok) return null;
    return (double.tryParse(amount.text) ?? t.total, reason.text);
  }

  Future<void> _receipt(BillingInvoice x) async {
    final d = pw.Document();
    d.addPage(
      pw.Page(
        build: (_) => pw.Column(
          children: [
            pw.Header(text: 'EcoTrace Invoice'),
            pw.Text(x.number),
            pw.Text(x.description),
            pw.Text(AppCurrency.format(x.amount, currencyCode: x.currency)),
            pw.Text('Status ${x.status.name}'),
            pw.Text('Due ${x.dueAt}'),
          ],
        ),
      ),
    );
    await Printing.layoutPdf(onLayout: (_) => d.save());
  }
}

Widget _m(String a, double b) => SizedBox(
  width: 150,
  child: Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Text(
            AppCurrency.format(b),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(a),
        ],
      ),
    ),
  ),
);
Future<bool> _f(BuildContext c, String t, List<Widget> w) async =>
    await showDialog<bool>(
      context: c,
      builder: (c) => AlertDialog(
        title: Text(t),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: w),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Save'),
          ),
        ],
      ),
    ) ??
    false;
