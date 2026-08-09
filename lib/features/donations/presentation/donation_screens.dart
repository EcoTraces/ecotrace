import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../data/donation_repository.dart';
import '../domain/donation.dart';

class DonationDashboardScreen extends StatelessWidget {
  const DonationDashboardScreen({
    super.key,
    required this.repository,
    required this.userId,
    required this.canManage,
  });
  final DonationRepository repository;
  final String userId;
  final bool canManage;
  @override
  Widget build(BuildContext c) => StreamBuilder<List<Beneficiary>>(
    stream: repository.watchBeneficiaries(),
    builder: (c, b) => StreamBuilder<List<DonationRequest>>(
      stream: repository.watchRequests(requesterId: canManage ? null : userId),
      builder: (c, r) {
        if (!b.hasData || !r.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final req = r.data!;
        final impact = DonationImpact(
          req.length,
          req
              .where(
                (x) => [
                  DonationStatus.delivered,
                  DonationStatus.confirmed,
                  DonationStatus.completed,
                ].contains(x.status),
              )
              .length,
          req.fold(0, (n, x) => n + x.allocatedJobIds.length),
          b.data!.fold(0, (n, x) => n + x.peopleServed),
        );
        return Scaffold(
          appBar: AppBar(title: const Text('Donation and social impact')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _request(c, b.data!),
            icon: const Icon(Icons.volunteer_activism),
            label: const Text('Donation request'),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 8,
                children: [
                  _m('Requests', '${impact.requests}'),
                  _m('Delivered', '${impact.delivered}'),
                  _m('Devices', '${impact.devices}'),
                  _m('People reached', '${impact.peopleReached}'),
                ],
              ),
              if (canManage)
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: () => _beneficiary(c),
                      child: const Text('Register beneficiary'),
                    ),
                  ],
                ),
              Text('Donation history', style: Theme.of(c).textTheme.titleLarge),
              for (final x in req)
                Card(
                  child: ExpansionTile(
                    title: Text('${x.requestNumber} • ${x.beneficiaryName}'),
                    subtitle: Text('${x.quantity} devices • ${x.status.name}'),
                    children: [
                      Text(x.purpose),
                      if (canManage)
                        Wrap(
                          spacing: 6,
                          children: [
                            if (x.status == DonationStatus.requested)
                              FilledButton(
                                onPressed: () =>
                                    repository.approve(x, true, userId),
                                child: const Text('Approve'),
                              ),
                            if (x.status == DonationStatus.approved)
                              FilledButton(
                                onPressed: () => _allocate(c, x),
                                child: const Text('Allocate'),
                              ),
                            if (x.status == DonationStatus.allocated)
                              FilledButton(
                                onPressed: () => repository.schedule(
                                  x,
                                  DateTime.now().add(const Duration(days: 7)),
                                  userId,
                                ),
                                child: const Text('Schedule'),
                              ),
                            if (x.status == DonationStatus.scheduled)
                              FilledButton(
                                onPressed: () => _deliver(c, x),
                                child: const Text('Delivery proof'),
                              ),
                            if (x.status == DonationStatus.confirmed)
                              FilledButton(
                                onPressed: () => _follow(c, x),
                                child: const Text('Follow-up'),
                              ),
                          ],
                        ),
                      if (!canManage && x.status == DonationStatus.delivered)
                        FilledButton(
                          onPressed: () => repository.confirm(
                            x,
                            'Beneficiary representative',
                          ),
                          child: const Text('Confirm receipt'),
                        ),
                      OutlinedButton(
                        onPressed: () => _certificate(x),
                        child: const Text('Certificate'),
                      ),
                    ],
                  ),
                ),
              if (canManage) ...[
                Text('Beneficiaries', style: Theme.of(c).textTheme.titleLarge),
                for (final beneficiary in b.data!)
                  ListTile(
                    title: Text(beneficiary.name),
                    subtitle: Text(
                      '${beneficiary.type.name} • ${beneficiary.eligibilityStatus.name} • ${beneficiary.eligibilityScore}%',
                    ),
                    trailing: TextButton(
                      onPressed: () => _assess(c, beneficiary),
                      child: const Text('Assess'),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    ),
  );
  Future<void> _beneficiary(BuildContext c) async {
    var type = BeneficiaryType.school;
    final n = TextEditingController(),
        contact = TextEditingController(),
        address = TextEditingController(),
        people = TextEditingController();
    final ok = await _form(c, 'Beneficiary', 'Register', [
      DropdownButtonFormField(
        initialValue: type,
        items: BeneficiaryType.values
            .map((x) => DropdownMenuItem(value: x, child: Text(x.name)))
            .toList(),
        onChanged: (x) => type = x!,
      ),
      TextField(
        controller: n,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      TextField(
        controller: contact,
        decoration: const InputDecoration(labelText: 'Contact'),
      ),
      TextField(
        controller: address,
        decoration: const InputDecoration(labelText: 'Address'),
      ),
      TextField(
        controller: people,
        decoration: const InputDecoration(labelText: 'People served'),
      ),
    ]);
    if (ok) {
      await repository.registerBeneficiary(
        name: n.text,
        type: type,
        contactName: contact.text,
        contact: contact.text,
        address: address.text,
        peopleServed: int.tryParse(people.text) ?? 0,
        actorId: userId,
      );
    }
  }

  Future<void> _request(BuildContext c, List<Beneficiary> b) async {
    if (b.isEmpty) {
      ScaffoldMessenger.of(c).showSnackBar(
        const SnackBar(content: Text('Register a beneficiary first.')),
      );
      return;
    }
    var selected = b.first;
    final q = TextEditingController(),
        types = TextEditingController(),
        purpose = TextEditingController();
    final ok = await _form(c, 'Donation request', 'Submit', [
      DropdownButtonFormField(
        initialValue: selected,
        items: b
            .map((x) => DropdownMenuItem(value: x, child: Text(x.name)))
            .toList(),
        onChanged: (x) => selected = x!,
      ),
      TextField(
        controller: types,
        decoration: const InputDecoration(
          labelText: 'Device types, comma separated',
        ),
      ),
      TextField(
        controller: q,
        decoration: const InputDecoration(labelText: 'Quantity'),
      ),
      TextField(
        controller: purpose,
        decoration: const InputDecoration(labelText: 'Purpose'),
      ),
    ]);
    if (ok) {
      await repository.submitRequest(
        requesterId: userId,
        beneficiary: selected,
        deviceTypes: types.text.split(','),
        quantity: int.tryParse(q.text) ?? 0,
        purpose: purpose.text,
      );
    }
  }

  Future<void> _assess(BuildContext c, Beneficiary beneficiary) async {
    var status = EligibilityStatus.eligible;
    final score = TextEditingController(text: '80'),
        notes = TextEditingController();
    final ok = await _form(c, 'Eligibility assessment', 'Record', [
      DropdownButtonFormField(
        initialValue: status,
        items: EligibilityStatus.values
            .map(
              (value) =>
                  DropdownMenuItem(value: value, child: Text(value.name)),
            )
            .toList(),
        onChanged: (value) => status = value!,
      ),
      TextField(
        controller: score,
        decoration: const InputDecoration(labelText: 'Eligibility score'),
      ),
      TextField(
        controller: notes,
        decoration: const InputDecoration(labelText: 'Assessment notes'),
      ),
    ]);
    if (ok) {
      await repository.assess(
        beneficiary,
        status: status,
        score: double.tryParse(score.text) ?? 0,
        notes: notes.text,
        actorId: userId,
      );
    }
  }

  Future<void> _allocate(BuildContext c, DonationRequest r) async {
    final jobs = await repository.watchEligibleDevices().first;
    if (jobs.isNotEmpty) {
      await repository.allocate(r, jobs.take(r.quantity).toList(), userId);
    }
  }

  Future<void> _deliver(BuildContext c, DonationRequest r) async {
    final f = await ImagePicker().pickImage(source: ImageSource.camera);
    if (f != null) await repository.deliver(r, await f.readAsBytes(), userId);
  }

  Future<void> _follow(BuildContext c, DonationRequest r) async {
    final p = TextEditingController(),
        a = TextEditingController(),
        n = TextEditingController();
    final ok = await _form(c, 'Usage follow-up', 'Complete', [
      TextField(
        controller: p,
        decoration: const InputDecoration(labelText: 'People reached'),
      ),
      TextField(
        controller: a,
        decoration: const InputDecoration(labelText: 'Active devices'),
      ),
      TextField(
        controller: n,
        decoration: const InputDecoration(labelText: 'Usage notes'),
      ),
    ]);
    if (ok) {
      await repository.followUp(
        r,
        peopleReached: int.tryParse(p.text) ?? 0,
        activeDevices: int.tryParse(a.text) ?? 0,
        notes: n.text,
        actorId: userId,
      );
    }
  }

  Future<void> _certificate(DonationRequest r) async {
    final certificate = await repository.certificate(r);
    final d = pw.Document();
    d.addPage(
      pw.Page(
        build: (_) => pw.Column(
          children: [
            pw.Header(text: 'EcoTrace Donation Certificate'),
            pw.Text('${certificate['certificateNumber'] ?? r.requestNumber}'),
            pw.Text(
              'Beneficiary: ${certificate['beneficiaryName'] ?? r.beneficiaryName}',
            ),
            pw.Text(
              'Devices: ${certificate['donatedQuantity'] ?? r.allocatedJobIds.length}',
            ),
            pw.Text('Status: ${r.status.name}'),
            pw.Text('Issued: ${certificate['issuedAt'] ?? r.deliveryAt}'),
          ],
        ),
      ),
    );
    await Printing.layoutPdf(onLayout: (_) => d.save());
  }
}

Widget _m(String a, String b) => SizedBox(
  width: 150,
  child: Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Text(
            b,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          Text(a),
        ],
      ),
    ),
  ),
);
Future<bool> _form(BuildContext c, String t, String a, List<Widget> w) async =>
    await showDialog<bool>(
      context: c,
      builder: (c) => AlertDialog(
        title: Text(t),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: w),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(a)),
        ],
      ),
    ) ??
    false;
