import 'package:flutter_test/flutter_test.dart';
import 'package:wastemanagementsystem/features/donations/domain/donation.dart';
import 'package:wastemanagementsystem/features/rewards/domain/rewards.dart';

void main() {
  test('donation impact calculates completion', () {
    const x = DonationImpact(10, 8, 20, 100);
    expect(x.completionRate, 80);
    expect(x.devices, 20);
  });
  test('reward levels follow lifetime thresholds', () {
    expect(RewardWallet.levelFor(0), RewardLevel.seedling);
    expect(RewardWallet.levelFor(500), RewardLevel.greenAdvocate);
    expect(RewardWallet.levelFor(2000), RewardLevel.ecoChampion);
    expect(RewardWallet.levelFor(5000), RewardLevel.circularLeader);
  });
  test('donation lifecycle includes approval delivery and follow-up', () {
    expect(DonationStatus.values, contains(DonationStatus.approved));
    expect(DonationStatus.values, contains(DonationStatus.delivered));
    expect(DonationStatus.values, contains(DonationStatus.followUp));
    expect(DonationStatus.values, contains(DonationStatus.completed));
  });
  test('reward ledger covers earning redemption and expiry', () {
    expect(
      RewardTransactionType.values,
      contains(RewardTransactionType.pickup),
    );
    expect(
      RewardTransactionType.values,
      contains(RewardTransactionType.referral),
    );
    expect(
      RewardTransactionType.values,
      contains(RewardTransactionType.challenge),
    );
    expect(
      RewardTransactionType.values,
      contains(RewardTransactionType.redemption),
    );
    expect(
      RewardTransactionType.values,
      contains(RewardTransactionType.expiry),
    );
  });
}
