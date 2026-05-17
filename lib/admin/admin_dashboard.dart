import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_config.dart';
import '../auth/login.dart';
import 'admin_users.dart';
import 'admin_reports.dart';
import 'admin_orders.dart';
import 'admin_notifications.dart';
import 'admin_send_notification.dart';
import 'admin_ads.dart';
import 'admin_kyc.dart';
import 'admin_services.dart';
import 'admin_subscriptions.dart';
import 'admin_themes.dart';
import 'admin_delete_requests.dart';
import 'admin_red_stars.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _userCount = 0;
  int _providerCount = 0;
  int _orderCount = 0;
  int _reportCount = 0;

  bool _isLoading = true;

  late final RealtimeChannel _subscription;

  @override
  void initState() {
    super.initState();
    _fetchStats();
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    SupabaseConfig.supabase.removeChannel(_subscription);
    super.dispose();
  }

  void _subscribeToRealtime() {
    _subscription = SupabaseConfig.supabase.channel('admin_dashboard_stats');
    _subscription
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'users',
          callback: (payload) => _fetchStats(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (payload) => _fetchStats(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'reports',
          callback: (payload) => _fetchStats(),
        )
        .subscribe();
  }

  Future<void> _fetchStats() async {
    try {
      final users = await SupabaseConfig.supabase
          .from('users')
          .select('id')
          .eq('is_provider', false);
      final providers = await SupabaseConfig.supabase
          .from('users')
          .select('id')
          .eq('is_provider', true);
      final orders = await SupabaseConfig.supabase.from('orders').select('id');
      final reports = await SupabaseConfig.supabase
          .from('reports')
          .select('id');

      if (mounted) {
        setState(() {
          _userCount = (users as List).length;
          _providerCount = (providers as List).length;
          _orderCount = (orders as List).length;
          _reportCount = (reports as List).length;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching admin stats: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _logout() async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.deepPurple,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Logging out...',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    // Wait a moment for the animation to show
    await Future.delayed(const Duration(milliseconds: 800));

    // Navigate to login
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchStats,
              child: CustomScrollView(
                slivers: [
                  _buildSliverAppBar(),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Overview",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildStatsGrid(),
                          const SizedBox(height: 24),
                          const Text(
                            "Quick Actions",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildActionGrid(context),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 180.0,
      floating: false,
      pinned: true,
      backgroundColor: Colors.deepPurple,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.deepPurple.shade900,
                Colors.deepPurple.shade500,
                Colors.purple.shade300,
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -30,
                top: -30,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Positioned(
                left: 20,
                bottom: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      'Hello, Admin',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Dashboard',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        IconButton(
          onPressed: _logout,
          icon: const Icon(Icons.logout, color: Colors.white),
        ),
      ],
    );
  }

  Widget _buildStatsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _StatCard(
          title: 'Users',
          count: _userCount,
          icon: Icons.person_outline,
          color: Colors.blueAccent,
        ),
        _StatCard(
          title: 'Providers',
          count: _providerCount,
          icon: Icons.engineering_outlined,
          color: Colors.orangeAccent,
        ),
        _StatCard(
          title: 'Orders',
          count: _orderCount,
          icon: Icons.shopping_cart_outlined,
          color: Colors.greenAccent,
        ),
        _StatCard(
          title: 'Active Reports',
          count: _reportCount,
          icon: Icons.report_gmailerrorred_outlined,
          color: Colors.redAccent,
        ),
      ],
    );
  }

  Widget _buildActionGrid(BuildContext context) {
    // Actions List
    final actions = [
      _ActionItem(
        title: 'Pending Approvals',
        icon: Icons.verified_user_outlined,
        color: Colors.orange,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminKycPage()),
        ),
      ),
      _ActionItem(
        title: 'Manage Users',
        icon: Icons.people_alt_outlined,
        color: Colors.blue,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminUsersPage()),
        ),
      ),
      _ActionItem(
        title: 'View Orders',
        icon: Icons.receipt_long_outlined,
        color: Colors.indigo,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminOrdersPage()),
        ),
      ),
      _ActionItem(
        title: 'Reports',
        icon: Icons.warning_amber_rounded,
        color: Colors.red,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminReportsPage()),
        ),
      ),
      _ActionItem(
        title: 'Manage Services',
        icon: Icons.category_outlined,
        color: Colors.brown,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminServicesPage()),
        ),
      ),
      _ActionItem(
        title: 'Advertisements',
        icon: Icons.campaign_outlined,
        color: Colors.purple,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminAdsPage()),
        ),
      ),
      _ActionItem(
        title: 'Notifications',
        icon: Icons.notifications_active_outlined,
        color: Colors.teal,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminNotificationsPage()),
        ),
      ),
      _ActionItem(
        title: 'Send Push Notification',
        icon: Icons.send_outlined,
        color: Colors.pinkAccent,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminSendNotificationPage()),
        ),
      ),
      _ActionItem(
        title: 'Festival Themes',
        icon: Icons.palette_outlined,
        color: Colors.deepOrange,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminThemesPage()),
        ),
      ),
      _ActionItem(
        title: 'Subscriptions',
        icon: Icons.card_membership_outlined,
        color: Colors.amber,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminSubscriptionsPage()),
        ),
      ),
      _ActionItem(
        title: 'Acc Deletions',
        icon: Icons.person_remove_outlined,
        color: Colors.redAccent,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminDeleteRequestsPage()),
        ),
      ),
      _ActionItem(
        title: 'Red Stars',
        icon: Icons.star_rounded,
        color: Colors.red,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminRedStarsPage()),
        ),
      ),
    ];

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: actions.map((action) {
        return _ActionCard(item: action);
      }).toList(),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final int count;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.count,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                count.toString(),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionItem {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  _ActionItem({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

class _ActionCard extends StatelessWidget {
  final _ActionItem item;

  const _ActionCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final width =
        (MediaQuery.of(context).size.width - 48) / 2; // 2 cols padding 16*3

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 2,
      shadowColor: Colors.grey.withValues(alpha: 0.1),
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: width,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(item.icon, size: 32, color: item.color),
              ),
              const SizedBox(height: 12),
              Text(
                item.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
