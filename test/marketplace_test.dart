import 'package:flutter_test/flutter_test.dart';
import 'package:wastemanagementsystem/features/marketplace/domain/marketplace.dart';

void main() {
  MarketplaceListing listing({
    String id = 'listing-1',
    String sellerId = 'seller-1',
    double available = 10,
    MarketplaceListingStatus status = MarketplaceListingStatus.active,
  }) => MarketplaceListing(
    id: id,
    type: MarketplaceListingType.recoveredMaterial,
    sellerId: sellerId,
    sellerName: 'Circular Seller',
    assetId: 'lot-1',
    assetCode: 'MAT-001',
    title: 'Recovered copper',
    description: 'Grade A copper',
    category: 'copper',
    grade: 'gradeA',
    unitPrice: 8,
    currency: 'USD',
    unit: 'kg',
    totalQuantity: 10,
    availableQuantity: available,
    imageUrls: const [],
    status: status,
    createdAt: null,
  );

  MarketplaceOrder order({
    required String id,
    MarketplaceOrderStatus status = MarketplaceOrderStatus.completed,
    double quantity = 2,
    double total = 16,
  }) => MarketplaceOrder(
    id: id,
    orderNumber: 'MKT-$id',
    listingId: 'listing-1',
    listingTitle: 'Recovered copper',
    buyerId: 'buyer-1',
    buyerName: 'Buyer',
    sellerId: 'seller-1',
    sellerName: 'Seller',
    quantity: quantity,
    unit: 'kg',
    unitPrice: 8,
    totalAmount: total,
    currency: 'USD',
    status: status,
    paymentStatus: MarketplacePaymentStatus.verified,
    paymentMethod: 'Mobile money',
    paymentReference: 'PAY-1',
    deliveryAddress: 'Address',
    carrier: 'Carrier',
    trackingNumber: 'TRACK-1',
    createdAt: null,
    deliveredAt: null,
  );

  test(
    'listing availability and price calculations support material units',
    () {
      final item = listing();
      expect(item.available, isTrue);
      expect(item.totalFor(2.5), 20);
      expect(listing(available: 0).available, isFalse);
      expect(
        listing(status: MarketplaceListingStatus.paused).available,
        isFalse,
      );
    },
  );

  test('orders can only be cancelled before dispatch', () {
    expect(
      order(
        id: 'placed',
        status: MarketplaceOrderStatus.awaitingPayment,
      ).cancellable,
      isTrue,
    );
    expect(
      order(
        id: 'dispatched',
        status: MarketplaceOrderStatus.dispatched,
      ).cancellable,
      isFalse,
    );
  });

  test('marketplace analytics calculate sales and order values', () {
    final analytics = MarketplaceAnalytics.calculate(
      [listing()],
      [
        order(id: 'one'),
        order(id: 'two', quantity: 3, total: 24),
        order(id: 'cancelled', status: MarketplaceOrderStatus.cancelled),
      ],
      sellerId: 'seller-1',
    );
    expect(analytics.activeListings, 1);
    expect(analytics.orders, 3);
    expect(analytics.completedOrders, 2);
    expect(analytics.grossSales, 40);
    expect(analytics.averageOrderValue, 20);
    expect(analytics.unitsSold, 5);
  });

  test('marketplace supports both circular listing categories', () {
    expect(
      MarketplaceListingType.values,
      contains(MarketplaceListingType.refurbishedDevice),
    );
    expect(
      MarketplaceListingType.values,
      contains(MarketplaceListingType.recoveredMaterial),
    );
  });
}
