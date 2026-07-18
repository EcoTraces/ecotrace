import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/admin_overview_repository.dart';
import '../domain/application_interface.dart';

class AdministratorOverviewDashboard extends StatefulWidget {
  const AdministratorOverviewDashboard({
    super.key,
    required this.repository,
    required this.onOpen,
    required this.footer,
  });

  final AdminOverviewRepository repository;
  final ValueChanged<WorkspaceDestination> onOpen;
  final Widget footer;

  @override
  State<AdministratorOverviewDashboard> createState() =>
      _AdministratorOverviewDashboardState();
}

class _AdministratorOverviewDashboardState
    extends State<AdministratorOverviewDashboard> {
  late Stream<AdminOverviewSnapshot> _stream;

  @override
  void initState() {
    super.initState();
    _stream = widget.repository.watchOverview();
  }

  void _retry() => setState(() => _stream = widget.repository.watchOverview());

  @override
  Widget build(BuildContext context) => StreamBuilder<AdminOverviewSnapshot>(
    stream: _stream,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _DashboardMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Unable to load the live dashboard',
          message:
              'Check the administrator Firestore permissions and try again.\n${snapshot.error}',
          actionLabel: 'Try again',
          onAction: _retry,
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return _DashboardBody(
        data: snapshot.data!,
        onOpen: widget.onOpen,
        footer: widget.footer,
      );
    },
  );
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.data,
    required this.onOpen,
    required this.footer,
  });

  final AdminOverviewSnapshot data;
  final ValueChanged<WorkspaceDestination> onOpen;
  final Widget footer;

  static const _gap = 12.0;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFFF6F9F7),
    child: CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          sliver: SliverToBoxAdapter(child: _metrics(context)),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          sliver: SliverToBoxAdapter(
            child: _AdaptivePanelRow(
              minPanelWidth: 300,
              children: [
                _PanelSlot(
                  flex: 11,
                  child: _CollectionTrendPanel(values: data.collectionTrend),
                ),
                _PanelSlot(
                  flex: 11,
                  child: _CategoryPanel(categories: data.categoryWeights),
                ),
                _PanelSlot(
                  flex: 12,
                  child: _PickupRequestsPanel(
                    statuses: data.pickupStatuses,
                    completionRate: data.pickupCompletionRate,
                    onOpen: () => onOpen(WorkspaceDestination.pickupRequests),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          sliver: SliverToBoxAdapter(
            child: _AdaptivePanelRow(
              minPanelWidth: 300,
              children: [
                _PanelSlot(
                  flex: 10,
                  child: _CollectionMapPanel(
                    locations: data.collectionLocations,
                    onOpen: () =>
                        onOpen(WorkspaceDestination.collectionCentres),
                  ),
                ),
                _PanelSlot(
                  flex: 11,
                  child: _RecentCollectionsPanel(
                    collections: data.recentCollections,
                    onOpen: () => onOpen(WorkspaceDestination.collections),
                  ),
                ),
                _PanelSlot(
                  flex: 12,
                  child: _EnvironmentalImpactPanel(
                    data: data,
                    onOpen: () => onOpen(WorkspaceDestination.analytics),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          sliver: SliverToBoxAdapter(
            child: _SummaryBar(
              data: data,
              onGenerateReport: () => onOpen(WorkspaceDestination.analytics),
            ),
          ),
        ),
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
          sliver: SliverToBoxAdapter(child: _LiveDataNote()),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          sliver: SliverToBoxAdapter(child: footer),
        ),
      ],
    ),
  );

  Widget _metrics(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1180
          ? 5
          : constraints.maxWidth >= 720
          ? 3
          : constraints.maxWidth >= 470
          ? 2
          : 1;
      final width = (constraints.maxWidth - ((columns - 1) * _gap)) / columns;
      final trend = data.collectionTrend;
      final metrics = [
        _MetricData(
          title: 'Total Collections',
          value: _whole(data.totalCollections),
          unit: '',
          icon: Icons.local_shipping_outlined,
          color: const Color(0xFF14854F),
          destination: WorkspaceDestination.collections,
        ),
        _MetricData(
          title: 'E-Waste Collected',
          value: _decimal(data.collectedKg),
          unit: 'kg',
          icon: Icons.recycling,
          color: const Color(0xFF4967C7),
          destination: WorkspaceDestination.inventory,
        ),
        _MetricData(
          title: 'Recycled (All Time)',
          value: _decimal(data.recycledKg),
          unit: 'kg',
          icon: Icons.factory_outlined,
          color: const Color(0xFF9047C8),
          destination: WorkspaceDestination.recyclingAndRecovery,
        ),
        _MetricData(
          title: 'Active Users',
          value: _whole(data.activeUsers),
          unit: '',
          icon: Icons.people_alt_outlined,
          color: const Color(0xFFF29A24),
          destination: WorkspaceDestination.usersAndOrganizations,
        ),
        _MetricData(
          title: 'CO₂ Avoided',
          value: _decimal(data.impact.carbonEmissionsAvoidedKg / 1000),
          unit: 'tonnes',
          icon: Icons.eco_outlined,
          color: const Color(0xFF10A49A),
          destination: WorkspaceDestination.analytics,
        ),
      ];
      return Wrap(
        spacing: _gap,
        runSpacing: _gap,
        children: metrics
            .map(
              (metric) => SizedBox(
                width: width,
                height: 144,
                child: _MetricCard(
                  data: metric,
                  trend: trend,
                  onTap: () => onOpen(metric.destination),
                ),
              ),
            )
            .toList(),
      );
    },
  );
}

class _DashboardPanel extends StatelessWidget {
  const _DashboardPanel({
    required this.title,
    required this.child,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
    height: 310,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFE1E9E4)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x08002D21),
          blurRadius: 8,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF17221D),
                ),
              ),
            ),
            if (actionLabel != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF117749),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  textStyle: const TextStyle(fontSize: 10),
                ),
                child: Text(actionLabel!),
              ),
          ],
        ),
        const Divider(height: 15, color: Color(0xFFEAF0EC)),
        Expanded(child: child),
      ],
    ),
  );
}

class _MetricData {
  const _MetricData({
    required this.title,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
    required this.destination,
  });

  final String title;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;
  final WorkspaceDestination destination;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.data,
    required this.trend,
    required this.onTap,
  });

  final _MetricData data;
  final List<double> trend;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE1E9E4)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 43,
                  height: 43,
                  decoration: BoxDecoration(
                    color: data.color,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(data.icon, color: Colors.white, size: 23),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF43524B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text.rich(
                          TextSpan(
                            text: data.value,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF15231D),
                            ),
                            children: [
                              if (data.unit.isNotEmpty)
                                TextSpan(
                                  text: ' ${data.unit}',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF5D6A64),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                const Icon(Icons.circle, size: 6, color: Color(0xFF1B9858)),
                const SizedBox(width: 4),
                const Text(
                  'Live Firestore data',
                  style: TextStyle(fontSize: 9, color: Color(0xFF6D7973)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SizedBox(
                    height: 29,
                    child: CustomPaint(
                      painter: _SparklinePainter(
                        values: trend,
                        color: data.color,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _CollectionTrendPanel extends StatelessWidget {
  const _CollectionTrendPanel({required this.values});

  final List<double> values;

  @override
  Widget build(BuildContext context) => _DashboardPanel(
    title: 'Collection Trend',
    actionLabel: 'Last 8 weeks',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'kg',
          style: TextStyle(fontSize: 9, color: Color(0xFF66736D)),
        ),
        const SizedBox(height: 5),
        Expanded(
          child: CustomPaint(
            painter: _LineChartPainter(values: values),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            values.length,
            (index) => Text(
              index == values.length - 1 ? 'Now' : 'W${index + 1}',
              style: const TextStyle(fontSize: 8, color: Color(0xFF718078)),
            ),
          ),
        ),
      ],
    ),
  );
}

class _CategoryPanel extends StatelessWidget {
  const _CategoryPanel({required this.categories});

  final Map<String, double> categories;

  static const _colors = [
    Color(0xFF0FA7A0),
    Color(0xFF2D69B7),
    Color(0xFF6754B8),
    Color(0xFF9E43C1),
    Color(0xFFDF4E4E),
    Color(0xFFF29A24),
    Color(0xFF209256),
  ];

  @override
  Widget build(BuildContext context) {
    final entries = categories.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final visible = entries.take(7).toList();
    final total = entries.fold<double>(0, (sum, item) => sum + item.value);
    return _DashboardPanel(
      title: 'E-Waste by Category',
      child: total <= 0
          ? const _EmptyPanel(
              icon: Icons.donut_large_outlined,
              label: 'Category data will appear here',
            )
          : Row(
              children: [
                Expanded(
                  flex: 4,
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          painter: _DonutPainter(
                            values: visible
                                .map((entry) => entry.value)
                                .toList(),
                            colors: _colors,
                          ),
                          child: const SizedBox.expand(),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _decimal(total),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Text(
                              'kg total',
                              style: TextStyle(
                                fontSize: 8,
                                color: Color(0xFF66736D),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 6,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var index = 0; index < visible.length; index++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: _colors[index % _colors.length],
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  visible[index].key,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 9),
                                ),
                              ),
                              Text(
                                '${_decimal(visible[index].value)} kg',
                                style: const TextStyle(
                                  fontSize: 8,
                                  color: Color(0xFF56645D),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _PickupRequestsPanel extends StatelessWidget {
  const _PickupRequestsPanel({
    required this.statuses,
    required this.completionRate,
    required this.onOpen,
  });

  final Map<String, int> statuses;
  final double completionRate;
  final VoidCallback onOpen;

  static const _statusData = [
    ('New Requests', Icons.note_add_outlined, Color(0xFF22905B)),
    ('Scheduled', Icons.calendar_month_outlined, Color(0xFF3977D2)),
    ('In Progress', Icons.local_shipping_outlined, Color(0xFFF0A123)),
    ('Completed', Icons.check_circle_outline, Color(0xFF159358)),
  ];

  @override
  Widget build(BuildContext context) => _DashboardPanel(
    title: 'Pickup Requests',
    actionLabel: 'View all',
    onAction: onOpen,
    child: Row(
      children: [
        Expanded(
          flex: 6,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final item in _statusData)
                Container(
                  margin: const EdgeInsets.only(bottom: 7),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAF9),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: const Color(0xFFE9EFEB)),
                  ),
                  child: Row(
                    children: [
                      Icon(item.$2, size: 18, color: item.$3),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.$1,
                          style: const TextStyle(fontSize: 9),
                        ),
                      ),
                      Text(
                        _whole(statuses[item.$1] ?? 0),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 4,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 94,
                height: 94,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: completionRate / 100,
                      strokeWidth: 8,
                      backgroundColor: const Color(0xFFE5EEE8),
                      color: const Color(0xFF26935A),
                    ),
                    Text(
                      '${completionRate.round()}%',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Completion Rate',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
              ),
              const Text(
                'All time',
                style: TextStyle(fontSize: 8, color: Color(0xFF728078)),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CollectionMapPanel extends StatelessWidget {
  const _CollectionMapPanel({required this.locations, required this.onOpen});

  final List<CollectionLocationSummary> locations;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => _DashboardPanel(
    title: 'Collection Map',
    actionLabel: 'Centres',
    onAction: onOpen,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CustomPaint(
        painter: _MapPainter(locations: locations),
        child: Stack(
          children: [
            if (locations.isEmpty)
              const Center(
                child: Text(
                  'Pickup locations will appear here',
                  style: TextStyle(fontSize: 10, color: Color(0xFF617068)),
                ),
              ),
            Positioned(
              right: 8,
              bottom: 8,
              child: Column(
                children: [
                  _MapControl(icon: Icons.add, onTap: onOpen),
                  const SizedBox(height: 2),
                  _MapControl(icon: Icons.remove, onTap: onOpen),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MapControl extends StatelessWidget {
  const _MapControl({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(4),
    child: InkWell(
      onTap: onTap,
      child: SizedBox(width: 27, height: 27, child: Icon(icon, size: 16)),
    ),
  );
}

class _RecentCollectionsPanel extends StatelessWidget {
  const _RecentCollectionsPanel({
    required this.collections,
    required this.onOpen,
  });

  final List<RecentCollectionSummary> collections;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => _DashboardPanel(
    title: 'Recent Collections',
    actionLabel: 'View all',
    onAction: onOpen,
    child: collections.isEmpty
        ? const _EmptyPanel(
            icon: Icons.inventory_2_outlined,
            label: 'No collection records yet',
          )
        : Column(
            children: [
              for (final collection in collections)
                Expanded(
                  child: InkWell(
                    onTap: onOpen,
                    borderRadius: BorderRadius.circular(7),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF4EE),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: const Icon(
                              Icons.devices_other_outlined,
                              size: 18,
                              color: Color(0xFF197A4B),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _collectionCode(collection.id),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '${collection.category} • ${collection.location}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 8,
                                    color: Color(0xFF65736C),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _dateLabel(collection.occurredAt),
                                style: const TextStyle(
                                  fontSize: 8,
                                  color: Color(0xFF617068),
                                ),
                              ),
                              const SizedBox(height: 3),
                              _StatusPill(status: collection.status),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
  );
}

class _EnvironmentalImpactPanel extends StatelessWidget {
  const _EnvironmentalImpactPanel({required this.data, required this.onOpen});

  final AdminOverviewSnapshot data;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final impact = data.impact;
    final items = [
      (
        'CO₂ Emissions Avoided',
        '${_decimal(impact.carbonEmissionsAvoidedKg / 1000)} tonnes',
        Icons.eco,
        const Color(0xFF218D54),
      ),
      (
        'Trees Equivalent',
        _whole(impact.treesEquivalent.round()),
        Icons.park,
        const Color(0xFF168248),
      ),
      (
        'Energy Saved',
        '${_decimal(impact.energySavedKwh)} kWh',
        Icons.bolt,
        const Color(0xFFF0A21B),
      ),
      (
        'Landfill Diversion',
        '${_decimal(impact.landfillDiversionRate)}%',
        Icons.delete_sweep_outlined,
        const Color(0xFF16885B),
      ),
    ];
    return _DashboardPanel(
      title: 'Environmental Impact',
      actionLabel: 'View report',
      onAction: onOpen,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 1.55,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5ECE7)),
            ),
            child: Row(
              children: [
                Icon(item.$3, color: item.$4, size: 26),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.$1,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 8,
                          color: Color(0xFF5E6B64),
                        ),
                      ),
                      const SizedBox(height: 3),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          item.$2,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.data, required this.onGenerateReport});

  final AdminOverviewSnapshot data;
  final VoidCallback onGenerateReport;

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        'Total Partners',
        _whole(data.totalPartners),
        'Service partners',
        Icons.handshake_outlined,
      ),
      (
        'Collection Centres',
        _whole(data.collectionCentres),
        'Active centres',
        Icons.warehouse_outlined,
      ),
      (
        'Registered Users',
        _whole(data.totalUsers),
        'Across all roles',
        Icons.people_outline,
      ),
      (
        'Total Items Tracked',
        _whole(data.trackedItems),
        'Inventory records',
        Icons.qr_code_2,
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F8F4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD7E7DC)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 850;
          final summaries = Wrap(
            spacing: 18,
            runSpacing: 12,
            children: items
                .map(
                  (item) => SizedBox(
                    width: compact ? 180 : 190,
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF116F45),
                          child: Icon(item.$4, size: 21),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.$1,
                                style: const TextStyle(
                                  fontSize: 8,
                                  color: Color(0xFF58665F),
                                ),
                              ),
                              Text(
                                item.$2,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                item.$3,
                                style: const TextStyle(
                                  fontSize: 8,
                                  color: Color(0xFF6D7973),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          );
          final button = FilledButton.icon(
            onPressed: onGenerateReport,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF14824D),
              minimumSize: const Size(168, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7),
              ),
            ),
            icon: const Icon(Icons.description_outlined, size: 19),
            label: const Text('Generate Report'),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [summaries, const SizedBox(height: 13), button],
            );
          }
          return Row(
            children: [
              Expanded(child: summaries),
              const SizedBox(width: 14),
              button,
            ],
          );
        },
      ),
    );
  }
}

class _AdaptivePanelRow extends StatelessWidget {
  const _AdaptivePanelRow({
    required this.children,
    required this.minPanelWidth,
  });

  final List<_PanelSlot> children;
  final double minPanelWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < minPanelWidth * children.length + 24) {
        return Column(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              children[index].child,
              if (index < children.length - 1) const SizedBox(height: 12),
            ],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < children.length; index++) ...[
            Expanded(flex: children[index].flex, child: children[index].child),
            if (index < children.length - 1) const SizedBox(width: 12),
          ],
        ],
      );
    },
  );
}

class _PanelSlot {
  const _PanelSlot({required this.flex, required this.child});
  final int flex;
  final Widget child;
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 34, color: const Color(0xFF9AABA2)),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10, color: Color(0xFF67756E)),
        ),
      ],
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final complete = status == 'completed' || status == 'collected';
    final progress = status == 'inProgress';
    final color = complete
        ? const Color(0xFF16814D)
        : progress
        ? const Color(0xFF356DBA)
        : const Color(0xFFB77A15);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          fontSize: 7,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _LiveDataNote extends StatelessWidget {
  const _LiveDataNote();

  @override
  Widget build(BuildContext context) => const Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      Icon(Icons.sync, size: 13, color: Color(0xFF5C6A63)),
      SizedBox(width: 5),
      Text(
        'Dashboard updates automatically from Firestore',
        style: TextStyle(fontSize: 9, color: Color(0xFF5C6A63)),
      ),
    ],
  );
}

class _DashboardMessage extends StatelessWidget {
  const _DashboardMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 500),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: const Color(0xFF617068)),
            const SizedBox(height: 14),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    ),
  );
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({required this.values, required this.color});
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final points = _points(
      values,
      size,
      horizontalPadding: 1,
      verticalPadding: 3,
    );
    if (points.length < 2) return;
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      line.lineTo(point.dx, point.dy);
    }
    final fill = Path.from(line)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .22), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

class _LineChartPainter extends CustomPainter {
  const _LineChartPainter({required this.values});
  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFFE7EEE9)
      ..strokeWidth = 1;
    for (var index = 0; index <= 4; index++) {
      final y = size.height / 4 * index;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final points = _points(
      values,
      size,
      horizontalPadding: 3,
      verticalPadding: 9,
    );
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 1; index < points.length; index++) {
      final previous = points[index - 1];
      final current = points[index];
      final middle = (previous.dx + current.dx) / 2;
      path.cubicTo(
        middle,
        previous.dy,
        middle,
        current.dy,
        current.dx,
        current.dy,
      );
    }
    final fill = Path.from(path)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x44339D68), Color(0x00339D68)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF168652)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
    for (final point in points) {
      canvas.drawCircle(point, 2.6, Paint()..color = const Color(0xFF168652));
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.values != values;
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.values, required this.colors});
  final List<double> values;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0) return;
    final rect = Offset.zero & size;
    var start = -math.pi / 2;
    for (var index = 0; index < values.length; index++) {
      final sweep = values[index] / total * math.pi * 2;
      canvas.drawArc(
        rect.deflate(size.shortestSide * .08),
        start,
        sweep,
        false,
        Paint()
          ..color = colors[index % colors.length]
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.shortestSide * .22,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) => true;
}

class _MapPainter extends CustomPainter {
  const _MapPainter({required this.locations});
  final List<CollectionLocationSummary> locations;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFE5F2E9), Color(0xFFD7EBE7), Color(0xFFEAF1DF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Offset.zero & size),
    );
    final roadPaint = Paint()
      ..color = Colors.white.withValues(alpha: .85)
      ..strokeWidth = 4;
    for (var index = 1; index < 6; index++) {
      final y = size.height / 6 * index;
      canvas.drawLine(Offset(0, y), Offset(size.width, y - 20), roadPaint);
    }
    for (var index = 1; index < 5; index++) {
      final x = size.width / 5 * index;
      canvas.drawLine(Offset(x, 0), Offset(x + 25, size.height), roadPaint);
    }
    final points = locations.isEmpty
        ? const <Offset>[]
        : locations.map((location) {
            final x = ((location.longitude + 180) / 360).clamp(.08, .92);
            final y = ((90 - location.latitude) / 180).clamp(.1, .9);
            return Offset(x * size.width, y * size.height);
          });
    for (final point in points) {
      canvas.drawCircle(point, 8, Paint()..color = const Color(0xFF168750));
      canvas.drawCircle(point, 3, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) => true;
}

List<Offset> _points(
  List<double> values,
  Size size, {
  required double horizontalPadding,
  required double verticalPadding,
}) {
  if (values.isEmpty) return const [];
  final maxValue = values.fold<double>(0, math.max);
  final minValue = values.fold<double>(values.first, math.min);
  final range = math.max(1, maxValue - minValue);
  return List.generate(values.length, (index) {
    final x = values.length == 1
        ? size.width / 2
        : horizontalPadding +
              index /
                  (values.length - 1) *
                  (size.width - horizontalPadding * 2);
    final normalized = (values[index] - minValue) / range;
    final y =
        size.height -
        verticalPadding -
        normalized * (size.height - verticalPadding * 2);
    return Offset(x, y);
  });
}

String _whole(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(',');
    buffer.write(digits[index]);
  }
  return buffer.toString();
}

String _decimal(double value) {
  final rounded = value.abs() >= 100
      ? value.round().toString()
      : value.toStringAsFixed(1);
  final parts = rounded.split('.');
  final whole = int.tryParse(parts.first) ?? 0;
  return parts.length == 1 ? _whole(whole) : '${_whole(whole)}.${parts.last}';
}

String _collectionCode(String id) {
  if (id.isEmpty) return 'COL-PENDING';
  final code = id.substring(0, math.min(8, id.length)).toUpperCase();
  return 'COL-$code';
}

String _dateLabel(DateTime? date) {
  if (date == null) return 'Pending';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

String _statusLabel(String status) => status
    .replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (match) => '${match.group(1)} ${match.group(2)}',
    )
    .split(' ')
    .map(
      (word) =>
          word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}',
    )
    .join(' ');
