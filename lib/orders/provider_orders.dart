import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../supabase_config.dart';
import '../auth/session_manager.dart';
import 'order_detail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../firebase/fcm_service.dart';
import '../services/otp_verification_service.dart';

class ProviderOrdersPage extends StatefulWidget {
  const ProviderOrdersPage({super.key});

  @override
  State<ProviderOrdersPage> createState() => _ProviderOrdersPageState();
}

class _ProviderOrdersPageState extends State<ProviderOrdersPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _allOrders = [];
  bool _isLoading = true;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchOrders();
    _setupRealtime();
  }

  void _setupRealtime() {
    _channel = SupabaseConfig.supabase
        .channel('public:provider_orders')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (payload) {
            // Simple approach: Refetch on any order change.
            // We could filter closer, but strict RLS might limit what we see anyway.
            // Ideally we check if provider_id matches or if it affects us,
            // but refetching is safe and ensures exact state.
            _fetchOrders();
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) SupabaseConfig.supabase.removeChannel(_channel!);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchOrders() async {
    try {
      final userId = await SessionManager.getUserId();
      if (userId == null) return;

      final response = await SupabaseConfig.supabase
          .from('orders')
          .select(
            '*, buyer:users!buyer_id(full_name, phone_number, avatar_url), service:services(name), locations(name)',
          )
          .eq('provider_id', userId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _allOrders = List<Map<String, dynamic>>.from(response);
          if (_allOrders.isNotEmpty) {
            debugPrint('First Order Debug: ${_allOrders.first}');
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching provider orders: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateStatus(
    String orderId,
    String buyerId,
    String newStatus, {
    double? price,
  }) async {
    try {
      // Optimistic Update
      setState(() {
        final index = _allOrders.indexWhere((o) => o['id'] == orderId);
        if (index != -1) {
          _allOrders[index]['status'] = newStatus;
          if (price != null) {
            _allOrders[index]['price'] = price;
          }
        }
      });

      final Map<String, dynamic> updateData = {'status': newStatus};
      if (newStatus == 'accepted' && price != null) {
        updateData['price'] = price;
      }

      await SupabaseConfig.supabase
          .from('orders')
          .update(updateData)
          .eq('id', orderId);

      // Set 24-hour OTP verification deadline when provider accepts
      if (newStatus == 'accepted') {
        await OtpVerificationService.setOtpDeadline(orderId);
      }

      // Notification logic with push notification
      String msg = '';
      String title = 'Order Update';
      if (newStatus == 'accepted') {
        msg = 'Your order has been accepted!';
        title = 'Order Accepted';
      } else if (newStatus == 'rejected') {
        msg = 'Your order has been rejected.';
        title = 'Order Rejected';
      } else if (newStatus == 'completed') {
        msg = 'Your order has been marked as completed!';
        title = 'Order Completed';
      }

      if (msg.isNotEmpty) {
        await FCMService.sendPushNotificationToUser(
          userId: buyerId,
          title: title,
          message: msg,
          screen: 'order_detail',
          orderId: orderId,
        );
      }

      _fetchOrders(); // Refresh to be sure
    } catch (e) {
      debugPrint('Error updating status: $e');
      _fetchOrders(); // Revert on error
    }
  }

  List<Map<String, dynamic>> _getOrdersByStatus(List<String> statuses) {
    return _allOrders.where((o) => statuses.contains(o['status'])).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'My Work',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: 'Active'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOrderList(
                  _getOrdersByStatus([
                    'accepted',
                    'confirmed',
                    'in_progress',
                    'working',
                    'verified',
                  ]),
                ),
                _buildOrderList(
                  _getOrdersByStatus(['completed', 'rejected', 'cancelled']),
                ),
              ],
            ),
    );
  }

  Widget _buildOrderList(List<Map<String, dynamic>> orders) {
    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.assignment_outlined,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'No orders here yet',
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
        return _buildOrderCard(orders[index]);
      },
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final buyerName = order['buyer']?['full_name'] ?? 'Unknown User';
    final serviceName = order['service']?['name'] ?? 'Service';
    final locationName =
        order['locations']?['name'] ??
        order['address_gps'] ??
        'Unknown Location';
    final status = order['status'] ?? 'pending';
    final price = order['price'] ?? order['user_price'] ?? 0;
    final date = order['created_at'] != null
        ? DateFormat(
            'MMM dd, hh:mm a',
          ).format(DateTime.parse(order['created_at']).toLocal())
        : '';

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OrderDetailPage(order: order, isProvider: true),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header with Status Color
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _getStatusColor(status).withOpacity(0.1),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 12,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          date,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getStatusColor(status),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status.toString().toUpperCase().replaceAll('_', ' '),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.deepPurple.shade50,
                        radius: 24,
                        child: Text(
                          buyerName.isNotEmpty
                              ? buyerName[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: Colors.deepPurple.shade700,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              buyerName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              serviceName,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.deepPurple.shade400,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on,
                                  size: 14,
                                  color: Colors.grey.shade500,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    locationName,
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'Price',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          Text(
                            '₹$price',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),

                  // Action Buttons based on status
                  // Action Buttons based on status
                  if (status == 'pending' || status == 'negotiating')
                    if (order['last_offer_by'] == 'provider')
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.hourglass_empty_rounded,
                              color: Colors.orange.shade700,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Waiting for user response',
                              style: TextStyle(
                                color: Colors.orange.shade800,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: _buildActionButton(
                              'Reject',
                              Colors.red.shade50,
                              Colors.red,
                              () => _updateStatus(
                                order['id'],
                                order['buyer_id'],
                                'rejected',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildActionButton(
                              'Accept Details',
                              Colors.deepPurple,
                              Colors.white,
                              // Open details to accept with logic, strictly strictly speaking simple accept here
                              () => _updateStatus(
                                order['id'],
                                order['buyer_id'],
                                'accepted',
                                price: double.tryParse(price.toString()),
                              ),
                            ),
                          ),
                        ],
                      )
                  else if (status == 'accepted')
                    Row(
                      children: [
                        Expanded(
                          child: _buildActionButton(
                            'View Details',
                            Colors.grey.shade100,
                            Colors.black87,
                            () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => OrderDetailPage(
                                    order: order,
                                    isProvider: true,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final lat = order['latitude'];
                              final lng = order['longitude'];
                              if (lat != null && lng != null) {
                                final uri = Uri.parse(
                                  'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
                                );
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(
                                    uri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                }
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Location not available'),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.map, size: 18),
                            label: const Text('View Location'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade50,
                              foregroundColor: Colors.blue.shade700,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.phone, color: Colors.green),
                            onPressed: () async {
                              final phone = order['buyer']?['phone_number'];
                              if (phone != null) {
                                final uri = Uri.parse('tel:$phone');
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri);
                                }
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("No phone number"),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    )
                  else
                    Center(
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => OrderDetailPage(
                                order: order,
                                isProvider: true,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('View Receipt'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
    String label,
    Color bg,
    Color fg,
    VoidCallback onTap,
  ) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
      case 'confirmed':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'cancelled':
        return Colors.grey;
      case 'negotiating':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }
}
