import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_config.dart';
import '../domain/rewards.dart';

class RewardsRepository {
  RewardsRepository({FirebaseFirestore? firestore, ApiClient? apiClient})
    : _db = firestore ?? FirebaseFirestore.instance,
      _api = apiClient ?? ApiClient.instance,
      _useApi = apiClient != null || (firestore == null && ApiConfig.enabled);

  final FirebaseFirestore _db;
  final ApiClient _api;
  final bool _useApi;

  Stream<RewardWallet> watchWallet(String id) => _useApi
      ? _pollOne('/api/v1/rewards/wallet', RewardWallet.fromJson)
      : _db
            .collection('rewardWallets')
            .doc(id)
            .snapshots()
            .map(RewardWallet.fromDoc);

  Stream<List<RewardEntry>> watchHistory(String id) => _useApi
      ? _pollList('/api/v1/rewards/history', RewardEntry.fromJson)
      : _db
            .collection('rewardWallets')
            .doc(id)
            .collection('transactions')
            .snapshots()
            .map((s) => s.docs.map(RewardEntry.fromDoc).toList());

  Stream<List<RewardWallet>> watchLeaderboard() => _useApi
      ? _pollList('/api/v1/rewards/leaderboard', RewardWallet.fromJson)
      : _db
            .collection('rewardWallets')
            .snapshots()
            .map(
              (s) => s.docs.map(RewardWallet.fromDoc).toList()
                ..sort((a, b) => b.lifetimePoints.compareTo(a.lifetimePoints)),
            );

  Stream<List<RecyclingChallenge>> watchChallenges() => _useApi
      ? _pollList('/api/v1/rewards/challenges', RecyclingChallenge.fromJson)
      : _db
            .collection('rewardChallenges')
            .snapshots()
            .map((s) => s.docs.map(RecyclingChallenge.fromDoc).toList());

  Stream<List<RewardCoupon>> watchCoupons() => _useApi
      ? _pollList('/api/v1/rewards/catalog', RewardCoupon.fromJson)
      : _db
            .collection('rewardCatalog')
            .snapshots()
            .map((s) => s.docs.map(RewardCoupon.fromDoc).toList());

  Stream<T> _pollOne<T>(
    String path,
    T Function(Map<String, dynamic>) decode,
  ) async* {
    while (true) {
      yield decode(await _api.get(path));
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Stream<List<T>> _pollList<T>(
    String path,
    T Function(Map<String, dynamic>) decode,
  ) async* {
    while (true) {
      final data = await _api.getList(path);
      yield data.map(decode).toList();
      await Future<void>.delayed(
        const Duration(seconds: ApiConfig.pollingSeconds),
      );
    }
  }

  Future<void> ensureWallet(String id) async {
    if (_useApi) {
      await _api.get('/api/v1/rewards/wallet');
      return;
    }
    final ref = _db.collection('rewardWallets').doc(id);
    if ((await ref.get()).exists) return;
    await ref.set({
      'userId': id,
      'balance': 0,
      'lifetimeEarned': 0,
      'lifetimeRedeemed': 0,
      'level': 'greenStarter',
      'referralCode': 'ECO-${id.substring(0, 6).toUpperCase()}',
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
    if (_useApi) {
      await _api.post('/api/v1/rewards/adjustments', {
        'userId': userId,
        'points': points,
        'description': description.isEmpty
            ? '${type.name} reward'
            : description,
        'referenceId': '${type.name}-$referenceId',
        'expiresAfterDays': 365,
      });
      return;
    }
    await _fallbackAdjustment(
      userId,
      points,
      type.name,
      description,
      referenceId,
    );
  }

  Future<void> redeem(String userId, RewardCoupon coupon) async {
    if (_useApi) {
      await _api.post('/api/v1/rewards/redemptions', {
        'rewardId': coupon.id,
        'quantity': 1,
      });
      return;
    }
    final wallet = _db.collection('rewardWallets').doc(userId);
    await _db.runTransaction((tx) async {
      final snapshot = await tx.get(wallet);
      final balance = (snapshot.data()?['balance'] as num? ?? 0).toInt();
      if (balance < coupon.pointsCost || coupon.status != CouponStatus.active) {
        throw StateError('Coupon is unavailable or points are insufficient.');
      }
      tx.update(wallet, {
        'balance': FieldValue.increment(-coupon.pointsCost),
        'lifetimeRedeemed': FieldValue.increment(coupon.pointsCost),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(_db.collection('rewardRedemptions').doc(), {
        'userId': userId,
        'rewardId': coupon.id,
        'pointsSpent': coupon.pointsCost,
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
    if (_useApi) {
      await _api.post('/api/v1/rewards/expiry', {
        'userId': userId,
        'points': points,
        'referenceId': referenceId,
      });
      return;
    }
    await _fallbackAdjustment(
      userId,
      -points,
      RewardTransactionType.expiry.name,
      'Expired green points',
      referenceId,
    );
  }

  Future<void> _fallbackAdjustment(
    String userId,
    int points,
    String type,
    String description,
    String referenceId,
  ) async {
    final wallet = _db.collection('rewardWallets').doc(userId);
    final entry = wallet.collection('transactions').doc('$type-$referenceId');
    await _db.runTransaction((tx) async {
      if ((await tx.get(entry)).exists) {
        throw StateError('This activity was already processed.');
      }
      tx.set(wallet, {
        'balance': FieldValue.increment(points),
        if (points > 0) 'lifetimeEarned': FieldValue.increment(points),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      tx.set(entry, {
        'type': type,
        'points': points,
        'description': description,
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
  }) => _useApi
      ? _api
            .post('/api/v1/rewards/challenges', {
              'title': title,
              'description': description,
              'metric': 'pickups',
              'target': target,
              'rewardPoints': points,
              'startsAt': DateTime.now().toUtc().toIso8601String(),
              'endsAt': endsAt.toUtc().toIso8601String(),
              'participantRoles': ['household', 'business', 'institution'],
            })
            .then((_) {})
      : _db.collection('rewardChallenges').add({
          'title': title,
          'description': description,
          'target': target,
          'rewardPoints': points,
          'active': true,
          'endsAt': Timestamp.fromDate(endsAt),
          'createdAt': FieldValue.serverTimestamp(),
        });

  Future<void> createCoupon({
    required String code,
    required String title,
    required int cost,
    required String partner,
    required DateTime expiresAt,
  }) => _useApi
      ? _api
            .put('/api/v1/rewards/catalog/$code', {
              'name': title,
              'description': 'EcoTrace partner reward',
              'pointsCost': cost,
              'stock': 100,
              'type': 'coupon',
              'partnerId': partner,
              'couponPrefix': code,
              'active': true,
            })
            .then((_) {})
      : _db.collection('rewardCatalog').doc(code).set({
          'name': title,
          'pointsCost': cost,
          'partnerName': partner,
          'couponPrefix': code,
          'active': true,
          'expiresAt': Timestamp.fromDate(expiresAt),
          'createdAt': FieldValue.serverTimestamp(),
        });

  Future<void> joinChallenge(String challengeId) async {
    if (_useApi) {
      await _api.post('/api/v1/rewards/challenges/$challengeId/join', {});
    }
  }

  Future<void> refer(String email) async {
    if (_useApi) {
      await _api.post('/api/v1/rewards/referrals', {'referredEmail': email});
    }
  }

  Future<Map<String, dynamic>> certificate() =>
      _api.get('/api/v1/rewards/certificate');
}
