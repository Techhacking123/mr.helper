import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../supabase_config.dart';

class AdminSendNotificationPage extends StatefulWidget {
  const AdminSendNotificationPage({super.key});

  @override
  State<AdminSendNotificationPage> createState() =>
      _AdminSendNotificationPageState();
}

class _AdminSendNotificationPageState extends State<AdminSendNotificationPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();

  String _recipientType = 'all_users';
  List<Map<String, dynamic>> _selectedUsers = [];
  List<Map<String, dynamic>> _availableUsers = [];
  bool _isLoadingUsers = false;

  DateTime? _scheduledDateTime;
  bool _isScheduled = false;

  bool _isSending = false;

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoadingUsers = true);

    try {
      final isProvider = _recipientType == 'selected_providers';

      // Use RPC function to bypass RLS
      final response = await SupabaseConfig.supabase.rpc(
        'get_users_for_admin',
        params: {'p_is_provider': isProvider},
      );

      setState(() {
        _availableUsers = List<Map<String, dynamic>>.from(response);
        _isLoadingUsers = false;
      });
    } catch (e) {
      debugPrint('Error loading users: $e');
      setState(() => _isLoadingUsers = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading users: $e')));
      }
    }
  }

  Future<void> _selectScheduleDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(hours: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (date != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(
          DateTime.now().add(const Duration(hours: 1)),
        ),
      );

      if (time != null) {
        setState(() {
          _scheduledDateTime = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }

  Future<void> _sendNotification() async {
    if (!_formKey.currentState!.validate()) return;

    if (_recipientType.startsWith('selected_') && _selectedUsers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one recipient')),
      );
      return;
    }

    if (_isScheduled && _scheduledDateTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a schedule date and time')),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      final recipientIds = _selectedUsers.map((u) => u['id']).toList();

      await SupabaseConfig.adminClient.from('scheduled_notifications').insert({
        'title': _titleController.text.trim(),
        'message': _messageController.text.trim(),
        'recipient_type': _recipientType,
        'recipient_ids': recipientIds,
        'scheduled_at': _isScheduled && _scheduledDateTime != null
            ? _scheduledDateTime!.toIso8601String()
            : null,
        'status': 'pending',
        'created_by': SupabaseConfig.supabase.auth.currentUser?.id,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isScheduled
                  ? 'Notification scheduled successfully!'
                  : 'Notification sent successfully!',
            ),
            backgroundColor: Colors.green,
          ),
        );

        // Reset form
        _titleController.clear();
        _messageController.clear();
        setState(() {
          _selectedUsers.clear();
          _scheduledDateTime = null;
          _isScheduled = false;
        });
      }
    } catch (e) {
      debugPrint('Error sending notification: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Push Notification'),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdminNotificationHistoryPage(),
                ),
              );
            },
            icon: const Icon(Icons.history, color: Colors.white),
            label: const Text('History', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Title Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Notification Details',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.title),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a title';
                        }
                        return null;
                      },
                      maxLength: 100,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        labelText: 'Message',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.message),
                      ),
                      maxLines: 4,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a message';
                        }
                        return null;
                      },
                      maxLength: 500,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Recipients Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Recipients',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _recipientType,
                      decoration: const InputDecoration(
                        labelText: 'Recipient Type',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.people),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'all_users',
                          child: Text('All Users'),
                        ),
                        DropdownMenuItem(
                          value: 'all_providers',
                          child: Text('All Providers'),
                        ),
                        DropdownMenuItem(
                          value: 'selected_users',
                          child: Text('Select Users'),
                        ),
                        DropdownMenuItem(
                          value: 'selected_providers',
                          child: Text('Select Providers'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _recipientType = value!;
                          _selectedUsers.clear();
                          _availableUsers.clear();
                        });
                      },
                    ),
                    if (_recipientType.startsWith('selected_')) ...[
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _isLoadingUsers ? null : _loadUsers,
                        icon: _isLoadingUsers
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh),
                        label: Text(
                          _isLoadingUsers
                              ? 'Loading...'
                              : 'Load ${_recipientType == "selected_users" ? "Users" : "Providers"}',
                        ),
                      ),
                      if (_availableUsers.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 300),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _availableUsers.length,
                            itemBuilder: (context, index) {
                              final user = _availableUsers[index];
                              final isSelected = _selectedUsers.any(
                                (u) => u['id'] == user['id'],
                              );

                              return CheckboxListTile(
                                title: Text(user['full_name'] ?? 'Unknown'),
                                subtitle: Text(
                                  user['email'] ??
                                      user['phone'] ??
                                      'No contact',
                                ),
                                value: isSelected,
                                onChanged: (selected) {
                                  setState(() {
                                    if (selected == true) {
                                      _selectedUsers.add(user);
                                    } else {
                                      _selectedUsers.removeWhere(
                                        (u) => u['id'] == user['id'],
                                      );
                                    }
                                  });
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Selected: ${_selectedUsers.length} of ${_availableUsers.length}',
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_selectedUsers.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _selectedUsers.map((user) {
                              return Chip(
                                label: Text(user['full_name'] ?? 'Unknown'),
                                deleteIcon: const Icon(Icons.close, size: 18),
                                onDeleted: () {
                                  setState(() {
                                    _selectedUsers.removeWhere(
                                      (u) => u['id'] == user['id'],
                                    );
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Schedule Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Schedule',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Schedule for later'),
                      subtitle: Text(
                        _isScheduled
                            ? 'Notification will be sent at scheduled time'
                            : 'Notification will be sent immediately',
                      ),
                      value: _isScheduled,
                      onChanged: (value) {
                        setState(() {
                          _isScheduled = value;
                          if (!value) _scheduledDateTime = null;
                        });
                      },
                    ),
                    if (_isScheduled) ...[
                      const SizedBox(height: 16),
                      ListTile(
                        leading: const Icon(Icons.calendar_today),
                        title: Text(
                          _scheduledDateTime == null
                              ? 'Select Date & Time'
                              : DateFormat(
                                  'MMM dd, yyyy - hh:mm a',
                                ).format(_scheduledDateTime!),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios),
                        onTap: _selectScheduleDateTime,
                        tileColor: Colors.grey[100],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Send Button
            ElevatedButton.icon(
              onPressed: _isSending ? null : _sendNotification,
              icon: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(_isScheduled ? Icons.schedule_send : Icons.send),
              label: Text(
                _isSending
                    ? 'Sending...'
                    : _isScheduled
                    ? 'Schedule Notification'
                    : 'Send Now',
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// History Page to view sent/scheduled notifications
class AdminNotificationHistoryPage extends StatefulWidget {
  const AdminNotificationHistoryPage({super.key});

  @override
  State<AdminNotificationHistoryPage> createState() =>
      _AdminNotificationHistoryPageState();
}

class _AdminNotificationHistoryPageState
    extends State<AdminNotificationHistoryPage> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);

    try {
      final response = await SupabaseConfig.supabase
          .from('scheduled_notifications')
          .select()
          .order('created_at', ascending: false)
          .limit(50);

      setState(() {
        _notifications = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading notifications: $e');
      setState(() => _isLoading = false);
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'sent':
        return Colors.green;
      case 'scheduled':
        return Colors.blue;
      case 'failed':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  IconData _getRecipientIcon(String recipientType) {
    switch (recipientType) {
      case 'all_users':
        return Icons.people;
      case 'all_providers':
        return Icons.business;
      case 'selected_users':
        return Icons.person_outline;
      case 'selected_providers':
        return Icons.store_outlined;
      default:
        return Icons.notification_important;
    }
  }

  String _getRecipientLabel(String recipientType) {
    switch (recipientType) {
      case 'all_users':
        return 'All Users';
      case 'all_providers':
        return 'All Providers';
      case 'selected_users':
        return 'Selected Users';
      case 'selected_providers':
        return 'Selected Providers';
      default:
        return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadNotifications,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No notifications sent yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _notifications.length,
              itemBuilder: (context, index) {
                final notif = _notifications[index];
                final status = notif['status'] ?? 'pending';
                final recipientType = notif['recipient_type'] ?? '';

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: ExpansionTile(
                    leading: Icon(
                      _getRecipientIcon(recipientType),
                      color: _getStatusColor(status),
                    ),
                    title: Text(
                      notif['title'] ?? 'No Title',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _getStatusColor(status),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                status.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _getRecipientLabel(recipientType),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (notif['scheduled_at'] != null)
                          Text(
                            'Scheduled: ${DateFormat('MMM dd, hh:mm a').format(DateTime.parse(notif['scheduled_at']))}',
                            style: const TextStyle(fontSize: 12),
                          )
                        else if (notif['sent_at'] != null)
                          Text(
                            'Sent: ${DateFormat('MMM dd, hh:mm a').format(DateTime.parse(notif['sent_at']))}',
                            style: const TextStyle(fontSize: 12),
                          )
                        else
                          Text(
                            'Created: ${DateFormat('MMM dd, hh:mm a').format(DateTime.parse(notif['created_at']))}',
                            style: const TextStyle(fontSize: 12),
                          ),
                      ],
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Message:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(notif['message'] ?? 'No message'),
                            const Divider(height: 24),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildInfoChip(
                                    'Sent',
                                    '${notif['sent_count'] ?? 0}',
                                    Colors.green,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _buildInfoChip(
                                    'Failed',
                                    '${notif['failed_count'] ?? 0}',
                                    Colors.red,
                                  ),
                                ),
                              ],
                            ),
                            if (notif['error_message'] != null) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.red[50],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.error,
                                      color: Colors.red,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        notif['error_message'],
                                        style: const TextStyle(
                                          color: Colors.red,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildInfoChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}
