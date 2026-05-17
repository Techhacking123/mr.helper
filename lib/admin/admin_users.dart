import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filteredUsers = []; // Displayed list
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedRoleFilter = 'All'; // All, User, Provider

  final TextEditingController _searchController = TextEditingController();
  late final RealtimeChannel _subscription;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    _searchController.dispose();
    SupabaseConfig.supabase.removeChannel(_subscription);
    super.dispose();
  }

  void _subscribeToRealtime() {
    _subscription = SupabaseConfig.supabase.channel('admin_users_list');
    _subscription
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'users',
          callback: (payload) => _fetchUsers(),
        )
        .subscribe();
  }

  Future<void> _fetchUsers() async {
    try {
      final response = await SupabaseConfig.supabase
          .from('users')
          .select()
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _users = List<Map<String, dynamic>>.from(response);
          _applyFilters();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching users: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredUsers = _users.where((user) {
        final email = (user['email'] as String? ?? '').toLowerCase();
        final name = (user['full_name'] as String? ?? '').toLowerCase();
        final searchLower = _searchQuery.toLowerCase();

        final matchesSearch =
            email.contains(searchLower) || name.contains(searchLower);

        bool matchesRole = true;
        if (_selectedRoleFilter == 'User') {
          matchesRole = user['is_provider'] == false;
        } else if (_selectedRoleFilter == 'Provider') {
          matchesRole = user['is_provider'] == true;
        }

        return matchesSearch && matchesRole;
      }).toList();
    });
  }

  Widget _buildFilterChip(String role) {
    final isSelected = _selectedRoleFilter == role;
    return FilterChip(
      label: Text(role),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedRoleFilter = role;
          _applyFilters();
        });
      },
      selectedColor: Theme.of(context).primaryColor.withOpacity(0.2),
      checkmarkColor: Theme.of(context).primaryColor,
      labelStyle: TextStyle(
        color: isSelected ? Theme.of(context).primaryColor : Colors.black,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Future<void> _deleteUser(String userId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete User?'),
        content: const Text(
          'This will permanently delete the user and ALL their data (orders, reports, feedback, notifications). This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final admin = SupabaseConfig.adminClient;

      // 1. First, delete any storage files (avatar, aadhar, pan)
      final user = await admin
          .from('users')
          .select()
          .eq('id', userId)
          .single();
      
      final filesToDelete = [
        user['avatar_url'],
        user['aadhar_card_url'],
        user['pan_card_url'],
      ].whereType<String>().where((f) => f.isNotEmpty).toList();
      
      for (final file in filesToDelete) {
        try {
          // Extract bucket name and path from storage URL
          // Format: .../storage/v1/object/public/<bucket>/<file_path>
          final parts = file.split('/storage/v1/object/');
          if (parts.length >= 2) {
            final pathParts = parts[1].split('/');
            // pathParts[0] = 'public' (access level), pathParts[1] = bucket, rest = file path
            if (pathParts.length >= 3) {
              final bucketName = pathParts[1];
              final filePath = pathParts.sublist(2).join('/');
              await admin.storage.from(bucketName).remove([filePath]);
            }
          }
        } catch (e) {
          debugPrint('Warning: Could not delete storage file $file: $e');
        }
      }

      // 2. NULL out storage URL columns to break any FK/trigger cascade to storage.objects
      await admin
          .from('users')
          .update({
            'avatar_url': null,
            'aadhar_card_url': null,
            'pan_card_url': null,
          })
          .eq('id', userId);

      // 3. Manually cleanup dependencies to ensure no FK errors if CASCADE is missing

      // Subscriptions and Subscription History (for providers)
      await admin
          .from('subscription_history')
          .delete()
          .eq('provider_id', userId);
      await admin
          .from('subscriptions')
          .delete()
          .eq('user_id', userId);

      // Provider Reviews
      await admin
          .from('provider_reviews')
          .delete()
          .eq('provider_id', userId);
      await admin
          .from('provider_reviews')
          .delete()
          .eq('user_id', userId);

      // Notifications
      await admin
          .from('notifications')
          .delete()
          .eq('user_id', userId);
      // Feedback
      await admin
          .from('feedback')
          .delete()
          .eq('reviewer_id', userId);
      await admin
          .from('feedback')
          .delete()
          .eq('target_id', userId);
      // Offers
      await admin
          .from('order_offers')
          .delete()
          .eq('provider_id', userId);
      // Orders (as Buyer)
      await admin
          .from('orders')
          .delete()
          .eq('buyer_id', userId);
      // Orders (as Provider)
      await admin
          .from('orders')
          .delete()
          .eq('provider_id', userId);
      // Reports (as Reporter or Reported)
      await admin
          .from('reports')
          .delete()
          .eq('reporter_id', userId);
      await admin
          .from('reports')
          .delete()
          .eq('reported_id', userId);

      // 4. Delete User
      final deletedUsers = await admin
          .from('users')
          .delete()
          .eq('id', userId)
          .select();

      if (deletedUsers.isEmpty) {
        throw 'User deletion returned 0 rows. Check RLS policies.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User deleted successfully')),
        );
        _fetchUsers(); // Refresh list
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error deleting user: $e')));
      }
    }
  }

  void _viewUser(Map<String, dynamic> user) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AdminUserProfileView(user: user)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('User Management (${_users.length})')),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by name or email',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onChanged: (val) {
                    _searchQuery = val;
                    _applyFilters();
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text(
                      'Filter by Role:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 10),
                    _buildFilterChip('All'),
                    const SizedBox(width: 8),
                    _buildFilterChip('User'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Provider'),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredUsers.isEmpty
                ? const Center(child: Text("No users found matching filters"))
                : ListView.builder(
                    itemCount: _filteredUsers.length,
                    itemBuilder: (context, index) {
                      final user = _filteredUsers[index];
                      final isProvider = user['is_provider'] == true;
                      final avatarUrl = user['avatar_url'];
                      final createdDate = DateTime.parse(user['created_at']);

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundImage: avatarUrl != null
                                ? NetworkImage(
                                    SupabaseConfig.proxyImageUrl(avatarUrl),
                                  )
                                : null,
                            child: avatarUrl == null
                                ? const Icon(Icons.person)
                                : null,
                          ),
                          title: Text(
                            '${user['full_name']} (${user['email']})',
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Role: ${isProvider ? "Provider" : "User"}'),
                              if (isProvider)
                                Text(
                                  'Service ID: ${user['service_id'] ?? "N/A"}',
                                ),
                              Text(
                                'Joined: ${DateFormat.yMMMd().format(createdDate)}',
                              ),
                              if (user['location'] != null)
                                Text('Location: ${user['location']}'),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.visibility,
                                  color: Colors.blue,
                                ),
                                onPressed: () => _viewUser(user),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                                onPressed: () => _deleteUser(user['id']),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class AdminUserProfileView extends StatelessWidget {
  final Map<String, dynamic> user;
  const AdminUserProfileView({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final avatarUrl = user['avatar_url'];
    final isProvider = user['is_provider'] == true;
    final aadharUrl = user['aadhar_card_url'];
    final panUrl = user['pan_card_url'];

    return Scaffold(
      appBar: AppBar(title: Text(user['full_name'])),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            Center(
              child: CircleAvatar(
                radius: 60,
                backgroundImage: avatarUrl != null
                    ? NetworkImage(SupabaseConfig.proxyImageUrl(avatarUrl))
                    : null,
                child: avatarUrl == null
                    ? const Icon(Icons.person, size: 60)
                    : null,
              ),
            ),
            const SizedBox(height: 20),

            // Basic Info
            _InfoRow('User ID', user['id']?.toString() ?? 'N/A'),
            _InfoRow('Email', user['email']?.toString() ?? 'N/A'),
            _InfoRow('Full Name', user['full_name']?.toString() ?? 'N/A'),
            _InfoRow(
              'Role',
              (user['is_provider'] == true) ? 'Service Provider' : 'Customer',
            ),
            if (user['bio'] != null) _InfoRow('Bio', user['bio'].toString()),
            if (user['price'] != null) _InfoRow('Price', '₹${user['price']}'),
            if (user['location'] != null)
              _InfoRow('Location', user['location'].toString()),

            // Document Images for Providers
            if (isProvider) ...[
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              const Text(
                'KYC Documents',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
              const SizedBox(height: 16),

              if (aadharUrl != null || panUrl != null)
                Row(
                  children: [
                    if (aadharUrl != null)
                      Expanded(
                        child: _buildDocPreview(
                          context,
                          'Aadhaar Card',
                          aadharUrl,
                          Icons.credit_card,
                        ),
                      ),
                    if (aadharUrl != null && panUrl != null)
                      const SizedBox(width: 16),
                    if (panUrl != null)
                      Expanded(
                        child: _buildDocPreview(
                          context,
                          'PAN Card',
                          panUrl,
                          Icons.badge,
                        ),
                      ),
                  ],
                )
              else
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.red.shade700,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'No KYC documents uploaded',
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDocPreview(
    BuildContext context,
    String label,
    String imageUrl,
    IconData icon,
  ) {
    return GestureDetector(
      onTap: () {
        // Show full-screen image in dialog
        showDialog(
          context: context,
          builder: (context) => Dialog(
            backgroundColor: Colors.transparent,
            child: Stack(
              children: [
                Center(
                  child: InteractiveViewer(
                    child: Image.network(
                      SupabaseConfig.proxyImageUrl(imageUrl),
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const Center(child: CircularProgressIndicator());
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          padding: const EdgeInsets.all(20),
                          color: Colors.white,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 48,
                                color: Colors.red,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Failed to load image',
                                style: TextStyle(color: Colors.red),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                Positioned(
                  top: 40,
                  right: 20,
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 30,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black54,
                    ),
                  ),
                ),
                Positioned(
                  top: 40,
                  left: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300, width: 2),
          color: Colors.grey.shade50,
        ),
        child: Column(
          children: [
            // Image Preview
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
              child: Container(
                height: 150,
                width: double.infinity,
                color: Colors.grey.shade200,
                child: Image.network(
                  SupabaseConfig.proxyImageUrl(imageUrl),
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: progress.expectedTotalBytes != null
                            ? progress.cumulativeBytesLoaded /
                                  progress.expectedTotalBytes!
                            : null,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.broken_image,
                            size: 40,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Failed to load',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            // Label
            Container(
              padding: const EdgeInsets.all(12),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade50,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(10),
                  bottomRight: Radius.circular(10),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: Colors.deepPurple),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
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

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 16))),
        ],
      ),
    );
  }
}
