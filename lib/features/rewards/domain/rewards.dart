import 'package:cloud_firestore/cloud_firestore.dart';

enum RewardTransactionType {
  pickup,
  referral,
  challenge,
  redemption,
  adjustment,
  expiry,
}

enum RewardLevel { seedling, greenAdvocate, ecoChampion, circularLeader }

enum ChallengeStatus { draft, active, completed, expired }

enum CouponStatus { active, redeemed, expired, disabled }

class RewardWallet {
  const RewardWallet({
    required this.userId,
    required this.balance,
    required this.lifetimePoints,
    required this.level,
    required this.referralCode,
    required this.businessSustainabilityScore,
  });
  final String userId, referralCode;
  final int balance, lifetimePoints;
  final RewardLevel level;
  final double businessSustainabilityScore;
  static RewardLevel levelFor(int p) => p >= 5000
      ? RewardLevel.circularLeader
      : p >= 2000
      ? RewardLevel.ecoChampion
      : p >= 500
      ? RewardLevel.greenAdvocate
      : RewardLevel.seedling;
  factory RewardWallet.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    return RewardWallet.fromJson({'id': d.id, ...?d.data()});
  }
  factory RewardWallet.fromJson(Map<String, dynamic> x) {
    final lifetime =
        (x['lifetimeEarned'] ?? x['lifetimePoints'] as num? ?? 0) as num;
    return RewardWallet(
      userId: (x['userId'] ?? x['id'] ?? '').toString(),
      balance: (x['balance'] as num? ?? 0).toInt(),
      lifetimePoints: lifetime.toInt(),
      level: _rewardLevel(x['level']?.toString(), lifetime.toInt()),
      referralCode: (x['referralCode'] ?? '').toString(),
      businessSustainabilityScore:
          (x['businessSustainabilityScore'] as num? ?? 0).toDouble(),
    );
  }
}

class RewardEntry {
  const RewardEntry({
    required this.type,
    required this.points,
    required this.description,
    required this.referenceId,
    required this.expiresAt,
    required this.createdAt,
  });
  final RewardTransactionType type;
  final int points;
  final String description, referenceId;
  final DateTime? expiresAt, createdAt;
  factory RewardEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    return RewardEntry.fromJson({'id': d.id, ...?d.data()});
  }
  factory RewardEntry.fromJson(Map<String, dynamic> x) {
    return RewardEntry(
      type: _transactionType(x['type']?.toString(), x['ruleId']?.toString()),
      points: (x['points'] as num? ?? 0).toInt(),
      description: (x['description'] ?? x['notes'] ?? '').toString(),
      referenceId: (x['referenceId'] ?? '').toString(),
      expiresAt: _date(x['expiresAt']),
      createdAt: _date(x['createdAt']),
    );
  }
}

class RecyclingChallenge {
  const RecyclingChallenge({
    required this.id,
    required this.title,
    required this.description,
    required this.target,
    required this.rewardPoints,
    required this.status,
    required this.endsAt,
  });
  final String id, title, description;
  final int target, rewardPoints;
  final ChallengeStatus status;
  final DateTime? endsAt;
  factory RecyclingChallenge.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    return RecyclingChallenge.fromJson({'id': d.id, ...?d.data()});
  }
  factory RecyclingChallenge.fromJson(Map<String, dynamic> x) {
    return RecyclingChallenge(
      id: (x['id'] ?? '').toString(),
      title: (x['title'] ?? '').toString(),
      description: (x['description'] ?? '').toString(),
      target: (x['target'] as num? ?? 0).toInt(),
      rewardPoints: (x['rewardPoints'] as num? ?? 0).toInt(),
      status: _challengeStatus(x),
      endsAt: _date(x['endsAt']),
    );
  }
}

class RewardCoupon {
  const RewardCoupon({
    required this.id,
    required this.code,
    required this.title,
    required this.pointsCost,
    required this.partnerName,
    required this.status,
    required this.expiresAt,
  });
  final String id, code, title, partnerName;
  final int pointsCost;
  final CouponStatus status;
  final DateTime? expiresAt;
  factory RewardCoupon.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    return RewardCoupon.fromJson({'id': d.id, ...?d.data()});
  }
  factory RewardCoupon.fromJson(Map<String, dynamic> x) {
    return RewardCoupon(
      id: (x['id'] ?? '').toString(),
      code: (x['couponPrefix'] ?? x['code'] ?? '').toString(),
      title: (x['name'] ?? x['title'] ?? '').toString(),
      pointsCost: (x['pointsCost'] as num? ?? 0).toInt(),
      partnerName: (x['partnerName'] ?? x['partnerId'] ?? '').toString(),
      status: x['active'] == false
          ? CouponStatus.disabled
          : _couponStatus(x['status']?.toString()),
      expiresAt: _date(x['expiresAt']),
    );
  }
}

DateTime? _date(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value);
  return null;
}

RewardLevel _rewardLevel(String? value, int points) {
  switch (value) {
    case 'platinum':
      return RewardLevel.circularLeader;
    case 'gold':
      return RewardLevel.ecoChampion;
    case 'silver':
      return RewardLevel.greenAdvocate;
    case 'greenStarter':
      return RewardLevel.seedling;
    default:
      return RewardWallet.levelFor(points);
  }
}

RewardTransactionType _transactionType(String? value, String? ruleId) {
  if (value == 'debit') return RewardTransactionType.redemption;
  if (value == 'expiry') return RewardTransactionType.expiry;
  final normalized = (ruleId ?? value ?? '').toLowerCase();
  if (normalized.contains('referral')) return RewardTransactionType.referral;
  if (normalized.contains('challenge')) return RewardTransactionType.challenge;
  if (normalized.contains('adjust')) return RewardTransactionType.adjustment;
  return RewardTransactionType.pickup;
}

ChallengeStatus _challengeStatus(Map<String, dynamic> value) {
  final status = value['status']?.toString();
  if (status != null) {
    for (final item in ChallengeStatus.values) {
      if (item.name == status) return item;
    }
  }
  if (value['active'] == true) return ChallengeStatus.active;
  return ChallengeStatus.draft;
}

CouponStatus _couponStatus(String? value) {
  for (final item in CouponStatus.values) {
    if (item.name == value) return item;
  }
  return CouponStatus.active;
}
