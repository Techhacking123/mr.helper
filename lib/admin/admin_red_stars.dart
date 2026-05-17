import 'package:flutter/material.dart';
import '../supabase_config.dart';

class AdminRedStarsPage extends StatefulWidget {
  const AdminRedStarsPage({super.key});

  @override
  State<AdminRedStarsPage> createState() => _AdminRedStarsPageState();
}

class _AdminRedStarsPageState extends State<AdminRedStarsPage> {
  List<Map<String, dynamic>> _providers = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchProviders();
  }

  Future<void> _fetchProviders() async {
    try {
      final response = await SupabaseConfig.adminClient
          .from('users')
          .select('id, full_name, email, avatar_url, red_stars, is_blocked, services(name)')
          .eq('is_provider', true)
          .order('red_stars', ascending: false);

      if (mounted) {
        setState(() {
          _providers = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching providers: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredProviders {
    if (_searchQuery.isEmpty) return _providers;
    final q = _searchQuery.toLowerCase();
    return _providers.where((p) {
      final name = (p['full_name'] as String? ?? '').toLowerCase();
      final email = (p['email'] as String? ?? '').toLowerCase();
      return name.contains(q) || email.contains(q);
    }).toList();
  }

  Future<void> _addRedStar(Map<String, dynamic> provider) async {
    final reasonController = TextEditingController(
      text: 'Admin penalty: Guideline violation',
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.star, color: Colors.red.shade600, size: 24),
            const SizedBox(width: 8),
            const Text('Add Red Star'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Give a red star to ${provider['full_name']}?',
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              'Current: ${provider['red_stars'] ?? 0} star(s)',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            if ((provider['red_stars'] ?? 0) >= 2)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning, color: Colors.red.shade700, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This will block the provider (3+ stars)!',
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                labelText: 'Reason',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Add Red Star'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final admin = SupabaseConfig.adminClient;
      final providerId = provider['id'];
      final reason = reasonController.text.trim();

      // Insert red star record
      await admin.from('provider_red_stars').insert({
        'provider_id': providerId,
        'reason': reason.isEmpty ? 'Admin penalty' : reason,
      });

      // Increment red_stars count
      final currentStars = (provider['red_stars'] as int?) ?? 0;
      final newStars = currentStars + 1;

      final updates = <String, dynamic>{'red_stars': newStars};
      if (newStars >= 3) updates['is_blocked'] = true;

      await admin.from('users').update(updates).eq('id', providerId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStars >= 3
                  ? '⭐ Red star added. ${provider['full_name']} is now BLOCKED.'
                  : '⭐ Red star added to ${provider['full_name']} ($newStars/3)',
            ),
            backgroundColor: newStars >= 3 ? Colors.red : Colors.orange,
          ),
        );
        _fetchProviders();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _removeRedStar(Map<String, dynamic> provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Red Star?'),
        content: Text(
          'Remove 1 red star from ${provider['full_name']}?\n'
          'Current: ${provider['red_stars'] ?? 0} star(s)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final admin = SupabaseConfig.adminClient;
      final providerId = provider['id'];
      final currentStars = (provider['red_stars'] as int?) ?? 0;

      if (currentStars <= 0) return;

      // Delete the most recent red star record
      final records = await admin
          .from('provider_red_stars')
          .select('id')
          .eq('provider_id', providerId)
          .order('created_at', ascending: false)
          .limit(1);

      if ((records as List).isNotEmpty) {
        await admin.from('provider_red_stars').delete().eq('id', records[0]['id']);
      }

      final newStars = currentStars - 1;
      final updates = <String, dynamic>{'red_stars': newStars};
      if (newStars < 3) updates['is_blocked'] = false;

      await admin.from('users').update(updates).eq('id', providerId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Red star removed from ${provider['full_name']} ($newStars/3)'),
            backgroundColor: Colors.green,
          ),
        );
        _fetchProviders();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _unblockProvider(Map<String, dynamic> provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Unblock Provider?'),
        content: Text(
          'Unblock ${provider['full_name']} and reset all red stars to 0?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Unblock'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final admin = SupabaseConfig.adminClient;
      final providerId = provider['id'];

      await admin.from('users').update({
        'red_stars': 0,
        'is_blocked': false,
      }).eq('id', providerId);

      await admin.from('provider_red_stars').delete().eq('provider_id', providerId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${provider['full_name']} unblocked successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _fetchProviders();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredProviders;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Red Star Management'),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search provider by name or email...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),

          // List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? const Center(child: Text('No providers found'))
                    : RefreshIndicator(
                        onRefresh: _fetchProviders,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final p = filtered[index];
                            return _buildProviderCard(p);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderCard(Map<String, dynamic> provider) {
    final name = provider['full_name'] ?? 'Unknown';
    final email = provider['email'] ?? '';
    final redStars = (provider['red_stars'] as int?) ?? 0;
    final isBlocked = provider['is_blocked'] == true;
    final service = provider['services']?['name'] ?? 'N/A';
    final avatarUrl = provider['avatar_url'];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isBlocked
            ? BorderSide(color: Colors.red.shade300, width: 2)
            : BorderSide.none,
      ),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Provider info row
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundImage: avatarUrl != null
                      ? NetworkImage(SupabaseConfig.proxyImageUrl(avatarUrl))
                      : null,
                  child: avatarUrl == null
                      ? Text(name[0].toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.bold))
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isBlocked) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'BLOCKED',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red.shade700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$email • $service',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Stars display
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    return Icon(
                      Icons.star_rounded,
                      size: 22,
                      color: i < redStars ? Colors.red : Colors.grey.shade300,
                    );
                  }),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _addRedStar(provider),
                    icon: Icon(Icons.add, size: 18, color: Colors.red.shade700),
                    label: Text(
                      'Add Star',
                      style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.red.shade200),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (redStars > 0)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _removeRedStar(provider),
                      icon: Icon(Icons.remove, size: 18, color: Colors.orange.shade700),
                      label: Text(
                        'Remove',
                        style: TextStyle(color: Colors.orange.shade700, fontSize: 13),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.orange.shade200),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                if (isBlocked) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _unblockProvider(provider),
                      icon: const Icon(Icons.lock_open, size: 18),
                      label: const Text('Unblock', style: TextStyle(fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
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
}
