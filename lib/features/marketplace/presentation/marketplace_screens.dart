import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/app_currency.dart';
import '../../../core/media/cloudinary_upload_service.dart';
import '../../recovery/domain/recovered_material.dart';
import '../../repairs/domain/repair_job.dart';
import '../data/marketplace_repository.dart';
import '../domain/marketplace.dart';

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({
    super.key,
    required this.repository,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserEmail,
    required this.canListDevices,
    required this.canListMaterials,
  });
  final MarketplaceRepository repository;
  final String currentUserId, currentUserName, currentUserEmail;
  final bool canListDevices, canListMaterials;
  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  String search = '';
  bool get canSell => widget.canListDevices || widget.canListMaterials;

  @override
  Widget build(BuildContext context) => StreamBuilder<MarketplaceProfile?>(
    stream: widget.repository.watchProfile(widget.currentUserId),
    builder: (context, profileSnapshot) =>
        StreamBuilder<List<MarketplaceListing>>(
          stream: widget.repository.watchListings(),
          builder: (context, listingSnapshot) =>
              StreamBuilder<List<MarketplaceOrder>>(
                stream: widget.repository.watchOrders(widget.currentUserId),
                builder: (context, orderSnapshot) =>
                    StreamBuilder<List<PriceQuotation>>(
                      stream: widget.repository.watchQuotes(
                        widget.currentUserId,
                      ),
                      builder: (context, quoteSnapshot) {
                        if (!listingSnapshot.hasData ||
                            !orderSnapshot.hasData ||
                            !quoteSnapshot.hasData) {
                          return const Scaffold(
                            body: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final profile = profileSnapshot.data;
                        final listings = listingSnapshot.data!;
                        final orders = orderSnapshot.data!
                            .where(
                              (order) =>
                                  order.buyerId == widget.currentUserId ||
                                  order.sellerId == widget.currentUserId,
                            )
                            .toList();
                        final quotes = quoteSnapshot.data!
                            .where(
                              (quote) =>
                                  quote.buyerId == widget.currentUserId ||
                                  quote.sellerId == widget.currentUserId,
                            )
                            .toList();
                        return DefaultTabController(
                          length: canSell ? 4 : 3,
                          child: Scaffold(
                            appBar: AppBar(
                              title: const Text('Circular marketplace'),
                              actions: [
                                IconButton(
                                  onPressed: () => _profile(context, profile),
                                  icon: Icon(
                                    profile == null
                                        ? Icons.person_add_alt
                                        : Icons.account_circle_outlined,
                                  ),
                                  tooltip: 'Buyer and seller profile',
                                ),
                              ],
                              bottom: TabBar(
                                isScrollable: true,
                                tabs: [
                                  const Tab(text: 'Marketplace'),
                                  const Tab(text: 'Orders'),
                                  const Tab(text: 'Quotes'),
                                  if (canSell)
                                    const Tab(text: 'Sell & analytics'),
                                ],
                              ),
                            ),
                            body: TabBarView(
                              children: [
                                _browse(profile, listings),
                                _orders(profile, orders),
                                _quotes(profile, quotes),
                                if (canSell) _seller(profile, listings, orders),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
              ),
        ),
  );

  Widget _browse(
    MarketplaceProfile? profile,
    List<MarketplaceListing> listings,
  ) {
    final filtered = listings
        .where(
          (listing) =>
              listing.available &&
              '${listing.title} ${listing.category} ${listing.description} ${listing.sellerName}'
                  .toLowerCase()
                  .contains(search.toLowerCase()),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        TextField(
          onChanged: (value) => setState(() => search = value),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Search devices, materials, sellers, or categories',
          ),
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          const ListTile(title: Text('No matching marketplace listings.')),
        for (final listing in filtered)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (listing.imageUrls.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        listing.imageUrls.first,
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      listing.type == MarketplaceListingType.refurbishedDevice
                          ? Icons.devices_other
                          : Icons.category_outlined,
                    ),
                    title: Text(listing.title),
                    subtitle: Text(
                      '${listing.category} • ${listing.grade}\nSeller: ${listing.sellerName}',
                    ),
                    isThreeLine: true,
                    trailing: Text(
                      '${AppCurrency.format(listing.unitPrice, currencyCode: listing.currency)}\nper ${listing.unit}',
                      textAlign: TextAlign.end,
                    ),
                  ),
                  Text(listing.description),
                  Text(
                    'Available: ${listing.availableQuantity.toStringAsFixed(listing.unit == 'device' ? 0 : 2)} ${listing.unit}',
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton(
                        onPressed: profile == null
                            ? () => _profile(context, null)
                            : () => _order(context, listing, profile),
                        child: const Text('Place order'),
                      ),
                      OutlinedButton(
                        onPressed: profile == null
                            ? () => _profile(context, null)
                            : () => _quote(context, listing, profile),
                        child: const Text('Request quote'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _orders(
    MarketplaceProfile? profile,
    List<MarketplaceOrder> orders,
  ) => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      if (orders.isEmpty) const ListTile(title: Text('No marketplace orders.')),
      for (final order in orders)
        Card(
          child: ExpansionTile(
            leading: const Icon(Icons.shopping_bag_outlined),
            title: Text('${order.orderNumber} • ${order.listingTitle}'),
            subtitle: Text(
              '${order.quantity} ${order.unit} • ${AppCurrency.format(order.totalAmount, currencyCode: order.currency)}\n${order.status.name} • Payment ${order.paymentStatus.name}',
            ),
            children: [
              ListTile(
                title: Text('Buyer: ${order.buyerName}'),
                subtitle: Text(
                  'Seller: ${order.sellerName}\nDeliver to: ${order.deliveryAddress}\n${order.carrier} ${order.trackingNumber}',
                ),
              ),
              StreamBuilder<List<DeliveryEvent>>(
                stream: widget.repository.watchDelivery(order.id),
                builder: (context, snapshot) => Column(
                  children: [
                    for (final event
                        in snapshot.data ?? const <DeliveryEvent>[])
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.local_shipping_outlined),
                        title: Text(event.status),
                        subtitle: Text('${event.location} • ${event.notes}'),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _orderActions(context, profile, order),
                ),
              ),
            ],
          ),
        ),
    ],
  );

  List<Widget> _orderActions(
    BuildContext context,
    MarketplaceProfile? profile,
    MarketplaceOrder order,
  ) {
    final buyer = order.buyerId == widget.currentUserId,
        seller = order.sellerId == widget.currentUserId;
    return [
      if (buyer && order.paymentStatus == MarketplacePaymentStatus.pending)
        FilledButton(
          onPressed: () => _payment(context, order),
          child: const Text('Submit payment'),
        ),
      if (seller && order.paymentStatus == MarketplacePaymentStatus.submitted)
        FilledButton(
          onPressed: () => _runMarket(
            context,
            () => widget.repository.confirmPayment(order),
            'Payment verified.',
          ),
          child: const Text('Verify payment'),
        ),
      if (seller && order.status == MarketplaceOrderStatus.refundPending)
        FilledButton(
          onPressed: () => _runMarket(
            context,
            () => widget.repository.confirmRefund(order),
            'Refund confirmed.',
          ),
          child: const Text('Confirm refund'),
        ),
      if (seller &&
          [
            MarketplaceOrderStatus.paid,
            MarketplaceOrderStatus.processing,
          ].contains(order.status))
        FilledButton(
          onPressed: () => _dispatch(context, order),
          child: const Text('Dispatch'),
        ),
      if (seller && order.status == MarketplaceOrderStatus.dispatched)
        FilledButton(
          onPressed: () => _delivery(context, order),
          child: const Text('Delivery update'),
        ),
      if (buyer && order.status == MarketplaceOrderStatus.delivered)
        FilledButton(
          onPressed: () => _runMarket(
            context,
            () => widget.repository.confirmReceipt(order),
            'Receipt confirmed.',
          ),
          child: const Text('Confirm receipt'),
        ),
      if (buyer &&
          order.status == MarketplaceOrderStatus.completed &&
          profile != null)
        OutlinedButton(
          onPressed: () => _review(context, order, profile),
          child: const Text('Review seller'),
        ),
      if (buyer && order.cancellable)
        OutlinedButton(
          onPressed: () => _runMarket(
            context,
            () => widget.repository.cancelOrder(order),
            'Order cancelled.',
          ),
          child: const Text('Cancel order'),
        ),
      OutlinedButton.icon(
        onPressed: () => _receipt(order),
        icon: const Icon(Icons.receipt_long_outlined),
        label: const Text('Digital receipt'),
      ),
    ];
  }

  Widget _quotes(
    MarketplaceProfile? profile,
    List<PriceQuotation> quotes,
  ) => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      if (quotes.isEmpty) const ListTile(title: Text('No price quotations.')),
      for (final quote in quotes)
        Card(
          child: ListTile(
            leading: const Icon(Icons.request_quote_outlined),
            title: Text(
              '${quote.quantity} units • ${AppCurrency.format(quote.requestedUnitPrice, currencyCode: quote.currency)} requested',
            ),
            subtitle: Text(
              '${quote.status.name} • ${quote.message}${quote.quotedUnitPrice <= 0 ? '' : '\nQuoted ${AppCurrency.format(quote.quotedUnitPrice, currencyCode: quote.currency)}'}',
            ),
            trailing:
                quote.sellerId == widget.currentUserId &&
                    quote.status == QuoteStatus.requested
                ? TextButton(
                    onPressed: () => _respondQuote(context, quote),
                    child: const Text('Respond'),
                  )
                : null,
          ),
        ),
    ],
  );

  Widget _seller(
    MarketplaceProfile? profile,
    List<MarketplaceListing> listings,
    List<MarketplaceOrder> orders,
  ) {
    final own = listings
        .where((listing) => listing.sellerId == widget.currentUserId)
        .toList();
    final analytics = MarketplaceAnalytics.calculate(
      listings,
      orders,
      sellerId: widget.currentUserId,
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (profile == null)
          Card(
            child: ListTile(
              title: const Text(
                'Create a seller profile before listing inventory.',
              ),
              trailing: FilledButton(
                onPressed: () => _profile(context, null),
                child: const Text('Create'),
              ),
            ),
          )
        else
          FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CreateMarketplaceListingScreen(
                  repository: widget.repository,
                  seller: profile,
                  canListDevices: widget.canListDevices,
                  canListMaterials: widget.canListMaterials,
                ),
              ),
            ),
            icon: const Icon(Icons.add_business),
            label: const Text('Create listing'),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _metric('Active listings', '${analytics.activeListings}'),
            _metric('Orders', '${analytics.orders}'),
            _metric('Completed', '${analytics.completedOrders}'),
            _metric('Gross sales', AppCurrency.format(analytics.grossSales)),
            _metric(
              'Average order',
              AppCurrency.format(analytics.averageOrderValue),
            ),
            _metric('Units sold', analytics.unitsSold.toStringAsFixed(2)),
          ],
        ),
        const SizedBox(height: 18),
        Text('My listings', style: Theme.of(context).textTheme.titleLarge),
        for (final listing in own)
          ListTile(
            leading: const Icon(Icons.sell_outlined),
            title: Text(listing.title),
            subtitle: Text(
              '${listing.status.name} • ${listing.availableQuantity}/${listing.totalQuantity} ${listing.unit}',
            ),
            trailing: Text(
              AppCurrency.format(
                listing.unitPrice,
                currencyCode: listing.currency,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _profile(
    BuildContext context,
    MarketplaceProfile? current,
  ) async {
    var type = canSell
        ? MarketplaceProfileType.buyerAndSeller
        : MarketplaceProfileType.buyer;
    final display = TextEditingController(
          text: current?.displayName ?? widget.currentUserName,
        ),
        business = TextEditingController(text: current?.businessName ?? ''),
        email = TextEditingController(
          text: current?.email ?? widget.currentUserEmail,
        ),
        phone = TextEditingController(text: current?.phone ?? ''),
        address = TextEditingController(text: current?.deliveryAddress ?? '');
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Marketplace profile'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<MarketplaceProfileType>(
                      initialValue: current?.type ?? type,
                      items: MarketplaceProfileType.values
                          .where(
                            (value) =>
                                canSell ||
                                value == MarketplaceProfileType.buyer,
                          )
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setLocal(() => type = value!),
                    ),
                    TextField(
                      controller: display,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                      ),
                    ),
                    TextField(
                      controller: business,
                      decoration: const InputDecoration(
                        labelText: 'Business / seller name',
                      ),
                    ),
                    TextField(
                      controller: email,
                      decoration: const InputDecoration(labelText: 'Email'),
                    ),
                    TextField(
                      controller: phone,
                      decoration: const InputDecoration(labelText: 'Phone'),
                    ),
                    TextField(
                      controller: address,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Delivery address',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (ok && context.mounted) {
      await _runMarket(
        context,
        () => widget.repository.saveProfile(
          userId: widget.currentUserId,
          type: type,
          displayName: display.text,
          businessName: business.text,
          email: email.text,
          phone: phone.text,
          deliveryAddress: address.text,
        ),
        'Marketplace profile saved.',
      );
    }
    for (final controller in [display, business, email, phone, address]) {
      controller.dispose();
    }
  }

  Future<void> _order(
    BuildContext context,
    MarketplaceListing listing,
    MarketplaceProfile buyer,
  ) async {
    final quantity = TextEditingController(
      text: listing.unit == 'device' ? '1' : '',
    );
    final ok = await _text(
      context,
      'Place order',
      'Quantity (${listing.unit})',
      quantity,
      'Order',
    );
    if (ok && context.mounted) {
      await _runMarket(
        context,
        () => widget.repository.placeOrder(
          listing: listing,
          buyer: buyer,
          quantity: double.tryParse(quantity.text) ?? 0,
        ),
        'Order placed.',
      );
    }
    quantity.dispose();
  }

  Future<void> _quote(
    BuildContext context,
    MarketplaceListing listing,
    MarketplaceProfile buyer,
  ) async {
    final quantity = TextEditingController(),
        price = TextEditingController(),
        message = TextEditingController();
    final ok = await _form(context, 'Request price quotation', 'Request', [
      TextField(
        controller: quantity,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: 'Quantity (${listing.unit})'),
      ),
      TextField(
        controller: price,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: AppCurrency.inputLabel('Requested unit price'),
        ),
      ),
      TextField(
        controller: message,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Message'),
      ),
    ]);
    if (ok && context.mounted) {
      await _runMarket(
        context,
        () => widget.repository.requestQuote(
          listing: listing,
          buyer: buyer,
          quantity: double.tryParse(quantity.text) ?? 0,
          requestedUnitPrice: double.tryParse(price.text) ?? 0,
          message: message.text,
        ),
        'Quotation requested.',
      );
    }
    quantity.dispose();
    price.dispose();
    message.dispose();
  }

  Future<void> _respondQuote(BuildContext context, PriceQuotation quote) async {
    final price = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Respond to quotation'),
        content: TextField(
          controller: price,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Quoted unit price (Le)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Reject'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send quote'),
          ),
        ],
      ),
    );
    if (accepted != null && context.mounted) {
      await _runMarket(
        context,
        () => widget.repository.respondQuote(
          quote,
          accepted: accepted,
          quotedPrice: double.tryParse(price.text) ?? 0,
        ),
        'Quotation updated.',
      );
    }
    price.dispose();
  }

  Future<void> _payment(BuildContext context, MarketplaceOrder order) async {
    final method = TextEditingController(), reference = TextEditingController();
    final ok = await _form(
      context,
      'Payment processing',
      'Submit for verification',
      [
        const Text(
          'Do not enter card numbers or banking credentials. Record only the payment method and provider transaction reference.',
        ),
        TextField(
          controller: method,
          decoration: const InputDecoration(labelText: 'Payment method'),
        ),
        TextField(
          controller: reference,
          decoration: const InputDecoration(labelText: 'Transaction reference'),
        ),
      ],
    );
    if (ok && context.mounted) {
      await _runMarket(
        context,
        () => widget.repository.submitPayment(
          order,
          method: method.text,
          reference: reference.text,
        ),
        'Payment submitted for verification.',
      );
    }
    method.dispose();
    reference.dispose();
  }

  Future<void> _dispatch(BuildContext context, MarketplaceOrder order) async {
    final carrier = TextEditingController(),
        tracking = TextEditingController(),
        location = TextEditingController();
    final ok = await _form(context, 'Dispatch order', 'Dispatch', [
      TextField(
        controller: carrier,
        decoration: const InputDecoration(labelText: 'Carrier'),
      ),
      TextField(
        controller: tracking,
        decoration: const InputDecoration(labelText: 'Tracking number'),
      ),
      TextField(
        controller: location,
        decoration: const InputDecoration(labelText: 'Dispatch location'),
      ),
    ]);
    if (ok && context.mounted) {
      await _runMarket(
        context,
        () => widget.repository.dispatch(
          order,
          carrier: carrier.text,
          trackingNumber: tracking.text,
          location: location.text,
        ),
        'Order dispatched.',
      );
    }
    carrier.dispose();
    tracking.dispose();
    location.dispose();
  }

  Future<void> _delivery(BuildContext context, MarketplaceOrder order) async {
    final status = TextEditingController(text: 'Delivered'),
        location = TextEditingController(),
        notes = TextEditingController();
    var delivered = true;
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Delivery tracking update'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: status,
                    decoration: const InputDecoration(
                      labelText: 'Tracking status',
                    ),
                  ),
                  TextField(
                    controller: location,
                    decoration: const InputDecoration(labelText: 'Location'),
                  ),
                  TextField(
                    controller: notes,
                    decoration: const InputDecoration(labelText: 'Notes'),
                  ),
                  SwitchListTile(
                    value: delivered,
                    onChanged: (value) => setLocal(() => delivered = value),
                    title: const Text('Final delivery'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Update'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (ok && context.mounted) {
      await _runMarket(
        context,
        () => widget.repository.updateDelivery(
          order,
          status: status.text,
          location: location.text,
          notes: notes.text,
          delivered: delivered,
        ),
        'Delivery updated.',
      );
    }
    status.dispose();
    location.dispose();
    notes.dispose();
  }

  Future<void> _review(
    BuildContext context,
    MarketplaceOrder order,
    MarketplaceProfile buyer,
  ) async {
    var rating = 5;
    final comment = TextEditingController();
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
              title: const Text('Review seller'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: List.generate(
                      5,
                      (index) => IconButton(
                        onPressed: () => setLocal(() => rating = index + 1),
                        icon: Icon(
                          index < rating ? Icons.star : Icons.star_border,
                        ),
                      ),
                    ),
                  ),
                  TextField(
                    controller: comment,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Review'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Submit'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (ok && context.mounted) {
      await _runMarket(
        context,
        () => widget.repository.reviewOrder(
          order,
          buyer: buyer,
          rating: rating,
          comment: comment.text,
        ),
        'Review submitted.',
      );
    }
    comment.dispose();
  }

  Future<void> _receipt(MarketplaceOrder order) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Header(level: 0, text: 'EcoTrace Marketplace Receipt'),
            pw.Text('Order ${order.orderNumber}'),
            pw.Text(order.listingTitle),
            pw.Text('Buyer: ${order.buyerName}'),
            pw.Text('Seller: ${order.sellerName}'),
            pw.Text('Quantity: ${order.quantity} ${order.unit}'),
            pw.Text(
              'Unit price: ${AppCurrency.format(order.unitPrice, currencyCode: order.currency)}',
            ),
            pw.Text(
              'Total: ${AppCurrency.format(order.totalAmount, currencyCode: order.currency)}',
            ),
            pw.Text(
              'Payment: ${order.paymentStatus.name} • ${order.paymentMethod} • ${order.paymentReference}',
            ),
            pw.Text('Order status: ${order.status.name}'),
            pw.Text('Delivery: ${order.carrier} ${order.trackingNumber}'),
          ],
        ),
      ),
    );
    await Printing.layoutPdf(onLayout: (_) => doc.save());
  }
}

class CreateMarketplaceListingScreen extends StatefulWidget {
  const CreateMarketplaceListingScreen({
    super.key,
    required this.repository,
    required this.seller,
    required this.canListDevices,
    required this.canListMaterials,
  });
  final MarketplaceRepository repository;
  final MarketplaceProfile seller;
  final bool canListDevices, canListMaterials;
  @override
  State<CreateMarketplaceListingScreen> createState() =>
      _CreateMarketplaceListingScreenState();
}

class _CreateMarketplaceListingScreenState
    extends State<CreateMarketplaceListingScreen> {
  late MarketplaceListingType type = widget.canListDevices
      ? MarketplaceListingType.refurbishedDevice
      : MarketplaceListingType.recoveredMaterial;
  RepairJob? device;
  RecoveredMaterialLot? material;
  final images = <XFile>[];
  bool saving = false;
  final description = TextEditingController(),
      price = TextEditingController(),
      currency = TextEditingController(text: 'SLE');
  @override
  void dispose() {
    description.dispose();
    price.dispose();
    currency.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Create marketplace listing')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<MarketplaceListingType>(
          initialValue: type,
          items: MarketplaceListingType.values
              .where(
                (value) => value == MarketplaceListingType.refurbishedDevice
                    ? widget.canListDevices
                    : widget.canListMaterials,
              )
              .map(
                (value) =>
                    DropdownMenuItem(value: value, child: Text(value.name)),
              )
              .toList(),
          onChanged: (value) => setState(() {
            type = value!;
            device = null;
            material = null;
          }),
        ),
        const SizedBox(height: 12),
        if (type == MarketplaceListingType.refurbishedDevice)
          StreamBuilder<List<RepairJob>>(
            stream: widget.repository.watchEligibleDevices(),
            builder: (context, snapshot) => DropdownButtonFormField<RepairJob>(
              initialValue: device,
              decoration: const InputDecoration(
                labelText: 'Resale-approved refurbished device',
              ),
              items: (snapshot.data ?? const <RepairJob>[])
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text('${value.itemCode} • ${value.deviceName}'),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => device = value),
            ),
          )
        else
          StreamBuilder<List<RecoveredMaterialLot>>(
            stream: widget.repository.watchEligibleMaterials(),
            builder: (context, snapshot) =>
                DropdownButtonFormField<RecoveredMaterialLot>(
                  initialValue: material,
                  decoration: const InputDecoration(
                    labelText: 'Sales-ready recovered material',
                  ),
                  items: (snapshot.data ?? const <RecoveredMaterialLot>[])
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(
                            '${value.lotCode} • ${value.material.label} • ${value.weightKg} kg',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => material = value),
                ),
          ),
        TextField(
          controller: description,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Listing description'),
        ),
        TextField(
          controller: price,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: type == MarketplaceListingType.refurbishedDevice
                ? 'Device price (Le)'
                : 'Price per kg (Le)',
          ),
        ),
        TextField(
          controller: currency,
          readOnly: true,
          decoration: const InputDecoration(
            labelText: 'Currency',
            helperText: 'Sierra Leone leone (Le)',
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: saving || images.length >= 5
              ? null
              : () async {
                  final selected = await ImagePicker().pickMultiImage(
                    imageQuality: 75,
                  );
                  if (selected.isNotEmpty) {
                    setState(() {
                      images.addAll(selected.take(5 - images.length));
                    });
                  }
                },
          icon: const Icon(Icons.add_a_photo_outlined),
          label: Text(
            images.isEmpty
                ? 'Add listing photos'
                : 'Listing photos (${images.length}/5)',
          ),
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: saving ? null : _save,
          child: Text(saving ? 'Publishing…' : 'Publish listing'),
        ),
      ],
    ),
  );
  Future<void> _save() async {
    setState(() => saving = true);
    try {
      final imageUrls = images.isEmpty
          ? const <String>[]
          : await CloudinaryUploadService.instance.uploadImages(
              await Future.wait(
                images.map((image) async => Uint8List.fromList(await image.readAsBytes())),
              ),
              scope: 'marketplace',
            );
      if (type == MarketplaceListingType.refurbishedDevice && device != null) {
        await widget.repository.listDevice(
          job: device!,
          seller: widget.seller,
          description: description.text,
          price: double.tryParse(price.text) ?? 0,
          currency: currency.text,
          imageUrls: imageUrls,
        );
      } else if (material != null) {
        await widget.repository.listMaterial(
          lot: material!,
          seller: widget.seller,
          description: description.text,
          pricePerKg: double.tryParse(price.text) ?? 0,
          currency: currency.text,
          imageUrls: imageUrls,
        );
      } else {
        throw StateError('Select an eligible asset.');
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to publish listing: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

Widget _metric(String label, String value) => SizedBox(
  width: 165,
  child: Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          Text(label),
        ],
      ),
    ),
  ),
);
Future<bool> _form(
  BuildContext context,
  String title,
  String action,
  List<Widget> children,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;
Future<bool> _text(
  BuildContext context,
  String title,
  String label,
  TextEditingController controller,
  String action,
) => _form(context, title, action, [
  TextField(
    controller: controller,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label),
  ),
]);
Future<void> _runMarket(
  BuildContext context,
  Future<void> Function() action,
  String success,
) async {
  try {
    await action();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Marketplace operation failed: $error')),
      );
    }
  }
}
