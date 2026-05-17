import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_config.dart';
import '../auth/session_manager.dart';
import '../widgets/safe_network_image.dart';
import 'product_negotiate_page.dart';

class ProductOrdersPage extends StatefulWidget {
  const ProductOrdersPage({super.key});
  @override
  State<ProductOrdersPage> createState() => _ProductOrdersPageState();
}

class _ProductOrdersPageState extends State<ProductOrdersPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _activeOrders = [];
  List<Map<String, dynamic>> _completedOrders = [];
  bool _isLoading = true;
  String? _userId;
  RealtimeChannel? _ordersChannel;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadOrders();
    _subscribeToOrders();
  }

  @override
  void dispose() {
    _tabController.dispose();
    if (_ordersChannel != null) SupabaseConfig.supabase.removeChannel(_ordersChannel!);
    super.dispose();
  }

  void _subscribeToOrders() {
    SessionManager.getUserId().then((uid) {
      if (uid == null) return;
      _ordersChannel = SupabaseConfig.supabase.channel('product_orders_provider_$uid')
          .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'product_orders',
            callback: (payload) => _loadOrders())
          .subscribe();
    });
  }

  Future<void> _loadOrders() async {
    try {
      _userId = await SessionManager.getUserId();
      if (_userId == null) return;
      final response = await SupabaseConfig.supabase.from('product_orders')
          .select('*, product:products(*), buyer:users!buyer_id(id, full_name, avatar_url, phone_number)')
          .eq('provider_id', _userId!).order('created_at', ascending: false);
      final orders = List<Map<String, dynamic>>.from(response);

      // Load latest negotiation message for each order
      for (var order in orders) {
        final msgs = await SupabaseConfig.supabase.from('negotiation_messages')
            .select('*, sender:users!sender_id(full_name)')
            .eq('product_order_id', order['id']).order('created_at', ascending: false).limit(1);
        order['_latest_message'] = (msgs as List).isNotEmpty ? msgs.first : null;
        // Get message count
        final allMsgs = await SupabaseConfig.supabase.from('negotiation_messages')
            .select('id').eq('product_order_id', order['id']);
        order['_message_count'] = (allMsgs as List).length;
      }

      if (mounted) setState(() {
        _activeOrders = orders.where((o) => o['status'] == 'negotiating').toList();
        _completedOrders = orders.where((o) => o['status'] != 'negotiating').toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading product orders: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleAction(Map<String, dynamic> order, String action, {double? amount}) async {
    try {
      await SupabaseConfig.supabase.from('negotiation_messages').insert({
        'product_order_id': order['id'], 'sender_id': _userId, 'sender_role': 'provider', 'action': action, 'amount': amount,
      });
      final productName = order['product']?['name'] ?? 'Product';
      final buyerId = order['buyer_id'];
      if (action == 'accept') {
        final lastBuyerMsg = await SupabaseConfig.supabase.from('negotiation_messages')
            .select('amount').eq('product_order_id', order['id']).eq('sender_role', 'buyer')
            .not('amount', 'is', null).order('created_at', ascending: false).limit(1);
        final finalPrice = (lastBuyerMsg as List).isNotEmpty ? lastBuyerMsg.first['amount'] : order['original_price'];
        await SupabaseConfig.supabase.from('product_orders').update({'status': 'accepted', 'final_price': finalPrice}).eq('id', order['id']);
        await SupabaseConfig.supabase.from('notifications').insert({
          'user_id': buyerId, 'message': 'Your offer for $productName has been accepted! 🎉', 'type': 'product_negotiation',
        });
      } else if (action == 'cancel') {
        await SupabaseConfig.supabase.from('product_orders').update({'status': 'cancelled'}).eq('id', order['id']);
        await SupabaseConfig.supabase.from('notifications').insert({
          'user_id': buyerId, 'message': 'Negotiation for $productName was cancelled by provider.', 'type': 'product_negotiation',
        });
      } else if (action == 'counter_offer' && amount != null) {
        await SupabaseConfig.supabase.from('notifications').insert({
          'user_id': buyerId, 'message': 'Counter offer of ₹$amount for $productName', 'type': 'product_negotiation',
        });
      }
      _loadOrders();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(action == 'accept' ? '✓ Offer accepted' : action == 'cancel' ? 'Order cancelled' : '✓ Counter offer sent'),
        backgroundColor: action == 'cancel' ? Colors.red : Colors.green));
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  void _showCounterOfferDialog(Map<String, dynamic> order) {
    final controller = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Counter Offer'), content: TextField(controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(prefixText: '₹ ', hintText: 'Enter your counter price',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(onPressed: () { final a = double.tryParse(controller.text.trim());
          if (a != null && a > 0) { Navigator.pop(ctx); _handleAction(order, 'counter_offer', amount: a); }},
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange), child: const Text('Send')),
      ]));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(title: const Text('Product Orders'), backgroundColor: Colors.white, foregroundColor: Colors.black87, elevation: 0,
        bottom: TabBar(controller: _tabController, labelColor: const Color(0xFF6366F1), unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF6366F1), tabs: [
            Tab(text: 'Active (${_activeOrders.length})'), Tab(text: 'Accepted'), const Tab(text: 'Cancelled'),
          ])),
      body: _isLoading ? const Center(child: CircularProgressIndicator())
          : TabBarView(controller: _tabController, children: [
              _buildOrderList(_activeOrders, showActions: true),
              _buildOrderList(_completedOrders.where((o) => o['status'] == 'accepted').toList()),
              _buildOrderList(_completedOrders.where((o) => o['status'] == 'cancelled').toList()),
            ]),
    );
  }

  Widget _buildOrderList(List<Map<String, dynamic>> orders, {bool showActions = false}) {
    if (orders.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade300),
      const SizedBox(height: 16), Text('No orders', style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
    ]));
    return RefreshIndicator(onRefresh: _loadOrders, child: ListView.builder(
      padding: const EdgeInsets.all(16), itemCount: orders.length,
      itemBuilder: (context, index) => _buildOrderCard(orders[index], showActions: showActions)));
  }

  Widget _buildOrderCard(Map<String, dynamic> order, {bool showActions = false}) {
    final product = order['product'] as Map<String, dynamic>?;
    final buyer = order['buyer'] as Map<String, dynamic>?;
    final latestMsg = order['_latest_message'] as Map<String, dynamic>?;
    final status = order['status'] as String;
    final time = order['created_at'] != null ? DateFormat('MMM d, hh:mm a').format(DateTime.parse(order['created_at']).toLocal()) : '';

    return Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Product info row
        Row(children: [
          ClipRRect(borderRadius: BorderRadius.circular(10),
            child: SafeNetworkImage(imageUrl: product?['image_url'], width: 60, height: 60, borderRadius: BorderRadius.circular(10),
              errorWidget: Container(width: 60, height: 60, color: Colors.grey.shade200, child: const Icon(Icons.image, color: Colors.grey)))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(product?['name'] ?? 'Product', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Row(children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(4)),
                child: Text('₹${order['original_price']}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green.shade700))),
              const SizedBox(width: 8),
              if (order['final_price'] != null) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)),
                child: Text('Final: ₹${order['final_price']}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue.shade700))),
            ])])),
          // Status badge
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: status == 'accepted' ? Colors.green.shade50 : status == 'cancelled' ? Colors.red.shade50 : Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8)),
            child: Text(status[0].toUpperCase() + status.substring(1),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: status == 'accepted' ? Colors.green.shade700 : status == 'cancelled' ? Colors.red.shade700 : Colors.orange.shade700))),
        ]),
        const Divider(height: 20),
        // Buyer info
        Row(children: [
          SafeAvatar(imageUrl: buyer?['avatar_url'], radius: 16, userName: buyer?['full_name']),
          const SizedBox(width: 8),
          Expanded(child: Text(buyer?['full_name'] ?? 'Buyer', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
          Text(time, style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
        ]),
        // Latest negotiation message
        if (latestMsg != null) ...[
          const SizedBox(height: 8),
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Icon(latestMsg['action'] == 'offer' ? Icons.local_offer : latestMsg['action'] == 'counter_offer' ? Icons.swap_horiz
                  : latestMsg['action'] == 'accept' ? Icons.check_circle : Icons.cancel,
                size: 16, color: latestMsg['action'] == 'accept' ? Colors.green : latestMsg['action'] == 'cancel' ? Colors.red : Colors.orange),
              const SizedBox(width: 8),
              Expanded(child: Text('${latestMsg['sender']?['full_name'] ?? 'User'}: ${latestMsg['action'] == 'offer' || latestMsg['action'] == 'counter_offer' ? '₹${latestMsg['amount']}' : latestMsg['action']}',
                style: const TextStyle(fontSize: 13))),
            ])),
        ],
        // Action buttons
        if (showActions && status == 'negotiating') ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => _handleAction(order, 'cancel'), child: const Text('Cancel'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: () => _showCounterOfferDialog(order), child: const Text('Counter'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.orange, side: const BorderSide(color: Colors.orange),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))))),
            const SizedBox(width: 8),
            Expanded(child: ElevatedButton(onPressed: () => _handleAction(order, 'accept'), child: const Text('Accept'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))))),
          ]),
        ],
        // View full negotiation
        if (status == 'negotiating') ...[
          const SizedBox(height: 8),
          Center(child: TextButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => ProductNegotiatePage(product: {'id': order['product_id'], 'provider_id': order['provider_id'], 'name': product?['name'], 'image_url': product?['image_url'], 'price': order['original_price']},
              existingOrderId: order['id']))),
            icon: const Icon(Icons.chat, size: 16), label: Text('View Negotiation (${order['_message_count'] ?? 0} messages)'))),
        ],
      ]));
  }
}
