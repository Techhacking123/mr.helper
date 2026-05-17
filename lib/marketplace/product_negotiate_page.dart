import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_config.dart';
import '../auth/session_manager.dart';
import '../widgets/safe_network_image.dart';

class ProductNegotiatePage extends StatefulWidget {
  final Map<String, dynamic> product;
  final String? existingOrderId;
  const ProductNegotiatePage({super.key, required this.product, this.existingOrderId});

  @override
  State<ProductNegotiatePage> createState() => _ProductNegotiatePageState();
}

class _ProductNegotiatePageState extends State<ProductNegotiatePage> with SingleTickerProviderStateMixin {
  final _offerController = TextEditingController();
  String? _orderId;
  String? _userId;
  String _orderStatus = 'negotiating';
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  bool _showOfferInput = false;
  late AnimationController _pulseController;
  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _orderChannel;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _orderId = widget.existingOrderId;
    _initialize();
  }

  @override
  void dispose() {
    _offerController.dispose();
    _pulseController.dispose();
    if (_messagesChannel != null) SupabaseConfig.supabase.removeChannel(_messagesChannel!);
    if (_orderChannel != null) SupabaseConfig.supabase.removeChannel(_orderChannel!);
    super.dispose();
  }

  Future<void> _initialize() async {
    _userId = await SessionManager.getUserId();
    if (_orderId != null) {
      await _loadExistingOrder();
    } else {
      setState(() { _isLoading = false; _showOfferInput = true; });
    }
  }

  Future<void> _loadExistingOrder() async {
    try {
      final order = await SupabaseConfig.supabase.from('product_orders').select().eq('id', _orderId!).single();
      _orderStatus = order['status'] ?? 'negotiating';
      final msgs = await SupabaseConfig.supabase.from('negotiation_messages')
          .select('*, sender:users!sender_id(full_name)')
          .eq('product_order_id', _orderId!)
          .order('created_at', ascending: true);
      if (mounted) {
        setState(() { _messages = List<Map<String, dynamic>>.from(msgs); _isLoading = false; });
        _subscribeToUpdates();
      }
    } catch (e) {
      debugPrint('Error loading order: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _subscribeToUpdates() {
    if (_orderId == null) return;
    _messagesChannel = SupabaseConfig.supabase.channel('neg_msgs_$_orderId')
        .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'negotiation_messages',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'product_order_id', value: _orderId!),
          callback: (payload) => _loadExistingOrder(),
        ).subscribe();
    _orderChannel = SupabaseConfig.supabase.channel('neg_order_$_orderId')
        .onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'product_orders',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: _orderId!),
          callback: (payload) { final nr = payload.newRecord; if (mounted && nr['status'] != null) setState(() => _orderStatus = nr['status']); },
        ).subscribe();
  }

  Future<void> _submitInitialOffer() async {
    final amountText = _offerController.text.trim();
    if (amountText.isEmpty) return;
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount'), backgroundColor: Colors.red)); return; }
    setState(() => _isSending = true);
    try {
      final result = await SupabaseConfig.supabase.from('product_orders').insert({
        'product_id': widget.product['id'],
        'buyer_id': _userId,
        'provider_id': widget.product['provider_id'],
        'original_price': widget.product['price'],
        'status': 'negotiating',
      }).select('id').single();
      _orderId = result['id'];
      await SupabaseConfig.supabase.from('negotiation_messages').insert({
        'product_order_id': _orderId, 'sender_id': _userId, 'sender_role': 'buyer', 'action': 'offer', 'amount': amount,
      });
      // Notify provider
      await SupabaseConfig.supabase.from('notifications').insert({
        'user_id': widget.product['provider_id'],
        'message': 'New offer of ₹$amount for ${widget.product['name']}',
        'type': 'product_negotiation',
      });
      _offerController.clear();
      setState(() { _showOfferInput = false; _isSending = false; });
      await _loadExistingOrder();
    } catch (e) {
      debugPrint('Error submitting offer: $e');
      if (mounted) { setState(() => _isSending = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red)); }
    }
  }

  Future<void> _sendAction(String action, {double? amount}) async {
    if (_orderId == null) return;
    setState(() => _isSending = true);
    try {
      final role = 'buyer';
      await SupabaseConfig.supabase.from('negotiation_messages').insert({
        'product_order_id': _orderId, 'sender_id': _userId, 'sender_role': role, 'action': action, 'amount': amount,
      });
      if (action == 'accept') {
        final lastProviderMsg = _messages.lastWhere((m) => m['sender_role'] == 'provider' && m['amount'] != null, orElse: () => {});
        final finalPrice = lastProviderMsg.isNotEmpty ? lastProviderMsg['amount'] : widget.product['price'];
        await SupabaseConfig.supabase.from('product_orders').update({'status': 'accepted', 'final_price': finalPrice}).eq('id', _orderId!);
        await SupabaseConfig.supabase.from('notifications').insert({
          'user_id': widget.product['provider_id'], 'message': 'Your product ${widget.product['name']} offer has been accepted!', 'type': 'product_negotiation',
        });
      } else if (action == 'cancel') {
        await SupabaseConfig.supabase.from('product_orders').update({'status': 'cancelled'}).eq('id', _orderId!);
        await SupabaseConfig.supabase.from('notifications').insert({
          'user_id': widget.product['provider_id'], 'message': 'Negotiation for ${widget.product['name']} was cancelled.', 'type': 'product_negotiation',
        });
      } else if (action == 'counter_offer' && amount != null) {
        await SupabaseConfig.supabase.from('notifications').insert({
          'user_id': widget.product['provider_id'], 'message': 'Counter offer of ₹$amount for ${widget.product['name']}', 'type': 'product_negotiation',
        });
      }
      _offerController.clear();
      setState(() { _isSending = false; _showOfferInput = false; });
      await _loadExistingOrder();
    } catch (e) {
      debugPrint('Error sending action: $e');
      if (mounted) { setState(() => _isSending = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red)); }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(title: const Text('Negotiation'), backgroundColor: Colors.white, foregroundColor: Colors.black87, elevation: 0),
      body: _isLoading ? const Center(child: CircularProgressIndicator())
          : _orderId == null ? _buildInitialOfferView()
          : _buildNegotiationView(),
    );
  }

  Widget _buildInitialOfferView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        // Product preview
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            ClipRRect(borderRadius: BorderRadius.circular(12),
              child: SafeNetworkImage(imageUrl: widget.product['image_url'], width: 80, height: 80, borderRadius: BorderRadius.circular(12),
                errorWidget: Container(width: 80, height: 80, color: Colors.grey.shade200, child: const Icon(Icons.image)))),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.product['name'] ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Original Price: ₹${widget.product['price']}', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
            ])),
          ])),
        const SizedBox(height: 24),
        const Text('Make Your Offer', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Enter the amount you\'d like to pay', style: TextStyle(color: Colors.grey.shade600)),
        const SizedBox(height: 24),
        TextField(controller: _offerController, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
          decoration: InputDecoration(prefixText: '₹ ', filled: true, fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade200)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2)),
            hintText: '0', hintStyle: TextStyle(color: Colors.grey.shade300, fontSize: 28, fontWeight: FontWeight.bold))),
        const SizedBox(height: 24),
        SizedBox(width: double.infinity, height: 56, child: ElevatedButton(
          onPressed: _isSending ? null : _submitInitialOffer,
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          child: _isSending ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
              : const Text('Submit Offer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))),
      ]),
    );
  }

  Widget _buildNegotiationView() {
    final isFinalized = _orderStatus == 'accepted' || _orderStatus == 'cancelled';
    final lastMsg = _messages.isNotEmpty ? _messages.last : null;
    final isMyTurn = lastMsg == null || lastMsg['sender_role'] == 'provider';

    return Column(children: [
      // Status banner
      Container(width: double.infinity, padding: const EdgeInsets.all(12),
        color: _orderStatus == 'accepted' ? Colors.green.shade50 : _orderStatus == 'cancelled' ? Colors.red.shade50 : Colors.blue.shade50,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(_orderStatus == 'accepted' ? Icons.check_circle : _orderStatus == 'cancelled' ? Icons.cancel : Icons.handshake,
            color: _orderStatus == 'accepted' ? Colors.green : _orderStatus == 'cancelled' ? Colors.red : Colors.blue, size: 20),
          const SizedBox(width: 8),
          Text(_orderStatus == 'accepted' ? 'Deal Accepted!' : _orderStatus == 'cancelled' ? 'Negotiation Cancelled' : 'Negotiation in Progress',
            style: TextStyle(fontWeight: FontWeight.bold, color: _orderStatus == 'accepted' ? Colors.green.shade700 : _orderStatus == 'cancelled' ? Colors.red.shade700 : Colors.blue.shade700)),
        ])),
      // Messages timeline
      Expanded(child: ListView.builder(
        padding: const EdgeInsets.all(16), itemCount: _messages.length,
        itemBuilder: (context, index) {
          final msg = _messages[index];
          final isMe = msg['sender_id'] == _userId;
          return _buildMessageBubble(msg, isMe);
        })),
      // Waiting indicator
      if (!isFinalized && !isMyTurn)
        AnimatedBuilder(animation: _pulseController, builder: (context, child) {
          return Container(padding: const EdgeInsets.all(16), color: Colors.white,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color.lerp(Colors.grey.shade300, const Color(0xFF6366F1), _pulseController.value))),
              const SizedBox(width: 12),
              Text('Waiting for provider response...', style: TextStyle(color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
            ]));
        }),
      // Action buttons
      if (!isFinalized && isMyTurn) _buildActionButtons(),
    ]);
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, bool isMe) {
    final action = msg['action'] as String;
    final amount = msg['amount'];
    final sender = msg['sender']?['full_name'] ?? (isMe ? 'You' : 'Provider');
    final time = msg['created_at'] != null ? DateFormat('MMM d, hh:mm a').format(DateTime.parse(msg['created_at']).toLocal()) : '';
    IconData icon;
    Color color;
    String label;
    switch (action) {
      case 'offer': icon = Icons.local_offer; color = Colors.blue; label = 'Offered ₹$amount'; break;
      case 'counter_offer': icon = Icons.swap_horiz; color = Colors.orange; label = 'Counter: ₹$amount'; break;
      case 'accept': icon = Icons.check_circle; color = Colors.green; label = 'Accepted'; break;
      case 'cancel': icon = Icons.cancel; color = Colors.red; label = 'Cancelled'; break;
      default: icon = Icons.message; color = Colors.grey; label = action;
    }
    return Align(alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(color: isMe ? const Color(0xFF6366F1).withOpacity(0.1) : Colors.white, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isMe ? const Color(0xFF6366F1).withOpacity(0.2) : Colors.grey.shade200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(icon, size: 16, color: color), const SizedBox(width: 6),
            Text(sender, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600))]),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(time, style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
        ])));
  }

  Widget _buildActionButtons() {
    return Container(padding: const EdgeInsets.all(16), color: Colors.white,
      child: Column(children: [
        if (_showOfferInput) ...[
          TextField(controller: _offerController, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(prefixText: '₹ ', hintText: 'Enter counter offer', filled: true, fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2)))),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _isSending ? null : () { final a = double.tryParse(_offerController.text.trim()); if (a != null && a > 0) _sendAction('counter_offer', amount: a); },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Send Counter Offer', style: TextStyle(fontWeight: FontWeight.bold)))),
          const SizedBox(height: 8),
          TextButton(onPressed: () => setState(() => _showOfferInput = false), child: const Text('Cancel')),
        ] else ...[
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: _isSending ? null : () => _sendAction('cancel'),
              icon: const Icon(Icons.close, size: 18), label: const Text('Cancel'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: () => setState(() => _showOfferInput = true),
              icon: const Icon(Icons.swap_horiz, size: 18), label: const Text('Counter'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.orange, side: const BorderSide(color: Colors.orange), padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
            const SizedBox(width: 8),
            Expanded(child: ElevatedButton.icon(onPressed: _isSending ? null : () => _sendAction('accept'),
              icon: const Icon(Icons.check, size: 18), label: const Text('Accept'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
          ]),
        ],
      ]));
  }
}
