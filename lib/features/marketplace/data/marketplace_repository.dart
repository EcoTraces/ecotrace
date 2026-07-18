import 'package:cloud_firestore/cloud_firestore.dart';

import '../../inventory/domain/inventory_item.dart';
import '../../recovery/domain/recovered_material.dart';
import '../../repairs/domain/repair_job.dart';
import '../domain/marketplace.dart';

class MarketplaceRepository {
  MarketplaceRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  Stream<MarketplaceProfile?> watchProfile(String userId) => _db
      .collection('marketplaceProfiles')
      .doc(userId)
      .snapshots()
      .map((doc) => doc.exists ? MarketplaceProfile.fromDoc(doc) : null);
  Stream<List<MarketplaceListing>> watchListings() => _db
      .collection('marketplaceListings')
      .snapshots()
      .map(
        (s) => s.docs.map(MarketplaceListing.fromDoc).toList()
          ..sort(
            (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
              a.createdAt ?? DateTime(0),
            ),
          ),
      );
  Stream<List<MarketplaceOrder>> watchOrders(String userId) => _db
      .collection('marketplaceOrders')
      .where('participantIds', arrayContains: userId)
      .snapshots()
      .map(
        (s) => s.docs.map(MarketplaceOrder.fromDoc).toList()
          ..sort(
            (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
              a.createdAt ?? DateTime(0),
            ),
          ),
      );
  Stream<List<PriceQuotation>> watchQuotes(String userId) => _db
      .collection('marketplaceQuotes')
      .where('participantIds', arrayContains: userId)
      .snapshots()
      .map((s) => s.docs.map(PriceQuotation.fromDoc).toList());
  Stream<List<DeliveryEvent>> watchDelivery(String orderId) => _db
      .collection('marketplaceOrders')
      .doc(orderId)
      .collection('deliveryEvents')
      .snapshots()
      .map(
        (s) => s.docs.map(DeliveryEvent.fromDoc).toList()
          ..sort(
            (a, b) => (a.createdAt ?? DateTime(0)).compareTo(
              b.createdAt ?? DateTime(0),
            ),
          ),
      );
  Stream<List<MarketplaceReview>> watchReviews(String sellerId) => _db
      .collection('marketplaceReviews')
      .where('sellerId', isEqualTo: sellerId)
      .snapshots()
      .map((s) => s.docs.map(MarketplaceReview.fromDoc).toList());
  Stream<List<RepairJob>> watchEligibleDevices() => _db
      .collection('repairJobs')
      .where('status', isEqualTo: RepairStatus.completed.name)
      .snapshots()
      .map(
        (s) => s.docs
            .map(RepairJob.fromDoc)
            .where(
              (job) =>
                  job.dispositionApproved &&
                  job.disposition == RefurbishedDisposition.resale,
            )
            .toList(),
      );
  Stream<List<RecoveredMaterialLot>> watchEligibleMaterials() => _db
      .collection('recoveredMaterialLots')
      .where('status', isEqualTo: MaterialLotStatus.salesReady.name)
      .snapshots()
      .map((s) => s.docs.map(RecoveredMaterialLot.fromDoc).toList());

  Future<void> saveProfile({
    required String userId,
    required MarketplaceProfileType type,
    required String displayName,
    required String businessName,
    required String email,
    required String phone,
    required String deliveryAddress,
  }) => _db.collection('marketplaceProfiles').doc(userId).set({
    'type': type.name,
    'displayName': displayName.trim(),
    'businessName': businessName.trim(),
    'email': email.trim(),
    'phone': phone.trim(),
    'deliveryAddress': deliveryAddress.trim(),
    'rating': 0,
    'reviewCount': 0,
    'verified': false,
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  Future<void> listDevice({
    required RepairJob job,
    required MarketplaceProfile seller,
    required String description,
    required double price,
    required String currency,
  }) async {
    if (!job.dispositionApproved ||
        job.disposition != RefurbishedDisposition.resale) {
      throw StateError('Device is not approved for resale.');
    }
    await _ensureNotListed(job.itemId);
    final itemDoc = await _db
        .collection('inventoryItems')
        .doc(job.itemId)
        .get();
    final item = InventoryItem.fromDoc(itemDoc);
    await _db.collection('marketplaceListings').add({
      'type': MarketplaceListingType.refurbishedDevice.name,
      'sellerId': seller.id,
      'sellerName': seller.businessName.isEmpty
          ? seller.displayName
          : seller.businessName,
      'assetId': job.itemId,
      'assetCode': job.itemCode,
      'title': job.deviceName,
      'description': description.trim(),
      'category': item.deviceType,
      'grade': job.grade?.name ?? '',
      'unitPrice': price,
      'currency': currency.trim(),
      'unit': 'device',
      'totalQuantity': 1,
      'availableQuantity': 1,
      'imageUrls': item.imageUrls,
      'status': MarketplaceListingStatus.active.name,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> listMaterial({
    required RecoveredMaterialLot lot,
    required MarketplaceProfile seller,
    required String description,
    required double pricePerKg,
    required String currency,
  }) async {
    if (lot.status != MaterialLotStatus.salesReady) {
      throw StateError('Material lot is not sales-ready.');
    }
    await _ensureNotListed(lot.id);
    await _db.collection('marketplaceListings').add({
      'type': MarketplaceListingType.recoveredMaterial.name,
      'sellerId': seller.id,
      'sellerName': seller.businessName.isEmpty
          ? seller.displayName
          : seller.businessName,
      'assetId': lot.id,
      'assetCode': lot.lotCode,
      'title': '${lot.material.label} recovered material',
      'description': description.trim(),
      'category': lot.material.name,
      'grade': lot.qualityGrade.name,
      'unitPrice': pricePerKg,
      'currency': currency.trim(),
      'unit': 'kg',
      'totalQuantity': lot.weightKg,
      'availableQuantity': lot.weightKg,
      'imageUrls': [],
      'status': MarketplaceListingStatus.active.name,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> placeOrder({
    required MarketplaceListing listing,
    required MarketplaceProfile buyer,
    required double quantity,
  }) async {
    if (quantity <= 0) throw StateError('Quantity must be positive.');
    final listingRef = _db.collection('marketplaceListings').doc(listing.id),
        orderRef = _db.collection('marketplaceOrders').doc();
    await _db.runTransaction((tx) async {
      final current = MarketplaceListing.fromDoc(await tx.get(listingRef));
      if (!current.available || quantity > current.availableQuantity) {
        throw StateError('Requested quantity is unavailable.');
      }
      final remaining = current.availableQuantity - quantity;
      tx.update(listingRef, {
        'availableQuantity': remaining,
        if (remaining <= 0) 'status': MarketplaceListingStatus.soldOut.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(orderRef, {
        'orderNumber': 'MKT-${DateTime.now().millisecondsSinceEpoch}',
        'listingId': current.id,
        'listingTitle': current.title,
        'buyerId': buyer.id,
        'buyerName': buyer.displayName,
        'sellerId': current.sellerId,
        'sellerName': current.sellerName,
        'participantIds': [buyer.id, current.sellerId],
        'quantity': quantity,
        'unit': current.unit,
        'unitPrice': current.unitPrice,
        'totalAmount': current.totalFor(quantity),
        'currency': current.currency,
        'status': MarketplaceOrderStatus.awaitingPayment.name,
        'paymentStatus': MarketplacePaymentStatus.pending.name,
        'paymentMethod': '',
        'paymentReference': '',
        'deliveryAddress': buyer.deliveryAddress,
        'carrier': '',
        'trackingNumber': '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> requestQuote({
    required MarketplaceListing listing,
    required MarketplaceProfile buyer,
    required double quantity,
    required double requestedUnitPrice,
    required String message,
  }) => _db.collection('marketplaceQuotes').add({
    'listingId': listing.id,
    'listingTitle': listing.title,
    'buyerId': buyer.id,
    'buyerName': buyer.displayName,
    'sellerId': listing.sellerId,
    'participantIds': [buyer.id, listing.sellerId],
    'quantity': quantity,
    'requestedUnitPrice': requestedUnitPrice,
    'quotedUnitPrice': 0,
    'currency': listing.currency,
    'message': message.trim(),
    'status': QuoteStatus.requested.name,
    'createdAt': FieldValue.serverTimestamp(),
  });
  Future<void> respondQuote(
    PriceQuotation quote, {
    required bool accepted,
    required double quotedPrice,
  }) => _db.collection('marketplaceQuotes').doc(quote.id).update({
    'status': accepted ? QuoteStatus.quoted.name : QuoteStatus.rejected.name,
    'quotedUnitPrice': quotedPrice,
    'respondedAt': FieldValue.serverTimestamp(),
  });

  Future<void> submitPayment(
    MarketplaceOrder order, {
    required String method,
    required String reference,
  }) {
    if (method.trim().isEmpty || reference.trim().isEmpty) {
      throw StateError(
        'Payment method and transaction reference are required.',
      );
    }
    return _db.collection('marketplaceOrders').doc(order.id).update({
      'paymentMethod': method.trim(),
      'paymentReference': reference.trim(),
      'paymentStatus': MarketplacePaymentStatus.submitted.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> confirmPayment(MarketplaceOrder order) =>
      _db.collection('marketplaceOrders').doc(order.id).update({
        'paymentStatus': MarketplacePaymentStatus.verified.name,
        'status': MarketplaceOrderStatus.paid.name,
        'paidAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
  Future<void> confirmRefund(MarketplaceOrder order) =>
      _db.collection('marketplaceOrders').doc(order.id).update({
        'paymentStatus': MarketplacePaymentStatus.refunded.name,
        'status': MarketplaceOrderStatus.refunded.name,
        'refundedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
  Future<void> dispatch(
    MarketplaceOrder order, {
    required String carrier,
    required String trackingNumber,
    required String location,
  }) async {
    final ref = _db.collection('marketplaceOrders').doc(order.id),
        batch = _db.batch();
    batch.update(ref, {
      'status': MarketplaceOrderStatus.dispatched.name,
      'carrier': carrier.trim(),
      'trackingNumber': trackingNumber.trim(),
      'dispatchedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(ref.collection('deliveryEvents').doc(), {
      'status': 'Dispatched',
      'location': location.trim(),
      'notes': '$carrier • $trackingNumber',
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> updateDelivery(
    MarketplaceOrder order, {
    required String status,
    required String location,
    required String notes,
    required bool delivered,
  }) async {
    final ref = _db.collection('marketplaceOrders').doc(order.id),
        batch = _db.batch();
    batch.update(ref, {
      'status': delivered
          ? MarketplaceOrderStatus.delivered.name
          : order.status.name,
      if (delivered) 'deliveredAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(ref.collection('deliveryEvents').doc(), {
      'status': status.trim(),
      'location': location.trim(),
      'notes': notes.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> confirmReceipt(MarketplaceOrder order) =>
      _db.collection('marketplaceOrders').doc(order.id).update({
        'status': MarketplaceOrderStatus.completed.name,
        'completedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> cancelOrder(MarketplaceOrder order) async {
    if (!order.cancellable) {
      throw StateError('This order can no longer be cancelled.');
    }
    final orderRef = _db.collection('marketplaceOrders').doc(order.id),
        listingRef = _db.collection('marketplaceListings').doc(order.listingId);
    await _db.runTransaction((tx) async {
      final current = MarketplaceOrder.fromDoc(await tx.get(orderRef));
      if (!current.cancellable) {
        throw StateError('This order can no longer be cancelled.');
      }
      final listing = MarketplaceListing.fromDoc(await tx.get(listingRef));
      tx.update(orderRef, {
        'status': current.paymentStatus == MarketplacePaymentStatus.verified
            ? MarketplaceOrderStatus.refundPending.name
            : MarketplaceOrderStatus.cancelled.name,
        'cancelledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.update(listingRef, {
        'availableQuantity': listing.availableQuantity + current.quantity,
        'status': MarketplaceListingStatus.active.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> reviewOrder(
    MarketplaceOrder order, {
    required MarketplaceProfile buyer,
    required int rating,
    required String comment,
  }) async {
    if (order.status != MarketplaceOrderStatus.completed ||
        rating < 1 ||
        rating > 5) {
      throw StateError('Complete the order before rating it.');
    }
    final reviewRef = _db.collection('marketplaceReviews').doc(order.id),
        profileRef = _db.collection('marketplaceProfiles').doc(order.sellerId);
    await _db.runTransaction((tx) async {
      final existing = await tx.get(reviewRef);
      if (existing.exists) {
        throw StateError('This order has already been reviewed.');
      }
      final profile = MarketplaceProfile.fromDoc(await tx.get(profileRef));
      final count = profile.reviewCount + 1,
          average = (profile.rating * profile.reviewCount + rating) / count;
      tx.set(reviewRef, {
        'orderId': order.id,
        'listingId': order.listingId,
        'buyerId': buyer.id,
        'buyerName': buyer.displayName,
        'sellerId': order.sellerId,
        'rating': rating,
        'comment': comment.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.update(profileRef, {
        'rating': average,
        'reviewCount': count,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> _ensureNotListed(String assetId) async {
    final existing = await _db
        .collection('marketplaceListings')
        .where('assetId', isEqualTo: assetId)
        .where(
          'status',
          whereIn: [
            MarketplaceListingStatus.active.name,
            MarketplaceListingStatus.paused.name,
            MarketplaceListingStatus.soldOut.name,
          ],
        )
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      throw StateError('This asset already has a marketplace listing.');
    }
  }
}
