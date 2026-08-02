import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import '../data/pickup_repository.dart';
import '../domain/pickup.dart';

class PickupListScreen extends StatelessWidget {
  const PickupListScreen({
    super.key,
    required this.uid,
    required this.repository,
  });
  final String uid;
  final PickupRepository repository;
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('E-waste pickups')),
    body: StreamBuilder<List<PickupRequest>>(
      stream: repository.watchMine(uid),
      builder: (c, s) {
        if (!s.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.data!.isEmpty) {
          return const Center(child: Text('No pickup requests yet.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: s.data!.length,
          itemBuilder: (c, i) {
            final p = s.data![i];
            return Card(
              child: ListTile(
                leading: const Icon(Icons.local_shipping_outlined),
                title: Text('${p.category.name} • ${p.quantity} item(s)'),
                subtitle: Text('${p.status.name} • ${p.scheduledAt.toLocal()}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  c,
                  MaterialPageRoute(
                    builder: (_) =>
                        PickupDetailScreen(pickup: p, repository: repository),
                  ),
                ),
              ),
            );
          },
        );
      },
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => Navigator.push(
        c,
        MaterialPageRoute(
          builder: (_) => CreatePickupScreen(uid: uid, repository: repository),
        ),
      ),
      icon: const Icon(Icons.add),
      label: const Text('Request pickup'),
    ),
  );
}

class CreatePickupScreen extends StatefulWidget {
  const CreatePickupScreen({
    super.key,
    required this.uid,
    required this.repository,
  });
  final String uid;
  final PickupRepository repository;
  @override
  State<CreatePickupScreen> createState() => _CreatePickupState();
}

class _CreatePickupState extends State<CreatePickupScreen> {
  final q = TextEditingController(text: '1'),
      w = TextEditingController(),
      condition = TextEditingController(),
      location = TextEditingController(),
      instructions = TextEditingController();
  WasteCategory category = WasteCategory.computers;
  DateTime date = DateTime.now().add(const Duration(days: 1));
  bool urgent = false, busy = false;
  final photos = <XFile>[];
  double? latitude, longitude;
  @override
  Widget build(BuildContext c) {
    final fee = estimatePickupFee(
      quantity: int.tryParse(q.text) ?? 0,
      weight: double.tryParse(w.text) ?? 0,
      urgent: urgent,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('New pickup request')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          DropdownButtonFormField(
            initialValue: category,
            items: WasteCategory.values
                .map((x) => DropdownMenuItem(value: x, child: Text(x.name)))
                .toList(),
            onChanged: (x) => setState(() => category = x!),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: q,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Quantity'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: photos.length >= 5
                ? null
                : () async {
                    final selected = await ImagePicker().pickMultiImage(
                      imageQuality: 75,
                    );
                    if (selected.isNotEmpty) {
                      setState(() {
                        photos.addAll(selected.take(5 - photos.length));
                      });
                    }
                  },
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text(
              photos.isEmpty
                  ? 'Add required pickup photo'
                  : 'Pickup photos (${photos.length}/5)',
            ),
          ),
          if (photos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${photos.length} photo(s) ready for secure Cloudinary upload.',
                style: Theme.of(c).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: w,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Estimated weight (kg)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: condition,
            decoration: const InputDecoration(labelText: 'Item condition'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: location,
            decoration: const InputDecoration(labelText: 'Pickup location'),
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
              setState(() {
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
          const SizedBox(height: 12),
          ListTile(
            title: const Text('Pickup date and time'),
            subtitle: Text(date.toLocal().toString()),
            trailing: const Icon(Icons.calendar_month),
            onTap: () async {
              final d = await showDatePicker(
                context: c,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                initialDate: date,
              );
              if (d != null) {
                setState(() => date = DateTime(d.year, d.month, d.day, 9));
              }
            },
          ),
          SwitchListTile(
            value: urgent,
            onChanged: (x) => setState(() => urgent = x),
            title: const Text('Urgent pickup'),
          ),
          TextField(
            controller: instructions,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Special handling instructions',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Estimated fee: \$${fee.toStringAsFixed(2)}',
            style: Theme.of(c).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    final quantity = int.tryParse(q.text);
                    final weight = double.tryParse(w.text);
                    if (quantity == null ||
                        quantity < 1 ||
                        weight == null ||
                        weight < 0 ||
                        condition.text.trim().isEmpty ||
                        location.text.trim().isEmpty ||
                        photos.isEmpty) {
                      ScaffoldMessenger.of(c).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Complete all required details and add at least one pickup photo.',
                          ),
                        ),
                      );
                      return;
                    }
                    setState(() => busy = true);
                    try {
                      final uploads = await Future.wait(
                        photos.map(
                          (photo) async => PickupPhoto(
                            name: photo.name,
                            bytes: await photo.readAsBytes(),
                          ),
                        ),
                      );
                      await widget.repository.create(
                        uid: widget.uid,
                        category: category,
                        quantity: quantity,
                        weight: weight,
                        condition: condition.text,
                        location: location.text,
                        scheduledAt: date,
                        urgent: urgent,
                        instructions: instructions.text,
                        photos: uploads,
                        latitude: latitude,
                        longitude: longitude,
                      );
                      if (c.mounted) Navigator.pop(c);
                    } catch (error) {
                      if (c.mounted) {
                        ScaffoldMessenger.of(c).showSnackBar(
                          SnackBar(
                            content: Text('Could not create pickup: $error'),
                          ),
                        );
                      }
                      if (mounted) setState(() => busy = false);
                    }
                  },
            child: const Text('Confirm pickup request'),
          ),
        ],
      ),
    );
  }
}

class PickupDetailScreen extends StatelessWidget {
  const PickupDetailScreen({
    super.key,
    required this.pickup,
    required this.repository,
  });
  final PickupRequest pickup;
  final PickupRepository repository;
  @override
  Widget build(BuildContext c) => StreamBuilder<PickupRequest>(
    stream: repository.watchOne(pickup.id),
    initialData: pickup,
    builder: (context, snapshot) =>
        _buildDetail(context, snapshot.data ?? pickup),
  );

  Widget _buildDetail(BuildContext c, PickupRequest pickup) => Scaffold(
    appBar: AppBar(title: const Text('Pickup tracking')),
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(pickup.status.name, style: Theme.of(c).textTheme.headlineMedium),
          Text(
            '${pickup.category.name} • ${pickup.quantity} items • ${pickup.weight} kg',
          ),
          Text(pickup.location),
          Text('Scheduled: ${pickup.scheduledAt.toLocal()}'),
          Text('Estimated fee: \$${pickup.fee.toStringAsFixed(2)}'),
          const Spacer(),
          if ([
            PickupStatus.submitted,
            PickupStatus.approved,
            PickupStatus.scheduled,
          ].contains(pickup.status))
            OutlinedButton.icon(
              onPressed: () async {
                final selected = await showDatePicker(
                  context: c,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  initialDate: pickup.scheduledAt.isAfter(DateTime.now())
                      ? pickup.scheduledAt
                      : DateTime.now(),
                );
                if (selected != null) {
                  await repository.reschedule(
                    pickup.id,
                    DateTime(selected.year, selected.month, selected.day, 9),
                  );
                }
              },
              icon: const Icon(Icons.event_repeat),
              label: const Text('Reschedule'),
            ),
          if (![
            PickupStatus.cancelled,
            PickupStatus.completed,
            PickupStatus.collected,
          ].contains(pickup.status))
            OutlinedButton(
              onPressed: () => repository.cancel(pickup.id).then((_) {
                if (c.mounted) Navigator.pop(c);
              }),
              child: const Text('Cancel request'),
            ),
          if (pickup.status == PickupStatus.completed)
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    onPressed: () => repository.rate(pickup.id, i),
                    icon: Icon(
                      (pickup.rating ?? 0) >= i
                          ? Icons.star
                          : Icons.star_border,
                    ),
                  ),
              ],
            ),
        ],
      ),
    ),
  );
}
