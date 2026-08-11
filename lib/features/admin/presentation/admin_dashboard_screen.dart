import 'package:flutter/material.dart';

import '../../audit/data/audit_repository.dart';
import '../../audit/presentation/audit_trail_screen.dart';
import '../../auth/domain/app_role.dart';
import '../../auth/domain/user_profile.dart';
import '../data/admin_repository.dart';
import '../domain/system_administration.dart';

class AdministrationDashboardScreen extends StatelessWidget {
  const AdministrationDashboardScreen({
    super.key,
    required this.repository,
    required this.auditRepository,
    this.initialTab = 0,
  });

  final AdminRepository repository;
  final AuditRepository auditRepository;
  final int initialTab;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 5,
    initialIndex: initialTab,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Administration'),
        bottom: const TabBar(
          isScrollable: true,
          tabs: [
            Tab(icon: Icon(Icons.dashboard_outlined), text: 'Overview'),
            Tab(icon: Icon(Icons.people_outline), text: 'Users'),
            Tab(
              icon: Icon(Icons.security_outlined),
              text: 'Roles & permissions',
            ),
            Tab(icon: Icon(Icons.tune), text: 'Configuration'),
            Tab(icon: Icon(Icons.history), text: 'Audit'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          _Overview(repository: repository),
          _Users(repository: repository),
          _Roles(repository: repository),
          _Configuration(repository: repository),
          AuditTrailScreen(repository: auditRepository, embedded: true),
        ],
      ),
    ),
  );
}

class _Overview extends StatefulWidget {
  const _Overview({required this.repository});
  final AdminRepository repository;
  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> {
  late Future<PlatformHealthSnapshot> health = widget.repository.checkHealth();
  bool seeding = false;

  @override
  Widget build(BuildContext context) => FutureBuilder<PlatformHealthSnapshot>(
    future: health,
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final data = snapshot.data!;
      return RefreshIndicator(
        onRefresh: () async =>
            setState(() => health = widget.repository.checkHealth()),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Platform health',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Metric(
                  label: 'Users',
                  value: '${data.userCount}',
                  icon: Icons.people,
                ),
                _Metric(
                  label: 'Pending claim sync',
                  value: '${data.pendingRoleChanges}',
                  icon: Icons.sync_problem,
                ),
                _Metric(
                  label: 'Overall',
                  value: data.healthy ? 'Healthy' : 'Attention',
                  icon: data.healthy
                      ? Icons.check_circle_outline
                      : Icons.warning_amber,
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...data.services.entries.map(
              (entry) => Card(
                child: ListTile(
                  leading: Icon(
                    _healthIcon(entry.value),
                    color: _healthColor(entry.value),
                  ),
                  title: Text(entry.key),
                  trailing: Text(entry.value.name),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Card(
              child: ListTile(
                leading: Icon(Icons.monitor_heart_outlined),
                title: Text('Health monitoring'),
                subtitle: Text(
                  'Checks authentication, Firestore access, configuration availability, user totals, and pending role-claim synchronization.',
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.auto_awesome_outlined),
                title: const Text('Dashboard demonstration data'),
                subtitle: Text(
                  widget.repository.canSeedDemoData
                      ? 'Create or refresh role-specific sample activity for every registered user.'
                      : 'Run the application with API_BASE_URL to enable secure demo-data generation.',
                ),
                trailing: FilledButton.icon(
                  onPressed:
                      !widget.repository.canSeedDemoData || seeding
                      ? null
                      : _seedDemoData,
                  icon: seeding
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.dataset_outlined),
                  label: Text(seeding ? 'Generating...' : 'Generate data'),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  IconData _healthIcon(PlatformServiceStatus status) => switch (status) {
    PlatformServiceStatus.operational => Icons.check_circle_outline,
    PlatformServiceStatus.degraded => Icons.warning_amber,
    PlatformServiceStatus.unavailable => Icons.error_outline,
  };
  Color _healthColor(PlatformServiceStatus status) => switch (status) {
    PlatformServiceStatus.operational => Colors.green,
    PlatformServiceStatus.degraded => Colors.orange,
    PlatformServiceStatus.unavailable => Colors.red,
  };

  Future<void> _seedDemoData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Generate demonstration data?'),
        content: const Text(
          'This creates clearly marked sample records for dashboards. '
          'Running it again refreshes the same records instead of duplicating them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Generate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => seeding = true);
    try {
      final count = await widget.repository.seedDemoData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count demonstration records are ready.')),
      );
      setState(() => health = widget.repository.checkHealth());
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to generate demo data: $error')),
      );
    } finally {
      if (mounted) setState(() => seeding = false);
    }
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.icon});
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 190,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}

class _Users extends StatelessWidget {
  const _Users({required this.repository});
  final AdminRepository repository;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<UserProfile>>(
    stream: repository.watchUsers(),
    builder: (context, snapshot) {
      if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: snapshot.data!.length,
        itemBuilder: (context, index) {
          final user = snapshot.data![index];
          return Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(
                user.displayName.isEmpty ? user.email : user.displayName,
              ),
              subtitle: Text(
                '${user.email}\n${user.role.label} • ${user.accountStatus.name}',
              ),
              isThreeLine: true,
              trailing: PopupMenuButton<String>(
                onSelected: (value) => _action(context, user, value),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'role', child: Text('Change role')),
                  PopupMenuItem(
                    value: 'status',
                    child: Text('Change account status'),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );

  Future<void> _action(
    BuildContext context,
    UserProfile user,
    String value,
  ) async {
    try {
      if (value == 'role') {
        var selected = user.role;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
              title: Text('Role for ${user.displayName}'),
              content: DropdownButtonFormField<AppRole>(
                initialValue: selected,
                items: AppRole.values
                    .map(
                      (role) => DropdownMenuItem(
                        value: role,
                        child: Text(role.label),
                      ),
                    )
                    .toList(),
                onChanged: (role) => setState(() => selected = role!),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save & queue claim sync'),
                ),
              ],
            ),
          ),
        );
        if (confirmed == true && selected != user.role) {
          await repository.changeRole(user, selected);
        }
      } else {
        var selected = user.accountStatus;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
              title: const Text('Account status'),
              content: DropdownButtonFormField<AccountStatus>(
                initialValue: selected,
                items: AccountStatus.values
                    .map(
                      (status) => DropdownMenuItem(
                        value: status,
                        child: Text(status.name),
                      ),
                    )
                    .toList(),
                onChanged: (status) => setState(() => selected = status!),
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Update'),
                ),
              ],
            ),
          ),
        );
        if (confirmed == true && selected != user.accountStatus) {
          await repository.updateAccountStatus(user, selected);
        }
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Administrative change saved and audited.'),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}

class _Roles extends StatelessWidget {
  const _Roles({required this.repository});
  final AdminRepository repository;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<RoleDefinition>>(
    stream: repository.watchRoles(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final stored = {
        for (final definition in snapshot.data!) definition.role: definition,
      };
      return ListView(
        padding: const EdgeInsets.all(12),
        children: AppRole.values.map((role) {
          final definition =
              stored[role] ?? RoleDefinition(role: role, permissions: const {});
          return Card(
            child: ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: Text(role.label),
              subtitle: Text(
                definition.permissions.isEmpty
                    ? 'No explicit permissions configured'
                    : definition.permissions.join(', '),
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _edit(context, definition),
            ),
          );
        }).toList(),
      );
    },
  );

  Future<void> _edit(BuildContext context, RoleDefinition definition) async {
    final selected = {...definition.permissions};
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('${definition.role.label} permissions'),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: administrationPermissions
                  .map(
                    (permission) => CheckboxListTile(
                      value: selected.contains(permission),
                      title: Text(permission),
                      onChanged: (enabled) => setState(
                        () => enabled!
                            ? selected.add(permission)
                            : selected.remove(permission),
                      ),
                    ),
                  )
                  .toList(),
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
    );
    if (saved == true) {
      await repository.saveRole(
        RoleDefinition(
          role: definition.role,
          permissions: selected,
          description: definition.description,
        ),
      );
    }
  }
}

class _Configuration extends StatelessWidget {
  const _Configuration({required this.repository});
  final AdminRepository repository;

  @override
  Widget build(BuildContext context) => StreamBuilder<SystemConfiguration>(
    stream: repository.watchConfiguration(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final config = snapshot.data!;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: () => _edit(context, config),
            icon: const Icon(Icons.tune),
            label: const Text('Edit platform configuration'),
          ),
          const SizedBox(height: 16),
          _section('Waste categories', config.wasteCategories),
          _section('Item conditions', config.itemConditions),
          _section('Service areas', config.serviceAreas),
          _section('Supported languages', config.supportedLanguages),
          _section(
            'Integrations (names only; secrets stay server-side)',
            config.integrationNames,
          ),
          _mapSection('Environmental formulas', config.environmentalFormulas),
          _textMapSection('System settings', config.settings),
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Managed elsewhere'),
              subtitle: Text(
                'Notification templates: Notifications screen.\n'
                'Pickup fees and reward rules: not yet exposed here - '
                'each is read from a separate configuration location by '
                'the code that calculates them.',
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget _section(String title, List<String> values) => Card(
    child: ListTile(
      title: Text(title),
      subtitle: Text(values.isEmpty ? 'Not configured' : values.join(', ')),
    ),
  );
  Widget _mapSection(String title, Map<String, double> values) => Card(
    child: ListTile(
      title: Text(title),
      subtitle: Text(
        values.entries.map((e) => '${e.key}=${e.value}').join(', '),
      ),
    ),
  );
  Widget _textMapSection(String title, Map<String, String> values) => Card(
    child: ListTile(
      title: Text(title),
      subtitle: Text(
        values.entries.map((e) => '${e.key}=${e.value}').join(', '),
      ),
    ),
  );

  Future<void> _edit(BuildContext context, SystemConfiguration config) async {
    final categories = TextEditingController(
      text: config.wasteCategories.join(', '),
    );
    final conditions = TextEditingController(
      text: config.itemConditions.join(', '),
    );
    final areas = TextEditingController(text: config.serviceAreas.join(', '));
    final languages = TextEditingController(
      text: config.supportedLanguages.join(', '),
    );
    final formulas = TextEditingController(
      text: _encodeNumbers(config.environmentalFormulas),
    );
    final settings = TextEditingController(
      text: config.settings.entries
          .map((e) => '${e.key}=${e.value}')
          .join('\n'),
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Platform configuration'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              children: [
                _field(categories, 'Waste categories (comma separated)'),
                _field(conditions, 'Item conditions (comma separated)'),
                _field(areas, 'Service areas (comma separated)'),
                _field(languages, 'Supported languages (comma separated)'),
                _field(
                  formulas,
                  'Environmental formulas (key=value, one per line)',
                  lines: 5,
                ),
                _field(
                  settings,
                  'System settings (key=value, one per line)',
                  lines: 5,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save & audit'),
          ),
        ],
      ),
    );
    if (saved == true) {
      try {
        await repository.saveConfiguration(
          SystemConfiguration(
            wasteCategories: _list(categories.text),
            itemConditions: _list(conditions.text),
            serviceAreas: _list(areas.text),
            supportedLanguages: _list(languages.text),
            integrationNames: config.integrationNames,
            notificationTemplateNames: const [],
            pickupFees: config.pickupFees,
            rewardRules: config.rewardRules,
            environmentalFormulas: _numberMap(formulas.text),
            settings: _stringMap(settings.text),
          ),
        );
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Configuration not saved: $error')),
          );
        }
      }
    }
    for (final controller in [
      categories,
      conditions,
      areas,
      languages,
      formulas,
      settings,
    ]) {
      controller.dispose();
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int lines = 2,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      maxLines: lines,
      decoration: InputDecoration(labelText: label, alignLabelWithHint: true),
    ),
  );

  String _encodeNumbers(Map<String, double> values) =>
      values.entries.map((e) => '${e.key}=${e.value}').join('\n');
  List<String> _list(String value) => value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList();
  Map<String, double> _numberMap(String value) => Map.fromEntries(
    value.split('\n').where((line) => line.trim().isNotEmpty).map((line) {
      final parts = line.split('=');
      if (parts.length < 2) {
        throw const FormatException('Use key=value for numeric rules.');
      }
      return MapEntry(
        parts.first.trim(),
        double.parse(parts.sublist(1).join('=').trim()),
      );
    }),
  );
  Map<String, String> _stringMap(String value) => Map.fromEntries(
    value.split('\n').where((line) => line.trim().isNotEmpty).map((line) {
      final split = line.indexOf('=');
      if (split < 1) {
        throw const FormatException('Use key=value for system settings.');
      }
      return MapEntry(
        line.substring(0, split).trim(),
        line.substring(split + 1).trim(),
      );
    }),
  );
}
