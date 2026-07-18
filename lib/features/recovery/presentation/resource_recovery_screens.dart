import 'package:flutter/material.dart';

import '../../recycling/domain/recycling_batch.dart';
import '../data/resource_recovery_repository.dart';
import '../domain/recovered_material.dart';

class ResourceRecoveryDashboardScreen extends StatelessWidget {
  const ResourceRecoveryDashboardScreen({
    super.key,
    required this.repository,
    required this.currentUserId,
  });
  final ResourceRecoveryRepository repository;
  final String currentUserId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Resource recovery'),
      actions: [
        IconButton(
          onPressed: () => _category(context),
          icon: const Icon(Icons.category_outlined),
          tooltip: 'Material categories',
        ),
        IconButton(
          onPressed: () => _buyer(context),
          icon: const Icon(Icons.business_outlined),
          tooltip: 'Add buyer',
        ),
      ],
    ),
    body: StreamBuilder<List<RecoveredMaterialLot>>(
      stream: repository.watchLots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Unable to load recovered materials: ${snapshot.error}',
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final lots = snapshot.data!;
        final weight = lots.fold<double>(0, (sum, lot) => sum + lot.weightKg);
        final value = lots.fold<double>(
          0,
          (sum, lot) => sum + lot.estimatedMarketValue,
        );
        final revenue = lots.fold<double>(
          0,
          (sum, lot) => sum + lot.saleRevenue,
        );
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resource recovery dashboard',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 24,
                      runSpacing: 8,
                      children: [
                        Text('Material lots: ${lots.length}'),
                        Text('Recovered: ${weight.toStringAsFixed(2)} kg'),
                        Text('Market value: ${value.toStringAsFixed(2)}'),
                        Text('Sales revenue: ${revenue.toStringAsFixed(2)}'),
                        Text(
                          'Sales-ready: ${lots.where((lot) => lot.status == MaterialLotStatus.salesReady).length}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    StreamBuilder<List<RecyclingBatch>>(
                      stream: repository.watchRecyclingBatches(),
                      builder: (context, source) {
                        final batches = source.data ?? const <RecyclingBatch>[];
                        final input = batches.fold<double>(
                          0,
                          (sum, batch) => sum + batch.inputWeightKg,
                        );
                        return Text(
                          'Overall recovery efficiency: ${input == 0 ? '0.0' : (weight / input * 100).toStringAsFixed(1)}%',
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            if (lots.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('No recovered material recorded.')),
              ),
            for (final lot in lots)
              Card(
                child: ExpansionTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text('${lot.lotCode} • ${lot.material.label}'),
                  subtitle: Text(
                    '${lot.weightKg.toStringAsFixed(2)} kg • ${lot.qualityGrade.name} • ${lot.status.name}\nValue ${lot.estimatedMarketValue.toStringAsFixed(2)} • ${lot.storageLocation}',
                  ),
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () => _assignBuyer(context, lot),
                          child: const Text('Assign buyer'),
                        ),
                        OutlinedButton(
                          onPressed: lot.status == MaterialLotStatus.sold
                              ? null
                              : () => _run(
                                  context,
                                  () => repository.markSalesReady(lot),
                                  'Lot marked sales-ready.',
                                ),
                          child: const Text('Sales ready'),
                        ),
                        OutlinedButton(
                          onPressed: lot.status == MaterialLotStatus.sold
                              ? null
                              : () => _transfer(context, lot),
                          child: const Text('Transfer'),
                        ),
                        FilledButton(
                          onPressed: lot.status == MaterialLotStatus.sold
                              ? null
                              : () => _sale(context, lot),
                          child: const Text('Record sale'),
                        ),
                      ],
                    ),
                    StreamBuilder<List<MaterialTransferRecord>>(
                      stream: repository.watchTransfers(lot.id),
                      builder: (context, transfers) => Column(
                        children:
                            (transfers.data ?? const <MaterialTransferRecord>[])
                                .map(
                                  (transfer) => ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.swap_horiz),
                                    title: Text(
                                      '${transfer.from} → ${transfer.to}',
                                    ),
                                    subtitle: Text(
                                      '${transfer.carrier} • ${transfer.reference}',
                                    ),
                                  ),
                                )
                                .toList(),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _record(context),
      icon: const Icon(Icons.add),
      label: const Text('Record material'),
    ),
  );

  Future<void> _record(BuildContext context) async {
    final batches = await repository.watchRecyclingBatches().first;
    final definitions = await repository.watchCategories().first;
    if (!context.mounted) return;
    final active = batches.where((batch) => !batch.completionVerified).toList();
    if (active.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Create an active recycling batch first.'),
        ),
      );
      return;
    }
    var batch = active.first;
    var material = RecoverableMaterial.copper;
    var grade = MaterialQualityGrade.gradeA;
    final weight = TextEditingController(),
        quantity = TextEditingController(text: '0'),
        location = TextEditingController(),
        value = TextEditingController(text: '0');
    void applyDefault() {
      final match = definitions.where(
        (definition) => definition.material == material,
      );
      if (match.isNotEmpty) {
        value.text = match.first.defaultUnitValue.toString();
      }
    }

    applyDefault();
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Record recovered material'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<RecyclingBatch>(
                      initialValue: batch,
                      decoration: const InputDecoration(
                        labelText: 'Source recycling batch',
                      ),
                      items: active
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item.code),
                            ),
                          )
                          .toList(),
                      onChanged: (item) => setLocal(() => batch = item!),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<RecoverableMaterial>(
                      initialValue: material,
                      decoration: const InputDecoration(
                        labelText: 'Material category',
                      ),
                      items: RecoverableMaterial.values
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item.label),
                            ),
                          )
                          .toList(),
                      onChanged: (item) => setLocal(() {
                        material = item!;
                        applyDefault();
                      }),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: weight,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Weight (kg)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: quantity,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Quantity / units',
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<MaterialQualityGrade>(
                      initialValue: grade,
                      decoration: const InputDecoration(
                        labelText: 'Quality grade',
                      ),
                      items: MaterialQualityGrade.values
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item.name),
                            ),
                          )
                          .toList(),
                      onChanged: (item) => setLocal(() => grade = item!),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: location,
                      decoration: const InputDecoration(
                        labelText: 'Material storage location',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: value,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Market value per kg',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Record'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (ok && context.mounted) {
      await _run(
        context,
        () => repository.recordMaterial(
          batch: batch,
          material: material,
          weightKg: double.tryParse(weight.text) ?? 0,
          quantity: int.tryParse(quantity.text) ?? 0,
          qualityGrade: grade,
          storageLocation: location.text,
          unitMarketValue: double.tryParse(value.text) ?? 0,
          actorId: currentUserId,
        ),
        'Recovered material recorded.',
      );
    }
    for (final c in [weight, quantity, location, value]) {
      c.dispose();
    }
  }

  Future<void> _category(BuildContext context) async {
    var material = RecoverableMaterial.copper;
    final value = TextEditingController(text: '0');
    var active = true;
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Material category management'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<RecoverableMaterial>(
                    initialValue: material,
                    items: RecoverableMaterial.values
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(item.label),
                          ),
                        )
                        .toList(),
                    onChanged: (item) => setLocal(() => material = item!),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: value,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Default market value per kg',
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: active,
                    onChanged: (item) => setLocal(() => active = item),
                    title: const Text('Active category'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (ok && context.mounted) {
      await _run(
        context,
        () => repository.upsertCategory(
          material,
          defaultUnitValue: double.tryParse(value.text) ?? 0,
          active: active,
        ),
        'Material category saved.',
      );
    }
    value.dispose();
  }

  Future<void> _buyer(BuildContext context) async {
    final name = TextEditingController(), contact = TextEditingController();
    final selected = <RecoverableMaterial>{};
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Add material buyer'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: 'Buyer name',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: contact,
                      decoration: const InputDecoration(
                        labelText: 'Contact details',
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final item in RecoverableMaterial.values)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: selected.contains(item),
                        onChanged: (checked) => setLocal(
                          () => checked == true
                              ? selected.add(item)
                              : selected.remove(item),
                        ),
                        title: Text(item.label),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Add'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (ok && context.mounted) {
      await _run(
        context,
        () => repository.addBuyer(
          name: name.text,
          contact: contact.text,
          materials: selected.toList(),
        ),
        'Buyer added.',
      );
    }
    name.dispose();
    contact.dispose();
  }

  Future<void> _assignBuyer(
    BuildContext context,
    RecoveredMaterialLot lot,
  ) async {
    final buyers = await repository.watchBuyers().first;
    if (!context.mounted || buyers.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Add a buyer first.')));
      }
      return;
    }
    var buyer = buyers.first;
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Assign buyer'),
              content: DropdownButtonFormField<MaterialBuyer>(
                initialValue: buyer,
                items: buyers
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item.name)),
                    )
                    .toList(),
                onChanged: (item) => setLocal(() => buyer = item!),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Assign'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (ok && context.mounted) {
      await _run(
        context,
        () => repository.assignBuyer(lot, buyer.id),
        'Buyer assigned.',
      );
    }
  }

  Future<void> _transfer(BuildContext context, RecoveredMaterialLot lot) async {
    final destination = TextEditingController(),
        carrier = TextEditingController(),
        reference = TextEditingController();
    final ok = await _form(context, 'Material transfer', 'Transfer', [
      TextField(
        controller: destination,
        decoration: const InputDecoration(labelText: 'Destination'),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: carrier,
        decoration: const InputDecoration(labelText: 'Carrier'),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: reference,
        decoration: const InputDecoration(labelText: 'Transfer reference'),
      ),
    ]);
    if (ok && context.mounted) {
      await _run(
        context,
        () => repository.recordTransfer(
          lot,
          destination: destination.text,
          carrier: carrier.text,
          reference: reference.text,
          actorId: currentUserId,
        ),
        'Material transfer recorded.',
      );
    }
    destination.dispose();
    carrier.dispose();
    reference.dispose();
  }

  Future<void> _sale(BuildContext context, RecoveredMaterialLot lot) async {
    final revenue = TextEditingController(
      text: lot.estimatedMarketValue.toStringAsFixed(2),
    );
    final ok = await _form(context, 'Record material sale', 'Complete sale', [
      TextField(
        controller: revenue,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Sale revenue'),
      ),
    ]);
    if (ok && context.mounted) {
      await _run(
        context,
        () => repository.recordSale(
          lot,
          revenue: double.tryParse(revenue.text) ?? 0,
          actorId: currentUserId,
        ),
        'Sale and revenue recorded.',
      );
    }
    revenue.dispose();
  }
}

Future<bool> _form(
  BuildContext context,
  String title,
  String action,
  List<Widget> children,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;
Future<void> _run(
  BuildContext context,
  Future<void> Function() action,
  String success,
) async {
  try {
    await action();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Recovery operation failed: $error')),
      );
    }
  }
}
