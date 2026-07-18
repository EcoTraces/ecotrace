import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../data/rewards_repository.dart';
import '../domain/rewards.dart';

class RewardsScreen extends StatefulWidget {
  const RewardsScreen({
    super.key,
    required this.repository,
    required this.userId,
    required this.canManage,
  });
  final RewardsRepository repository;
  final String userId;
  final bool canManage;
  @override
  State<RewardsScreen> createState() => _R();
}

class _R extends State<RewardsScreen> {
  @override
  void initState() {
    super.initState();
    widget.repository.ensureWallet(widget.userId);
  }

  @override
  Widget build(BuildContext c) => StreamBuilder<RewardWallet>(
    stream: widget.repository.watchWallet(widget.userId),
    builder: (c, w) => StreamBuilder<List<RewardEntry>>(
      stream: widget.repository.watchHistory(widget.userId),
      builder: (c, h) => StreamBuilder<List<RewardCoupon>>(
        stream: widget.repository.watchCoupons(),
        builder: (c, cp) => StreamBuilder<List<RecyclingChallenge>>(
          stream: widget.repository.watchChallenges(),
          builder: (c, ch) {
            if (!w.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            return Scaffold(
              appBar: AppBar(
                title: const Text('Green rewards'),
                actions: [
                  IconButton(
                    onPressed: () => _certificate(w.data!),
                    icon: const Icon(Icons.workspace_premium_outlined),
                  ),
                ],
              ),
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          Text(
                            '${w.data!.balance} points',
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(w.data!.level.name),
                          Text(
                            'Lifetime ${w.data!.lifetimePoints} • Sustainability ${w.data!.businessSustainabilityScore.toStringAsFixed(1)}%',
                          ),
                          Text('Referral code ${w.data!.referralCode}'),
                        ],
                      ),
                    ),
                  ),
                  if (widget.canManage)
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton.tonal(
                          onPressed: () => _award(c),
                          child: const Text('Award points'),
                        ),
                        FilledButton.tonal(
                          onPressed: () => _coupon(c),
                          child: const Text('Create coupon'),
                        ),
                        FilledButton.tonal(
                          onPressed: () => _challenge(c),
                          child: const Text('Create challenge'),
                        ),
                      ],
                    ),
                  Text(
                    'Recycling challenges',
                    style: Theme.of(c).textTheme.titleLarge,
                  ),
                  for (final x in ch.data ?? <RecyclingChallenge>[])
                    ListTile(
                      title: Text(x.title),
                      subtitle: Text('${x.description} • Target ${x.target}'),
                      trailing: Text('+${x.rewardPoints}'),
                    ),
                  Text(
                    'Partner rewards and coupons',
                    style: Theme.of(c).textTheme.titleLarge,
                  ),
                  for (final x in cp.data ?? <RewardCoupon>[])
                    Card(
                      child: ListTile(
                        title: Text(x.title),
                        subtitle: Text(
                          '${x.partnerName} • ${x.code} • Expires ${x.expiresAt}',
                        ),
                        trailing: FilledButton(
                          onPressed: () =>
                              widget.repository.redeem(widget.userId, x),
                          child: Text('${x.pointsCost} pts'),
                        ),
                      ),
                    ),
                  Text(
                    'Reward history',
                    style: Theme.of(c).textTheme.titleLarge,
                  ),
                  for (final x in h.data ?? <RewardEntry>[])
                    ListTile(
                      leading: Icon(
                        x.points >= 0
                            ? Icons.add_circle_outline
                            : Icons.remove_circle_outline,
                      ),
                      title: Text(x.description),
                      subtitle: Text(
                        '${x.type.name} • ${x.referenceId} • expires ${x.expiresAt}',
                      ),
                      trailing: Text('${x.points > 0 ? '+' : ''}${x.points}'),
                    ),
                  Text('Leaderboard', style: Theme.of(c).textTheme.titleLarge),
                  StreamBuilder<List<RewardWallet>>(
                    stream: widget.repository.watchLeaderboard(),
                    builder: (c, s) => Column(
                      children: [
                        for (var i = 0; i < (s.data ?? []).take(10).length; i++)
                          ListTile(
                            leading: CircleAvatar(child: Text('${i + 1}')),
                            title: Text((s.data ?? [])[i].userId),
                            trailing: Text(
                              '${(s.data ?? [])[i].lifetimePoints}',
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
      ),
    ),
  );
  Future<void> _award(BuildContext c) async {
    var type = RewardTransactionType.pickup;
    final u = TextEditingController(text: widget.userId),
        p = TextEditingController(),
        r = TextEditingController(),
        d = TextEditingController();
    final ok = await _f(c, 'Award verified activity', [
      DropdownButtonFormField<RewardTransactionType>(
        initialValue: type,
        items: RewardTransactionType.values
            .where((value) => value != RewardTransactionType.redemption)
            .map(
              (value) =>
                  DropdownMenuItem(value: value, child: Text(value.name)),
            )
            .toList(),
        onChanged: (value) => type = value!,
      ),
      TextField(
        controller: u,
        decoration: const InputDecoration(labelText: 'User ID'),
      ),
      TextField(
        controller: p,
        decoration: const InputDecoration(labelText: 'Points'),
      ),
      TextField(
        controller: r,
        decoration: const InputDecoration(
          labelText: 'Unique pickup/referral reference',
        ),
      ),
      TextField(
        controller: d,
        decoration: const InputDecoration(labelText: 'Description'),
      ),
    ]);
    if (ok) {
      if (type == RewardTransactionType.expiry) {
        await widget.repository.expirePoints(
          u.text,
          int.tryParse(p.text) ?? 0,
          r.text,
        );
      } else {
        await widget.repository.award(
          u.text,
          type: type,
          points: int.tryParse(p.text) ?? 0,
          description: d.text,
          referenceId: r.text,
        );
      }
    }
  }

  Future<void> _coupon(BuildContext c) async {
    final code = TextEditingController(),
        title = TextEditingController(),
        cost = TextEditingController(),
        partner = TextEditingController();
    final ok = await _f(c, 'Coupon', [
      TextField(controller: code),
      TextField(controller: title),
      TextField(controller: cost),
      TextField(controller: partner),
    ]);
    if (ok) {
      await widget.repository.createCoupon(
        code: code.text,
        title: title.text,
        cost: int.tryParse(cost.text) ?? 0,
        partner: partner.text,
        expiresAt: DateTime.now().add(const Duration(days: 180)),
      );
    }
  }

  Future<void> _challenge(BuildContext c) async {
    final title = TextEditingController(),
        desc = TextEditingController(),
        target = TextEditingController(),
        points = TextEditingController();
    final ok = await _f(c, 'Challenge', [
      TextField(controller: title),
      TextField(controller: desc),
      TextField(controller: target),
      TextField(controller: points),
    ]);
    if (ok) {
      await widget.repository.createChallenge(
        title: title.text,
        description: desc.text,
        target: int.tryParse(target.text) ?? 0,
        points: int.tryParse(points.text) ?? 0,
        endsAt: DateTime.now().add(const Duration(days: 30)),
      );
    }
  }

  Future<void> _certificate(RewardWallet w) async {
    final d = pw.Document();
    d.addPage(
      pw.Page(
        build: (_) => pw.Column(
          children: [
            pw.Header(text: 'Digital Environmental Certificate'),
            pw.Text('Participant ${w.userId}'),
            pw.Text('Green points ${w.lifetimePoints}'),
            pw.Text('Level ${w.level.name}'),
            pw.Text(
              'Business sustainability score ${w.businessSustainabilityScore.toStringAsFixed(1)}%',
            ),
          ],
        ),
      ),
    );
    await Printing.layoutPdf(onLayout: (_) => d.save());
  }
}

Future<bool> _f(BuildContext c, String t, List<Widget> w) async =>
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
