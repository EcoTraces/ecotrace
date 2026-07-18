import 'package:flutter/material.dart';

import '../data/organization_repository.dart';
import '../domain/organization.dart';

class OrganizationListScreen extends StatelessWidget {
  const OrganizationListScreen({
    super.key,
    required this.repository,
    required this.userId,
  });

  final OrganizationRepository repository;
  final String userId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Organizations')),
    body: StreamBuilder<List<Organization>>(
      stream: repository.watchForUser(userId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Unable to load organizations: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final organizations = snapshot.data!;
        if (organizations.isEmpty) {
          return const _EmptyOrganizations();
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: organizations.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final organization = organizations[index];
            return Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.apartment)),
                title: Text(organization.name),
                subtitle: Text(
                  '${organization.type.label} • ${_statusLabel(organization.status)}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => OrganizationDetailScreen(
                      repository: repository,
                      organizationId: organization.id,
                      userId: userId,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RegisterOrganizationScreen(
            repository: repository,
            userId: userId,
          ),
        ),
      ),
      icon: const Icon(Icons.add_business),
      label: const Text('Register'),
    ),
  );
}

class OrganizationReviewScreen extends StatelessWidget {
  const OrganizationReviewScreen({super.key, required this.repository});
  final OrganizationRepository repository;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Organization verification')),
    body: StreamBuilder<List<Organization>>(
      stream: repository.watchPendingVerification(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Unable to load applications: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Center(
            child: Text('No applications awaiting verification.'),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: snapshot.data!.length,
          itemBuilder: (context, index) {
            final organization = snapshot.data![index];
            return Card(
              child: ListTile(
                leading: const Icon(Icons.pending_actions),
                title: Text(organization.name),
                subtitle: Text(
                  '${organization.type.label}\n${organization.registrationNumber}',
                ),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  onSelected: (decision) =>
                      _review(context, organization, decision == 'approve'),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'approve', child: Text('Approve')),
                    PopupMenuItem(value: 'reject', child: Text('Reject')),
                  ],
                ),
              ),
            );
          },
        );
      },
    ),
  );

  Future<void> _review(
    BuildContext context,
    Organization organization,
    bool approved,
  ) async {
    String? reason;
    if (!approved) {
      final controller = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reject application'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Reason'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Reject'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (reason == null || reason.trim().isEmpty) return;
    }
    try {
      await repository.review(
        organizationId: organization.id,
        approved: approved,
        reason: reason,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              approved ? 'Organization approved.' : 'Organization rejected.',
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Review failed: $error')));
      }
    }
  }
}

class _EmptyOrganizations extends StatelessWidget {
  const _EmptyOrganizations();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.domain_add_outlined, size: 72),
          SizedBox(height: 16),
          Text(
            'No organizations yet',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 8),
          Text(
            'Register a business, institution, recycler, or service provider.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class RegisterOrganizationScreen extends StatefulWidget {
  const RegisterOrganizationScreen({
    super.key,
    required this.repository,
    required this.userId,
  });
  final OrganizationRepository repository;
  final String userId;

  @override
  State<RegisterOrganizationScreen> createState() =>
      _RegisterOrganizationScreenState();
}

class _RegisterOrganizationScreenState
    extends State<RegisterOrganizationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _registration = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _areas = TextEditingController();
  OrganizationType _type = OrganizationType.business;
  bool _busy = false;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _registration,
      _email,
      _phone,
      _address,
      _areas,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final id = await widget.repository.create(
        ownerId: widget.userId,
        name: _name.text,
        type: _type,
        registrationNumber: _registration.text,
        contactEmail: _email.text,
        contactPhone: _phone.text,
        address: _address.text,
        serviceAreas: _areas.text
            .split(',')
            .map((area) => area.trim())
            .where((area) => area.isNotEmpty)
            .toSet()
            .toList(),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => OrganizationDetailScreen(
            repository: widget.repository,
            organizationId: id,
            userId: widget.userId,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Register organization')),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Organization details',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 20),
          _field(
            _name,
            'Legal or registered name',
            Icons.apartment,
            required: true,
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<OrganizationType>(
            initialValue: _type,
            decoration: const InputDecoration(
              labelText: 'Organization type',
              prefixIcon: Icon(Icons.category_outlined),
            ),
            items: OrganizationType.values
                .map(
                  (type) =>
                      DropdownMenuItem(value: type, child: Text(type.label)),
                )
                .toList(),
            onChanged: _busy ? null : (type) => setState(() => _type = type!),
          ),
          const SizedBox(height: 14),
          _field(
            _registration,
            'Registration number',
            Icons.numbers,
            required: true,
          ),
          const SizedBox(height: 14),
          _field(
            _email,
            'Contact email',
            Icons.email_outlined,
            required: true,
            email: true,
          ),
          const SizedBox(height: 14),
          _field(_phone, 'Contact phone', Icons.phone_outlined, required: true),
          const SizedBox(height: 14),
          _field(
            _address,
            'Primary address',
            Icons.location_on_outlined,
            required: true,
            lines: 2,
          ),
          const SizedBox(height: 14),
          _field(
            _areas,
            'Service areas (comma separated)',
            Icons.map_outlined,
            required: true,
            lines: 2,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: const Icon(Icons.send_outlined),
            label: Text(_busy ? 'Submitting…' : 'Submit for verification'),
          ),
        ],
      ),
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    required bool required,
    bool email = false,
    int lines = 1,
  }) => TextFormField(
    controller: controller,
    maxLines: lines,
    keyboardType: email ? TextInputType.emailAddress : TextInputType.text,
    decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
    validator: (value) {
      if (required && (value == null || value.trim().isEmpty)) {
        return 'This field is required.';
      }
      if (email && value != null && !value.contains('@')) {
        return 'Enter a valid email.';
      }
      return null;
    },
  );
}

class OrganizationDetailScreen extends StatelessWidget {
  const OrganizationDetailScreen({
    super.key,
    required this.repository,
    required this.organizationId,
    required this.userId,
  });
  final OrganizationRepository repository;
  final String organizationId;
  final String userId;

  @override
  Widget build(BuildContext context) => StreamBuilder<Organization?>(
    stream: repository.watchOrganization(organizationId),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(child: CircularProgressIndicator()),
        );
      }
      final organization = snapshot.data!;
      return Scaffold(
        appBar: AppBar(title: Text(organization.name)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StatusCard(organization: organization),
            const SizedBox(height: 12),
            _InformationCard(organization: organization),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Verification documents',
              action: TextButton.icon(
                onPressed: () => _upload(context),
                icon: const Icon(Icons.upload_file),
                label: const Text('Upload'),
              ),
              child: StreamBuilder<List<OrganizationDocument>>(
                stream: repository.watchDocuments(organizationId),
                builder: (context, documentSnapshot) => _SimpleList(
                  empty: 'No documents uploaded.',
                  items: (documentSnapshot.data ?? [])
                      .map((document) => document.name)
                      .toList(),
                  icon: Icons.description_outlined,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Branches',
              action: TextButton.icon(
                onPressed: () => _addBranch(context),
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
              child: StreamBuilder<List<OrganizationBranch>>(
                stream: repository.watchBranches(organizationId),
                builder: (context, branchSnapshot) => _SimpleList(
                  empty: 'No branches added.',
                  items: (branchSnapshot.data ?? [])
                      .map((branch) => '${branch.name} — ${branch.address}')
                      .toList(),
                  icon: Icons.location_city_outlined,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Staff',
              action: TextButton.icon(
                onPressed: () => _inviteStaff(context),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Invite'),
              ),
              child: const Text(
                'Invite staff by email. Membership becomes active after the invitation is accepted.',
              ),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _upload(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Document selection is temporarily unavailable. The secure Storage upload service is configured.',
        ),
      ),
    );
  }

  Future<void> _addBranch(BuildContext context) async {
    final name = TextEditingController();
    final address = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add branch'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Branch name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: address,
              decoration: const InputDecoration(labelText: 'Address'),
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
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (confirmed == true &&
        name.text.trim().isNotEmpty &&
        address.text.trim().isNotEmpty) {
      await repository.addBranch(
        organizationId,
        name: name.text,
        address: address.text,
      );
    }
    name.dispose();
    address.dispose();
  }

  Future<void> _inviteStaff(BuildContext context) async {
    final email = TextEditingController();
    String role = 'staff';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Invite staff member'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(
                  labelText: 'Organization role',
                ),
                items: const [
                  DropdownMenuItem(value: 'manager', child: Text('Manager')),
                  DropdownMenuItem(value: 'staff', child: Text('Staff')),
                  DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
                ],
                onChanged: (value) => setDialogState(() => role = value!),
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
              child: const Text('Invite'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && email.text.contains('@')) {
      await repository.inviteStaff(
        organizationId,
        email: email.text,
        role: role,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invitation created.')));
      }
    }
    email.dispose();
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.organization});
  final Organization organization;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: ListTile(
      leading: const Icon(Icons.fact_check_outlined),
      title: Text(_statusLabel(organization.status)),
      subtitle: Text(
        organization.rejectionReason ?? _statusMessage(organization.status),
      ),
    ),
  );
}

class _InformationCard extends StatelessWidget {
  const _InformationCard({required this.organization});
  final Organization organization;

  @override
  Widget build(BuildContext context) => _SectionCard(
    title: 'Organization information',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(organization.type.label),
        Text('Registration: ${organization.registrationNumber}'),
        Text(organization.contactEmail),
        Text(organization.contactPhone),
        Text(organization.address),
        Text('Service areas: ${organization.serviceAreas.join(', ')}'),
      ],
    ),
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.action});
  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

class _SimpleList extends StatelessWidget {
  const _SimpleList({
    required this.empty,
    required this.items,
    required this.icon,
  });
  final String empty;
  final List<String> items;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return Text(empty);
    return Column(
      children: items
          .map(
            (item) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon),
              title: Text(item),
            ),
          )
          .toList(),
    );
  }
}

String _statusLabel(OrganizationStatus status) => switch (status) {
  OrganizationStatus.draft => 'Draft',
  OrganizationStatus.pendingVerification => 'Pending verification',
  OrganizationStatus.approved => 'Approved',
  OrganizationStatus.rejected => 'Rejected',
  OrganizationStatus.suspended => 'Suspended',
};

String _statusMessage(OrganizationStatus status) => switch (status) {
  OrganizationStatus.draft => 'Complete the registration before submission.',
  OrganizationStatus.pendingVerification =>
    'EcoTrace is reviewing the organization and its documents.',
  OrganizationStatus.approved => 'This organization has been verified.',
  OrganizationStatus.rejected =>
    'Review the rejection reason and update the application.',
  OrganizationStatus.suspended =>
    'Organization access is temporarily suspended.',
};
