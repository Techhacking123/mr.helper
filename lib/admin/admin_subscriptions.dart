import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../supabase_config.dart';

class AdminSubscriptionsPage extends StatefulWidget {
  const AdminSubscriptionsPage({super.key});

  @override
  State<AdminSubscriptionsPage> createState() => _AdminSubscriptionsPageState();
}

class _AdminSubscriptionsPageState extends State<AdminSubscriptionsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;

  // Statistics
  int _totalProviders = 0;
  int _activeSubscriptions = 0;
  int _expiredSubscriptions = 0;
  int _cancelledByAdmin = 0;

  // Providers data
  List<Map<String, dynamic>> _activeProviders = [];
  List<Map<String, dynamic>> _expiredProviders = [];
  List<Map<String, dynamic>> _cancelledProviders = [];
  List<Map<String, dynamic>> _subscriptionHistory = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([_loadStatistics(), _loadProviders()]);
    } catch (e) {
      debugPrint('Error loading data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadStatistics() async {
    try {
      final response = await SupabaseConfig.supabase.rpc(
        'get_subscription_stats',
      );

      if (response != null) {
        setState(() {
          _totalProviders = response['total_providers'] ?? 0;
          _activeSubscriptions = response['active_subscriptions'] ?? 0;
          _expiredSubscriptions = response['expired_subscriptions'] ?? 0;
          _cancelledByAdmin = response['cancelled_by_admin'] ?? 0;
        });
      }
    } catch (e) {
      debugPrint('Error loading stats: $e');
    }
  }

  Future<void> _loadProviders() async {
    try {
      debugPrint('🔍 Loading providers data...');

      // Active subscriptions
      final active = await SupabaseConfig.supabase
          .from('users')
          .select('id, full_name, email, subscription_expiry, services(name)')
          .eq('is_provider', true)
          .eq('is_subscribed', true)
          .gt('subscription_expiry', DateTime.now().toIso8601String())
          .order('subscription_expiry', ascending: true);

      debugPrint('✅ Active providers query returned: ${active.length} results');

      // Expired subscriptions
      final expired = await SupabaseConfig.supabase
          .from('users')
          .select('id, full_name, email, subscription_expiry, services(name)')
          .eq('is_provider', true)
          .eq('is_subscribed', true)
          .lte('subscription_expiry', DateTime.now().toIso8601String())
          .order('subscription_expiry', ascending: false);

      debugPrint(
        '✅ Expired providers query returned: ${expired.length} results',
      );

      // Cancelled by admin
      final cancelled = await SupabaseConfig.supabase
          .from('users')
          .select(
            'id, full_name, email, cancelled_at, cancellation_reason, services(name)',
          )
          .eq('is_provider', true)
          .eq('cancelled_by_admin', true)
          .order('cancelled_at', ascending: false);

      debugPrint(
        '✅ Cancelled providers query returned: ${cancelled.length} results',
      );

      setState(() {
        _activeProviders = List<Map<String, dynamic>>.from(active);
        _expiredProviders = List<Map<String, dynamic>>.from(expired);
        _cancelledProviders = List<Map<String, dynamic>>.from(cancelled);
      });

      debugPrint(
        '📊 Summary: ${active.length} active, ${expired.length} expired, ${cancelled.length} cancelled',
      );
    } catch (e) {
      debugPrint('❌ Error loading providers: $e');
    }
  }

  Future<void> _cancelSubscription(
    String providerId,
    String providerName,
  ) async {
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cancel Subscription - $providerName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to cancel this provider\'s subscription?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Cancellation Reason*',
                hintText: 'Enter reason for cancellation...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Provider will receive a notification about this cancellation.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No, Keep Subscription'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a reason')),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('Yes, Cancel Subscription'),
          ),
        ],
      ),
    );

    if (confirmed == true && reasonController.text.trim().isNotEmpty) {
      try {
        final adminId = await SupabaseConfig.supabase.auth.currentUser?.id;

        final result = await SupabaseConfig.supabase.rpc(
          'admin_cancel_subscription',
          params: {
            'p_provider_id': providerId,
            'p_admin_id': adminId,
            'p_reason': reasonController.text.trim(),
          },
        );

        if (mounted) {
          if (result['success'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Subscription cancelled for $providerName'),
                backgroundColor: Colors.green,
              ),
            );
            _loadData(); // Reload data
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(result['message'] ?? 'Failed to cancel'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _showProviderHistory(
    String providerId,
    String providerName,
  ) async {
    setState(() => _isLoading = true);

    try {
      final history = await SupabaseConfig.supabase
          .from('subscription_history')
          .select('*')
          .eq('provider_id', providerId)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _subscriptionHistory = List<Map<String, dynamic>>.from(history);
          _isLoading = false;
        });

        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => DraggableScrollableSheet(
            initialChildSize: 0.9,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (_, controller) => Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // Handle bar
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.history, color: Colors.deepPurple),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Subscription History - $providerName',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // History list
                  Expanded(
                    child: _subscriptionHistory.isEmpty
                        ? const Center(child: Text('No history found'))
                        : ListView.builder(
                            controller: controller,
                            itemCount: _subscriptionHistory.length,
                            itemBuilder: (context, index) {
                              final record = _subscriptionHistory[index];
                              return _buildHistoryItem(record);
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error loading history: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildHistoryItem(Map<String, dynamic> record) {
    final action = record['action'] as String;
    final createdAt = DateTime.parse(record['created_at']);

    IconData icon;
    Color color;
    String title;

    switch (action) {
      case 'activated':
        icon = Icons.check_circle;
        color = Colors.green;
        title = 'Subscription Activated';
        break;
      case 'renewed':
        icon = Icons.refresh;
        color = Colors.blue;
        title = 'Subscription Renewed';
        break;
      case 'expired':
        icon = Icons.timer_off;
        color = Colors.orange;
        title = 'Subscription Expired';
        break;
      case 'cancelled_by_admin':
        icon = Icons.cancel;
        color = Colors.red;
        title = 'Cancelled by Admin';
        break;
      default:
        icon = Icons.info;
        color = Colors.grey;
        title = action;
    }

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 24),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(DateFormat('MMM dd, yyyy - hh:mm a').format(createdAt)),
          if (record['cancellation_reason'] != null)
            Text(
              'Reason: ${record['cancellation_reason']}',
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          if (record['previous_expiry'] != null || record['new_expiry'] != null)
            Text(
              'Expiry: ${record['previous_expiry'] != null ? DateFormat('MMM dd, yyyy').format(DateTime.parse(record['previous_expiry'])) : 'None'} → ${record['new_expiry'] != null ? DateFormat('MMM dd, yyyy').format(DateTime.parse(record['new_expiry'])) : 'None'}',
              style: const TextStyle(fontSize: 12),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription Management'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Active', icon: Icon(Icons.check_circle_outline)),
            Tab(text: 'Expired', icon: Icon(Icons.timer_off_outlined)),
            Tab(text: 'Cancelled', icon: Icon(Icons.cancel_outlined)),
            Tab(text: 'Stats', icon: Icon(Icons.analytics_outlined)),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildActiveTab(),
                  _buildExpiredTab(),
                  _buildCancelledTab(),
                  _buildStatsTab(),
                ],
              ),
            ),
    );
  }

  Widget _buildActiveTab() {
    if (_activeProviders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info_outline, size: 64, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              const Text(
                'No active subscriptions found',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Need to activate a provider subscription?\nRun DEBUG_SUBSCRIPTIONS.sql in Supabase',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              if (_totalProviders > 0)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Found $_totalProviders provider(s) total',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'But none have active subscriptions',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh),
                label: const Text('Reload Data'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _activeProviders.length,
      itemBuilder: (context, index) {
        final provider = _activeProviders[index];
        return _buildProviderCard(
          provider,
          isActive: true,
          expiryDate: DateTime.parse(provider['subscription_expiry']),
        );
      },
    );
  }

  Widget _buildExpiredTab() {
    if (_expiredProviders.isEmpty) {
      return const Center(child: Text('No expired subscriptions'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _expiredProviders.length,
      itemBuilder: (context, index) {
        final provider = _expiredProviders[index];
        return _buildProviderCard(
          provider,
          isExpired: true,
          expiryDate: DateTime.parse(provider['subscription_expiry']),
        );
      },
    );
  }

  Widget _buildCancelledTab() {
    if (_cancelledProviders.isEmpty) {
      return const Center(child: Text('No cancelled subscriptions'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _cancelledProviders.length,
      itemBuilder: (context, index) {
        final provider = _cancelledProviders[index];
        return _buildProviderCard(
          provider,
          isCancelled: true,
          cancelledDate: provider['cancelled_at'] != null
              ? DateTime.parse(provider['cancelled_at'])
              : null,
        );
      },
    );
  }

  Widget _buildProviderCard(
    Map<String, dynamic> provider, {
    bool isActive = false,
    bool isExpired = false,
    bool isCancelled = false,
    DateTime? expiryDate,
    DateTime? cancelledDate,
  }) {
    final serviceName = provider['services'] != null
        ? provider['services']['name']
        : 'Unknown Service';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: isActive
                      ? Colors.green.shade100
                      : isExpired
                      ? Colors.orange.shade100
                      : Colors.red.shade100,
                  child: Icon(
                    isActive
                        ? Icons.check_circle
                        : isExpired
                        ? Icons.timer_off
                        : Icons.cancel,
                    color: isActive
                        ? Colors.green
                        : isExpired
                        ? Colors.orange
                        : Colors.red,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provider['full_name'] ?? 'Unknown',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        serviceName,
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (provider['email'] != null)
              Row(
                children: [
                  Icon(Icons.email, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(provider['email'], style: const TextStyle(fontSize: 14)),
                ],
              ),
            // Phone field not available in database
            // if (provider['phone'] != null)
            //   Row(
            //     children: [
            //       Icon(Icons.phone, size: 16, color: Colors.grey[600]),
            //       const SizedBox(width: 8),
            //       Text(provider['phone'], style: const TextStyle(fontSize: 14)),
            //     ],
            //   ),
            if (expiryDate != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    isExpired
                        ? 'Expired: ${DateFormat('MMM dd, yyyy').format(expiryDate)}'
                        : 'Expires: ${DateFormat('MMM dd, yyyy').format(expiryDate)}',
                    style: TextStyle(
                      fontSize: 14,
                      color: isExpired ? Colors.red : Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (isActive)
                    Text(
                      ' (${expiryDate.difference(DateTime.now()).inDays} days left)',
                      style: const TextStyle(fontSize: 12),
                    ),
                ],
              ),
            ],
            if (isCancelled && provider['cancellation_reason'] != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        provider['cancellation_reason'],
                        style: const TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _showProviderHistory(
                    provider['id'],
                    provider['full_name'],
                  ),
                  icon: const Icon(Icons.history, size: 16),
                  label: const Text('History'),
                ),
                if (isActive) ...[
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _cancelSubscription(
                      provider['id'],
                      provider['full_name'],
                    ),
                    icon: const Icon(Icons.cancel, size: 16),
                    label: const Text('Cancel'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildStatCard(
            'Total Providers',
            _totalProviders.toString(),
            Icons.people,
            Colors.blue,
          ),
          _buildStatCard(
            'Active Subscriptions',
            _activeSubscriptions.toString(),
            Icons.check_circle,
            Colors.green,
          ),
          _buildStatCard(
            'Expired Subscriptions',
            _expiredSubscriptions.toString(),
            Icons.timer_off,
            Colors.orange,
          ),
          _buildStatCard(
            'Cancelled by Admin',
            _cancelledByAdmin.toString(),
            Icons.cancel,
            Colors.red,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 32, color: color),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
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
}
