import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_users.dart'; // Reuse user profile view if needed

class AdminReportsPage extends StatefulWidget {
  const AdminReportsPage({super.key});

  @override
  State<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends State<AdminReportsPage> {
  List<Map<String, dynamic>> _reports = [];
  bool _isLoading = true;

  late final RealtimeChannel _subscription;

  @override
  void initState() {
    super.initState();
    _fetchReports();
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    SupabaseConfig.supabase.removeChannel(_subscription);
    super.dispose();
  }

  void _subscribeToRealtime() {
    _subscription = SupabaseConfig.supabase.channel('admin_reports_list');
    _subscription
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'reports',
          callback: (payload) => _fetchReports(),
        )
        .subscribe();
  }

  Future<void> _fetchReports() async {
    try {
      // NOTE: Using column-based foreign key hint.
      // If this fails due to ambiguous relation, we might need constraint names.
      final response = await SupabaseConfig.supabase
          .from('reports')
          .select(
            '*, reporter:users!reporter_id(email, full_name), reported:users!reported_id(id, email, full_name, avatar_url, bio, is_provider, location, price, service_id, aadhar_card_url, pan_card_url)',
          ) // Fetching full profile for reported to view
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _reports = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching reports: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _ignoreReport(String reportId) async {
    try {
      await SupabaseConfig.adminClient.from('reports').delete().eq('id', reportId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report ignored (deleted)')),
        );
        _fetchReports();
      }
    } catch (e) {
      debugPrint('Error ignoring report: $e');
    }
  }

  Future<void> _banUser(String userId, String reportId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('BAN USER?'),
        content: const Text(
          'This will PERMANENTLY DELETE the reported user and all their data. The report will also be resolved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('BAN & DELETE'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Delete user (cascade should handle report, but we explicitly delete report first? No, cascade handles it)
      // Actually deleting user is enough.
      await SupabaseConfig.adminClient.from('users').delete().eq('id', userId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User BANNED and deleted.')),
        );
        _fetchReports();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error banning user: $e')));
      }
    }
  }

  void _viewReportedProfile(Map<String, dynamic> userMap) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AdminUserProfileView(user: userMap)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report Management')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _reports.length,
              itemBuilder: (context, index) {
                final report = _reports[index];
                final reporter =
                    report['reporter'] ??
                    {'email': 'Unknown', 'full_name': 'Unknown'};
                final reported =
                    report['reported'] ??
                    {'email': 'Unknown', 'full_name': 'Deleted User'};

                // If reported user is null (already deleted), handle gracefully
                final bool isReportedUserDeleted = report['reported'] == null;

                return Card(
                  color: Colors.red.shade50,
                  margin: const EdgeInsets.all(10),
                  shape: RoundedRectangleBorder(
                    side: const BorderSide(color: Colors.red, width: 1.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.warning, color: Colors.red),
                            const SizedBox(width: 8),
                            const Text(
                              'REPORT',
                              style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              DateFormat.yMMMd().format(
                                DateTime.parse(report['created_at']),
                              ),
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const Divider(color: Colors.red),
                        const SizedBox(height: 8),
                        Text(
                          'Reason:',
                          style: TextStyle(
                            color: Colors.red.shade900,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          report['reason'] ?? 'No reason provided',
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Reporter:',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  Text(
                                    '${reporter['full_name']} (${reporter['email']})',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Reported User:',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.red,
                                    ),
                                  ),
                                  Text(
                                    isReportedUserDeleted
                                        ? "USER DELETED"
                                        : '${reported['full_name']} (${reported['email']})',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => _ignoreReport(report['id']),
                              child: const Text('Ignore'),
                            ),
                            const SizedBox(width: 8),
                            if (!isReportedUserDeleted) ...[
                              OutlinedButton(
                                onPressed: () => _viewReportedProfile(reported),
                                child: const Text('View Profile'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.delete_forever),
                                label: const Text('BAN USER'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () =>
                                    _banUser(reported['id'], report['id']),
                              ),
                            ] else
                              const Text(
                                "(User already deleted)",
                                style: TextStyle(color: Colors.grey),
                              ),
                          ],
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
