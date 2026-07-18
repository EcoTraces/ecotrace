import 'package:flutter/material.dart';

import '../../../core/app_currency.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/domain/inventory_item.dart';
import '../data/repair_repository.dart';
import '../domain/repair_job.dart';

class RepairDashboardScreen extends StatefulWidget {
  const RepairDashboardScreen({
    super.key,
    required this.repository,
    required this.inventoryRepository,
    required this.currentUserId,
    required this.canApprove,
  });

  final RepairRepository repository;
  final InventoryRepository inventoryRepository;
  final String currentUserId;
  final bool canApprove;

  @override
  State<RepairDashboardScreen> createState() => _RepairDashboardState();
}

class _RepairDashboardState extends State<RepairDashboardScreen> {
  RepairStatus? statusFilter;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Repair and refurbishment'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Repair board'),
            Tab(text: 'Refurbished inventory'),
          ],
        ),
      ),
      body: StreamBuilder<List<RepairJob>>(
        stream: widget.repository.watchJobs(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Unable to load repair jobs: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final allJobs = snapshot.data!;
          final permitted = widget.canApprove
              ? allJobs
              : allJobs
                    .where((job) => job.technicianId == widget.currentUserId)
                    .toList();
          return TabBarView(
            children: [
              _RepairBoard(
                jobs: permitted,
                statusFilter: statusFilter,
                onFilterChanged: (value) =>
                    setState(() => statusFilter = value),
                onOpen: _open,
              ),
              _RefurbishedInventory(
                jobs: permitted
                    .where((job) => job.status == RepairStatus.completed)
                    .toList(),
                onOpen: _open,
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createAssessment,
        icon: const Icon(Icons.build_circle_outlined),
        label: const Text('New assessment'),
      ),
    ),
  );

  void _open(RepairJob job) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => RepairJobScreen(
        repository: widget.repository,
        initial: job,
        currentUserId: widget.currentUserId,
        canApprove: widget.canApprove,
      ),
    ),
  );

  Future<void> _createAssessment() async {
    final items = await widget.inventoryRepository.watchItems().first;
    if (!mounted) return;
    final candidates = items
        .where(
          (item) =>
              [
                ItemCondition.repairable,
                ItemCondition.reusable,
                ItemCondition.refurbishable,
              ].contains(item.condition) &&
              ![
                ProcessingStatus.refurbished,
                ProcessingStatus.disposed,
                ProcessingStatus.recycling,
              ].contains(item.status),
        )
        .toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No repairable or refurbishable inventory is available.',
          ),
        ),
      );
      return;
    }
    var selected = candidates.first;
    final notes = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Create repair assessment'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<InventoryItem>(
                  initialValue: selected,
                  decoration: const InputDecoration(
                    labelText: 'Inventory item',
                  ),
                  items: candidates
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(
                            '${item.itemCode} • ${item.brand} ${item.model}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setLocalState(() => selected = value!),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notes,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Assessment request and observed condition',
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
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (submitted == true && mounted) {
      await _runRepairAction(
        context,
        () => widget.repository.createAssessment(
          item: selected,
          assessmentNotes: notes.text,
          createdBy: widget.currentUserId,
          technicianId: widget.canApprove ? '' : widget.currentUserId,
        ),
        'Repair assessment created.',
      );
    }
    notes.dispose();
  }
}

class _RepairBoard extends StatelessWidget {
  const _RepairBoard({
    required this.jobs,
    required this.statusFilter,
    required this.onFilterChanged,
    required this.onOpen,
  });
  final List<RepairJob> jobs;
  final RepairStatus? statusFilter;
  final ValueChanged<RepairStatus?> onFilterChanged;
  final ValueChanged<RepairJob> onOpen;

  @override
  Widget build(BuildContext context) {
    final visible = statusFilter == null
        ? jobs
        : jobs.where((job) => job.status == statusFilter).toList();
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
                  'Repair performance',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 18,
                  runSpacing: 8,
                  children: [
                    Text('Total: ${jobs.length}'),
                    Text(
                      'Active: ${jobs.where((job) => [RepairStatus.approved, RepairStatus.repairInProgress, RepairStatus.qualityTesting].contains(job.status)).length}',
                    ),
                    Text(
                      'Completed: ${jobs.where((job) => job.status == RepairStatus.completed).length}',
                    ),
                    Text(
                      'Unrepairable: ${jobs.where((job) => job.status == RepairStatus.unrepairable).length}',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        DropdownButtonFormField<RepairStatus?>(
          initialValue: statusFilter,
          decoration: const InputDecoration(labelText: 'Filter by status'),
          items: [
            const DropdownMenuItem<RepairStatus?>(
              value: null,
              child: Text('All statuses'),
            ),
            ...RepairStatus.values.map(
              (status) => DropdownMenuItem<RepairStatus?>(
                value: status,
                child: Text(status.label),
              ),
            ),
          ],
          onChanged: onFilterChanged,
        ),
        const SizedBox(height: 8),
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('No repair jobs match this view.')),
          ),
        for (final job in visible)
          Card(
            child: ListTile(
              leading: CircleAvatar(child: Icon(_statusIcon(job.status))),
              title: Text('${job.itemCode} • ${job.deviceName}'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${job.status.label} • ${job.technicianId.isEmpty ? 'Unassigned' : job.technicianId}',
                  ),
                  const SizedBox(height: 5),
                  LinearProgressIndicator(value: job.progressPercent / 100),
                ],
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onOpen(job),
            ),
          ),
      ],
    );
  }
}

class _RefurbishedInventory extends StatelessWidget {
  const _RefurbishedInventory({required this.jobs, required this.onOpen});
  final List<RepairJob> jobs;
  final ValueChanged<RepairJob> onOpen;

  @override
  Widget build(BuildContext context) {
    if (jobs.isEmpty) {
      return const Center(child: Text('No refurbished devices yet.'));
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                Text('Refurbished: ${jobs.length}'),
                Text(
                  'Under warranty: ${jobs.where((job) => job.warrantyActive).length}',
                ),
                Text(
                  'Donation approved: ${jobs.where((job) => job.dispositionApproved && job.disposition == RefurbishedDisposition.donation).length}',
                ),
                Text(
                  'Resale approved: ${jobs.where((job) => job.dispositionApproved && job.disposition == RefurbishedDisposition.resale).length}',
                ),
              ],
            ),
          ),
        ),
        for (final job in jobs)
          Card(
            child: ListTile(
              leading: const Icon(Icons.verified_outlined),
              title: Text('${job.itemCode} • ${job.deviceName}'),
              subtitle: Text(
                '${job.grade?.label ?? 'Ungraded'} • ${job.warrantyActive ? 'Warranty active' : 'Warranty expired'}\n${job.dispositionApproved ? '${job.disposition.name} approved' : 'Disposition pending'}',
              ),
              isThreeLine: true,
              onTap: () => onOpen(job),
            ),
          ),
      ],
    );
  }
}

class RepairJobScreen extends StatelessWidget {
  const RepairJobScreen({
    super.key,
    required this.repository,
    required this.initial,
    required this.currentUserId,
    required this.canApprove,
  });

  final RepairRepository repository;
  final RepairJob initial;
  final String currentUserId;
  final bool canApprove;

  bool _canWork(RepairJob job) =>
      canApprove || job.technicianId == currentUserId;

  @override
  Widget build(BuildContext context) => StreamBuilder<RepairJob>(
    stream: repository.watchJob(initial.id),
    initialData: initial,
    builder: (context, snapshot) {
      final job = snapshot.data!;
      return Scaffold(
        appBar: AppBar(title: Text('Repair • ${job.itemCode}')),
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
                      job.deviceName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(job.status.label),
                    Text(
                      'Technician: ${job.technicianId.isEmpty ? 'Unassigned' : job.technicianId}',
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(value: job.progressPercent / 100),
                    Text('${job.progressPercent}% complete'),
                  ],
                ),
              ),
            ),
            _AssessmentCard(job: job),
            _CostCard(job: job),
            _ActionPanel(
              job: job,
              canApprove: canApprove,
              canWork: _canWork(job),
              assign: () => _assign(context, job),
              diagnose: () => _diagnose(context, job),
              approve: () => _review(context, job, true),
              reject: () => _review(context, job, false),
              start: () => _runRepairAction(
                context,
                () => repository.startRepair(job, currentUserId),
                'Repair started.',
              ),
              addPart: () => _addPart(context, job),
              progress: () => _recordProgress(context, job),
              beginQc: () => _runRepairAction(
                context,
                () => repository.beginQualityTesting(job, currentUserId),
                'Device submitted for quality testing.',
              ),
              qualityControl: () => _qualityControl(context, job),
              unrepairable: () => _markUnrepairable(context, job),
              warranty: () => _updateWarranty(context, job),
              disposition: () => _approveDisposition(context, job),
            ),
            if (job.status == RepairStatus.completed)
              _RefurbishmentCard(job: job),
            Text(
              'Spare parts used',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            StreamBuilder<List<SparePartUsage>>(
              stream: repository.watchParts(job.id),
              builder: (context, snapshot) {
                final parts = snapshot.data ?? const <SparePartUsage>[];
                if (parts.isEmpty) {
                  return const ListTile(title: Text('No parts recorded.'));
                }
                return Column(
                  children: parts
                      .map(
                        (part) => ListTile(
                          leading: const Icon(Icons.settings_outlined),
                          title: Text('${part.name} × ${part.quantity}'),
                          subtitle: Text(
                            '${part.partNumber} • ${AppCurrency.format(part.totalCost)}',
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const Divider(height: 32),
            Text(
              'Repair progress',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            StreamBuilder<List<RepairProgressEvent>>(
              stream: repository.watchProgress(job.id),
              builder: (context, snapshot) => Column(
                children: (snapshot.data ?? const <RepairProgressEvent>[])
                    .map(
                      (event) => ListTile(
                        leading: const Icon(Icons.history),
                        title: Text(event.type),
                        subtitle: Text(
                          '${event.details}\n${event.actorId} • ${event.at ?? ''}',
                        ),
                        trailing: Text('${event.progressPercent}%'),
                        isThreeLine: true,
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _assign(BuildContext context, RepairJob job) async {
    final technician = TextEditingController(text: job.technicianId);
    final submitted = await _repairDialog(
      context,
      title: 'Assign technician',
      actionLabel: 'Assign',
      children: [
        TextField(
          controller: technician,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Technician user ID'),
        ),
      ],
    );
    if (submitted && context.mounted) {
      await _runRepairAction(
        context,
        () => repository.assignTechnician(
          job,
          technicianId: technician.text,
          actorId: currentUserId,
        ),
        'Technician assigned.',
      );
    }
    technician.dispose();
  }

  Future<void> _diagnose(BuildContext context, RepairJob job) async {
    final diagnosis = TextEditingController(text: job.diagnosis);
    final faults = TextEditingController(text: job.faults.join(', '));
    final estimate = TextEditingController(
      text: job.estimatedRepairCost.toString(),
    );
    final submitted = await _repairDialog(
      context,
      title: 'Diagnose device',
      actionLabel: 'Save diagnosis',
      children: [
        TextField(
          controller: diagnosis,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Diagnosis'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: faults,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Faults (comma separated)',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: estimate,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Estimated repair cost (Le)',
          ),
        ),
      ],
    );
    if (submitted && context.mounted) {
      await _runRepairAction(
        context,
        () => repository.diagnose(
          job,
          diagnosis: diagnosis.text,
          faults: faults.text
              .split(',')
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList(),
          estimatedRepairCost: double.tryParse(estimate.text) ?? 0,
          actorId: currentUserId,
        ),
        'Diagnosis recorded.',
      );
    }
    diagnosis.dispose();
    faults.dispose();
    estimate.dispose();
  }

  Future<void> _review(
    BuildContext context,
    RepairJob job,
    bool approved,
  ) async {
    final notes = TextEditingController();
    final submitted = await _repairDialog(
      context,
      title: approved ? 'Approve repair' : 'Reject repair',
      actionLabel: approved ? 'Approve' : 'Reject',
      children: [
        TextField(
          controller: notes,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Approval notes / reason',
          ),
        ),
      ],
    );
    if (submitted && context.mounted) {
      await _runRepairAction(
        context,
        () => repository.reviewRepair(
          job,
          approved: approved,
          actorId: currentUserId,
          notes: notes.text,
        ),
        approved ? 'Repair approved.' : 'Repair rejected.',
      );
    }
    notes.dispose();
  }

  Future<void> _addPart(BuildContext context, RepairJob job) async {
    final name = TextEditingController();
    final number = TextEditingController();
    final quantity = TextEditingController(text: '1');
    final cost = TextEditingController(text: '0');
    final submitted = await _repairDialog(
      context,
      title: 'Record spare part',
      actionLabel: 'Add part',
      children: [
        TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'Part name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: number,
          decoration: const InputDecoration(labelText: 'Part number'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: quantity,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Quantity'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: cost,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Unit cost (Le)'),
        ),
      ],
    );
    if (submitted && context.mounted) {
      await _runRepairAction(
        context,
        () => repository.addPart(
          job,
          name: name.text,
          partNumber: number.text,
          quantity: int.tryParse(quantity.text) ?? 0,
          unitCost: double.tryParse(cost.text) ?? -1,
          actorId: currentUserId,
        ),
        'Spare part recorded.',
      );
    }
    name.dispose();
    number.dispose();
    quantity.dispose();
    cost.dispose();
  }

  Future<void> _recordProgress(BuildContext context, RepairJob job) async {
    var progress = job.progressPercent.clamp(10, 95).toDouble();
    final details = TextEditingController();
    final submitted =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocalState) => AlertDialog(
              title: const Text('Update repair progress'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${progress.round()}%'),
                  Slider(
                    value: progress,
                    min: 10,
                    max: 95,
                    divisions: 17,
                    onChanged: (value) => setLocalState(() => progress = value),
                  ),
                  TextField(
                    controller: details,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Work completed / next step',
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
                  child: const Text('Update'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (submitted && context.mounted) {
      await _runRepairAction(
        context,
        () => repository.recordProgress(
          job,
          progressPercent: progress.round(),
          details: details.text,
          actorId: currentUserId,
        ),
        'Repair progress updated.',
      );
    }
    details.dispose();
  }

  Future<void> _qualityControl(BuildContext context, RepairJob job) async {
    final checks = <String, bool>{
      'Device powers on and functions': false,
      'Electrical and battery safety passed': false,
      'Data securely wiped': false,
      'Cosmetic condition verified': false,
      'Accessories and ports tested': false,
    };
    var grade = RefurbishmentGrade.gradeB;
    final warranty = TextEditingController(text: '3');
    final notes = TextEditingController();
    final submitted =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocalState) => AlertDialog(
              title: const Text('Quality control'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final entry in checks.entries)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: entry.value,
                        onChanged: (value) => setLocalState(
                          () => checks[entry.key] = value ?? false,
                        ),
                        title: Text(entry.key),
                      ),
                    DropdownButtonFormField<RefurbishmentGrade>(
                      initialValue: grade,
                      decoration: const InputDecoration(
                        labelText: 'Refurbishment grade',
                      ),
                      items: RefurbishmentGrade.values
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value.label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setLocalState(() => grade = value!),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: warranty,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Warranty (months)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notes,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Quality findings',
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'All checks must pass to mark the device repaired. A failed test returns it to repair in progress.',
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
                  child: const Text('Submit QC'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (submitted && context.mounted) {
      await _runRepairAction(
        context,
        () => repository.performQualityControl(
          job,
          checks: checks,
          notes: notes.text,
          grade: grade,
          warrantyMonths: (int.tryParse(warranty.text) ?? 0).clamp(0, 60),
          actorId: currentUserId,
        ),
        checks.values.every((value) => value)
            ? 'Quality control passed; item marked refurbished.'
            : 'Quality control failed; item returned for repair.',
      );
    }
    warranty.dispose();
    notes.dispose();
  }

  Future<void> _markUnrepairable(BuildContext context, RepairJob job) async {
    final reason = TextEditingController();
    final submitted = await _repairDialog(
      context,
      title: 'Mark item unrepairable',
      actionLabel: 'Mark unrepairable',
      children: [
        TextField(
          controller: reason,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Technical reason'),
        ),
      ],
    );
    if (submitted && context.mounted) {
      await _runRepairAction(
        context,
        () => repository.markUnrepairable(
          job,
          reason: reason.text,
          actorId: currentUserId,
        ),
        'Item marked unrepairable and routed to recycling.',
      );
    }
    reason.dispose();
  }

  Future<void> _updateWarranty(BuildContext context, RepairJob job) async {
    final initialDate =
        job.warrantyEnd ?? DateTime.now().add(const Duration(days: 90));
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date != null && context.mounted) {
      await _runRepairAction(
        context,
        () => repository.updateWarranty(
          job,
          warrantyEnd: date,
          actorId: currentUserId,
        ),
        'Warranty updated.',
      );
    }
  }

  Future<void> _approveDisposition(BuildContext context, RepairJob job) async {
    var disposition = RefurbishedDisposition.donation;
    final recipient = TextEditingController();
    final price = TextEditingController();
    final notes = TextEditingController();
    final submitted =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocalState) => AlertDialog(
              title: const Text('Donation or resale approval'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<RefurbishedDisposition>(
                      initialValue: disposition,
                      decoration: const InputDecoration(
                        labelText: 'Disposition',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: RefurbishedDisposition.donation,
                          child: Text('Donation'),
                        ),
                        DropdownMenuItem(
                          value: RefurbishedDisposition.resale,
                          child: Text('Resale'),
                        ),
                      ],
                      onChanged: (value) =>
                          setLocalState(() => disposition = value!),
                    ),
                    const SizedBox(height: 12),
                    if (disposition == RefurbishedDisposition.donation)
                      TextField(
                        controller: recipient,
                        decoration: const InputDecoration(
                          labelText: 'Donation recipient',
                        ),
                      ),
                    if (disposition == RefurbishedDisposition.resale)
                      TextField(
                        controller: price,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Approved resale price (Le)',
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notes,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Approval notes',
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
                  child: const Text('Approve'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (submitted && context.mounted) {
      await _runRepairAction(
        context,
        () => repository.approveDisposition(
          job,
          disposition: disposition,
          resalePrice: double.tryParse(price.text),
          donationRecipient: recipient.text,
          actorId: currentUserId,
          notes: notes.text,
        ),
        '${disposition.name} approved.',
      );
    }
    recipient.dispose();
    price.dispose();
    notes.dispose();
  }
}

class _AssessmentCard extends StatelessWidget {
  const _AssessmentCard({required this.job});
  final RepairJob job;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Assessment and diagnosis',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            job.assessmentNotes.isEmpty
                ? 'No assessment notes.'
                : job.assessmentNotes,
          ),
          const Divider(),
          Text(job.diagnosis.isEmpty ? 'Awaiting diagnosis.' : job.diagnosis),
          if (job.faults.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final fault in job.faults) Text('• $fault'),
          ],
        ],
      ),
    ),
  );
}

class _CostCard extends StatelessWidget {
  const _CostCard({required this.job});
  final RepairJob job;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 24,
        runSpacing: 8,
        children: [
          Text(
            'Repair estimate: ${AppCurrency.format(job.estimatedRepairCost)}',
          ),
          Text('Parts used: ${AppCurrency.format(job.actualPartsCost)}'),
          Text(
            'Projected total: ${AppCurrency.format(job.projectedTotalCost)}',
          ),
        ],
      ),
    ),
  );
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.job,
    required this.canApprove,
    required this.canWork,
    required this.assign,
    required this.diagnose,
    required this.approve,
    required this.reject,
    required this.start,
    required this.addPart,
    required this.progress,
    required this.beginQc,
    required this.qualityControl,
    required this.unrepairable,
    required this.warranty,
    required this.disposition,
  });
  final RepairJob job;
  final bool canApprove, canWork;
  final VoidCallback assign,
      diagnose,
      approve,
      reject,
      start,
      addPart,
      progress,
      beginQc,
      qualityControl,
      unrepairable,
      warranty,
      disposition;

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[];
    if (canApprove && job.status == RepairStatus.awaitingAssessment) {
      actions.add(_button(Icons.person_add_alt, 'Assign technician', assign));
    }
    if (canWork &&
        [
          RepairStatus.awaitingAssessment,
          RepairStatus.diagnosed,
        ].contains(job.status)) {
      actions.add(_button(Icons.search, 'Diagnose / record faults', diagnose));
    }
    if (canApprove && job.status == RepairStatus.diagnosed) {
      actions.add(
        _button(Icons.check_circle_outline, 'Approve repair', approve),
      );
      actions.add(_button(Icons.cancel_outlined, 'Reject repair', reject));
    }
    if (canWork && job.status == RepairStatus.approved) {
      actions.add(_button(Icons.play_arrow, 'Start repair', start));
    }
    if (canWork && job.status == RepairStatus.repairInProgress) {
      actions.add(_button(Icons.settings, 'Record spare part', addPart));
      actions.add(_button(Icons.trending_up, 'Update progress', progress));
      actions.add(
        _button(Icons.fact_check_outlined, 'Begin quality testing', beginQc),
      );
    }
    if (canWork && job.status == RepairStatus.qualityTesting) {
      actions.add(
        _button(
          Icons.verified_outlined,
          'Perform quality control',
          qualityControl,
        ),
      );
    }
    if (canWork &&
        ![
          RepairStatus.completed,
          RepairStatus.rejected,
          RepairStatus.unrepairable,
        ].contains(job.status)) {
      actions.add(
        _button(Icons.build_circle_outlined, 'Mark unrepairable', unrepairable),
      );
    }
    if (canApprove && job.status == RepairStatus.completed) {
      actions.add(_button(Icons.shield_outlined, 'Manage warranty', warranty));
      actions.add(
        _button(
          Icons.volunteer_activism_outlined,
          'Approve donation or resale',
          disposition,
        ),
      );
    }
    if (actions.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(spacing: 8, runSpacing: 8, children: actions),
      ),
    );
  }

  Widget _button(IconData icon, String label, VoidCallback onPressed) =>
      FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      );
}

class _RefurbishmentCard extends StatelessWidget {
  const _RefurbishmentCard({required this.job});
  final RepairJob job;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Refurbishment and warranty',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text('Grade: ${job.grade?.label ?? 'Not assigned'}'),
          Text(
            'Warranty: ${job.warrantyStart ?? '—'} to ${job.warrantyEnd ?? '—'}',
          ),
          Text(
            job.warrantyActive
                ? 'Warranty active'
                : 'Warranty expired or not configured',
          ),
          const Divider(),
          Text('Disposition: ${job.disposition.name}'),
          Text(job.dispositionApproved ? 'Approved' : 'Awaiting approval'),
          if (job.disposition == RefurbishedDisposition.donation)
            Text('Recipient: ${job.donationRecipient}'),
          if (job.disposition == RefurbishedDisposition.resale)
            Text(
              'Resale price: ${job.resalePrice == null ? '—' : AppCurrency.format(job.resalePrice!)}',
            ),
        ],
      ),
    ),
  );
}

IconData _statusIcon(RepairStatus status) => switch (status) {
  RepairStatus.awaitingAssessment => Icons.pending_actions,
  RepairStatus.diagnosed => Icons.search,
  RepairStatus.approved => Icons.check_circle_outline,
  RepairStatus.repairInProgress => Icons.build,
  RepairStatus.qualityTesting => Icons.fact_check_outlined,
  RepairStatus.completed => Icons.verified,
  RepairStatus.rejected => Icons.cancel_outlined,
  RepairStatus.unrepairable => Icons.build_circle_outlined,
};

Future<bool> _repairDialog(
  BuildContext context, {
  required String title,
  required String actionLabel,
  required List<Widget> children,
}) async =>
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
            child: Text(actionLabel),
          ),
        ],
      ),
    ) ??
    false;

Future<void> _runRepairAction(
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
        SnackBar(content: Text('Repair operation failed: $error')),
      );
    }
  }
}
