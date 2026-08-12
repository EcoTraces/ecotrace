import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../data/incident_repository.dart';
import '../domain/safety_incident.dart';

class IncidentDashboardScreen extends StatelessWidget {
  const IncidentDashboardScreen({
    super.key,
    required this.repository,
    required this.userId,
    required this.canManage,
  });
  final IncidentRepository repository;
  final String userId;
  final bool canManage;
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('Incident and safety management')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _report(c),
      icon: const Icon(Icons.add_alert),
      label: const Text('Report incident'),
    ),
    body: StreamBuilder<List<SafetyIncident>>(
      stream: repository.watchIncidents(),
      builder: (c, s) {
        if (s.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Incident data is unavailable: ${s.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final stats = SafetyStatistics.fromIncidents(s.data!);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _m('Total', stats.total),
                _m('Open', stats.open),
                _m('Closed', stats.closed),
                _m('Critical', stats.critical),
                _m('Overdue', stats.overdue),
              ],
            ),
            if (canManage)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _contact(c),
                  icon: const Icon(Icons.contact_phone),
                  label: const Text('Emergency contact'),
                ),
              ),
            Text('Safety incidents', style: Theme.of(c).textTheme.titleLarge),
            for (final i in s.data!)
              Card(
                color: i.overdue
                    ? Theme.of(c).colorScheme.errorContainer
                    : null,
                child: ListTile(
                  leading: Icon(
                    i.severity == SafetyIncidentSeverity.critical
                        ? Icons.emergency
                        : Icons.health_and_safety_outlined,
                  ),
                  title: Text('${i.number} • ${i.title}'),
                  subtitle: Text(
                    '${i.type.name} • ${i.severity.name} • ${i.status.name}\n${i.location}',
                  ),
                  isThreeLine: true,
                  onTap: () => Navigator.push(
                    c,
                    MaterialPageRoute(
                      builder: (_) => IncidentDetailScreen(
                        repository: repository,
                        id: i.id,
                        userId: userId,
                        canManage: canManage,
                      ),
                    ),
                  ),
                ),
              ),
            Text('Emergency contacts', style: Theme.of(c).textTheme.titleLarge),
            StreamBuilder<List<EmergencyContact>>(
              stream: repository.watchContacts(),
              builder: (c, x) => Column(
                children: [
                  for (final e in x.data ?? <EmergencyContact>[])
                    ListTile(
                      leading: const Icon(Icons.phone_in_talk),
                      title: Text(e.name),
                      subtitle: Text('${e.role} • ${e.region}'),
                      trailing: Text(e.phone),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
  Future<void> _report(BuildContext c) async {
    var type = SafetyIncidentType.accident,
        severity = SafetyIncidentSeverity.moderate;
    double? latitude, longitude;
    final title = TextEditingController(),
        description = TextEditingController(),
        location = TextEditingController(),
        staff = TextEditingController(),
        injury = TextEditingController(),
        hazard = TextEditingController(),
        response = TextEditingController();
    final evidence = <Uint8List>[];
    final ok = await showDialog<bool>(
      context: c,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Incident report'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField(
                  initialValue: type,
                  items: SafetyIncidentType.values
                      .map(
                        (x) => DropdownMenuItem(value: x, child: Text(x.name)),
                      )
                      .toList(),
                  onChanged: (x) => set(() => type = x!),
                ),
                DropdownButtonFormField(
                  initialValue: severity,
                  items: SafetyIncidentSeverity.values
                      .map(
                        (x) => DropdownMenuItem(value: x, child: Text(x.name)),
                      )
                      .toList(),
                  onChanged: (x) => set(() => severity = x!),
                ),
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                TextField(
                  controller: description,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                TextField(
                  controller: location,
                  decoration: const InputDecoration(
                    labelText: 'Incident location',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    var permission = await Geolocator.checkPermission();
                    if (permission == LocationPermission.denied) {
                      permission = await Geolocator.requestPermission();
                    }
                    if (permission == LocationPermission.denied ||
                        permission == LocationPermission.deniedForever) {
                      return;
                    }
                    final position = await Geolocator.getCurrentPosition();
                    set(() {
                      latitude = position.latitude;
                      longitude = position.longitude;
                    });
                  },
                  icon: const Icon(Icons.my_location),
                  label: Text(
                    latitude == null
                        ? 'Attach GPS coordinates'
                        : '${latitude!.toStringAsFixed(5)}, ${longitude!.toStringAsFixed(5)}',
                  ),
                ),
                TextField(
                  controller: staff,
                  decoration: const InputDecoration(
                    labelText: 'Staff involved, comma separated',
                  ),
                ),
                TextField(
                  controller: injury,
                  decoration: const InputDecoration(
                    labelText: 'Injury details',
                  ),
                ),
                TextField(
                  controller: hazard,
                  decoration: const InputDecoration(labelText: 'Hazard type'),
                ),
                TextField(
                  controller: response,
                  decoration: const InputDecoration(
                    labelText: 'Immediate response action',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final f = await ImagePicker().pickMultiImage();
                    for (final x in f) {
                      evidence.add(await x.readAsBytes());
                    }
                    set(() {});
                  },
                  icon: const Icon(Icons.photo),
                  label: Text('Evidence (${evidence.length})'),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Report'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await repository.report(
        type: type,
        severity: severity,
        title: title.text,
        description: description.text,
        location: location.text,
        latitude: latitude,
        longitude: longitude,
        staff: staff.text.split(',').map((x) => x.trim()).toList(),
        injuryDetails: injury.text,
        hazardType: hazard.text,
        response: response.text,
        evidence: evidence,
        actorId: userId,
      );
    }
  }

  Future<void> _contact(BuildContext c) async {
    final n = TextEditingController(),
        r = TextEditingController(),
        p = TextEditingController(),
        e = TextEditingController(),
        g = TextEditingController();
    final ok = await _form(c, 'Emergency contact', [
      TextField(
        controller: n,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      TextField(
        controller: r,
        decoration: const InputDecoration(labelText: 'Role'),
      ),
      TextField(
        controller: p,
        decoration: const InputDecoration(labelText: 'Phone'),
      ),
      TextField(
        controller: e,
        decoration: const InputDecoration(labelText: 'Email'),
      ),
      TextField(
        controller: g,
        decoration: const InputDecoration(labelText: 'Region'),
      ),
    ]);
    if (ok) {
      await repository.contact(
        name: n.text,
        role: r.text,
        phone: p.text,
        email: e.text,
        region: g.text,
      );
    }
  }
}

class IncidentDetailScreen extends StatelessWidget {
  const IncidentDetailScreen({
    super.key,
    required this.repository,
    required this.id,
    required this.userId,
    required this.canManage,
  });
  final IncidentRepository repository;
  final String id, userId;
  final bool canManage;
  @override
  Widget build(BuildContext c) => StreamBuilder<SafetyIncident>(
    stream: repository.watchIncident(id),
    builder: (c, s) {
      if (!s.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final i = s.data!;
      return Scaffold(
        appBar: AppBar(title: Text(i.number)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(i.title, style: Theme.of(c).textTheme.headlineSmall),
            Text('${i.status.name} • ${i.location}'),
            Text(i.description),
            Text('Staff: ${i.staffInvolved.join(', ')}'),
            Text('Injury: ${i.injuryDetails}'),
            Text('Hazard: ${i.hazardType}'),
            Text('Immediate response: ${i.immediateResponse}'),
            for (final u in i.evidenceUrls) Image.network(u, height: 160),
            if (i.rootCause.isNotEmpty)
              ListTile(
                title: const Text('Root cause'),
                subtitle: Text(i.rootCause),
              ),
            if (i.correctiveAction.isNotEmpty)
              ListTile(
                title: const Text('Corrective action'),
                subtitle: Text(
                  '${i.correctiveAction}\n${i.correctiveOwner} • due ${i.correctiveDueAt}',
                ),
              ),
            if (canManage)
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: () => repository.startInvestigation(i, userId),
                    child: const Text('Investigate'),
                  ),
                  FilledButton.tonal(
                    onPressed: () => _root(c, i),
                    child: const Text('Root cause'),
                  ),
                  FilledButton.tonal(
                    onPressed: () => _follow(c, i),
                    child: const Text('Follow-up'),
                  ),
                  FilledButton(
                    onPressed: () => _close(c, i),
                    child: const Text('Close'),
                  ),
                ],
              ),
            StreamBuilder<List<IncidentFollowUp>>(
              stream: repository.watchFollowUps(i.id),
              builder: (c, x) => Column(
                children: [
                  for (final f in x.data ?? <IncidentFollowUp>[])
                    ListTile(
                      title: Text(f.findings),
                      subtitle: Text('Risk remaining: ${f.riskRemaining}'),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
  Future<void> _root(BuildContext c, SafetyIncident i) async {
    final root = TextEditingController(),
        action = TextEditingController(),
        owner = TextEditingController();
    var due = DateTime.now().add(const Duration(days: 30));
    final ok = await showDialog<bool>(
      context: c,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Root cause and corrective action'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: root,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Root cause'),
                ),
                TextField(
                  controller: action,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Corrective action',
                  ),
                ),
                TextField(
                  controller: owner,
                  decoration: const InputDecoration(
                    labelText: 'Responsible owner',
                  ),
                ),
                ListTile(
                  title: const Text('Due date'),
                  subtitle: Text('$due'),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: c,
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2100),
                      initialDate: due,
                    );
                    if (date != null) set(() => due = date);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await repository.recordRootCause(
        i,
        rootCause: root.text,
        correctiveAction: action.text,
        owner: owner.text,
        dueAt: due,
      );
    }
  }

  Future<void> _follow(BuildContext c, SafetyIncident i) async {
    final n = TextEditingController();
    var riskRemaining = false;
    final ok = await showDialog<bool>(
      context: c,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Follow-up monitoring'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: n,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Findings'),
              ),
              SwitchListTile(
                value: riskRemaining,
                onChanged: (value) => set(() => riskRemaining = value),
                title: const Text('Risk remains after this follow-up'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await repository.followUp(
        i,
        findings: n.text,
        riskRemaining: riskRemaining,
        actorId: userId,
      );
    }
  }

  Future<void> _close(BuildContext c, SafetyIncident i) async {
    final notes = TextEditingController(text: 'Corrective actions verified');
    final ok = await _form(c, 'Close incident', [
      TextField(
        controller: notes,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Closure notes'),
      ),
    ]);
    if (ok) {
      await repository.close(i, notes.text, userId);
    }
  }
}

Widget _m(String s, int n) => SizedBox(
  width: 130,
  child: Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Text(
            '$n',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          Text(s),
        ],
      ),
    ),
  ),
);
Future<bool> _form(BuildContext c, String t, List<Widget> w) async =>
    await showDialog<bool>(
      context: c,
      builder: (c) => AlertDialog(
        title: Text(t),
        content: Column(mainAxisSize: MainAxisSize.min, children: w),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Save'),
          ),
        ],
      ),
    ) ??
    false;
