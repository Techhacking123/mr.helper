import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_config.dart';
import '../auth/session_manager.dart';
import 'order_detail.dart';

class UserOrdersPage extends StatefulWidget {
  const UserOrdersPage({super.key});

  @override
  State<UserOrdersPage> createState() => _UserOrdersPageState();
}

class _UserOrdersPageState extends State<UserOrdersPage> {
  List<Map<String, dynamic>> _orders = [];
  bool _isLoading = true;
  late RealtimeChannel _channel;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final uid = await SessionManager.getUserId();
    if (mounted) {
      if (uid != null) {
        _fetchOrders();
        _setupRealtime(uid);
      } else {
        setState(() => _isLoading = false);
      }
    }
  }

  void _setupRealtime(String uid) {
    debugPrint("Setting up realtime for orders with buyer_id: $uid");
    _channel = SupabaseConfig.supabase
        .channel('public:orders:user:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'buyer_id',
            value: uid,
          ),
          callback: (payload) {
            debugPrint("Order update received! Event: ${payload.eventType}");
            _fetchOrders();
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    SupabaseConfig.supabase.removeChannel(_channel);
    super.dispose();
  }

  Future<void> _fetchOrders() async {
    try {
      final userId = await SessionManager.getUserId();
      if (userId == null) return;

      // Fetch orders with provider details, service details
      final response = await SupabaseConfig.supabase
          .from('orders')
          .select(
            '*, provider:users!provider_id(full_name, phone_number, avatar_url), service:services(name), location:locations(name)',
          )
          .eq('buyer_id', userId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _orders = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } on PostgrestException catch (error) {
      debugPrint(
        'Postgrest Error fetching user orders: ${error.message} code: ${error.code} details: ${error.details}',
      );
      if (mounted) setState(() => _isLoading = false);
    } catch (e, stackTrace) {
      debugPrint('General Error fetching user orders: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getFriendlyStatus(String status) {
    switch (status.toLowerCase()) {
      case 'request_open':
        return 'Searching...';
      case 'pending':
        return 'Provider Found';
      case 'accepted':
        return 'In Progress';
      case 'confirmed':
        return 'In Progress';
      case 'in_progress': // Handle if you use this too
        return 'In Progress';
      case 'completed':
        return 'Completed';
      case 'expired':
        return 'Expired - No Provider Found';
      case 'cancelled':
        return 'Cancelled';
      case 'rejected':
        return 'Declined';
      default:
        return status.replaceAll('_', ' ').capitalize();
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'request_open':
        return Colors.orange.shade700;
      case 'pending':
        return Colors.purple.shade700;
      case 'accepted':
      case 'confirmed':
      case 'in_progress':
        return Colors.blue.shade700;
      case 'completed':
        return Colors.green.shade700;
      case 'expired':
        return Colors.brown.shade700;
      case 'cancelled':
      case 'rejected':
        return Colors.red.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  Color _getStatusBgColor(String status) {
    switch (status.toLowerCase()) {
      case 'request_open':
        return Colors.orange.shade50;
      case 'pending':
        return Colors.purple.shade50;
      case 'accepted':
      case 'confirmed':
      case 'in_progress':
        return Colors.blue.shade50;
      case 'completed':
        return Colors.green.shade50;
      case 'expired':
        return Colors.brown.shade50;
      case 'cancelled':
      case 'rejected':
        return Colors.red.shade50;
      default:
        return Colors.grey.shade100;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('My Bookings'),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _orders.isEmpty
          ? Center(
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
                    'No bookings yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your requested services will appear here.',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _orders.length,
              itemBuilder: (context, index) {
                final order = _orders[index];
                final providerName =
                    (order['provider'] != null &&
                        order['provider']['full_name'] != null)
                    ? order['provider']['full_name']
                    : null;

                final serviceName = order['service'] != null
                    ? order['service']['name']
                    : 'Custom Service';

                final rawStatus = order['status'] ?? 'Unknown';
                final createdAt = DateTime.parse(order['created_at']);

                // Client-side expiry check
                // If status is 'request_open' and it's been more than 24 hours
                String effectiveStatus = rawStatus;
                if (rawStatus == 'request_open') {
                  final now = DateTime.now();
                  final diff = now.difference(createdAt);
                  if (diff.inHours >= 24) {
                    effectiveStatus = 'expired';
                  }
                }

                final friendlyStatus = _getFriendlyStatus(effectiveStatus);
                final statusColor = _getStatusColor(effectiveStatus);
                final statusBgColor = _getStatusBgColor(effectiveStatus);

                // Parse Date
                final dateStr =
                    "${createdAt.day}/${createdAt.month}/${createdAt.year}";

                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            OrderDetailPage(order: order, isProvider: false),
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
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Header: Status and ID
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(16),
                            ),
                            border: Border(
                              bottom: BorderSide(color: Colors.grey.shade200),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'ID: #${order['id'].toString().substring(0, 8)}...',
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: statusBgColor,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _getStatusIcon(effectiveStatus),
                                      size: 14,
                                      color: statusColor,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      friendlyStatus,
                                      style: TextStyle(
                                        color: statusColor,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Body: Service & Provider
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.handyman,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      serviceName,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    if (providerName != null)
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.person,
                                            size: 14,
                                            color: Colors.grey,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            providerName,
                                            style: TextStyle(
                                              color: Colors.grey.shade700,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      )
                                    else if (effectiveStatus == 'expired')
                                      Text(
                                        'No providers accepted.',
                                        style: TextStyle(
                                          color: Colors.brown.shade600,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      )
                                    else if (effectiveStatus == 'rejected')
                                      Text(
                                        'Request was declined.',
                                        style: TextStyle(
                                          color: Colors.red.shade600,
                                          fontSize: 12,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      )
                                    else
                                      Text(
                                        'Waiting for provider to accept...',
                                        style: TextStyle(
                                          color: Colors.orange.shade700,
                                          fontSize: 12,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),

                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.calendar_today,
                                          size: 12,
                                          color: Colors.grey,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          dateStr,
                                          style: TextStyle(
                                            color: Colors.grey.shade500,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                color: Colors.grey.shade300,
                              ),
                            ],
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

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'request_open':
        return Icons.search;
      case 'pending':
        return Icons.hourglass_empty;
      case 'accepted':
        return Icons.build;
      case 'completed':
        return Icons.check_circle;
      case 'expired':
        return Icons.timer_off;
      case 'cancelled':
        return Icons.cancel;
      case 'rejected':
        return Icons.block;
      default:
        return Icons.info;
    }
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}
