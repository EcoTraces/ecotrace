import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../auth/domain/app_role.dart';
import '../../notifications/presentation/notification_badge.dart';
import '../../pickups/data/pickup_repository.dart';
import '../../pickups/domain/pickup.dart';
import '../../rewards/data/rewards_repository.dart';
import '../../rewards/domain/rewards.dart';
import '../domain/application_interface.dart';

class CitizenDashboard extends StatefulWidget {
  const CitizenDashboard({
    super.key,
    required this.userId,
    required this.displayName,
    required this.role,
    this.pickupRepository,
    this.rewardsRepository,
    this.pickupsStream,
    this.walletStream,
    required this.onOpen,
    required this.onOpenMenu,
    required this.footer,
    required this.mobileLayout,
  }) : assert(
         pickupRepository != null || pickupsStream != null,
         'Provide a pickup repository or pickup stream.',
       ),
       assert(
         rewardsRepository != null || walletStream != null,
         'Provide a rewards repository or wallet stream.',
       );

  final String userId;
  final String displayName;
  final AppRole role;
  final PickupRepository? pickupRepository;
  final RewardsRepository? rewardsRepository;
  final Stream<List<PickupRequest>>? pickupsStream;
  final Stream<RewardWallet>? walletStream;
  final ValueChanged<WorkspaceDestination> onOpen;
  final VoidCallback onOpenMenu;
  final Widget footer;
  final bool mobileLayout;

  @override
  State<CitizenDashboard> createState() => _CitizenDashboardState();
}

class _CitizenDashboardState extends State<CitizenDashboard> {
  late Stream<List<PickupRequest>> _pickups;
  late Stream<RewardWallet> _wallet;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _connect() {
    _pickups =
        widget.pickupsStream ??
        widget.pickupRepository!.watchMine(widget.userId);
    _wallet =
        widget.walletStream ??
        widget.rewardsRepository!.watchWallet(widget.userId);
  }

  void _retry() => setState(_connect);

  @override
  Widget build(BuildContext context) => StreamBuilder<List<PickupRequest>>(
    stream: _pickups,
    builder: (context, pickupSnapshot) {
      if (pickupSnapshot.hasError) {
        return _CitizenMessage(
          title: 'Unable to load your dashboard',
          message: '${pickupSnapshot.error}',
          onRetry: _retry,
        );
      }
      if (!pickupSnapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return StreamBuilder<RewardWallet>(
        stream: _wallet,
        builder: (context, walletSnapshot) {
          final data = _CitizenDashboardData(
            pickups: pickupSnapshot.data!,
            wallet: walletSnapshot.data,
          );
          if (widget.mobileLayout) {
            return _MobileCitizenDashboard(
              data: data,
              displayName: widget.displayName,
              role: widget.role,
              onOpen: widget.onOpen,
              onOpenMenu: widget.onOpenMenu,
            );
          }
          return _DesktopCitizenDashboard(
            data: data,
            role: widget.role,
            onOpen: widget.onOpen,
            footer: widget.footer,
          );
        },
      );
    },
  );
}

class _CitizenDashboardData {
  _CitizenDashboardData({required this.pickups, required this.wallet});

  final List<PickupRequest> pickups;
  final RewardWallet? wallet;

  int get totalPickups => pickups.length;
  double get totalWeight =>
      pickups.fold<double>(0, (sum, pickup) => sum + pickup.weight);
  List<PickupRequest> get successful => pickups
      .where(
        (pickup) =>
            pickup.status == PickupStatus.collected ||
            pickup.status == PickupStatus.completed,
      )
      .toList();
  double get collectedWeight =>
      successful.fold<double>(0, (sum, pickup) => sum + pickup.weight);
  int get rewards => wallet?.balance ?? 0;
  double get carbonAvoidedKg => collectedWeight * 1.5;

  List<PickupRequest> get recent => pickups.take(4).toList();

  Map<WasteCategory, double> get categories {
    final values = <WasteCategory, double>{};
    for (final pickup in pickups) {
      values.update(
        pickup.category,
        (weight) => weight + pickup.weight,
        ifAbsent: () => pickup.weight,
      );
    }
    return values;
  }

  List<double> get monthlyTrend {
    final now = DateTime.now();
    return List<double>.generate(6, (index) {
      final offset = 5 - index;
      final month = DateTime(now.year, now.month - offset);
      return pickups
          .where(
            (pickup) =>
                pickup.scheduledAt.year == month.year &&
                pickup.scheduledAt.month == month.month,
          )
          .fold<double>(0, (sum, pickup) => sum + pickup.weight);
    });
  }
}

class _DesktopCitizenDashboard extends StatelessWidget {
  const _DesktopCitizenDashboard({
    required this.data,
    required this.role,
    required this.onOpen,
    required this.footer,
  });

  final _CitizenDashboardData data;
  final AppRole role;
  final ValueChanged<WorkspaceDestination> onOpen;
  final Widget footer;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFFF5F9F6),
    child: CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          sliver: SliverToBoxAdapter(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1000 ? 4 : 2;
                const gap = 12.0;
                final width =
                    (constraints.maxWidth - (columns - 1) * gap) / columns;
                final cards = [
                  _CitizenMetric(
                    label: 'Total Pickups',
                    value: '${data.totalPickups}',
                    detail: '${data.successful.length} completed',
                    icon: Icons.local_shipping_outlined,
                    color: const Color(0xFF168B50),
                    destination: WorkspaceDestination.myPickups,
                  ),
                  _CitizenMetric(
                    label: 'Total E-Waste',
                    value: '${data.totalWeight.toStringAsFixed(1)} kg',
                    detail: 'Across all requests',
                    icon: Icons.scale_outlined,
                    color: const Color(0xFF4267C9),
                    destination: WorkspaceDestination.trackWaste,
                  ),
                  _CitizenMetric(
                    label: 'Collected',
                    value: '${data.collectedWeight.toStringAsFixed(1)} kg',
                    detail: 'Successfully recovered',
                    icon: Icons.recycling,
                    color: const Color(0xFF8C48C6),
                    destination: WorkspaceDestination.myPickups,
                  ),
                  _CitizenMetric(
                    label: role == AppRole.business
                        ? 'Business Rewards'
                        : role == AppRole.institution
                        ? 'Institution Rewards'
                        : 'Green Rewards',
                    value: '${data.rewards}',
                    detail: 'Available points',
                    icon: Icons.workspace_premium_outlined,
                    color: const Color(0xFFF39B28),
                    destination: WorkspaceDestination.rewards,
                  ),
                ];
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: cards
                      .map(
                        (card) => SizedBox(
                          width: width,
                          height: 132,
                          child: _MetricCard(
                            metric: card,
                            onTap: () => onOpen(card.destination),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          sliver: SliverToBoxAdapter(
            child: _ResponsiveRow(
              children: [
                Expanded(
                  flex: 12,
                  child: _DashboardPanel(
                    title: 'Pickup Trends',
                    trailing: 'Last 6 months',
                    child: _TrendChart(values: data.monthlyTrend),
                  ),
                ),
                Expanded(
                  flex: 10,
                  child: _DashboardPanel(
                    title: 'E-Waste by Category',
                    trailing: '${data.totalWeight.toStringAsFixed(1)} kg',
                    child: _CategoryBreakdown(values: data.categories),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          sliver: SliverToBoxAdapter(
            child: _ResponsiveRow(
              children: [
                Expanded(
                  flex: 12,
                  child: _RecentPickupsPanel(
                    pickups: data.recent,
                    onOpen: () => onOpen(WorkspaceDestination.myPickups),
                  ),
                ),
                Expanded(
                  flex: 10,
                  child: _QuickActionsPanel(role: role, onOpen: onOpen),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          sliver: SliverToBoxAdapter(
            child: _CampaignBanner(
              compact: false,
              onLearnMore: () => onOpen(WorkspaceDestination.rewards),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          sliver: SliverToBoxAdapter(child: footer),
        ),
      ],
    ),
  );
}

class _MobileCitizenDashboard extends StatelessWidget {
  const _MobileCitizenDashboard({
    required this.data,
    required this.displayName,
    required this.role,
    required this.onOpen,
    required this.onOpenMenu,
  });

  final _CitizenDashboardData data;
  final String displayName;
  final AppRole role;
  final ValueChanged<WorkspaceDestination> onOpen;
  final VoidCallback onOpenMenu;

  @override
  Widget build(BuildContext context) {
    final firstName = displayName.trim().isEmpty
        ? 'Eco champion'
        : displayName.trim().split(RegExp(r'\s+')).first;
    return ColoredBox(
      color: const Color(0xFFF1F6F2),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _MobileHero(
              name: firstName,
              role: role,
              onMenu: onOpenMenu,
              onNotifications: () => onOpen(WorkspaceDestination.notifications),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            sliver: SliverToBoxAdapter(
              child: Transform.translate(
                offset: const Offset(0, -22),
                child: _MobileImpactCard(data: data),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            sliver: SliverToBoxAdapter(
              child: _MobileActions(role: role, onOpen: onOpen),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            sliver: SliverToBoxAdapter(
              child: _MobileRecent(
                pickup: data.recent.firstOrNull,
                onOpen: () => onOpen(WorkspaceDestination.myPickups),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
            sliver: SliverToBoxAdapter(
              child: _CampaignBanner(
                compact: true,
                onLearnMore: () => onOpen(WorkspaceDestination.rewards),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileHero extends StatelessWidget {
  const _MobileHero({
    required this.name,
    required this.role,
    required this.onMenu,
    required this.onNotifications,
  });

  final String name;
  final AppRole role;
  final VoidCallback onMenu;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) => Container(
    height: 180,
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 48),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFF087751), Color(0xFF159B67)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
    ),
    child: SafeArea(
      bottom: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton.filled(
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF16865A),
            ),
            onPressed: onMenu,
            icon: const Icon(Icons.eco_outlined),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hello, $name 👋',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    role == AppRole.business
                        ? 'Your greener business starts here.'
                        : role == AppRole.institution
                        ? 'Building a greener institution together.'
                        : "Let's make our environment better together!",
                    style: const TextStyle(
                      color: Color(0xE6FFFFFF),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: onNotifications,
            color: Colors.white,
            icon: const NotificationBadgeIcon(color: Colors.white),
          ),
        ],
      ),
    ),
  );
}

class _MobileImpactCard extends StatelessWidget {
  const _MobileImpactCard({required this.data});

  final _CitizenDashboardData data;

  @override
  Widget build(BuildContext context) => _SurfaceCard(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'My Impact This Month',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        const SizedBox(height: 13),
        Row(
          children: [
            _MobileImpactMetric(
              label: 'Pickups',
              value: '${data.totalPickups}',
              icon: Icons.local_shipping,
              color: const Color(0xFF168B50),
              background: const Color(0xFFE6F5EB),
            ),
            _MobileImpactMetric(
              label: 'E-Waste',
              value: data.totalWeight.toStringAsFixed(1),
              icon: Icons.scale,
              color: const Color(0xFF4267C9),
              background: const Color(0xFFE8EEFC),
            ),
            _MobileImpactMetric(
              label: 'CO₂ Saved',
              value: data.carbonAvoidedKg.toStringAsFixed(1),
              icon: Icons.eco,
              color: const Color(0xFF8251C5),
              background: const Color(0xFFF1EAFC),
            ),
            _MobileImpactMetric(
              label: 'Rewards',
              value: '${data.rewards}',
              icon: Icons.card_giftcard,
              color: const Color(0xFFF08B20),
              background: const Color(0xFFFFF1E2),
            ),
          ],
        ),
      ],
    ),
  );
}

class _MobileImpactMetric extends StatelessWidget {
  const _MobileImpactMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.background,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: 8),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 6),
          Icon(icon, color: color, size: 19),
        ],
      ),
    ),
  );
}

class _MobileActions extends StatelessWidget {
  const _MobileActions({required this.role, required this.onOpen});

  final AppRole role;
  final ValueChanged<WorkspaceDestination> onOpen;

  @override
  Widget build(BuildContext context) {
    final actions = [
      (
        role == AppRole.household ? 'Request\nPickup' : 'Schedule\nPickup',
        Icons.local_shipping_outlined,
        const Color(0xFF188D56),
        const Color(0xFFE6F5EB),
        WorkspaceDestination.requestPickup,
      ),
      (
        'Track\nRequest',
        Icons.location_on_outlined,
        const Color(0xFF3970D3),
        const Color(0xFFE8EEFC),
        WorkspaceDestination.trackWaste,
      ),
      (
        'Pickup\nHistory',
        Icons.history,
        const Color(0xFF7655C5),
        const Color(0xFFF0EBFC),
        WorkspaceDestination.myPickups,
      ),
      (
        'My\nRewards',
        Icons.card_giftcard,
        const Color(0xFFEC8121),
        const Color(0xFFFFF0E3),
        WorkspaceDestination.rewards,
      ),
    ];
    return _SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What would you like to do?',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 13),
          Row(
            children: actions
                .map(
                  (action) => Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onOpen(action.$5),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: action.$4,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(action.$2, color: action.$3),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              action.$1,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                height: 1.15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _MobileRecent extends StatelessWidget {
  const _MobileRecent({required this.pickup, required this.onOpen});

  final PickupRequest? pickup;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => _SurfaceCard(
    padding: const EdgeInsets.all(14),
    child: Column(
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Recent Request',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ),
            TextButton(onPressed: onOpen, child: const Text('View all')),
          ],
        ),
        if (pickup == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text('No pickup requests yet.'),
          )
        else
          _PickupTile(pickup: pickup!, compact: true),
      ],
    ),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric, required this.onTap});

  final _CitizenMetric metric;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _SurfaceCard(
    padding: EdgeInsets.zero,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: metric.color.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(metric.icon, color: metric.color),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    metric.label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF5D6A63),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    metric.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    metric.detail,
                    style: TextStyle(fontSize: 9, color: metric.color),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DashboardPanel extends StatelessWidget {
  const _DashboardPanel({
    required this.title,
    required this.trailing,
    required this.child,
  });

  final String title;
  final String trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) => _SurfaceCard(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              trailing,
              style: const TextStyle(fontSize: 10, color: Color(0xFF67746D)),
            ),
          ],
        ),
        const Divider(height: 24),
        Expanded(child: child),
      ],
    ),
  );
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.values});

  final List<double> values;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: CustomPaint(
          painter: _TrendPainter(values),
          child: const SizedBox.expand(),
        ),
      ),
      const SizedBox(height: 8),
      const Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('6 months ago', style: TextStyle(fontSize: 9)),
          Text('Today', style: TextStyle(fontSize: 9)),
        ],
      ),
    ],
  );
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFFE4ECE7)
      ..strokeWidth = 1;
    for (var index = 0; index <= 4; index++) {
      final y = size.height * index / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (values.isEmpty) return;
    final maxValue = math.max(
      1.0,
      values.fold<double>(0, (current, value) => math.max(current, value)),
    );
    final path = Path();
    final fill = Path();
    for (var index = 0; index < values.length; index++) {
      final x = values.length == 1
          ? 0.0
          : size.width * index / (values.length - 1);
      final y = size.height - values[index] / maxValue * (size.height * 0.85);
      if (index == 0) {
        path.moveTo(x, y);
        fill
          ..moveTo(x, size.height)
          ..lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0x55199A61), Color(0x00199A61)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF18945B)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.values != values;
}

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.values});

  final Map<WasteCategory, double> values;

  static const colors = [
    Color(0xFF18A197),
    Color(0xFF4267C9),
    Color(0xFFF1A12B),
    Color(0xFF8C4CC5),
    Color(0xFFEA6757),
    Color(0xFF70B85B),
    Color(0xFF97A5A0),
  ];

  @override
  Widget build(BuildContext context) {
    final entries = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) {
      return const Center(child: Text('Category data will appear here.'));
    }
    return Row(
      children: [
        SizedBox(
          width: 130,
          height: 130,
          child: CustomPaint(
            painter: _DonutPainter(
              values: entries.map((entry) => entry.value).toList(),
              colors: colors,
            ),
            child: Center(
              child: Text(
                '${entries.fold<double>(0, (sum, entry) => sum + entry.value).toStringAsFixed(1)}\nkg',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ListView.separated(
            physics: const NeverScrollableScrollPhysics(),
            itemCount: math.min(entries.length, 5),
            separatorBuilder: (_, _) => const SizedBox(height: 7),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: colors[index % colors.length],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      _categoryLabel(entry.key),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                  Text(
                    '${entry.value.toStringAsFixed(1)} kg',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.values, required this.colors});

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
        rect.deflate(12),
        start,
        sweep,
        false,
        Paint()
          ..color = colors[index % colors.length]
          ..strokeWidth = 20
          ..style = PaintingStyle.stroke,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) => true;
}

class _RecentPickupsPanel extends StatelessWidget {
  const _RecentPickupsPanel({required this.pickups, required this.onOpen});

  final List<PickupRequest> pickups;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => _SurfaceCard(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Recent Pickup Requests',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            TextButton(onPressed: onOpen, child: const Text('View all')),
          ],
        ),
        const Divider(),
        if (pickups.isEmpty)
          const Expanded(child: Center(child: Text('No pickup requests yet.')))
        else
          Expanded(
            child: ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: pickups.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) =>
                  _PickupTile(pickup: pickups[index]),
            ),
          ),
      ],
    ),
  );
}

class _PickupTile extends StatelessWidget {
  const _PickupTile({required this.pickup, this.compact = false});

  final PickupRequest pickup;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(pickup.status);
    return ListTile(
      dense: true,
      contentPadding: compact ? EdgeInsets.zero : null,
      leading: Container(
        width: compact ? 44 : 38,
        height: compact ? 44 : 38,
        decoration: BoxDecoration(
          color: const Color(0xFFE9F4ED),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(
          _categoryIcon(pickup.category),
          color: const Color(0xFF168B50),
        ),
      ),
      title: Text(
        _categoryLabel(pickup.category),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: compact ? 11 : 12,
        ),
      ),
      subtitle: Text(
        '${pickup.location} • ${_date(pickup.scheduledAt)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: compact ? 9 : 10),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          _statusLabel(pickup.status),
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _QuickActionsPanel extends StatelessWidget {
  const _QuickActionsPanel({required this.role, required this.onOpen});

  final AppRole role;
  final ValueChanged<WorkspaceDestination> onOpen;

  @override
  Widget build(BuildContext context) {
    final actions = [
      (
        role == AppRole.household
            ? 'Request New Pickup'
            : 'Schedule a New Pickup',
        'Create a new e-waste pickup',
        Icons.add_box_outlined,
        WorkspaceDestination.requestPickup,
      ),
      (
        'View My Collections',
        'Track collection history',
        Icons.calendar_month_outlined,
        WorkspaceDestination.myPickups,
      ),
      (
        'Track E-Waste',
        'Follow an item or request',
        Icons.qr_code_scanner,
        WorkspaceDestination.trackWaste,
      ),
      (
        'Rewards & Benefits',
        'Use your available green points',
        Icons.card_giftcard_outlined,
        WorkspaceDestination.rewards,
      ),
    ];
    return _SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Actions',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const Divider(height: 24),
          Expanded(
            child: ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: actions.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final action = actions[index];
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F3EC),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      action.$3,
                      color: const Color(0xFF168B50),
                      size: 18,
                    ),
                  ),
                  title: Text(
                    action.$1,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    action.$2,
                    style: const TextStyle(fontSize: 9),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => onOpen(action.$4),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CampaignBanner extends StatelessWidget {
  const _CampaignBanner({required this.compact, required this.onLearnMore});

  final bool compact;
  final VoidCallback onLearnMore;

  @override
  Widget build(BuildContext context) => Container(
    height: compact ? 108 : 134,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF087651), Color(0xFF2AA468)],
      ),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Stack(
      children: [
        Positioned(
          right: compact ? -18 : 36,
          bottom: compact ? -26 : -48,
          child: Icon(
            Icons.public,
            size: compact ? 120 : 190,
            color: Colors.white.withValues(alpha: 0.13),
          ),
        ),
        Positioned(
          right: compact ? 20 : 220,
          top: 16,
          child: Icon(
            Icons.eco,
            size: compact ? 48 : 62,
            color: const Color(0xFF8DDB74),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(compact ? 16 : 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                compact
                    ? 'Recycle Today\nFor a Better Tomorrow'
                    : 'Together, we build a Cleaner & Greener Future',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: compact ? 15 : 20,
                  height: 1.15,
                ),
              ),
              if (!compact) ...[
                const SizedBox(height: 5),
                const Text(
                  'Thank you for contributing to a sustainable Sierra Leone.',
                  style: TextStyle(color: Color(0xE6FFFFFF), fontSize: 11),
                ),
              ],
              const SizedBox(height: 9),
              SizedBox(
                height: 30,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF087651),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    textStyle: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onPressed: onLearnMore,
                  child: const Text('Learn More'),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ResponsiveRow extends StatelessWidget {
  const _ResponsiveRow({required this.children});

  final List<Expanded> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 820) {
        return Column(
          children: children
              .map(
                (child) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SizedBox(height: 320, child: child.child),
                ),
              )
              .toList(),
        );
      }
      return SizedBox(
        height: 320,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [children.first, const SizedBox(width: 12), children.last],
        ),
      );
    },
  );
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child, required this.padding});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(13),
      side: const BorderSide(color: Color(0xFFDDE8E1)),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class _CitizenMessage extends StatelessWidget {
  const _CitizenMessage({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 48),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

class _CitizenMetric {
  const _CitizenMetric({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
    required this.destination,
  });

  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color color;
  final WorkspaceDestination destination;
}

String _categoryLabel(WasteCategory category) => switch (category) {
  WasteCategory.computers => 'Computers',
  WasteCategory.phones => 'Mobile phones',
  WasteCategory.televisions => 'Televisions',
  WasteCategory.appliances => 'Appliances',
  WasteCategory.batteries => 'Batteries',
  WasteCategory.accessories => 'Accessories',
  WasteCategory.other => 'Other e-waste',
};

IconData _categoryIcon(WasteCategory category) => switch (category) {
  WasteCategory.computers => Icons.computer,
  WasteCategory.phones => Icons.smartphone,
  WasteCategory.televisions => Icons.tv,
  WasteCategory.appliances => Icons.kitchen,
  WasteCategory.batteries => Icons.battery_charging_full,
  WasteCategory.accessories => Icons.cable,
  WasteCategory.other => Icons.devices_other,
};

String _statusLabel(PickupStatus status) {
  final value = status.name.replaceAllMapped(
    RegExp(r'([A-Z])'),
    (match) => ' ${match.group(1)!.toLowerCase()}',
  );
  return '${value[0].toUpperCase()}${value.substring(1)}';
}

Color _statusColor(PickupStatus status) => switch (status) {
  PickupStatus.completed || PickupStatus.collected => const Color(0xFF168B50),
  PickupStatus.cancelled || PickupStatus.failed => const Color(0xFFD65348),
  PickupStatus.inProgress => const Color(0xFF4267C9),
  _ => const Color(0xFFE08A1E),
};

String _date(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
