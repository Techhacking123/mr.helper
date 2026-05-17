import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminOrdersPage extends StatefulWidget {
  const AdminOrdersPage({super.key});

  @override
  State<AdminOrdersPage> createState() => _AdminOrdersPageState();
}

class _AdminOrdersPageState extends State<AdminOrdersPage> {
  List<Map<String, dynamic>> _orders = [];
  bool _isLoading = true;

  late final RealtimeChannel _subscription;

  @override
  void initState() {
    super.initState();
    _fetchOrders();
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    SupabaseConfig.supabase.removeChannel(_subscription);
    super.dispose();
  }

  void _subscribeToRealtime() {
    _subscription = SupabaseConfig.supabase.channel('admin_orders_list');
    _subscription
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (payload) => _fetchOrders(),
        )
        .subscribe();
  }

  Future<void> _fetchOrders() async {
    try {
      final response = await SupabaseConfig.supabase
          .from('orders')
          .select(
            '*, buyer:users!buyer_id(full_name), provider:users!provider_id(full_name), service:services(name)',
          )
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _orders = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching orders: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateStatus(String orderId, String newStatus) async {
    try {
      await SupabaseConfig.adminClient
          .from('orders')
          .update({'status': newStatus})
          .eq('id', orderId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Order marked as $newStatus')));
        _fetchOrders();
      }
    } catch (e) {
      debugPrint('Error updating order: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _deleteOrder(String orderId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Order?'),
        content: const Text(
          'Are you sure run want to permanently delete (cancel) this order?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await SupabaseConfig.adminClient.from('orders').delete().eq('id', orderId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Order deleted.')));
        _fetchOrders();
      }
    } catch (e) {
      debugPrint('Error deleting order: $e');
    }
  }

  void _viewOrderDetails(Map<String, dynamic> order) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Order Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'ID: ${order['id']}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const Divider(),
              Text(
                'Service: ${order['service']?['name'] ?? 'Unknown'}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text('Status: ${order['status']}'),
              const SizedBox(height: 10),
              Text('Message: ${order['message'] ?? "None"}'),
              const SizedBox(height: 20),
              if (order['image_path'] != null) ...[
                const Text('Attached Image:'),
                const SizedBox(height: 5),
                Container(
                  height: 150,
                  width: double.infinity,
                  color: Colors.grey[200],
                  // Note: Fetching image URL would require storage.from('...').getPublicUrl
                  // For now, listing path.
                  child: Center(child: Text(order['image_path'].toString())),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('All Orders')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _orders.length,
              itemBuilder: (context, index) {
                final order = _orders[index];
                final buyer = order['buyer'] ?? {'full_name': 'Unknown'};
                final provider = order['provider'] ?? {'full_name': 'Unknown'};
                final status = order['status'];

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: ListTile(
                    title: Text('${order['service']?['name'] ?? 'Service'}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Buyer: ${buyer['full_name']}'),
                        Text('Provider: ${provider['full_name']}'),
                        Text(
                          'Price: ₹${order['user_price'] ?? "?"}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        Text(
                          'Status: $status',
                          style: TextStyle(
                            color: status == 'completed'
                                ? Colors.green
                                : (status == 'pending'
                                      ? Colors.orange
                                      : Colors.blue),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          DateFormat.yMMMd().format(
                            DateTime.parse(order['created_at']),
                          ),
                        ),
                      ],
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'view') _viewOrderDetails(order);
                        if (value == 'complete')
                          _updateStatus(order['id'], 'completed');
                        if (value == 'delete') _deleteOrder(order['id']);
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'view',
                          child: Text('View Details'),
                        ),
                        if (status != 'completed')
                          const PopupMenuItem(
                            value: 'complete',
                            child: Text('Force Complete'),
                          ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            'Force Cancel (Delete)',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
