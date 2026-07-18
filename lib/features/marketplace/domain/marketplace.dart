import 'package:cloud_firestore/cloud_firestore.dart';

enum MarketplaceProfileType { buyer, seller, buyerAndSeller }

enum MarketplaceListingType { refurbishedDevice, recoveredMaterial }

enum MarketplaceListingStatus { active, paused, soldOut, closed }

enum QuoteStatus { requested, quoted, accepted, rejected, expired }

enum MarketplaceOrderStatus {
  placed,
  awaitingPayment,
  paid,
  processing,
  dispatched,
  delivered,
  completed,
  cancelled,
  refundPending,
  refunded,
}

enum MarketplacePaymentStatus { pending, submitted, verified, failed, refunded }

class MarketplaceProfile {
  const MarketplaceProfile({
    required this.id,
    required this.type,
    required this.displayName,
    required this.businessName,
    required this.email,
    required this.phone,
    required this.deliveryAddress,
    required this.rating,
    required this.reviewCount,
    required this.verified,
  });
  final String id, displayName, businessName, email, phone, deliveryAddress;
  final MarketplaceProfileType type;
  final double rating;
  final int reviewCount;
  final bool verified;
  factory MarketplaceProfile.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return MarketplaceProfile(
      id: doc.id,
      type: MarketplaceProfileType.values.byName(
        data['type'] ?? MarketplaceProfileType.buyer.name,
      ),
      displayName: data['displayName'] ?? '',
      businessName: data['businessName'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      deliveryAddress: data['deliveryAddress'] ?? '',
      rating: (data['rating'] as num? ?? 0).toDouble(),
      reviewCount: data['reviewCount'] as int? ?? 0,
      verified: data['verified'] as bool? ?? false,
    );
  }
}

class MarketplaceListing {
  const MarketplaceListing({
    required this.id,
    required this.type,
    required this.sellerId,
    required this.sellerName,
    required this.assetId,
    required this.assetCode,
    required this.title,
    required this.description,
    required this.category,
    required this.grade,
    required this.unitPrice,
    required this.currency,
    required this.unit,
    required this.totalQuantity,
    required this.availableQuantity,
    required this.imageUrls,
    required this.status,
    required this.createdAt,
  });
  final String id,
      sellerId,
      sellerName,
      assetId,
      assetCode,
      title,
      description,
      category,
      grade,
      currency,
      unit;
  final MarketplaceListingType type;
  final double unitPrice, totalQuantity, availableQuantity;
  final List<String> imageUrls;
  final MarketplaceListingStatus status;
  final DateTime? createdAt;
  bool get available =>
      status == MarketplaceListingStatus.active && availableQuantity > 0;
  double totalFor(double quantity) => unitPrice * quantity;
  factory MarketplaceListing.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return MarketplaceListing(
      id: doc.id,
      type: MarketplaceListingType.values.byName(
        data['type'] ?? MarketplaceListingType.refurbishedDevice.name,
      ),
      sellerId: data['sellerId'] ?? '',
      sellerName: data['sellerName'] ?? '',
      assetId: data['assetId'] ?? '',
      assetCode: data['assetCode'] ?? '',
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      category: data['category'] ?? '',
      grade: data['grade'] ?? '',
      unitPrice: (data['unitPrice'] as num? ?? 0).toDouble(),
      currency: data['currency'] ?? 'USD',
      unit: data['unit'] ?? 'item',
      totalQuantity: (data['totalQuantity'] as num? ?? 0).toDouble(),
      availableQuantity: (data['availableQuantity'] as num? ?? 0).toDouble(),
      imageUrls: List<String>.from(data['imageUrls'] as List? ?? const []),
      status: MarketplaceListingStatus.values.byName(
        data['status'] ?? MarketplaceListingStatus.active.name,
      ),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class PriceQuotation {
  const PriceQuotation({
    required this.id,
    required this.listingId,
    required this.buyerId,
    required this.sellerId,
    required this.quantity,
    required this.requestedUnitPrice,
    required this.quotedUnitPrice,
    required this.currency,
    required this.message,
    required this.status,
    required this.createdAt,
  });
  final String id, listingId, buyerId, sellerId, currency, message;
  final double quantity, requestedUnitPrice, quotedUnitPrice;
  final QuoteStatus status;
  final DateTime? createdAt;
  factory PriceQuotation.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return PriceQuotation(
      id: doc.id,
      listingId: data['listingId'] ?? '',
      buyerId: data['buyerId'] ?? '',
      sellerId: data['sellerId'] ?? '',
      quantity: (data['quantity'] as num? ?? 0).toDouble(),
      requestedUnitPrice: (data['requestedUnitPrice'] as num? ?? 0).toDouble(),
      quotedUnitPrice: (data['quotedUnitPrice'] as num? ?? 0).toDouble(),
      currency: data['currency'] ?? 'USD',
      message: data['message'] ?? '',
      status: QuoteStatus.values.byName(
        data['status'] ?? QuoteStatus.requested.name,
      ),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class MarketplaceOrder {
  const MarketplaceOrder({
    required this.id,
    required this.orderNumber,
    required this.listingId,
    required this.listingTitle,
    required this.buyerId,
    required this.buyerName,
    required this.sellerId,
    required this.sellerName,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.totalAmount,
    required this.currency,
    required this.status,
    required this.paymentStatus,
    required this.paymentMethod,
    required this.paymentReference,
    required this.deliveryAddress,
    required this.carrier,
    required this.trackingNumber,
    required this.createdAt,
    required this.deliveredAt,
  });
  final String id,
      orderNumber,
      listingId,
      listingTitle,
      buyerId,
      buyerName,
      sellerId,
      sellerName,
      unit,
      currency,
      paymentMethod,
      paymentReference,
      deliveryAddress,
      carrier,
      trackingNumber;
  final double quantity, unitPrice, totalAmount;
  final MarketplaceOrderStatus status;
  final MarketplacePaymentStatus paymentStatus;
  final DateTime? createdAt, deliveredAt;
  bool get cancellable => [
    MarketplaceOrderStatus.placed,
    MarketplaceOrderStatus.awaitingPayment,
    MarketplaceOrderStatus.paid,
    MarketplaceOrderStatus.processing,
  ].contains(status);
  factory MarketplaceOrder.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return MarketplaceOrder(
      id: doc.id,
      orderNumber: data['orderNumber'] ?? doc.id,
      listingId: data['listingId'] ?? '',
      listingTitle: data['listingTitle'] ?? '',
      buyerId: data['buyerId'] ?? '',
      buyerName: data['buyerName'] ?? '',
      sellerId: data['sellerId'] ?? '',
      sellerName: data['sellerName'] ?? '',
      quantity: (data['quantity'] as num? ?? 0).toDouble(),
      unit: data['unit'] ?? 'item',
      unitPrice: (data['unitPrice'] as num? ?? 0).toDouble(),
      totalAmount: (data['totalAmount'] as num? ?? 0).toDouble(),
      currency: data['currency'] ?? 'USD',
      status: MarketplaceOrderStatus.values.byName(
        data['status'] ?? MarketplaceOrderStatus.placed.name,
      ),
      paymentStatus: MarketplacePaymentStatus.values.byName(
        data['paymentStatus'] ?? MarketplacePaymentStatus.pending.name,
      ),
      paymentMethod: data['paymentMethod'] ?? '',
      paymentReference: data['paymentReference'] ?? '',
      deliveryAddress: data['deliveryAddress'] ?? '',
      carrier: data['carrier'] ?? '',
      trackingNumber: data['trackingNumber'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      deliveredAt: (data['deliveredAt'] as Timestamp?)?.toDate(),
    );
  }
}

class DeliveryEvent {
  const DeliveryEvent({
    required this.status,
    required this.location,
    required this.notes,
    required this.createdAt,
  });
  final String status, location, notes;
  final DateTime? createdAt;
  factory DeliveryEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return DeliveryEvent(
      status: data['status'] ?? '',
      location: data['location'] ?? '',
      notes: data['notes'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class MarketplaceReview {
  const MarketplaceReview({
    required this.rating,
    required this.comment,
    required this.buyerName,
    required this.createdAt,
  });
  final int rating;
  final String comment, buyerName;
  final DateTime? createdAt;
  factory MarketplaceReview.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return MarketplaceReview(
      rating: data['rating'] as int? ?? 0,
      comment: data['comment'] ?? '',
      buyerName: data['buyerName'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class MarketplaceAnalytics {
  const MarketplaceAnalytics({
    required this.activeListings,
    required this.orders,
    required this.completedOrders,
    required this.grossSales,
    required this.averageOrderValue,
    required this.unitsSold,
  });
  final int activeListings, orders, completedOrders;
  final double grossSales, averageOrderValue, unitsSold;
  factory MarketplaceAnalytics.calculate(
    List<MarketplaceListing> listings,
    List<MarketplaceOrder> orders, {
    String? sellerId,
  }) {
    final filteredOrders = sellerId == null
        ? orders
        : orders.where((order) => order.sellerId == sellerId).toList();
    final completed = filteredOrders
        .where(
          (order) => [
            MarketplaceOrderStatus.completed,
            MarketplaceOrderStatus.delivered,
          ].contains(order.status),
        )
        .toList();
    final sales = completed.fold<double>(
      0,
      (total, order) => total + order.totalAmount,
    );
    return MarketplaceAnalytics(
      activeListings: listings
          .where(
            (listing) =>
                listing.status == MarketplaceListingStatus.active &&
                (sellerId == null || listing.sellerId == sellerId),
          )
          .length,
      orders: filteredOrders.length,
      completedOrders: completed.length,
      grossSales: sales,
      averageOrderValue: completed.isEmpty ? 0 : sales / completed.length,
      unitsSold: completed.fold(0, (total, order) => total + order.quantity),
    );
  }
}
