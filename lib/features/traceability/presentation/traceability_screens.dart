import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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
                data: item.qrPayload,
                width: 80,
                height: 80,
              ),
              pw.SizedBox(height: 4),
              pw.BarcodeWidget(
                barcode: pw.Barcode.code128(),
                data: item.barcodeValue,
                width: 160,
                height: 24,
                drawText: false,
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
    final certificate = await repository.certificate(item);
    final events = (certificate['chainOfCustody'] as List? ?? const [])
        .map((value) => Map<String, dynamic>.from(value as Map))
        .toList();
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Header(level: 0, text: 'EcoTrace Traceability Certificate'),
          pw.Text('Certificate: ${certificate['certificateNumber'] ?? ''}'),
          pw.Text('Issued: ${certificate['issuedAt'] ?? ''}'),
          pw.Text('Item: ${item.itemCode}'),
          pw.Text('Device: ${item.brand} ${item.model}'),
          pw.Text('Condition: ${item.condition.name}'),
          pw.Text('Current location: ${item.location}'),
          pw.Text('Processing status: ${item.status.name}'),
          pw.Text(
            'Integrity verified: ${certificate['integrityVerified'] == true ? 'Yes' : 'No'}',
          ),
          pw.SizedBox(height: 16),
          pw.Header(level: 1, text: 'Chain of custody'),
          ...events.map(
            (e) => pw.Text(
              '${e['createdAt'] ?? ''} • ${e['type'] ?? ''}: ${e['from'] ?? ''} → ${e['to'] ?? ''} • ${e['actor'] ?? ''} • ${e['notes'] ?? ''}',
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Integrity hash: ${certificate['finalIntegrityHash'] ?? 'Legacy record'}',
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
        Center(child: QrImageView(data: item.qrPayload, size: 160)),
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
              onPressed: () => _assign(c, 'collector'),
              child: const Text('Assign collector'),
            ),
            OutlinedButton(
              onPressed: () => _assign(c, 'facility'),
              child: const Text('Assign facility'),
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
            OutlinedButton(
              onPressed: () => _record(c, 'statusUpdated'),
              child: const Text('Update status'),
            ),
          ],
        ),
        const Divider(),
        FutureBuilder<Map<String, dynamic>>(
          future: repository.audit(item),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const LinearProgressIndicator();
            final verified = snapshot.data!['integrityVerified'] == true;
            final issues = List<String>.from(
              snapshot.data!['integrityIssues'] as List? ?? const [],
            );
            return ListTile(
              leading: Icon(
                verified ? Icons.verified_user : Icons.warning_amber,
                color: verified ? Colors.green : Colors.orange,
              ),
              title: Text(
                verified
                    ? 'Chain integrity verified'
                    : 'Chain integrity warning',
              ),
              subtitle: Text(
                verified
                    ? 'Recorded custody events have not been altered.'
                    : 'Events requiring investigation: ${issues.join(', ')}',
              ),
            );
          },
        ),
        Text('Processing timeline', style: Theme.of(c).textTheme.titleLarge),
        StreamBuilder<List<TraceEvent>>(
          stream: repository.watch(item.id),
          builder: (c, s) => Column(
            children: (s.data ?? [])
                .map(
                  (e) => ListTile(
                    leading: Icon(
                      e.integrityHash.isEmpty ? Icons.route : Icons.verified,
                    ),
                    title: Text(
                      e.sequence > 0 ? '#${e.sequence} ${e.type}' : e.type,
                    ),
                    subtitle: Text(
                      '${e.from} → ${e.to}\n${e.actor} • ${e.notes}\n${e.at ?? ''}'
                      '${e.evidenceUrls.isEmpty ? '' : '\n${e.evidenceUrls.length} evidence image(s)'}',
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
    final evidence = <XFile>[];
    var selectedStatus = item.status;
    final ok = await showDialog<bool>(
      context: c,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) => AlertDialog(
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
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: evidence.length >= 5
                    ? null
                    : () async {
                        final picked = await ImagePicker().pickMultiImage(
                          imageQuality: 75,
                        );
                        setDialogState(
                          () =>
                              evidence.addAll(picked.take(5 - evidence.length)),
                        );
                      },
                icon: const Icon(Icons.add_a_photo_outlined),
                label: Text('Evidence images (${evidence.length}/5)'),
              ),
              if (type == 'statusUpdated') ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<ProcessingStatus>(
                  initialValue: selectedStatus,
                  decoration: const InputDecoration(
                    labelText: 'Processing status',
                  ),
                  items: ProcessingStatus.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) selectedStatus = value;
                  },
                ),
              ],
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
      ),
    );
    if (ok == true) {
      try {
        if ((type == 'damaged' || type == 'missing') && evidence.isEmpty) {
          throw ArgumentError(
            'Photo evidence is required for damaged or missing items.',
          );
        }
        final evidenceUrls = evidence.isEmpty
            ? <String>[]
            : await repository.uploadEvidence(
                await Future.wait(evidence.map((image) => image.readAsBytes())),
              );
        await repository.record(
          item,
          type: type,
          destination: destination.text,
          actor: actor.text,
          notes: notes.text,
          status: type == 'statusUpdated' ? selectedStatus : null,
          evidenceUrls: evidenceUrls,
          updateLocation:
              type != 'damaged' && type != 'missing' && type != 'statusUpdated',
        );
        if (c.mounted) {
          ScaffoldMessenger.of(c).showSnackBar(
            const SnackBar(content: Text('Traceability event recorded.')),
          );
        }
      } catch (error) {
        if (c.mounted) {
          ScaffoldMessenger.of(c).showSnackBar(
            SnackBar(content: Text('Unable to record event: $error')),
          );
        }
      }
    }
    destination.dispose();
    actor.dispose();
    notes.dispose();
  }

  Future<void> _assign(BuildContext context, String assignmentType) async {
    final id = TextEditingController();
    final name = TextEditingController();
    final destination = TextEditingController(text: item.location);
    final notes = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          assignmentType == 'collector'
              ? 'Assign item to collector'
              : 'Assign item to facility',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: id,
                decoration: InputDecoration(
                  labelText:
                      '${assignmentType == 'collector' ? 'Collector' : 'Facility'} ID',
                ),
              ),
              TextField(
                controller: name,
                decoration: InputDecoration(
                  labelText:
                      '${assignmentType == 'collector' ? 'Collector' : 'Facility'} name',
                ),
              ),
              TextField(
                controller: destination,
                decoration: const InputDecoration(labelText: 'Destination'),
              ),
              TextField(
                controller: notes,
                decoration: const InputDecoration(
                  labelText: 'Assignment notes',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Assign'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await repository.assign(
          item,
          assignmentType: assignmentType,
          assigneeId: id.text,
          assigneeName: name.text,
          destination: destination.text,
          notes: notes.text,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Custody assignment recorded.')),
          );
        }
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Unable to assign custody: $error')),
          );
        }
      }
    }
    id.dispose();
    name.dispose();
    destination.dispose();
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
    body: Column(
      children: [
        Expanded(
          child: MobileScanner(
            onDetect: (capture) {
              final code = capture.barcodes.firstOrNull?.rawValue;
              if (code != null) _handleCode(code);
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: processing ? null : _enterCode,
                icon: const Icon(Icons.keyboard),
                label: const Text('Enter item code manually'),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _enterCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter item code'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'ECO-2026-XXXXXXXX'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Find item'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code != null && code.isNotEmpty) await _handleCode(code);
  }

  Future<void> _handleCode(String code) async {
    if (processing) return;
    processing = true;
    InventoryItem? item;
    try {
      item = await widget.repository.findByCode(code);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unable to scan item: $error')));
      }
      processing = false;
      return;
    }
    if (!mounted) return;
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
            TraceabilityScreen(item: item!, repository: widget.repository),
      ),
    );
  }
}
