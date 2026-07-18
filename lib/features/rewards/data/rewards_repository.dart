import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/rewards.dart';

class RewardsRepository {
  RewardsRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;
  Stream<RewardWallet> watchWallet(String id) => _db
      .collection('rewardWallets')
      .doc(id)
      .snapshots()
      .map(RewardWallet.fromDoc);
  Stream<List<RewardEntry>> watchHistory(String id) => _db
      .collection('rewardWallets')
      .doc(id)
      .collection('history')
      .snapshots()
      .map((s) => s.docs.map(RewardEntry.fromDoc).toList());
  Stream<List<RewardWallet>> watchLeaderboard() => _db
      .collection('rewardWallets')
      .snapshots()
      .map(
        (s) =>
            s.docs.map(RewardWallet.fromDoc).toList()
              ..sort((a, b) => b.lifetimePoints.compareTo(a.lifetimePoints)),
      );
  Stream<List<RecyclingChallenge>> watchChallenges() => _db
      .collection('recyclingChallenges')
      .snapshots()
      .map((s) => s.docs.map(RecyclingChallenge.fromDoc).toList());
  Stream<List<RewardCoupon>> watchCoupons() => _db
      .collection('rewardCoupons')
      .snapshots()
      .map((s) => s.docs.map(RewardCoupon.fromDoc).toList());
  Future<void> ensureWallet(String id) async {
    final ref = _db.collection('rewardWallets').doc(id);
    if ((await ref.get()).exists) return;
    await ref.set({
      'balance': 0,
      'lifetimePoints': 0,
      'level': RewardLevel.seedling.name,
      'referralCode': 'ECO-${id.substring(0, 6).toUpperCase()}',
      'businessSustainabilityScore': 0,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> award(
    String userId, {
    required RewardTransactionType type,
    required int points,
    required String description,
    required String referenceId,
  }) async {
    if (points <= 0 || referenceId.isEmpty) throw StateError('Invalid reward.');
    final wallet = _db.collection('rewardWallets').doc(userId),
        entry = wallet.collection('history').doc('${type.name}-$referenceId');
    await _db.runTransaction((tx) async {
      if ((await tx.get(entry)).exists) {
        throw StateError('This activity was already rewarded.');
      }
      final snap = await tx.get(wallet),
          current = snap.data()?['lifetimePoints'] as int? ?? 0,
          total = current + points;
      tx.set(wallet, {
        'balance': FieldValue.increment(points),
        'lifetimePoints': total,
        'level': RewardWallet.levelFor(total).name,
        'businessSustainabilityScore': (total / 50).clamp(0, 100),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      tx.set(entry, {
        'type': type.name,
        'points': points,
        'description': description,
        'referenceId': referenceId,
        'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 365)),
        ),
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> redeem(String userId, RewardCoupon coupon) async {
    final wallet = _db.collection('rewardWallets').doc(userId),
        entry = wallet
            .collection('history')
            .doc(
              'redemption-${coupon.id}-${DateTime.now().millisecondsSinceEpoch}',
            );
    await _db.runTransaction((tx) async {
      final w = RewardWallet.fromDoc(await tx.get(wallet));
      if (w.balance < coupon.pointsCost ||
          coupon.status != CouponStatus.active ||
          (coupon.expiresAt?.isBefore(DateTime.now()) ?? false)) {
        throw StateError('Coupon is unavailable or points are insufficient.');
      }
      tx.update(wallet, {
        'balance': FieldValue.increment(-coupon.pointsCost),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(entry, {
        'type': RewardTransactionType.redemption.name,
        'points': -coupon.pointsCost,
        'description': 'Redeemed ${coupon.title}',
        'referenceId': coupon.id,
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.set(_db.collection('rewardRedemptions').doc(), {
        'userId': userId,
        'couponId': coupon.id,
        'couponCode': coupon.code,
        'points': coupon.pointsCost,
        'status': 'issued',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> expirePoints(
    String userId,
    int points,
    String referenceId,
  ) async {
    if (points <= 0) throw StateError('Expiry points must be positive.');
    final wallet = _db.collection('rewardWallets').doc(userId),
        entry = wallet.collection('history').doc('expiry-$referenceId');
    await _db.runTransaction((tx) async {
      if ((await tx.get(entry)).exists) {
        throw StateError('This expiry was already processed.');
      }
      final current = RewardWallet.fromDoc(await tx.get(wallet));
      final amount = points.clamp(0, current.balance);
      tx.update(wallet, {
        'balance': FieldValue.increment(-amount),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(entry, {
        'type': RewardTransactionType.expiry.name,
        'points': -amount,
        'description': 'Expired green points',
        'referenceId': referenceId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> createChallenge({
    required String title,
    required String description,
    required int target,
    required int points,
    required DateTime endsAt,
  }) => _db.collection('recyclingChallenges').add({
    'title': title,
    'description': description,
    'target': target,
    'rewardPoints': points,
    'status': ChallengeStatus.active.name,
    'endsAt': Timestamp.fromDate(endsAt),
    'createdAt': FieldValue.serverTimestamp(),
  });
  Future<void> createCoupon({
    required String code,
    required String title,
    required int cost,
    required String partner,
    required DateTime expiresAt,
  }) => _db.collection('rewardCoupons').add({
    'code': code,
    'title': title,
    'pointsCost': cost,
    'partnerName': partner,
    'status': CouponStatus.active.name,
    'expiresAt': Timestamp.fromDate(expiresAt),
    'createdAt': FieldValue.serverTimestamp(),
  });
}
