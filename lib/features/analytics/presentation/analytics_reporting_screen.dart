import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/app_currency.dart';
import '../data/analytics_repository.dart';
import '../domain/analytics_snapshot.dart';

class AnalyticsReportingScreen extends StatefulWidget {
  const AnalyticsReportingScreen({super.key, required this.repository});
  final AnalyticsRepository repository;
  @override
  State<AnalyticsReportingScreen> createState() => _A();
}

class _A extends State<AnalyticsReportingScreen> {
  DateTime from = DateTime.now().subtract(const Duration(days: 30)),
      to = DateTime.now();
  AnalyticsSnapshot? data;
  bool busy = false;
  List<DashboardWidgetConfig> widgets = const [];
  List<ReportDefinition> definitions = const [];
  @override
  void initState() {
    super.initState();
    _load();
    _loadWidgets();
    _loadDefinitions();
  }

  Future<void> _load() async {
    setState(() => busy = true);
    data = await widget.repository.load(from, to);
    if (mounted) setState(() => busy = false);
  }

  Future<void> _loadWidgets() async {
    final result = await widget.repository.getWidgets();
    if (mounted) setState(() => widgets = result);
  }

  Future<void> _loadDefinitions() async {
    final result = await widget.repository.getDefinitions();
    if (mounted) setState(() => definitions = result);
  }

  @override
  Widget build(BuildContext c) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Analytics and reporting'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Business intelligence'),
            Tab(text: 'Reports'),
            Tab(text: 'Widgets'),
          ],
        ),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: busy
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(children: [_dashboard(c), _reports(c), _widgets(c)]),
    ),
  );
  Widget _dashboard(BuildContext c) {
    final d = data!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${from.toString().split(' ').first} to ${to.toString().split(' ').first}',
              ),
            ),
            TextButton(
              onPressed: () => _dates(c),
              child: const Text('Custom dates'),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: d.metrics.entries
              .map(
                (e) => SizedBox(
                  width: 170,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Text(
                            _metricValue(e.key, e.value),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(e.key),
                        ],
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        Text('Waste categories', style: Theme.of(c).textTheme.titleLarge),
        ...d.categories.entries.map(
          (e) => ListTile(
            title: Text(e.key),
            trailing: Text('${e.value.toStringAsFixed(1)} kg'),
          ),
        ),
        Text('Regional distribution', style: Theme.of(c).textTheme.titleLarge),
        ...d.regions.entries.map(
          (e) => ListTile(
            title: Text(e.key),
            trailing: Text('${e.value.toInt()}'),
          ),
        ),
      ],
    );
  }

  Widget _reports(BuildContext c) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Wrap(
        spacing: 8,
        children: [
          FilledButton.icon(
            onPressed: _pdf,
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('PDF'),
          ),
          FilledButton.icon(
            onPressed: _csv,
            icon: const Icon(Icons.table_view),
            label: const Text('CSV / Excel'),
          ),
          FilledButton.tonal(
            onPressed: () => _schedule(c),
            child: const Text('Schedule report'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: Text(
              'Report definitions',
              style: Theme.of(c).textTheme.titleLarge,
            ),
          ),
          FilledButton.icon(
            onPressed: () => _newDefinition(c),
            icon: const Icon(Icons.add_chart_outlined),
            label: const Text('New report definition'),
          ),
        ],
      ),
      if (definitions.isEmpty)
        const ListTile(title: Text('No custom report definitions yet.')),
      for (final d in definitions)
        Card(
          child: ListTile(
            title: Text(d.name),
            subtitle: Text('${d.type.name} • fields: ${d.fields.join(', ')}'),
            trailing: TextButton(
              onPressed: () => _generate(c, d),
              child: const Text('Generate'),
            ),
          ),
        ),
      const SizedBox(height: 12),
      Text('Operational data', style: Theme.of(c).textTheme.titleLarge),
      for (final r in data!.rows.take(100))
        ListTile(
          title: Text('${r['dataset']} • ${r['reference']}'),
          subtitle: Text('${r['status']}'),
          trailing: Text(
            r['dataset'] == 'Financial' && r['value'] is num
                ? AppCurrency.format(r['value']! as num)
                : '${r['value']}',
          ),
        ),
      StreamBuilder<List<ReportSchedule>>(
        stream: widget.repository.watchSchedules(),
        builder: (c, s) => Column(
          children: [
            for (final x in s.data ?? <ReportSchedule>[])
              ListTile(
                leading: const Icon(Icons.schedule),
                title: Text(x.name),
                subtitle: Text(
                  '${x.type.name} • ${x.frequency} • ${x.recipients.join(', ')}',
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _widgets(BuildContext c) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Dashboard widgets',
              style: Theme.of(c).textTheme.titleLarge,
            ),
          ),
          FilledButton.icon(
            onPressed: () => _editWidget(c),
            icon: const Icon(Icons.add),
            label: const Text('Add widget'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (widgets.isEmpty)
        const ListTile(title: Text('No dashboard widgets configured yet.')),
      for (final w in widgets)
        Card(
          child: ListTile(
            leading: Icon(w.active ? Icons.widgets : Icons.widgets_outlined),
            title: Text(w.title),
            subtitle: Text(
              '${w.metric} • ${w.visualization} • order ${w.order}'
              '${w.roles.isEmpty ? '' : ' • ${w.roles.join(', ')}'}',
            ),
            trailing: IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _editWidget(c, existing: w),
            ),
          ),
        ),
    ],
  );

  Future<void> _editWidget(BuildContext c, {DashboardWidgetConfig? existing}) async {
    var metric = existing?.metric ?? DashboardWidgetConfig.metrics.first;
    var visualization =
        existing?.visualization ?? DashboardWidgetConfig.visualizations.first;
    var active = existing?.active ?? true;
    final title = TextEditingController(text: existing?.title ?? '');
    final roles = TextEditingController(
      text: existing?.roles.join(', ') ?? '',
    );
    final order = TextEditingController(
      text: (existing?.order ?? widgets.length).toString(),
    );
    final ok = await _f(c, existing == null ? 'Add widget' : 'Edit widget', [
      TextField(
        controller: title,
        decoration: const InputDecoration(labelText: 'Widget title'),
      ),
      DropdownButtonFormField(
        initialValue: metric,
        items: DashboardWidgetConfig.metrics
            .map((m) => DropdownMenuItem(value: m, child: Text(m)))
            .toList(),
        onChanged: (m) => metric = m ?? metric,
        decoration: const InputDecoration(labelText: 'Metric'),
      ),
      DropdownButtonFormField(
        initialValue: visualization,
        items: DashboardWidgetConfig.visualizations
            .map((v) => DropdownMenuItem(value: v, child: Text(v)))
            .toList(),
        onChanged: (v) => visualization = v ?? visualization,
        decoration: const InputDecoration(labelText: 'Visualization'),
      ),
      TextField(
        controller: roles,
        decoration: const InputDecoration(
          labelText: 'Visible to roles (comma-separated, blank = all)',
        ),
      ),
      TextField(
        controller: order,
        decoration: const InputDecoration(labelText: 'Order'),
        keyboardType: TextInputType.number,
      ),
      StatefulBuilder(
        builder: (c, setLocal) => CheckboxListTile(
          value: active,
          title: const Text('Active'),
          onChanged: (v) => setLocal(() => active = v ?? true),
        ),
      ),
    ]);
    if (ok) {
      await widget.repository.saveWidget(
        id: existing?.id ?? 'widget-${DateTime.now().millisecondsSinceEpoch}',
        title: title.text,
        metric: metric,
        visualization: visualization,
        roles: roles.text
            .split(',')
            .map((x) => x.trim())
            .where((x) => x.isNotEmpty)
            .toList(),
        order: int.tryParse(order.text) ?? 0,
        active: active,
      );
      await _loadWidgets();
    }
  }

  Future<void> _newDefinition(BuildContext c) async {
    var type = ReportType.custom;
    final name = TextEditingController();
    final fields = TextEditingController(text: 'status, createdAt');
    final groupBy = TextEditingController();
    final selectedMetrics = <String>{'count'};
    final ok = await _f(c, 'New report definition', [
      TextField(
        controller: name,
        decoration: const InputDecoration(labelText: 'Report name'),
      ),
      DropdownButtonFormField<ReportType>(
        initialValue: type,
        items: ReportType.values
            .map((x) => DropdownMenuItem(value: x, child: Text(x.name)))
            .toList(),
        onChanged: (x) => type = x ?? type,
        decoration: const InputDecoration(labelText: 'Report type'),
      ),
      TextField(
        controller: fields,
        decoration: const InputDecoration(
          labelText: 'Fields (comma-separated)',
        ),
      ),
      TextField(
        controller: groupBy,
        decoration: const InputDecoration(labelText: 'Group by (optional)'),
      ),
      StatefulBuilder(
        builder: (c, setLocal) => Wrap(
          spacing: 6,
          children: ReportDefinition.availableMetrics
              .map(
                (m) => FilterChip(
                  label: Text(m),
                  selected: selectedMetrics.contains(m),
                  onSelected: (v) => setLocal(
                    () => v ? selectedMetrics.add(m) : selectedMetrics.remove(m),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    ]);
    if (ok) {
      await widget.repository.createDefinition(
        name: name.text,
        type: type,
        fields: fields.text
            .split(',')
            .map((x) => x.trim())
            .where((x) => x.isNotEmpty)
            .toList(),
        groupBy: groupBy.text,
        metrics: selectedMetrics.toList(),
      );
      await _loadDefinitions();
    }
  }

  Future<void> _generate(BuildContext c, ReportDefinition d) async {
    final rows = await widget.repository.generateReport(
      definitionId: d.id,
      from: from,
      to: to,
    );
    if (!c.mounted) return;
    await showDialog<void>(
      context: c,
      builder: (c) => AlertDialog(
        title: Text('${d.name} • ${rows.length} record(s)'),
        content: SizedBox(
          width: 400,
          height: 400,
          child: ListView(
            children: [
              for (final row in rows.take(200))
                ListTile(
                  dense: true,
                  title: Text(row['id']?.toString() ?? ''),
                  subtitle: Text(
                    d.fields.map((f) => '$f: ${row[f]}').join(' • '),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _dates(BuildContext c) async {
    final a = await showDateRangePicker(
      context: c,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: from, end: to),
    );
    if (a != null) {
      from = a.start;
      to = a.end;
      _load();
    }
  }

  Future<void> _pdf() async {
    final d = pw.Document();
    d.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Header(text: 'EcoTrace Analytics Report'),
          pw.Text('$from to $to'),
          ...data!.metrics.entries.map(
            (e) => pw.Text('${e.key}: ${_metricValue(e.key, e.value)}'),
          ),
          pw.TableHelper.fromTextArray(
            headers: const ['Dataset', 'Reference', 'Status', 'Value'],
            data: data!.rows.map((r) => r.values.toList()).toList(),
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (_) => d.save());
  }

  Future<void> _csv() async {
    final rows = [
      ['Dataset', 'Reference', 'Status', 'Value'],
      ...data!.rows.map((r) => r.values.toList()),
    ];
    final f = File(
      '${(await getTemporaryDirectory()).path}/ecotrace-report.csv',
    );
    await f.writeAsString(Csv().encode(rows));
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(f.path)],
        text: 'EcoTrace report (Excel-compatible CSV)',
      ),
    );
  }

  Future<void> _schedule(BuildContext c) async {
    await widget.repository.schedule(
      name: 'Scheduled operational report',
      type: ReportType.custom,
      frequency: 'monthly',
      recipients: ['administrator'],
    );
  }

  String _metricValue(String key, double value) =>
      key == 'revenue' ? AppCurrency.format(value) : value.toStringAsFixed(1);
}

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
