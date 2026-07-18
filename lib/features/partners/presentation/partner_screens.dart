import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/app_currency.dart';
import '../data/partner_repository.dart';
import '../domain/partner.dart';

class PartnerDashboardScreen extends StatelessWidget {
  const PartnerDashboardScreen({
    super.key,
    required this.repository,
    required this.currentUserId,
    required this.canManage,
  });
  final PartnerRepository repository;
  final String currentUserId;
  final bool canManage;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Recycling partners and vendors')),
    floatingActionButton: canManage
        ? FloatingActionButton.extended(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RegisterPartnerScreen(
                  repository: repository,
                  currentUserId: currentUserId,
                ),
              ),
            ),
            icon: const Icon(Icons.add_business_outlined),
            label: const Text('Register partner'),
          )
        : null,
    body: StreamBuilder<List<Partner>>(
      stream: repository.watchPartners(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Unable to load partners: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final partners = snapshot.data!;
        final analytics = PartnerAnalytics.fromPartners(partners);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
          children: [
            Text(
              'Partner analytics',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _metric(
                  'Registered',
                  analytics.total.toString(),
                  Icons.business_outlined,
                ),
                _metric(
                  'Active',
                  analytics.active.toString(),
                  Icons.verified_outlined,
                ),
                _metric(
                  'Pending verification',
                  analytics.pending.toString(),
                  Icons.pending_actions_outlined,
                ),
                _metric(
                  'Suspended',
                  analytics.suspended.toString(),
                  Icons.block_outlined,
                ),
                _metric(
                  'Average rating',
                  '${analytics.averageRating.toStringAsFixed(1)} / 5',
                  Icons.star_outline,
                ),
                _metric(
                  'Compliance',
                  '${analytics.averageCompliance.toStringAsFixed(1)}%',
                  Icons.policy_outlined,
                ),
                _metric(
                  'SLA compliance',
                  '${analytics.slaCompliancePercent.toStringAsFixed(1)}%',
                  Icons.timer_outlined,
                ),
                _metric(
                  'Total capacity',
                  '${analytics.totalCapacityKg.toStringAsFixed(0)} kg',
                  Icons.warehouse_outlined,
                ),
                _metric(
                  'Recorded spend',
                  AppCurrency.format(analytics.totalSpend),
                  Icons.payments_outlined,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Partners requiring attention',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final partner in partners.where(
              (value) => !value.canReceiveWork,
            ))
              ListTile(
                leading: const Icon(Icons.warning_amber),
                title: Text(partner.name),
                subtitle: Text(
                  '${partner.status.name} • Licence ${partner.licenceStatus.name}${partner.suspensionReason.isEmpty ? '' : '\n${partner.suspensionReason}'}',
                ),
              ),
            const SizedBox(height: 16),
            Text(
              'Partner directory',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (partners.isEmpty)
              const ListTile(title: Text('No external partners registered.')),
            for (final partner in partners)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(_partnerIcon(partner.type)),
                  ),
                  title: Text('${partner.partnerCode} • ${partner.name}'),
                  subtitle: Text(
                    '${partner.type.label} • ${partner.status.name}\nRating ${partner.performanceRating.toStringAsFixed(1)} • SLA ${partner.slaCompliancePercent.toStringAsFixed(1)}% • Compliance ${partner.complianceScore.toStringAsFixed(1)}%',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PartnerDetailScreen(
                        repository: repository,
                        partnerId: partner.id,
                        currentUserId: currentUserId,
                        canManage: canManage,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class RegisterPartnerScreen extends StatefulWidget {
  const RegisterPartnerScreen({
    super.key,
    required this.repository,
    required this.currentUserId,
  });
  final PartnerRepository repository;
  final String currentUserId;
  @override
  State<RegisterPartnerScreen> createState() => _RegisterPartnerScreenState();
}

class _RegisterPartnerScreenState extends State<RegisterPartnerScreen> {
  PartnerType type = PartnerType.recycler;
  final services = <PartnerServiceCategory>{
    PartnerServiceCategory.electronicsRecycling,
  };
  final name = TextEditingController(),
      contact = TextEditingController(),
      email = TextEditingController(),
      phone = TextEditingController(),
      address = TextEditingController(),
      areas = TextEditingController(),
      pricing = TextEditingController(),
      currency = TextEditingController(text: 'SLE'),
      capacity = TextEditingController(),
      paymentMethod = TextEditingController(),
      payee = TextEditingController(),
      paymentTerms = TextEditingController(text: 'Net 30 days');
  bool saving = false;

  @override
  void dispose() {
    for (final controller in [
      name,
      contact,
      email,
      phone,
      address,
      areas,
      pricing,
      currency,
      capacity,
      paymentMethod,
      payee,
      paymentTerms,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Partner registration')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<PartnerType>(
          initialValue: type,
          decoration: const InputDecoration(labelText: 'Partner type'),
          items: PartnerType.values
              .map(
                (value) =>
                    DropdownMenuItem(value: value, child: Text(value.label)),
              )
              .toList(),
          onChanged: (value) => setState(() => type = value!),
        ),
        TextField(
          controller: name,
          decoration: const InputDecoration(
            labelText: 'Registered partner name',
          ),
        ),
        TextField(
          controller: contact,
          decoration: const InputDecoration(labelText: 'Contact person'),
        ),
        TextField(
          controller: email,
          decoration: const InputDecoration(labelText: 'Contact email'),
        ),
        TextField(
          controller: phone,
          decoration: const InputDecoration(labelText: 'Contact phone'),
        ),
        TextField(
          controller: address,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Facility address'),
        ),
        const SizedBox(height: 12),
        Text(
          'Service categories',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Wrap(
          spacing: 6,
          children: PartnerServiceCategory.values
              .map(
                (value) => FilterChip(
                  label: Text(value.name),
                  selected: services.contains(value),
                  onSelected: (selected) => setState(
                    () =>
                        selected ? services.add(value) : services.remove(value),
                  ),
                ),
              )
              .toList(),
        ),
        TextField(
          controller: areas,
          decoration: const InputDecoration(
            labelText: 'Service areas',
            helperText: 'Comma-separated cities, districts, or regions',
          ),
        ),
        TextField(
          controller: pricing,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Pricing information'),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: currency,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Currency',
                  helperText: 'Sierra Leone leone (Le)',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: capacity,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Facility capacity (kg)',
                ),
              ),
            ),
          ],
        ),
        TextField(
          controller: paymentMethod,
          decoration: const InputDecoration(labelText: 'Payment method'),
        ),
        TextField(
          controller: payee,
          decoration: const InputDecoration(labelText: 'Payee name'),
        ),
        TextField(
          controller: paymentTerms,
          decoration: const InputDecoration(labelText: 'Payment terms'),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: saving ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Register for verification'),
        ),
      ],
    ),
  );

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await widget.repository.register(
        name: name.text,
        type: type,
        contactName: contact.text,
        contactEmail: email.text,
        contactPhone: phone.text,
        address: address.text,
        serviceCategories: services.toList(),
        serviceAreas: areas.text
            .split(',')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(),
        pricingInformation: pricing.text,
        currency: currency.text,
        facilityCapacityKg: double.tryParse(capacity.text) ?? 0,
        paymentMethod: paymentMethod.text,
        payeeName: payee.text,
        paymentTerms: paymentTerms.text,
        actorId: widget.currentUserId,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to register partner: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class PartnerDetailScreen extends StatelessWidget {
  const PartnerDetailScreen({
    super.key,
    required this.repository,
    required this.partnerId,
    required this.currentUserId,
    required this.canManage,
  });
  final PartnerRepository repository;
  final String partnerId, currentUserId;
  final bool canManage;

  @override
  Widget build(BuildContext context) => StreamBuilder<Partner>(
    stream: repository.watchPartner(partnerId),
    builder: (context, partnerSnapshot) {
      if (!partnerSnapshot.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final partner = partnerSnapshot.data!;
      return StreamBuilder<List<PartnerDocument>>(
        stream: repository.watchDocuments(partner.id),
        builder: (context, documentSnapshot) => StreamBuilder<List<PartnerContract>>(
          stream: repository.watchContracts(partner.id),
          builder: (context, contractSnapshot) => StreamBuilder<List<PartnerServiceRecord>>(
            stream: repository.watchServices(partner.id),
            builder: (context, serviceSnapshot) => StreamBuilder<List<PartnerComplianceRecord>>(
              stream: repository.watchCompliance(partner.id),
              builder: (context, complianceSnapshot) {
                final documents =
                    documentSnapshot.data ?? const <PartnerDocument>[];
                final contracts =
                    contractSnapshot.data ?? const <PartnerContract>[];
                final services =
                    serviceSnapshot.data ?? const <PartnerServiceRecord>[];
                final compliance =
                    complianceSnapshot.data ??
                    const <PartnerComplianceRecord>[];
                return Scaffold(
                  appBar: AppBar(
                    title: Text(partner.name),
                    actions: [
                      IconButton(
                        onPressed: () => _report(
                          partner,
                          documents,
                          contracts,
                          services,
                          compliance,
                        ),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
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
                                '${partner.partnerCode} • ${partner.type.label}',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              Text(
                                '${partner.status.name} • Licence ${partner.licenceStatus.name}',
                              ),
                              const Divider(),
                              Text(
                                '${partner.contactName} • ${partner.contactEmail} • ${partner.contactPhone}',
                              ),
                              Text(partner.address),
                              Text(
                                'Service areas: ${partner.serviceAreas.join(', ')}',
                              ),
                              Text(
                                'Services: ${partner.serviceCategories.map((value) => value.name).join(', ')}',
                              ),
                              Text(
                                'Capacity: ${partner.facilityCapacityKg.toStringAsFixed(1)} kg',
                              ),
                              Text(
                                'Pricing: ${partner.pricingInformation} (Sierra Leone leone)',
                              ),
                              Text(
                                'Payment: ${partner.paymentMethod} • ${partner.payeeName} • ${partner.paymentTerms}',
                              ),
                              if (partner.suspensionReason.isNotEmpty)
                                Text(
                                  'Suspension: ${partner.suspensionReason}',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (canManage)
                            FilledButton.tonal(
                              onPressed: () => _commercial(context, partner),
                              child: const Text('Commercial details'),
                            ),
                          if (canManage)
                            FilledButton.tonal(
                              onPressed: () => _document(context, partner),
                              child: const Text('Add document'),
                            ),
                          if (canManage)
                            FilledButton.tonal(
                              onPressed: () => _contract(context, partner),
                              child: const Text('Contract'),
                            ),
                          if (canManage)
                            FilledButton.tonal(
                              onPressed: () => _service(context, partner),
                              child: const Text('Record service'),
                            ),
                          if (canManage)
                            FilledButton.tonal(
                              onPressed: () => _compliance(context, partner),
                              child: const Text('Compliance review'),
                            ),
                          if (canManage &&
                              partner.licenceStatus !=
                                  LicenceVerificationStatus.verified)
                            FilledButton(
                              onPressed: () => _verify(context, partner),
                              child: const Text('Verify licence'),
                            ),
                          if (canManage &&
                              partner.status == PartnerStatus.suspended)
                            FilledButton(
                              onPressed: () => _runPartner(
                                context,
                                () => repository.reactivate(
                                  partner,
                                  currentUserId,
                                ),
                                'Partner reactivated.',
                              ),
                              child: const Text('Reactivate'),
                            ),
                          if (canManage &&
                              partner.status == PartnerStatus.active)
                            OutlinedButton(
                              onPressed: () => _suspend(context, partner),
                              child: const Text('Suspend'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Document expiry alerts',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (documents.isEmpty)
                        const ListTile(
                          title: Text('No partner documents uploaded.'),
                        ),
                      for (final document in documents)
                        Card(
                          color:
                              document.expiresWithin(const Duration(days: 60))
                              ? Theme.of(context).colorScheme.errorContainer
                              : null,
                          child: ListTile(
                            leading: Icon(
                              document.verified
                                  ? Icons.verified_outlined
                                  : Icons.pending_actions,
                            ),
                            title: Text(
                              '${document.documentType} • ${document.referenceNumber}',
                            ),
                            subtitle: Text(
                              '${document.expired ? 'Expired' : 'Expires'} ${document.expiresAt}',
                            ),
                            trailing: canManage && !document.verified
                                ? TextButton(
                                    onPressed: () => repository.verifyDocument(
                                      partner,
                                      document,
                                    ),
                                    child: const Text('Verify'),
                                  )
                                : null,
                          ),
                        ),
                      const SizedBox(height: 16),
                      Text(
                        'Contracts and service-level agreements',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      for (final contract in contracts)
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.assignment_outlined),
                            title: Text(
                              '${contract.contractNumber} • ${contract.title}',
                            ),
                            subtitle: Text(
                              '${contract.status.name} • ${contract.startAt} to ${contract.endAt}\nSLA ${contract.slaTargetHours} h • Minimum rating ${contract.minimumQualityRating} • ${AppCurrency.format(contract.contractValue, currencyCode: contract.currency)}',
                            ),
                            isThreeLine: true,
                          ),
                        ),
                      const SizedBox(height: 16),
                      Text(
                        'Performance and SLA tracking',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      ListTile(
                        title: Text(
                          'Rating ${partner.performanceRating.toStringAsFixed(2)} / 5',
                        ),
                        subtitle: Text(
                          '${partner.completedServiceCount} services • ${partner.slaCompliancePercent.toStringAsFixed(1)}% on time • Spend ${AppCurrency.format(partner.totalSpend, currencyCode: partner.currency)}',
                        ),
                      ),
                      for (final service in services)
                        ListTile(
                          leading: Icon(
                            service.metSla
                                ? Icons.timer_outlined
                                : Icons.timer_off_outlined,
                          ),
                          title: Text(
                            '${service.reference} • ${service.serviceCategory.name}',
                          ),
                          subtitle: Text(
                            '${service.actualHours} / ${service.targetHours} hours • Rating ${service.qualityRating} • Cost ${AppCurrency.format(service.serviceCost, currencyCode: partner.currency)}\n${service.notes}',
                          ),
                          isThreeLine: true,
                        ),
                      const SizedBox(height: 16),
                      Text(
                        'Compliance records',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      for (final record in compliance)
                        ListTile(
                          leading: const Icon(Icons.policy_outlined),
                          title: Text(
                            '${record.type} • ${record.score.toStringAsFixed(1)}% • ${record.outcome}',
                          ),
                          subtitle: Text(
                            '${record.findings}\nNext review ${record.nextReviewAt}',
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
    },
  );

  Future<void> _document(BuildContext context, Partner partner) async {
    final type = TextEditingController(text: 'Operating licence'),
        reference = TextEditingController();
    DateTime issued = DateTime.now(),
        expires = DateTime.now().add(const Duration(days: 365));
    Uint8List? file;
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Partner licence or document'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: type,
                    decoration: const InputDecoration(
                      labelText: 'Document type',
                    ),
                  ),
                  TextField(
                    controller: reference,
                    decoration: const InputDecoration(
                      labelText: 'Reference number',
                    ),
                  ),
                  ListTile(
                    title: const Text('Issued'),
                    subtitle: Text('$issued'),
                    onTap: () async {
                      final date = await _date(context, issued);
                      if (date != null) setLocal(() => issued = date);
                    },
                  ),
                  ListTile(
                    title: const Text('Expires'),
                    subtitle: Text('$expires'),
                    onTap: () async {
                      final date = await _date(context, expires);
                      if (date != null) setLocal(() => expires = date);
                    },
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await ImagePicker().pickImage(
                        source: ImageSource.gallery,
                        imageQuality: 80,
                      );
                      if (picked != null) {
                        file = await picked.readAsBytes();
                        setLocal(() {});
                      }
                    },
                    icon: const Icon(Icons.attach_file),
                    label: Text(
                      file == null
                          ? 'Select document image'
                          : 'Document selected',
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
                  child: const Text('Upload'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (ok && context.mounted && file != null) {
      await _runPartner(
        context,
        () => repository.addDocument(
          partner,
          documentType: type.text,
          referenceNumber: reference.text,
          issuedAt: issued,
          expiresAt: expires,
          file: file!,
          actorId: currentUserId,
        ),
        'Partner document uploaded.',
      );
    }
    type.dispose();
    reference.dispose();
  }

  Future<void> _verify(BuildContext context, Partner partner) async {
    final notes = TextEditingController();
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Licence verification'),
        content: TextField(
          controller: notes,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Verification notes'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Reject'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Verify and activate'),
          ),
        ],
      ),
    );
    if (approved != null && context.mounted) {
      await _runPartner(
        context,
        () => repository.verifyLicence(
          partner,
          approved: approved,
          notes: notes.text,
          actorId: currentUserId,
        ),
        approved ? 'Licence verified.' : 'Licence rejected.',
      );
    }
    notes.dispose();
  }

  Future<void> _suspend(BuildContext context, Partner partner) async {
    final reason = TextEditingController();
    final ok = await _textDialog(
      context,
      'Suspend partner',
      'Suspension reason',
      reason,
      'Suspend',
    );
    if (ok && context.mounted) {
      await _runPartner(
        context,
        () => repository.suspend(partner, reason.text, currentUserId),
        'Partner suspended.',
      );
    }
    reason.dispose();
  }

  Future<void> _commercial(BuildContext context, Partner partner) async {
    final pricing = TextEditingController(text: partner.pricingInformation),
        currency = TextEditingController(text: AppCurrency.code),
        capacity = TextEditingController(text: '${partner.facilityCapacityKg}'),
        method = TextEditingController(text: partner.paymentMethod),
        payee = TextEditingController(text: partner.payeeName),
        terms = TextEditingController(text: partner.paymentTerms);
    final ok = await _form(
      context,
      'Pricing, capacity and payment information',
      'Update',
      [
        TextField(
          controller: pricing,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Pricing information'),
        ),
        TextField(
          controller: currency,
          readOnly: true,
          decoration: const InputDecoration(
            labelText: 'Currency',
            helperText: 'Sierra Leone leone (Le)',
          ),
        ),
        TextField(
          controller: capacity,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Facility capacity (kg)',
          ),
        ),
        TextField(
          controller: method,
          decoration: const InputDecoration(labelText: 'Payment method'),
        ),
        TextField(
          controller: payee,
          decoration: const InputDecoration(labelText: 'Payee name'),
        ),
        TextField(
          controller: terms,
          decoration: const InputDecoration(labelText: 'Payment terms'),
        ),
      ],
    );
    if (ok && context.mounted) {
      await _runPartner(
        context,
        () => repository.updateCommercialDetails(
          partner,
          pricingInformation: pricing.text,
          currency: currency.text,
          capacityKg: double.tryParse(capacity.text) ?? 0,
          paymentMethod: method.text,
          payeeName: payee.text,
          paymentTerms: terms.text,
        ),
        'Commercial details updated.',
      );
    }
    for (final controller in [
      pricing,
      currency,
      capacity,
      method,
      payee,
      terms,
    ]) {
      controller.dispose();
    }
  }

  Future<void> _contract(BuildContext context, Partner partner) async {
    final number = TextEditingController(),
        title = TextEditingController(),
        value = TextEditingController(),
        currency = TextEditingController(text: AppCurrency.code),
        hours = TextEditingController(text: '48'),
        rating = TextEditingController(text: '4'),
        terms = TextEditingController();
    DateTime start = DateTime.now(),
        end = DateTime.now().add(const Duration(days: 365));
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Partner contract and SLA'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: number,
                      decoration: const InputDecoration(
                        labelText: 'Contract number',
                      ),
                    ),
                    TextField(
                      controller: title,
                      decoration: const InputDecoration(
                        labelText: 'Contract title',
                      ),
                    ),
                    ListTile(
                      title: const Text('Start date'),
                      subtitle: Text('$start'),
                      onTap: () async {
                        final date = await _date(context, start);
                        if (date != null) setLocal(() => start = date);
                      },
                    ),
                    ListTile(
                      title: const Text('End date'),
                      subtitle: Text('$end'),
                      onTap: () async {
                        final date = await _date(context, end);
                        if (date != null) setLocal(() => end = date);
                      },
                    ),
                    TextField(
                      controller: value,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Contract value (Le)',
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
                    TextField(
                      controller: hours,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'SLA completion target (hours)',
                      ),
                    ),
                    TextField(
                      controller: rating,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Minimum quality rating',
                      ),
                    ),
                    TextField(
                      controller: terms,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Contract terms',
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
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (ok && context.mounted) {
      await _runPartner(
        context,
        () => repository.addContract(
          partner,
          contractNumber: number.text,
          title: title.text,
          startAt: start,
          endAt: end,
          contractValue: double.tryParse(value.text) ?? 0,
          currency: currency.text,
          slaTargetHours: double.tryParse(hours.text) ?? 0,
          minimumQualityRating: double.tryParse(rating.text) ?? 0,
          terms: terms.text,
        ),
        'Contract and SLA saved.',
      );
    }
    for (final controller in [
      number,
      title,
      value,
      currency,
      hours,
      rating,
      terms,
    ]) {
      controller.dispose();
    }
  }

  Future<void> _service(BuildContext context, Partner partner) async {
    var category =
        partner.serviceCategories.firstOrNull ?? PartnerServiceCategory.other;
    final reference = TextEditingController(),
        target = TextEditingController(text: '48'),
        actual = TextEditingController(),
        rating = TextEditingController(text: '5'),
        cost = TextEditingController(),
        notes = TextEditingController();
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Partner service performance'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: reference,
                      decoration: const InputDecoration(
                        labelText: 'Service or job reference',
                      ),
                    ),
                    DropdownButtonFormField<PartnerServiceCategory>(
                      initialValue: category,
                      items: PartnerServiceCategory.values
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setLocal(() => category = value!),
                    ),
                    TextField(
                      controller: target,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'SLA target hours',
                      ),
                    ),
                    TextField(
                      controller: actual,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Actual completion hours',
                      ),
                    ),
                    TextField(
                      controller: rating,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Quality rating (1–5)',
                      ),
                    ),
                    TextField(
                      controller: cost,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Service cost (Le)',
                      ),
                    ),
                    TextField(
                      controller: notes,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Performance notes',
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
      await _runPartner(
        context,
        () => repository.recordService(
          partner,
          reference: reference.text,
          serviceCategory: category,
          targetHours: double.tryParse(target.text) ?? 0,
          actualHours: double.tryParse(actual.text) ?? 0,
          qualityRating: double.tryParse(rating.text) ?? 0,
          serviceCost: double.tryParse(cost.text) ?? 0,
          notes: notes.text,
        ),
        'Service performance recorded.',
      );
    }
    for (final controller in [reference, target, actual, rating, cost, notes]) {
      controller.dispose();
    }
  }

  Future<void> _compliance(BuildContext context, Partner partner) async {
    final type = TextEditingController(text: 'Annual compliance review'),
        score = TextEditingController(),
        outcome = TextEditingController(),
        findings = TextEditingController();
    DateTime next = DateTime.now().add(const Duration(days: 365));
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Partner compliance record'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: type,
                    decoration: const InputDecoration(labelText: 'Review type'),
                  ),
                  TextField(
                    controller: score,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Compliance score (0–100)',
                    ),
                  ),
                  TextField(
                    controller: outcome,
                    decoration: const InputDecoration(labelText: 'Outcome'),
                  ),
                  TextField(
                    controller: findings,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Findings'),
                  ),
                  ListTile(
                    title: const Text('Next review'),
                    subtitle: Text('$next'),
                    onTap: () async {
                      final date = await _date(context, next);
                      if (date != null) setLocal(() => next = date);
                    },
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
                  child: const Text('Record'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (ok && context.mounted) {
      await _runPartner(
        context,
        () => repository.recordCompliance(
          partner,
          type: type.text,
          score: double.tryParse(score.text) ?? 0,
          outcome: outcome.text,
          findings: findings.text,
          nextReviewAt: next,
          actorId: currentUserId,
        ),
        'Compliance review recorded.',
      );
    }
    type.dispose();
    score.dispose();
    outcome.dispose();
    findings.dispose();
  }

  Future<void> _report(
    Partner partner,
    List<PartnerDocument> documents,
    List<PartnerContract> contracts,
    List<PartnerServiceRecord> services,
    List<PartnerComplianceRecord> compliance,
  ) async {
    final report = pw.Document();
    report.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Header(level: 0, text: 'EcoTrace Partner Performance Report'),
          pw.Text(
            '${partner.partnerCode} • ${partner.name} • ${partner.type.label}',
          ),
          pw.Text(
            'Status ${partner.status.name}; licence ${partner.licenceStatus.name}',
          ),
          pw.Text(
            'Services: ${partner.serviceCategories.map((value) => value.name).join(', ')}',
          ),
          pw.Text('Service areas: ${partner.serviceAreas.join(', ')}'),
          pw.Text('Capacity: ${partner.facilityCapacityKg} kg'),
          pw.Text(
            'Rating: ${partner.performanceRating.toStringAsFixed(2)} / 5',
          ),
          pw.Text(
            'SLA compliance: ${partner.slaCompliancePercent.toStringAsFixed(1)}%',
          ),
          pw.Text(
            'Compliance score: ${partner.complianceScore.toStringAsFixed(1)}%',
          ),
          pw.Header(level: 1, text: 'Documents and expiry'),
          ...documents.map(
            (document) => pw.Text(
              '${document.documentType}; ${document.referenceNumber}; verified ${document.verified}; expires ${document.expiresAt}',
            ),
          ),
          pw.Header(level: 1, text: 'Contracts and SLAs'),
          ...contracts.map(
            (contract) => pw.Text(
              '${contract.contractNumber}; ${contract.title}; ${contract.status.name}; SLA ${contract.slaTargetHours} hours; ${contract.startAt} to ${contract.endAt}',
            ),
          ),
          pw.Header(level: 1, text: 'Service performance'),
          ...services.map(
            (service) => pw.Text(
              '${service.reference}; ${service.serviceCategory.name}; ${service.actualHours}/${service.targetHours} hours; rating ${service.qualityRating}; cost ${service.serviceCost}',
            ),
          ),
          pw.Header(level: 1, text: 'Compliance history'),
          ...compliance.map(
            (record) => pw.Text(
              '${record.type}; ${record.score}%; ${record.outcome}; next review ${record.nextReviewAt}',
            ),
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (_) => report.save());
  }
}

IconData _partnerIcon(PartnerType type) => switch (type) {
  PartnerType.recycler => Icons.recycling,
  PartnerType.repairCentre => Icons.handyman_outlined,
  PartnerType.materialBuyer => Icons.shopping_cart_outlined,
  PartnerType.transporter => Icons.local_shipping_outlined,
  PartnerType.collectionService => Icons.delete_sweep_outlined,
  PartnerType.disposalFacility => Icons.factory_outlined,
  PartnerType.serviceProvider => Icons.business_center_outlined,
};
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
Future<DateTime?> _date(BuildContext context, DateTime initial) =>
    showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDate: initial,
    );
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
Future<bool> _textDialog(
  BuildContext context,
  String title,
  String label,
  TextEditingController controller,
  String action,
) => _form(context, title, action, [
  TextField(
    controller: controller,
    maxLines: 4,
    decoration: InputDecoration(labelText: label),
  ),
]);
Future<void> _runPartner(
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
        SnackBar(content: Text('Partner operation failed: $error')),
      );
    }
  }
}
