import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
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
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => busy = true);
    data = await widget.repository.load(from, to);
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext c) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Analytics and reporting'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Business intelligence'),
            Tab(text: 'Reports'),
          ],
        ),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: busy
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(children: [_dashboard(c), _reports(c)]),
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
                            e.value.toStringAsFixed(1),
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
      DropdownButtonFormField<ReportType>(
        initialValue: ReportType.custom,
        items: ReportType.values
            .map((x) => DropdownMenuItem(value: x, child: Text(x.name)))
            .toList(),
        onChanged: (_) {},
        decoration: const InputDecoration(labelText: 'Custom report type'),
      ),
      for (final r in data!.rows.take(100))
        ListTile(
          title: Text('${r['dataset']} • ${r['reference']}'),
          subtitle: Text('${r['status']}'),
          trailing: Text('${r['value']}'),
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
            (e) => pw.Text('${e.key}: ${e.value.toStringAsFixed(2)}'),
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
}
