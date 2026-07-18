import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../auth/domain/user_profile.dart';
import '../../centres/domain/collection_centre.dart';
import '../../fleet/domain/vehicle.dart';
import '../data/reverse_logistics_repository.dart';
import '../domain/reverse_logistics_transfer.dart';

class ReverseLogisticsDashboardScreen extends StatelessWidget {
  const ReverseLogisticsDashboardScreen({
    super.key,
    required this.repository,
    required this.currentUserId,
    required this.isDriver,
    required this.canCreate,
    required this.canApprove,
    required this.canReceive,
  });

  final ReverseLogisticsRepository repository;
  final String currentUserId;
  final bool isDriver, canCreate, canApprove, canReceive;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Reverse logistics')),
    floatingActionButton: canCreate
        ? FloatingActionButton.extended(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CreateReverseTransferScreen(
                  repository: repository,
                  currentUserId: currentUserId,
                ),
              ),
            ),
            icon: const Icon(Icons.add_road),
            label: const Text('New transfer'),
          )
        : null,
    body: StreamBuilder<List<ReverseLogisticsTransfer>>(
      stream: repository.watchTransfers(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Unable to load transfers: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = snapshot.data!;
        final transfers = isDriver
            ? all
                  .where((transfer) => transfer.driverId == currentUserId)
                  .toList()
            : all;
        final completed = transfers
            .where((transfer) => transfer.isComplete)
            .length;
        final active = transfers
            .where(
              (transfer) => ![
                ReverseTransferStatus.received,
                ReverseTransferStatus.cancelled,
                ReverseTransferStatus.rejected,
              ].contains(transfer.status),
            )
            .length;
        final exceptions = transfers
            .where((transfer) => transfer.openExceptionCount > 0)
            .length;
        final durations = transfers
            .where(
              (transfer) =>
                  transfer.receivedAt != null && transfer.dispatchedAt != null,
            )
            .map((transfer) => transfer.transitDuration!.inMinutes / 60)
            .toList();
        final averageHours = durations.isEmpty
            ? 0.0
            : durations.reduce((a, b) => a + b) / durations.length;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Reverse logistics analytics',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _metric(
                  'Transfers',
                  transfers.length.toString(),
                  Icons.swap_horiz,
                ),
                _metric(
                  'Active',
                  active.toString(),
                  Icons.local_shipping_outlined,
                ),
                _metric(
                  'Received',
                  completed.toString(),
                  Icons.inventory_outlined,
                ),
                _metric(
                  'Exception holds',
                  exceptions.toString(),
                  Icons.report_problem_outlined,
                ),
                _metric(
                  'Completion rate',
                  transfers.isEmpty
                      ? '0%'
                      : '${(completed / transfers.length * 100).toStringAsFixed(1)}%',
                  Icons.trending_up,
                ),
                _metric(
                  'Average transit',
                  '${averageHours.toStringAsFixed(1)} h',
                  Icons.timer_outlined,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              'Transfer orders',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (transfers.isEmpty)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Center(
                  child: Text('No reverse-logistics transfers yet.'),
                ),
              ),
            for (final transfer in transfers)
              Card(
                child: ListTile(
                  leading: Icon(_typeIcon(transfer.type)),
                  title: Text(
                    '${transfer.transferNumber} • ${transfer.type.label}',
                  ),
                  subtitle: Text(
                    '${transfer.originName} → ${transfer.destinationName}\n'
                    '${transfer.itemCount} items • ${transfer.weightKg.toStringAsFixed(1)} kg • ${transfer.status.label}',
                  ),
                  isThreeLine: true,
                  trailing: transfer.openExceptionCount > 0
                      ? Badge(
                          label: Text('${transfer.openExceptionCount}'),
                          child: const Icon(Icons.warning_amber),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReverseTransferDetailScreen(
                        repository: repository,
                        transferId: transfer.id,
                        currentUserId: currentUserId,
                        isDriver: isDriver,
                        canApprove: canApprove,
                        canReceive: canReceive,
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 80),
          ],
        );
      },
    ),
  );
}

class CreateReverseTransferScreen extends StatefulWidget {
  const CreateReverseTransferScreen({
    super.key,
    required this.repository,
    required this.currentUserId,
  });
  final ReverseLogisticsRepository repository;
  final String currentUserId;

  @override
  State<CreateReverseTransferScreen> createState() =>
      _CreateReverseTransferScreenState();
}

class _CreateReverseTransferScreenState
    extends State<CreateReverseTransferScreen> {
  ReverseTransferType type = ReverseTransferType.pickupToCentre;
  final originId = TextEditingController();
  final originName = TextEditingController();
  final destinationId = TextEditingController();
  final destinationName = TextEditingController();
  final references = TextEditingController();
  final itemCount = TextEditingController(text: '1');
  final weight = TextEditingController();
  bool saving = false;

  @override
  void dispose() {
    originId.dispose();
    originName.dispose();
    destinationId.dispose();
    destinationName.dispose();
    references.dispose();
    itemCount.dispose();
    weight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Create transfer order')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<ReverseTransferType>(
          initialValue: type,
          decoration: const InputDecoration(labelText: 'Movement type'),
          items: ReverseTransferType.values
              .map(
                (value) =>
                    DropdownMenuItem(value: value, child: Text(value.label)),
              )
              .toList(),
          onChanged: (value) => setState(() => type = value!),
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<CollectionCentre>>(
          stream: widget.repository.watchCentres(),
          builder: (context, snapshot) {
            final centres = snapshot.data ?? const <CollectionCentre>[];
            return ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Use a registered collection centre'),
              subtitle: const Text(
                'Optional shortcut for origin or destination',
              ),
              children: [
                for (final centre in centres)
                  ListTile(
                    title: Text(centre.name),
                    subtitle: Text(centre.address),
                    trailing: Wrap(
                      children: [
                        TextButton(
                          onPressed: () {
                            originId.text = centre.id;
                            originName.text = centre.name;
                          },
                          child: const Text('Origin'),
                        ),
                        TextButton(
                          onPressed: () {
                            destinationId.text = centre.id;
                            destinationName.text = centre.name;
                          },
                          child: const Text('Destination'),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        TextField(
          controller: originName,
          decoration: const InputDecoration(
            labelText: 'Origin name / user address',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: originId,
          decoration: const InputDecoration(labelText: 'Origin reference ID'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: destinationName,
          decoration: const InputDecoration(
            labelText: 'Destination centre / facility',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: destinationId,
          decoration: const InputDecoration(
            labelText: 'Destination reference ID',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: references,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Pickup, inventory, repair, or batch references',
            helperText: 'Separate multiple references with commas',
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: itemCount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Item count'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: weight,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Weight (kg)'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: saving ? null : _save,
          icon: saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('Create draft transfer'),
        ),
      ],
    ),
  );

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await widget.repository.create(
        type: type,
        originId: originId.text,
        originName: originName.text,
        destinationId: destinationId.text,
        destinationName: destinationName.text,
        assetReferences: references.text
            .split(',')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(),
        itemCount: int.tryParse(itemCount.text) ?? 0,
        weightKg: double.tryParse(weight.text) ?? 0,
        actorId: widget.currentUserId,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to create transfer: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class ReverseTransferDetailScreen extends StatelessWidget {
  const ReverseTransferDetailScreen({
    super.key,
    required this.repository,
    required this.transferId,
    required this.currentUserId,
    required this.isDriver,
    required this.canApprove,
    required this.canReceive,
  });
  final ReverseLogisticsRepository repository;
  final String transferId, currentUserId;
  final bool isDriver, canApprove, canReceive;

  @override
  Widget build(BuildContext context) => StreamBuilder<ReverseLogisticsTransfer>(
    stream: repository.watchTransfer(transferId),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Scaffold(
          appBar: AppBar(),
          body: Center(child: Text('${snapshot.error}')),
        );
      }
      if (!snapshot.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final transfer = snapshot.data!;
      final assignedDriver = transfer.driverId == currentUserId;
      return Scaffold(
        appBar: AppBar(
          title: Text(transfer.transferNumber),
          actions: [
            IconButton(
              onPressed: () => _manifest(transfer),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              tooltip: 'Transport manifest',
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transfer.type.label,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(transfer.status.label),
                    const Divider(),
                    Text(
                      '${transfer.originName} → ${transfer.destinationName}',
                    ),
                    Text(
                      '${transfer.itemCount} items • ${transfer.weightKg.toStringAsFixed(2)} kg',
                    ),
                    Text('References: ${transfer.assetReferences.join(', ')}'),
                    Text(
                      'Vehicle: ${transfer.vehicleRegistration.isEmpty ? 'Not assigned' : transfer.vehicleRegistration}',
                    ),
                    Text(
                      'Driver: ${transfer.driverName.isEmpty ? 'Not assigned' : transfer.driverName}',
                    ),
                    Text(
                      'Transport document: ${transfer.transportDocumentNumber.isEmpty ? 'Not recorded' : transfer.transportDocumentNumber}',
                    ),
                    if (transfer.openExceptionCount > 0)
                      Text(
                        '${transfer.openExceptionCount} unresolved exception(s)',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if ([
                      ReverseTransferStatus.draft,
                      ReverseTransferStatus.pendingApproval,
                    ].contains(transfer.status) &&
                    canApprove)
                  FilledButton.tonalIcon(
                    onPressed: () => _assign(context, transfer),
                    icon: const Icon(Icons.local_shipping_outlined),
                    label: const Text('Assign transport'),
                  ),
                if (transfer.status == ReverseTransferStatus.draft &&
                    canApprove)
                  FilledButton(
                    onPressed: () => _run(
                      context,
                      () =>
                          repository.submitForApproval(transfer, currentUserId),
                      'Submitted for approval.',
                    ),
                    child: const Text('Submit approval'),
                  ),
                if (transfer.status == ReverseTransferStatus.pendingApproval &&
                    canApprove) ...[
                  FilledButton(
                    onPressed: () => _approve(context, transfer),
                    child: const Text('Approve'),
                  ),
                  OutlinedButton(
                    onPressed: () => _reject(context, transfer),
                    child: const Text('Reject'),
                  ),
                ],
                if (transfer.status == ReverseTransferStatus.approved &&
                    canApprove)
                  FilledButton(
                    onPressed: transfer.canDispatch
                        ? () => _run(
                            context,
                            () => repository.dispatch(transfer, currentUserId),
                            'Transfer dispatched.',
                          )
                        : null,
                    child: const Text('Dispatch'),
                  ),
                if (transfer.status == ReverseTransferStatus.dispatched &&
                    (canApprove || assignedDriver))
                  FilledButton(
                    onPressed: () => _run(
                      context,
                      () => repository.startTransit(transfer, currentUserId),
                      'Transfer is in transit.',
                    ),
                    child: const Text('Start transit'),
                  ),
                if (transfer.status == ReverseTransferStatus.inTransit &&
                    (canApprove || assignedDriver))
                  FilledButton(
                    onPressed: () => _delivery(context, transfer),
                    child: const Text('Confirm delivery'),
                  ),
                if (transfer.status == ReverseTransferStatus.delivered &&
                    canReceive)
                  FilledButton(
                    onPressed: () => _receipt(context, transfer),
                    child: const Text('Confirm receipt'),
                  ),
                if (![
                  ReverseTransferStatus.received,
                  ReverseTransferStatus.cancelled,
                  ReverseTransferStatus.rejected,
                ].contains(transfer.status))
                  OutlinedButton.icon(
                    onPressed: () => _exception(context, transfer),
                    icon: const Icon(Icons.report_problem_outlined),
                    label: const Text('Report exception'),
                  ),
                if (canApprove)
                  OutlinedButton.icon(
                    onPressed: () => _uploadDocument(context, transfer),
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Add document'),
                  ),
              ],
            ),
            if (transfer.deliveryProofUrl.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'Delivery proof',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  transfer.deliveryProofUrl,
                  height: 220,
                  fit: BoxFit.cover,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              'Transfer exceptions',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            StreamBuilder<List<TransferException>>(
              stream: repository.watchExceptions(transfer.id),
              builder: (context, exceptionSnapshot) {
                final exceptions =
                    exceptionSnapshot.data ?? const <TransferException>[];
                if (exceptions.isEmpty) {
                  return const ListTile(title: Text('No exceptions reported'));
                }
                return Column(
                  children: [
                    for (final exception in exceptions)
                      Card(
                        child: ListTile(
                          leading: Icon(
                            exception.resolved
                                ? Icons.check_circle_outline
                                : Icons.warning_amber,
                          ),
                          title: Text(exception.type.name),
                          subtitle: Text(
                            exception.resolved
                                ? '${exception.description}\nResolution: ${exception.resolution}'
                                : exception.description,
                          ),
                          isThreeLine: exception.resolved,
                          trailing: !exception.resolved && canApprove
                              ? TextButton(
                                  onPressed: () =>
                                      _resolve(context, transfer, exception),
                                  child: const Text('Resolve'),
                                )
                              : null,
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Chain of custody',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            StreamBuilder<List<CustodyEvent>>(
              stream: repository.watchCustody(transfer.id),
              builder: (context, custodySnapshot) => Column(
                children: [
                  for (final event
                      in custodySnapshot.data ?? const <CustodyEvent>[])
                    ListTile(
                      leading: const Icon(Icons.verified_user_outlined),
                      title: Text(event.action),
                      subtitle: Text(
                        '${event.custodianName} • ${event.location}\n${event.notes}',
                      ),
                      trailing: Text(
                        event.at == null
                            ? ''
                            : '${event.at!.month}/${event.at!.day} ${event.at!.hour}:${event.at!.minute.toString().padLeft(2, '0')}',
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _assign(
    BuildContext context,
    ReverseLogisticsTransfer transfer,
  ) async {
    final vehicles = await repository.watchVehicles().first;
    final drivers = await repository.watchDrivers().first;
    if (!context.mounted) return;
    if (vehicles.isEmpty || drivers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Register a vehicle and driver first.')),
      );
      return;
    }
    Vehicle? vehicle = vehicles
        .where((item) => item.availability == VehicleAvailability.available)
        .firstOrNull;
    UserProfile? driver = drivers.firstOrNull;
    final document = TextEditingController(
      text: transfer.transportDocumentNumber,
    );
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Vehicle, driver and documentation'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<Vehicle>(
                    initialValue: vehicle,
                    decoration: const InputDecoration(
                      labelText: 'Available vehicle',
                    ),
                    items: vehicles
                        .where(
                          (item) =>
                              item.availability ==
                              VehicleAvailability.available,
                        )
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(
                              '${item.registrationNumber} • ${item.capacityKg} kg',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setLocal(() => vehicle = value),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<UserProfile>(
                    initialValue: driver,
                    decoration: const InputDecoration(labelText: 'Driver'),
                    items: drivers
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(
                              item.displayName.isEmpty
                                  ? item.email
                                  : item.displayName,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setLocal(() => driver = value),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: document,
                    decoration: const InputDecoration(
                      labelText: 'Transport document / manifest number',
                    ),
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
                  child: const Text('Assign'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (ok && context.mounted && vehicle != null && driver != null) {
      await _run(
        context,
        () => repository.assignTransport(
          transfer,
          vehicle: vehicle!,
          driver: driver!,
          documentNumber: document.text,
          actorId: currentUserId,
        ),
        'Transport assigned.',
      );
    }
    document.dispose();
  }

  Future<void> _approve(
    BuildContext context,
    ReverseLogisticsTransfer transfer,
  ) async {
    final notes = TextEditingController();
    final ok = await _textDialog(
      context,
      'Approve transfer',
      'Approval notes',
      notes,
      'Approve',
    );
    if (ok && context.mounted) {
      await _run(
        context,
        () => repository.approve(
          transfer,
          actorId: currentUserId,
          notes: notes.text,
        ),
        'Transfer approved.',
      );
    }
    notes.dispose();
  }

  Future<void> _reject(
    BuildContext context,
    ReverseLogisticsTransfer transfer,
  ) async {
    final reason = TextEditingController();
    final ok = await _textDialog(
      context,
      'Reject transfer',
      'Required rejection reason',
      reason,
      'Reject',
    );
    if (ok && context.mounted) {
      await _run(
        context,
        () => repository.reject(
          transfer,
          actorId: currentUserId,
          reason: reason.text,
        ),
        'Transfer rejected.',
      );
    }
    reason.dispose();
  }

  Future<void> _uploadDocument(
    BuildContext context,
    ReverseLogisticsTransfer transfer,
  ) async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (context.mounted) {
      await _run(
        context,
        () => repository.uploadTransportDocument(transfer, bytes),
        'Transport document uploaded.',
      );
    }
  }

  Future<void> _delivery(
    BuildContext context,
    ReverseLogisticsTransfer transfer,
  ) async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (file == null || !context.mounted) return;
    final notes = TextEditingController();
    final ok = await _textDialog(
      context,
      'Delivery proof',
      'Delivery notes',
      notes,
      'Confirm',
    );
    if (ok && context.mounted) {
      final Uint8List proof = await file.readAsBytes();
      if (context.mounted) {
        await _run(
          context,
          () => repository.confirmDelivery(
            transfer,
            actorId: currentUserId,
            proof: proof,
            notes: notes.text,
          ),
          'Delivery confirmed.',
        );
      }
    }
    notes.dispose();
  }

  Future<void> _receipt(
    BuildContext context,
    ReverseLogisticsTransfer transfer,
  ) async {
    final receiver = TextEditingController();
    final notes = TextEditingController();
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Receipt confirmation'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: receiver,
                  decoration: const InputDecoration(labelText: 'Receiver name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notes,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Condition, quantity and receipt notes',
                  ),
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
                child: const Text('Confirm receipt'),
              ),
            ],
          ),
        ) ??
        false;
    if (ok && context.mounted) {
      await _run(
        context,
        () => repository.confirmReceipt(
          transfer,
          actorId: currentUserId,
          receiverName: receiver.text,
          notes: notes.text,
        ),
        'Receipt confirmed.',
      );
    }
    receiver.dispose();
    notes.dispose();
  }

  Future<void> _exception(
    BuildContext context,
    ReverseLogisticsTransfer transfer,
  ) async {
    var type = TransferExceptionType.delay;
    final description = TextEditingController();
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Report transfer exception'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<TransferExceptionType>(
                    initialValue: type,
                    items: TransferExceptionType.values
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setLocal(() => type = value!),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: description,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'What happened?',
                    ),
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
                  child: const Text('Place on hold'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (ok && context.mounted) {
      await _run(
        context,
        () => repository.reportException(
          transfer,
          type: type,
          description: description.text,
          actorId: currentUserId,
        ),
        'Exception reported.',
      );
    }
    description.dispose();
  }

  Future<void> _resolve(
    BuildContext context,
    ReverseLogisticsTransfer transfer,
    TransferException exception,
  ) async {
    final resolution = TextEditingController();
    final ok = await _textDialog(
      context,
      'Resolve exception',
      'Corrective action and resolution',
      resolution,
      'Resolve',
    );
    if (ok && context.mounted) {
      await _run(
        context,
        () => repository.resolveException(
          transfer,
          exception,
          resolution: resolution.text,
          actorId: currentUserId,
        ),
        'Exception resolved.',
      );
    }
    resolution.dispose();
  }

  Future<void> _manifest(ReverseLogisticsTransfer transfer) async {
    final custody = await repository.watchCustody(transfer.id).first;
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Header(level: 0, text: 'EcoTrace Reverse Logistics Manifest'),
          pw.Text('Transfer: ${transfer.transferNumber}'),
          pw.Text('Type: ${transfer.type.label}'),
          pw.Text('Status: ${transfer.status.label}'),
          pw.Text('Origin: ${transfer.originName} (${transfer.originId})'),
          pw.Text(
            'Destination: ${transfer.destinationName} (${transfer.destinationId})',
          ),
          pw.Text('Assets: ${transfer.assetReferences.join(', ')}'),
          pw.Text('Load: ${transfer.itemCount} items; ${transfer.weightKg} kg'),
          pw.Text('Vehicle: ${transfer.vehicleRegistration}'),
          pw.Text('Driver: ${transfer.driverName}'),
          pw.Text('Transport document: ${transfer.transportDocumentNumber}'),
          pw.Text('Approved by: ${transfer.approvedBy}'),
          pw.SizedBox(height: 12),
          pw.Header(level: 1, text: 'Chain of custody'),
          ...custody.reversed.map(
            (event) => pw.Text(
              '${event.at ?? ''} • ${event.action} • ${event.custodianName} • ${event.location} ${event.notes}',
            ),
          ),
          if (transfer.receivedBy.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text('Received by: ${transfer.receivedBy}'),
            pw.Text('Receipt notes: ${transfer.receiptNotes}'),
          ],
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (_) => document.save());
  }
}

Widget _metric(String label, String value, IconData icon) => SizedBox(
  width: 170,
  child: Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          Text(label),
        ],
      ),
    ),
  ),
);

IconData _typeIcon(ReverseTransferType type) => switch (type) {
  ReverseTransferType.pickupToCentre => Icons.home_work_outlined,
  ReverseTransferType.centreToRepair => Icons.handyman_outlined,
  ReverseTransferType.centreToRecycler => Icons.recycling,
  ReverseTransferType.interFacility => Icons.compare_arrows,
};

Future<bool> _textDialog(
  BuildContext context,
  String title,
  String label,
  TextEditingController controller,
  String action,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(labelText: label),
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
        SnackBar(content: Text('Reverse logistics operation failed: $error')),
      );
    }
  }
}
