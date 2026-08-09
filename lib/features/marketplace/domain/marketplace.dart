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
    return MarketplaceProfile.fromJson({...doc.data()!, 'id': doc.id});
  }
  factory MarketplaceProfile.fromJson(Map<String, dynamic> data) {
    return MarketplaceProfile(
      id: '${data['id'] ?? data['userId'] ?? ''}',
      type:
          MarketplaceProfileType.values
              .where((value) => value.name == data['type'])
              .firstOrNull ??
          MarketplaceProfileType.buyer,
      displayName: data['displayName'] ?? '',
      businessName: data['businessName'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      deliveryAddress: data['deliveryAddress'] ?? '',
      rating: (data['rating'] as num? ?? 0).toDouble(),
      reviewCount:
          (data['reviewCount'] as num? ?? data['ratingCount'] as num? ?? 0)
              .toInt(),
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
    return MarketplaceListing.fromJson({...doc.data()!, 'id': doc.id});
  }
  factory MarketplaceListing.fromJson(Map<String, dynamic> data) {
    final total =
        (data['totalQuantity'] as num? ??
                data['quantityAvailable'] as num? ??
                0)
            .toDouble();
    final reserved = (data['reservedQuantity'] as num? ?? 0).toDouble();
    final sold = (data['soldQuantity'] as num? ?? 0).toDouble();
    return MarketplaceListing(
      id: '${data['id'] ?? ''}',
      type: MarketplaceListingType.values.byName(
        data['type'] ?? MarketplaceListingType.refurbishedDevice.name,
      ),
      sellerId: data['sellerId'] ?? '',
      sellerName: data['sellerName'] ?? '',
      assetId: data['assetId'] ?? data['sourceId'] ?? '',
      assetCode: data['assetCode'] ?? data['listingCode'] ?? '',
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      category: data['category'] ?? '',
      grade: data['grade'] ?? data['conditionOrGrade'] ?? '',
      unitPrice: (data['unitPrice'] as num? ?? 0).toDouble(),
      currency: data['currency'] ?? 'SLE',
      unit: data['unit'] ?? 'item',
      totalQuantity: total,
      availableQuantity:
          (data['availableQuantity'] as num?)?.toDouble() ??
          total - reserved - sold,
      imageUrls: List<String>.from(data['imageUrls'] as List? ?? const []),
      status: MarketplaceListingStatus.values.byName(
        data['status'] ?? MarketplaceListingStatus.active.name,
      ),
      createdAt: _date(data['createdAt']),
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
    return PriceQuotation.fromJson({...doc.data()!, 'id': doc.id});
  }
  factory PriceQuotation.fromJson(Map<String, dynamic> data) {
    final apiStatus = '${data['status'] ?? ''}';
    final status = switch (apiStatus) {
      'pending' => QuoteStatus.requested,
      'countered' => QuoteStatus.quoted,
      _ =>
        QuoteStatus.values
                .where((value) => value.name == apiStatus)
                .firstOrNull ??
            QuoteStatus.requested,
    };
    return PriceQuotation(
      id: '${data['id'] ?? ''}',
      listingId: data['listingId'] ?? '',
      buyerId: data['buyerId'] ?? '',
      sellerId: data['sellerId'] ?? '',
      quantity: (data['quantity'] as num? ?? 0).toDouble(),
      requestedUnitPrice:
          (data['requestedUnitPrice'] as num? ??
                  data['offeredUnitPrice'] as num? ??
                  0)
              .toDouble(),
      quotedUnitPrice:
          (data['quotedUnitPrice'] as num? ??
                  data['finalUnitPrice'] as num? ??
                  0)
              .toDouble(),
      currency: data['currency'] ?? 'SLE',
      message: data['message'] ?? '',
      status: status,
      createdAt: _date(data['createdAt']),
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
    return MarketplaceOrder.fromJson({...doc.data()!, 'id': doc.id});
  }
  factory MarketplaceOrder.fromJson(Map<String, dynamic> data) {
    final rawStatus = '${data['status'] ?? ''}';
    final status = switch (rawStatus) {
      'pendingPayment' => MarketplaceOrderStatus.awaitingPayment,
      'confirmed' => MarketplaceOrderStatus.paid,
      'fulfilling' => MarketplaceOrderStatus.processing,
      _ =>
        MarketplaceOrderStatus.values
                .where((value) => value.name == rawStatus)
                .firstOrNull ??
            MarketplaceOrderStatus.placed,
    };
    final rawPayment = '${data['paymentStatus'] ?? ''}';
    final payment = switch (rawPayment) {
      'confirmed' => MarketplacePaymentStatus.verified,
      _ =>
        MarketplacePaymentStatus.values
                .where((value) => value.name == rawPayment)
                .firstOrNull ??
            MarketplacePaymentStatus.pending,
    };
    return MarketplaceOrder(
      id: '${data['id'] ?? ''}',
      orderNumber: data['orderNumber'] ?? '${data['id'] ?? ''}',
      listingId: data['listingId'] ?? '',
      listingTitle: data['listingTitle'] ?? '',
      buyerId: data['buyerId'] ?? '',
      buyerName: data['buyerName'] ?? '',
      sellerId: data['sellerId'] ?? '',
      sellerName: data['sellerName'] ?? '',
      quantity: (data['quantity'] as num? ?? 0).toDouble(),
      unit: data['unit'] ?? 'item',
      unitPrice: (data['unitPrice'] as num? ?? 0).toDouble(),
      totalAmount: (data['totalAmount'] as num? ?? data['total'] as num? ?? 0)
          .toDouble(),
      currency: data['currency'] ?? 'SLE',
      status: status,
      paymentStatus: payment,
      paymentMethod: data['paymentMethod'] ?? '',
      paymentReference:
          data['paymentReference'] ?? data['transactionReference'] ?? '',
      deliveryAddress: data['deliveryAddress'] ?? '',
      carrier: data['carrier'] ?? '',
      trackingNumber: data['trackingNumber'] ?? '',
      createdAt: _date(data['createdAt']),
      deliveredAt: _date(data['deliveredAt']),
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
    return DeliveryEvent.fromJson(doc.data()!);
  }
  factory DeliveryEvent.fromJson(Map<String, dynamic> data) {
    return DeliveryEvent(
      status: data['status'] ?? '',
      location: data['location'] ?? '',
      notes:
          data['notes'] ??
          '${data['carrier'] ?? ''} ${data['trackingNumber'] ?? ''}'.trim(),
      createdAt: _date(data['createdAt']),
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
    return MarketplaceReview.fromJson(doc.data()!);
  }
  factory MarketplaceReview.fromJson(Map<String, dynamic> data) {
    return MarketplaceReview(
      rating: data['rating'] as int? ?? 0,
      comment: data['comment'] ?? data['comments'] ?? '',
      buyerName: data['buyerName'] ?? '',
      createdAt: _date(data['createdAt']),
    );
  }
}

DateTime? _date(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value);
  if (value is Map) {
    final seconds = value['_seconds'] ?? value['seconds'];
    if (seconds is num) {
      return DateTime.fromMillisecondsSinceEpoch(
        seconds.toInt() * 1000,
        isUtc: true,
      );
    }
  }
  return null;
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
