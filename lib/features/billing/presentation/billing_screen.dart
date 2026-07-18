import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
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
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _payment(c),
            icon: const Icon(Icons.payment),
            label: const Text('New payment'),
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
                        Text('${x.currency} ${x.total.toStringAsFixed(2)}'),
                        if (canManage)
                          PopupMenuButton<String>(
                            onSelected: (a) => a == 'confirm'
                                ? repository.confirm(x, userId)
                                : a == 'refund'
                                ? repository.refund(x, userId)
                                : repository.fail(
                                    x,
                                    'Provider declined transaction',
                                  ),
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
                    child: Text('${x.currency} ${x.amount}'),
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
        currency = TextEditingController(text: 'USD');
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
        decoration: const InputDecoration(labelText: 'Subtotal'),
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
          labelText: 'Provider transaction reference',
        ),
      ),
      TextField(
        controller: masked,
        decoration: const InputDecoration(
          labelText: 'Masked account (e.g. ****1234)',
        ),
      ),
      TextField(controller: currency),
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
        providerReference: provider.text,
        maskedAccount: masked.text,
      );
    }
  }

  Future<void> _invoice(BuildContext c) async {
    final customer = TextEditingController(),
        desc = TextEditingController(),
        amount = TextEditingController();
    final ok = await _f(c, 'Invoice', [
      TextField(controller: customer),
      TextField(controller: desc),
      TextField(controller: amount),
    ]);
    if (ok) {
      await repository.invoice(
        customerId: customer.text,
        description: desc.text,
        amount: double.tryParse(amount.text) ?? 0,
        currency: 'USD',
        dueAt: DateTime.now().add(const Duration(days: 30)),
      );
    }
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
            pw.Text('${x.currency} ${x.amount}'),
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
            b.toStringAsFixed(2),
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
