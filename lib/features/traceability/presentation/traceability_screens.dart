import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../inventory/domain/inventory_item.dart';
import '../data/traceability_repository.dart';

class TraceabilityScreen extends StatelessWidget {
  const TraceabilityScreen({
    super.key,
    required this.item,
    required this.repository,
  });
  final InventoryItem item;
  final TraceabilityRepository repository;
  Future<void> _printLabel() async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(288, 144),
        build: (_) => pw.Center(
          child: pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: item.itemCode,
                width: 80,
                height: 80,
              ),
              pw.Text(item.itemCode),
              pw.Text('${item.brand} ${item.model}'),
            ],
          ),
        ),
      ),
    );
    await Printing.layoutPdf(onLayout: (_) => doc.save());
  }

  Future<void> _certificate() async {
    final events = await repository.watch(item.id).first;
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Header(level: 0, text: 'EcoTrace Traceability Certificate'),
          pw.Text('Item: ${item.itemCode}'),
          pw.Text('Device: ${item.brand} ${item.model}'),
          pw.Text('Condition: ${item.condition.name}'),
          pw.Text('Current location: ${item.location}'),
          pw.Text('Processing status: ${item.status.name}'),
          pw.SizedBox(height: 16),
          pw.Header(level: 1, text: 'Chain of custody'),
          ...events.reversed.map(
            (e) => pw.Text(
              '${e.at ?? ''} • ${e.type}: ${e.from} → ${e.to} • ${e.actor} • ${e.notes}',
            ),
          ),
        ],
      ),
    );
    await Printing.layoutPdf(onLayout: (_) => doc.save());
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: const Text('Traceability'),
      actions: [
        IconButton(
          onPressed: _printLabel,
          icon: const Icon(Icons.print),
          tooltip: 'Print QR label',
        ),
        IconButton(
          onPressed: _certificate,
          icon: const Icon(Icons.verified),
          tooltip: 'Certificate',
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(child: QrImageView(data: item.itemCode, size: 160)),
        Center(child: SelectableText(item.itemCode)),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            FilledButton(
              onPressed: () => _record(c, 'movement'),
              child: const Text('Record movement'),
            ),
            OutlinedButton(
              onPressed: () => _record(c, 'custodyTransfer'),
              child: const Text('Transfer custody'),
            ),
            OutlinedButton(
              onPressed: () => _record(c, 'receiptVerified'),
              child: const Text('Verify receipt'),
            ),
            OutlinedButton(
              onPressed: () => _record(c, 'damaged'),
              child: const Text('Damaged'),
            ),
            OutlinedButton(
              onPressed: () => _record(c, 'missing'),
              child: const Text('Missing'),
            ),
          ],
        ),
        const Divider(),
        Text('Processing timeline', style: Theme.of(c).textTheme.titleLarge),
        StreamBuilder<List<TraceEvent>>(
          stream: repository.watch(item.id),
          builder: (c, s) => Column(
            children: (s.data ?? [])
                .map(
                  (e) => ListTile(
                    leading: const Icon(Icons.route),
                    title: Text(e.type),
                    subtitle: Text(
                      '${e.from} → ${e.to}\n${e.actor} • ${e.notes}\n${e.at ?? ''}',
                    ),
                    isThreeLine: true,
                  ),
                )
                .toList(),
          ),
        ),
      ],
    ),
  );
  Future<void> _record(BuildContext c, String type) async {
    final destination = TextEditingController(text: item.location),
        actor = TextEditingController(),
        notes = TextEditingController();
    final ok = await showDialog<bool>(
      context: c,
      builder: (c) => AlertDialog(
        title: Text(type),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: destination,
              decoration: const InputDecoration(
                labelText: 'Facility or destination',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: actor,
              decoration: const InputDecoration(
                labelText: 'Collector, facility, or custodian',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: notes,
              decoration: const InputDecoration(labelText: 'Notes'),
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
            child: const Text('Record'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await repository.record(
        item,
        type: type,
        destination: destination.text,
        actor: actor.text,
        notes: notes.text,
        updateLocation: type != 'damaged' && type != 'missing',
      );
    }
    destination.dispose();
    actor.dispose();
    notes.dispose();
  }
}

class TraceScannerScreen extends StatefulWidget {
  const TraceScannerScreen({super.key, required this.repository});
  final TraceabilityRepository repository;
  @override
  State<TraceScannerScreen> createState() => _TraceScannerState();
}

class _TraceScannerState extends State<TraceScannerScreen> {
  bool processing = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan item QR')),
    body: MobileScanner(
      onDetect: (capture) async {
        if (processing) return;
        final code = capture.barcodes.firstOrNull?.rawValue;
        if (code == null) return;
        processing = true;
        final item = await widget.repository.findByCode(code);
        if (!context.mounted) return;
        if (item == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Inventory item not found.')),
          );
          processing = false;
          return;
        }
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                TraceabilityScreen(item: item, repository: widget.repository),
          ),
        );
      },
    ),
  );
}
