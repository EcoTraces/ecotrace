import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../dispatch/domain/collection_schedule.dart';
import '../data/route_repository.dart';
import '../domain/route_plan.dart';

const backgroundLocationDisclosure =
    'EcoTrace collects precise location data to enable live route progress, '
    'arrival detection, and route-deviation alerts even when the app is closed '
    'or not in use.';

class RouteDashboardScreen extends StatelessWidget {
  const RouteDashboardScreen({
    super.key,
    required this.repository,
    required this.canOptimize,
    required this.currentUserId,
  });
  final RouteRepository repository;
  final bool canOptimize;
  final String currentUserId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Route optimization and GPS')),
    body: StreamBuilder<List<RoutePlan>>(
      stream: repository.watchRoutes(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final routes = snapshot.data!
            .where((route) => canOptimize || route.driverId == currentUserId)
            .toList();
        final completed = routes.where(
          (r) => r.status == RoutePlanStatus.completed,
        );
        final total = completed.fold<double>(0, (sum, r) => sum + r.distanceKm);
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 24,
                  children: [
                    Text('Routes: ${routes.length}'),
                    Text(
                      'Active: ${routes.where((r) => r.status == RoutePlanStatus.active).length}',
                    ),
                    Text('Completed distance: ${total.toStringAsFixed(1)} km'),
                    Text(
                      'Deviations: ${routes.fold<int>(0, (sum, r) => sum + r.deviationCount)}',
                    ),
                  ],
                ),
              ),
            ),
            if (routes.isNotEmpty)
              SizedBox(
                height: 220,
                child: Card(
                  child: CustomPaint(
                    painter: CoveragePainter(routes),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            for (final route in routes)
              Card(
                child: ListTile(
                  leading: Icon(
                    route.status == RoutePlanStatus.active
                        ? Icons.gps_fixed
                        : Icons.alt_route,
                  ),
                  title: Text('Schedule ${route.scheduleId}'),
                  subtitle: Text(
                    '${route.stops.length} stops • ${route.distanceKm.toStringAsFixed(1)} km • ${route.estimatedMinutes.round()} min\n${route.status.name} • deviations ${route.deviationCount}',
                  ),
                  isThreeLine: true,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DriverRouteScreen(
                        repository: repository,
                        initial: route,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
    floatingActionButton: canOptimize
        ? FloatingActionButton.extended(
            onPressed: () => _create(context),
            icon: const Icon(Icons.auto_fix_high),
            label: const Text('Optimize'),
          )
        : null,
  );

  Future<void> _create(BuildContext context) async {
    final schedules = await repository.watchSchedulable().first;
    if (!context.mounted) return;
    final selected = await showDialog<CollectionSchedule>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Select dispatched schedule'),
        children: schedules
            .map(
              (schedule) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, schedule),
                child: Text(
                  '${schedule.scheduledAt} • ${schedule.serviceArea} • ${schedule.pickupIds.length} stops',
                ),
              ),
            )
            .toList(),
      ),
    );
    if (selected == null) return;
    try {
      final route = await repository.optimize(selected);
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                DriverRouteScreen(repository: repository, initial: route),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Optimization failed: $error')));
      }
    }
  }
}

class DriverRouteScreen extends StatefulWidget {
  const DriverRouteScreen({
    super.key,
    required this.repository,
    required this.initial,
  });
  final RouteRepository repository;
  final RoutePlan initial;
  @override
  State<DriverRouteScreen> createState() => _DriverRouteState();
}

class _DriverRouteState extends State<DriverRouteScreen> {
  StreamSubscription<Position>? subscription;
  bool tracking = false;
  bool requestingPermission = false;

  Future<void> _start(RoutePlan route) async {
    if (requestingPermission || tracking) return;
    setState(() => requestingPermission = true);
    try {
      if (!await _ensureBackgroundLocationPermission()) return;
      if (route.status == RoutePlanStatus.planned) {
        await widget.repository.start(route.id);
      }
      await subscription?.cancel();
      subscription = widget.repository.positionStream().listen(
        (position) => unawaited(
          widget.repository
              .recordPosition(route.id, position)
              .catchError((Object error) => _showTrackingError(error)),
        ),
        onError: (Object error) => _showTrackingError(error),
        onDone: () {
          if (mounted) setState(() => tracking = false);
        },
      );
      if (mounted) setState(() => tracking = true);
    } catch (error) {
      _showTrackingError(error);
    } finally {
      if (mounted) setState(() => requestingPermission = false);
    }
  }

  Future<bool> _ensureBackgroundLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (!mounted) return false;
      final openSettings = await _showActionDialog(
        title: 'Turn on location services',
        message:
            'EcoTrace cannot track an active route until device location services are turned on.',
        actionLabel: 'Location settings',
      );
      if (openSettings) await Geolocator.openLocationSettings();
      return false;
    }

    // Browsers do not support the mobile-only locationAlways permission.
    // Web navigation uses the browser geolocation prompt and remains active
    // while the EcoTrace tab is open.
    if (kIsWeb) return _ensureWebLocationPermission();

    if (await Permission.locationAlways.isGranted) return true;
    if (!mounted) return false;
    final accepted =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Background location for active routes'),
            content: const SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(backgroundLocationDisclosure),
                  SizedBox(height: 12),
                  Text(
                    'During an active route, your location and timestamp are sent to EcoTrace\'s Firebase backend and stored in the route location history for authorized dispatch operations. The data is not used for advertising.',
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Tracking starts only after you continue and grant permission. You can pause tracking or complete the route at any time.',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Not now'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continue'),
              ),
            ],
          ),
        ) ??
        false;
    if (!accepted) return false;

    var foreground = await Permission.locationWhenInUse.status;
    if (!foreground.isGranted) {
      foreground = await Permission.locationWhenInUse.request();
    }
    if (!foreground.isGranted) {
      if (!mounted) return false;
      final openSettings = await _showActionDialog(
        title: 'Location permission needed',
        message:
            'Allow precise location while using EcoTrace first. You can change this permission in system settings.',
        actionLabel: 'App settings',
      );
      if (openSettings) await openAppSettings();
      return false;
    }

    final background = await Permission.locationAlways.request();
    if (background.isGranted) return true;
    if (!mounted) return false;
    final openSettings = await _showActionDialog(
      title: 'Allow background location',
      message:
          'Choose “Allow all the time” on Android or “Always” on iOS so EcoTrace can update an active route when the app is not in use.',
      actionLabel: 'App settings',
    );
    if (openSettings) await openAppSettings();
    return false;
  }

  Future<bool> _ensureWebLocationPermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      return true;
    }
    if (!mounted) return false;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Browser location permission needed'),
        content: const Text(
          'Allow location access for this localhost site in your browser, '
          'then start live navigation again. Web tracking works while the '
          'EcoTrace tab remains open.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return false;
  }

  Future<bool> _showActionDialog({
    required String title,
    required String message,
    required String actionLabel,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(actionLabel),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _pause() async {
    await subscription?.cancel();
    subscription = null;
    if (mounted) setState(() => tracking = false);
  }

  void _showTrackingError(Object error) {
    if (!mounted) return;
    setState(() => tracking = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('GPS tracking stopped: $error')));
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<RoutePlan>(
    stream: widget.repository.watchRoute(widget.initial.id),
    initialData: widget.initial,
    builder: (context, snapshot) {
      final route = snapshot.data!;
      final next = route.stops.where((x) => !x.arrived).firstOrNull;
      return Scaffold(
        appBar: AppBar(title: const Text('Driver navigation')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SizedBox(
              height: 300,
              child: Card(
                child: CustomPaint(
                  painter: RoutePainter(route),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            Text(
              '${route.distanceKm.toStringAsFixed(1)} km • baseline ${route.estimatedMinutes.round()} min',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              next == null
                  ? 'All stops reached'
                  : 'Next: ${next.address} (${next.sequence}/${route.stops.length})',
            ),
            Text(
              'GPS: ${route.currentLatitude?.toStringAsFixed(5) ?? '—'}, ${route.currentLongitude?.toStringAsFixed(5) ?? '—'}',
            ),
            Text('Deviation alerts: ${route.deviationCount}'),
            if (tracking)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.location_on),
                  title: Text(
                    kIsWeb
                        ? 'Browser GPS is active'
                        : 'Background GPS is active',
                  ),
                  subtitle: Text(
                    kIsWeb
                        ? 'Keep this EcoTrace tab open to continue location updates. Pause or complete the route to stop.'
                        : 'Location updates continue when EcoTrace is not in use. Pause or complete the route to stop.',
                  ),
                ),
              ),
            const SizedBox(height: 12),
            if (route.status == RoutePlanStatus.planned)
              FilledButton.icon(
                onPressed: requestingPermission ? null : () => _start(route),
                icon: const Icon(Icons.navigation),
                label: Text(
                  requestingPermission
                      ? 'Requesting permission…'
                      : 'Start live navigation',
                ),
              ),
            if (route.status == RoutePlanStatus.active && !tracking)
              OutlinedButton.icon(
                onPressed: requestingPermission ? null : () => _start(route),
                icon: const Icon(Icons.gps_fixed),
                label: const Text('Resume GPS tracking'),
              ),
            if (route.status == RoutePlanStatus.active && tracking)
              OutlinedButton.icon(
                onPressed: _pause,
                icon: const Icon(Icons.pause),
                label: const Text('Pause GPS tracking'),
              ),
            if (route.status == RoutePlanStatus.active)
              FilledButton(
                onPressed: () async {
                  await _pause();
                  await widget.repository.complete(route.id);
                },
                child: const Text('Complete route'),
              ),
            const Divider(),
            Text(
              'Offline stop plan',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            ...route.stops.map(
              (stop) => ListTile(
                leading: CircleAvatar(
                  child: stop.arrived
                      ? const Icon(Icons.check)
                      : Text('${stop.sequence}'),
                ),
                title: Text(stop.address),
                subtitle: Text(
                  '${stop.latitude.toStringAsFixed(5)}, ${stop.longitude.toStringAsFixed(5)}',
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class RoutePainter extends CustomPainter {
  RoutePainter(this.route);
  final RoutePlan route;
  @override
  void paint(Canvas canvas, Size size) {
    if (route.stops.isEmpty) return;
    final lats = route.stops.map((s) => s.latitude).toList();
    final lngs = route.stops.map((s) => s.longitude).toList();
    if (route.currentLatitude != null) lats.add(route.currentLatitude!);
    if (route.currentLongitude != null) lngs.add(route.currentLongitude!);
    final minLat = lats.reduce(math.min), maxLat = lats.reduce(math.max);
    final minLng = lngs.reduce(math.min), maxLng = lngs.reduce(math.max);
    Offset point(double lat, double lng) => Offset(
      24 +
          (lng - minLng) /
              (maxLng - minLng == 0 ? 1 : maxLng - minLng) *
              (size.width - 48),
      size.height -
          24 -
          (lat - minLat) /
              (maxLat - minLat == 0 ? 1 : maxLat - minLat) *
              (size.height - 48),
    );
    final path = Path();
    for (var i = 0; i < route.stops.length; i++) {
      final p = point(route.stops[i].latitude, route.stops[i].longitude);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.green
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke,
    );
    for (final stop in route.stops) {
      canvas.drawCircle(
        point(stop.latitude, stop.longitude),
        8,
        Paint()..color = stop.arrived ? Colors.green : Colors.orange,
      );
    }
    if (route.currentLatitude != null && route.currentLongitude != null) {
      canvas.drawCircle(
        point(route.currentLatitude!, route.currentLongitude!),
        10,
        Paint()..color = Colors.blue,
      );
    }
  }

  @override
  bool shouldRepaint(covariant RoutePainter oldDelegate) =>
      oldDelegate.route != route;
}

class CoveragePainter extends CustomPainter {
  CoveragePainter(this.routes);
  final List<RoutePlan> routes;
  @override
  void paint(Canvas canvas, Size size) {
    final stops = routes.expand((route) => route.stops).toList();
    if (stops.isEmpty) return;
    final minLat = stops.map((s) => s.latitude).reduce(math.min);
    final maxLat = stops.map((s) => s.latitude).reduce(math.max);
    final minLng = stops.map((s) => s.longitude).reduce(math.min);
    final maxLng = stops.map((s) => s.longitude).reduce(math.max);
    Offset point(RouteStop stop) => Offset(
      20 +
          (stop.longitude - minLng) /
              (maxLng - minLng == 0 ? 1 : maxLng - minLng) *
              (size.width - 40),
      size.height -
          20 -
          (stop.latitude - minLat) /
              (maxLat - minLat == 0 ? 1 : maxLat - minLat) *
              (size.height - 40),
    );
    for (final route in routes) {
      final path = Path();
      for (var i = 0; i < route.stops.length; i++) {
        final p = point(route.stops[i]);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.green.withValues(alpha: .45)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
    for (final stop in stops) {
      canvas.drawCircle(point(stop), 5, Paint()..color = Colors.deepOrange);
    }
  }

  @override
  bool shouldRepaint(covariant CoveragePainter oldDelegate) =>
      oldDelegate.routes != routes;
}
