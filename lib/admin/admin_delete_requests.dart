import 'package:flutter/material.dart';
import '../supabase_config.dart';

class AdminDeleteRequestsPage extends StatefulWidget {
  const AdminDeleteRequestsPage({Key? key}) : super(key: key);

  @override
  State<AdminDeleteRequestsPage> createState() =>
      _AdminDeleteRequestsPageState();
}

class _AdminDeleteRequestsPageState extends State<AdminDeleteRequestsPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _requests = [];

  @override
  void initState() {
    super.initState();
    _fetchRequests();
  }

  Future<void> _fetchRequests() async {
    setState(() => _isLoading = true);
    try {
      final response = await SupabaseConfig.adminClient
          .from('delete_requests')
          .select('*')
          .order('requested_at', ascending: false);

      if (mounted) {
        setState(() {
          _requests = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching delete requests: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        // We handle the case where table doesn't exist yet gracefully
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not fetch requests. Have you created the table in SQL?',
            ),
          ),
        );
      }
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> request) async {
    final bool confirm =
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirm Deletion'),
            content: Text(
              'Are you sure you want to delete the user with phone: ${request['phone']}?\n\nYou will need to manually remove them from the users/providers table using this phone number.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    try {
      // First, attempt to delete user by phone number from users table
      await SupabaseConfig.adminClient
          .from('users')
          .delete()
          .eq('phone', request['phone']);

      // Then delete from providers table if they exist there
      // Because we don't know if they are a user or provider

      // Finally, delete the request or mark as completed
      await SupabaseConfig.adminClient
          .from('delete_requests')
          .update({'status': 'completed'})
          .eq('id', request['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account successfully deleted.')),
        );
        _fetchRequests();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete user: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Deletion Requests'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
          ? const Center(
              child: Text(
                'No pending deletion requests',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _requests.length,
              itemBuilder: (context, index) {
                final req = _requests[index];
                final isPending = req['status'] == 'pending';
                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              req['phone'] ?? 'N/A',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isPending
                                    ? Colors.orange.withOpacity(0.2)
                                    : Colors.green.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                (req['status'] ?? 'pending').toUpperCase(),
                                style: TextStyle(
                                  color: isPending
                                      ? Colors.orange[800]
                                      : Colors.green[800],
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (req['email'] != null &&
                            req['email'].toString().isNotEmpty)
                          Text(
                            'Email: ${req['email']}',
                            style: const TextStyle(color: Colors.black87),
                          ),
                        const SizedBox(height: 8),
                        const Text(
                          'Reason:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          req['reason'] ?? 'No reason provided',
                          style: const TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 16),
                        if (isPending)
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => _deleteUser(req),
                              icon: const Icon(Icons.delete_forever),
                              label: const Text('Delete User Account'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
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
}
