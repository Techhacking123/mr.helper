import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_config.dart';
import '../auth/session_manager.dart';
import '../orders/order_detail.dart';
import '../marketplace/product_orders_page.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  bool _isSelectionMode = false;
  bool _isDeleting = false;
  Set<String> _selectedNotifications = {};
  late RealtimeChannel _channel;

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
    _setupRealtimeSubscription();
  }

  Future<void> _setupRealtimeSubscription() async {
    final userId = await SessionManager.getUserId();
    if (userId == null) return;

    _channel = SupabaseConfig.supabase
        .channel('public:notifications:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            debugPrint("New notification received! Payload: $payload");
            _fetchNotifications();
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    SupabaseConfig.supabase.removeChannel(_channel);
    super.dispose();
  }

  Future<void> _fetchNotifications() async {
    try {
      final userId = await SessionManager.getUserId();
      if (userId == null) return;

      // Fetch Notifications
      final response = await SupabaseConfig.supabase
          .from('notifications')
          .select(
            '*, order:orders(*, provider:users!provider_id(full_name), buyer:users!buyer_id(full_name), service:services(name))',
          )
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _notifications = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }

      // Mark all as read optionally, or do it one by one
      _markAllAsRead(userId);
    } catch (e) {
      debugPrint('Error fetching notifications: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markAllAsRead(String userId) async {
    try {
      await SupabaseConfig.supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);
    } catch (_) {}
  }

  void _handleNotificationTap(Map<String, dynamic> notification) {
    // If it's a product negotiation, route to product orders
    if (notification['type'] == 'product_negotiation') {
      SessionManager.getRole().then((role) {
        if (role == 'provider' && context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ProductOrdersPage(),
            ),
          );
        } else if (context.mounted) {
          // Note: for buyers, a full integration would link to their specific orders/negotiations page
          // For now, returning to user_home is appropriate, or if a user product orders page existed, we'd link there.
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      });
      return;
    }

    // If has order_id, navigate to OrderDetail
    // We already joined order data, so pass it if available
    final order = notification['order'];
    if (order != null) {
      SessionManager.getRole().then((role) {
        final isProvider = role == 'provider';
        if (context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  OrderDetailPage(order: order, isProvider: isProvider),
            ),
          );
        }
      });
    }
  }

  Future<void> _clearAllNotifications() async {
    // Enter selection mode instead of deleting all immediately
    setState(() {
      _isSelectionMode = true;
      _selectedNotifications.clear();
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedNotifications.length == _notifications.length) {
        // All selected, deselect all
        _selectedNotifications.clear();
      } else {
        // Select all
        _selectedNotifications = _notifications
            .map((n) => n['id'].toString())
            .toSet();
      }
    });
  }

  void _cancelSelection() {
    setState(() {
      _isSelectionMode = false;
      _selectedNotifications.clear();
    });
  }

  Future<void> _deleteSelectedNotifications() async {
    if (_selectedNotifications.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No notifications selected'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            'Delete ${_selectedNotifications.length} notification(s)?',
          ),
          content: const Text(
            'This will permanently delete the selected notifications. This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      // Show loading overlay
      setState(() => _isDeleting = true);

      // Convert to list
      final idsToDelete = _selectedNotifications.toList();

      // Batch delete all selected notifications in one call
      await SupabaseConfig.supabase
          .from('notifications')
          .delete()
          .inFilter('id', idsToDelete);

      // Remove from UI
      if (mounted) {
        setState(() {
          _notifications.removeWhere(
            (n) => idsToDelete.contains(n['id'].toString()),
          );
          _selectedNotifications.clear();
          _isSelectionMode = false;
          _isDeleting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selected notifications deleted'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error deleting notifications: $e');
      if (mounted) {
        setState(() => _isDeleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting notifications: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _cancelSelection,
              )
            : null,
        title: _isSelectionMode
            ? Text('${_selectedNotifications.length} selected')
            : const Text('Notifications'),
        actions: [
          if (_isSelectionMode) ...[
            IconButton(
              icon: Icon(
                _selectedNotifications.length == _notifications.length
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
              ),
              tooltip: 'Select All',
              onPressed: _toggleSelectAll,
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              tooltip: 'Delete Selected',
              onPressed: _deleteSelectedNotifications,
            ),
          ] else if (_notifications.isNotEmpty && !_isLoading)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Select to Delete',
              onPressed: _clearAllNotifications,
            ),
        ],
      ),
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildNotificationsList(),
          if (_isDeleting)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: Card(
                  elevation: 8,
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text(
                          'Deleting notifications...',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNotificationsList() {
    if (_notifications.isEmpty) {
      return const Center(child: Text('No notifications.'));
    }
    return ListView.separated(
      itemCount: _notifications.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final notif = _notifications[index];

        final dateId = notif['created_at'] ?? DateTime.now().toIso8601String();

        DateTime dateTime;
        try {
          dateTime = DateTime.parse(dateId).toLocal();
        } catch (_) {
          dateTime = DateTime.now();
        }
        final date = DateFormat('MMM d, y hh:mm a').format(dateTime);
        final isRead = notif['is_read'] ?? false;

        final title = notif['title'] ?? 'Notification';
        final body = notif['message'] ?? '';
        final type = notif['type'];
        final notifId = notif['id'].toString();
        final isSelected = _selectedNotifications.contains(notifId);

        return ListTile(
          tileColor: isRead ? null : Colors.blue.withOpacity(0.05),
          selected: _isSelectionMode && isSelected,
          selectedTileColor: Colors.blue.withOpacity(0.15),
          leading: _isSelectionMode
              ? Checkbox(
                  value: isSelected,
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _selectedNotifications.add(notifId);
                      } else {
                        _selectedNotifications.remove(notifId);
                      }
                    });
                  },
                )
              : CircleAvatar(
                  backgroundColor: type == 'chat_message'
                      ? Colors.blue.shade100
                      : Colors.orange.shade100,
                  child: Icon(
                    type == 'chat_message' ? Icons.chat : Icons.notifications,
                    color: type == 'chat_message'
                        ? Colors.blue.shade700
                        : Colors.orange.shade700,
                    size: 20,
                  ),
                ),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
              fontSize: 15,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (body.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 4),
                  child: Text(
                    body,
                    style: const TextStyle(color: Colors.black87),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              Text(
                date,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
          onTap: () {
            if (_isSelectionMode) {
              // Toggle selection
              setState(() {
                if (isSelected) {
                  _selectedNotifications.remove(notifId);
                } else {
                  _selectedNotifications.add(notifId);
                }
              });
            } else {
              _handleNotificationTap(notif);
            }
          },
        );
      },
    );
  }
}
