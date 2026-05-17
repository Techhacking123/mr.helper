import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminNotificationsPage extends StatefulWidget {
  const AdminNotificationsPage({super.key});

  @override
  State<AdminNotificationsPage> createState() => _AdminNotificationsPageState();
}

class _AdminNotificationsPageState extends State<AdminNotificationsPage> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  late final RealtimeChannel _subscription;

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    SupabaseConfig.supabase.removeChannel(_subscription);
    super.dispose();
  }

  void _subscribeToRealtime() {
    _subscription = SupabaseConfig.supabase.channel('admin_notifications_list');
    _subscription
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          callback: (payload) => _fetchNotifications(),
        )
        .subscribe();
  }

  Future<void> _fetchNotifications() async {
    try {
      final response = await SupabaseConfig.supabase
          .from('notifications')
          .select('*, users(full_name)')
          .order('created_at', ascending: false)
          .limit(50); // Limit to last 50 for performance

      if (mounted) {
        setState(() {
          _notifications = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching notifications: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('System Notifications (Last 50)')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _notifications.length,
              itemBuilder: (context, index) {
                final notif = _notifications[index];
                final user = notif['users'] ?? {'full_name': 'Unknown'};
                final bool isRead = notif['is_read'] ?? false;

                return Card(
                  color: isRead ? Colors.white : Colors.blue.shade50,
                  margin: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  child: ListTile(
                    leading: Icon(
                      Icons.notifications,
                      color: isRead ? Colors.grey : Colors.blue,
                    ),
                    title: Text(notif['message'] ?? 'No Message'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('To: ${user['full_name']}'),
                        if (notif['order_id'] != null)
                          Text(
                            'Order ID: ${notif['order_id']}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                        Text(
                          DateFormat.yMMMd().add_jm().format(
                            DateTime.parse(notif['created_at']),
                          ),
                          style: const TextStyle(fontSize: 10),
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
