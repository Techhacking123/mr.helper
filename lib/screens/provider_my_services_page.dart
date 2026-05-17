import 'package:flutter/material.dart';

import '../supabase_config.dart';
import '../auth/session_manager.dart';
import '../orders/order_detail.dart';

class ProviderMyServicesPage extends StatefulWidget {
  const ProviderMyServicesPage({super.key});

  @override
  State<ProviderMyServicesPage> createState() => _ProviderMyServicesPageState();
}

class _ProviderMyServicesPageState extends State<ProviderMyServicesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _pendingOrders = [];
  List<Map<String, dynamic>> _completedOrders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchOrders();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchOrders() async {
    try {
      final userId = await SessionManager.getUserId();
      if (userId == null) return;

      // Fetch all orders for this provider
      final response = await SupabaseConfig.supabase
          .from('orders')
          .select('*, buyer:users!buyer_id(full_name), service:services(name)')
          .eq('provider_id', userId)
          .order('created_at', ascending: false);

      final List<Map<String, dynamic>> allOrders =
          List<Map<String, dynamic>>.from(response);

      setState(() {
        // "Pending" tab includes 'pending', 'accepted' (active work)
        // "Completed" tab includes 'completed' (and maybe 'rejected'?)
        // The user specifically asked for "Completed" and "Pending".
        // I'll group 'pending' and 'accepted' into Pending/Active tab.
        // And 'completed' into Completed tab.
        _pendingOrders = allOrders
            .where((o) => o['status'] == 'pending' || o['status'] == 'accepted')
            .toList();

        _completedOrders = allOrders
            .where((o) => o['status'] == 'completed')
            .toList();

        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching provider services: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _buildOrderList(
    List<Map<String, dynamic>> orders, {
    bool isCompleted = false,
  }) {
    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isCompleted ? Icons.check_circle_outline : Icons.pending_actions,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              isCompleted
                  ? 'No completed services yet.'
                  : 'No pending services.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        final buyerName = order['buyer']['full_name'] ?? 'Unknown User';
        final serviceName = order['service']['name'] ?? 'Service';
        final status = order['status'] ?? 'pending';
        final date = DateTime.parse(
          order['created_at'],
        ).toLocal().toString().split('.')[0];

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      OrderDetailPage(order: order, isProvider: true),
                ),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          serviceName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.deepPurple,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _getStatusColor(status).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _getStatusColor(status)),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            color: _getStatusColor(status),
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.person, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        'Client: $buyerName',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        size: 16,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        date,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Services'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.deepPurple,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.deepPurple,
          tabs: const [
            Tab(text: 'Pending & Active'),
            Tab(text: 'Completed'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOrderList(_pendingOrders, isCompleted: false),
                _buildOrderList(_completedOrders, isCompleted: true),
              ],
            ),
    );
  }
}
