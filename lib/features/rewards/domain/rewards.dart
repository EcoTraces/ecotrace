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
    final x = d.data() ?? {};
    return RewardWallet(
      userId: d.id,
      balance: x['balance'] ?? 0,
      lifetimePoints: x['lifetimePoints'] ?? 0,
      level: RewardLevel.values.byName(x['level'] ?? 'seedling'),
      referralCode: x['referralCode'] ?? '',
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
    final x = d.data()!;
    return RewardEntry(
      type: RewardTransactionType.values.byName(x['type']),
      points: x['points'],
      description: x['description'] ?? '',
      referenceId: x['referenceId'] ?? '',
      expiresAt: (x['expiresAt'] as Timestamp?)?.toDate(),
      createdAt: (x['createdAt'] as Timestamp?)?.toDate(),
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
    final x = d.data()!;
    return RecyclingChallenge(
      id: d.id,
      title: x['title'] ?? '',
      description: x['description'] ?? '',
      target: x['target'] ?? 0,
      rewardPoints: x['rewardPoints'] ?? 0,
      status: ChallengeStatus.values.byName(x['status'] ?? 'draft'),
      endsAt: (x['endsAt'] as Timestamp?)?.toDate(),
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
    final x = d.data()!;
    return RewardCoupon(
      id: d.id,
      code: x['code'] ?? '',
      title: x['title'] ?? '',
      pointsCost: x['pointsCost'] ?? 0,
      partnerName: x['partnerName'] ?? '',
      status: CouponStatus.values.byName(x['status'] ?? 'active'),
      expiresAt: (x['expiresAt'] as Timestamp?)?.toDate(),
    );
  }
}
