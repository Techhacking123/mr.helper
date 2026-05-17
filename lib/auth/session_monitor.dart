import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_config.dart';
import 'session_manager.dart';
import 'login.dart';

class SessionMonitor extends StatefulWidget {
  final Widget child;
  const SessionMonitor({super.key, required this.child});

  @override
  State<SessionMonitor> createState() => _SessionMonitorState();
}

class _SessionMonitorState extends State<SessionMonitor> {
  RealtimeChannel? _userChannel;

  @override
  void initState() {
    super.initState();
    _initMonitor();
  }

  Future<void> _initMonitor() async {
    final userId = await SessionManager.getUserId();
    debugPrint('🔍 SessionMonitor: Initializing for user ID: $userId');

    if (userId == null) {
      debugPrint('⚠️ SessionMonitor: No user ID found, skipping monitor');
      return;
    }

    _userChannel = SupabaseConfig.supabase
        .channel('user_deletion_monitor_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'users',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: userId,
          ),
          callback: (payload) {
            debugPrint(
              '🚨 SessionMonitor: DELETE event detected for user $userId',
            );
            debugPrint('Payload: $payload');
            _handleAccountDeleted();
          },
        )
        .subscribe((status, [error]) {
          // Only log errors and critical status changes to reduce noise
          if (status == RealtimeSubscribeStatus.subscribed) {
            debugPrint('✅ SessionMonitor: Successfully subscribed');
          } else if (status == RealtimeSubscribeStatus.closed) {
            debugPrint('🔴 SessionMonitor: Connection closed');
          } else if (error != null) {
            debugPrint('❌ SessionMonitor: Subscription error: $error');
          }
          // Ignore timeout warnings as they're transient and typically resolve automatically
        });

    debugPrint('📡 SessionMonitor: Channel subscription initiated');
  }

  Future<void> _handleAccountDeleted() async {
    debugPrint('🚨 SessionMonitor: _handleAccountDeleted called!');
    debugPrint('📱 Clearing session...');
    await SessionManager.clearSession();
    debugPrint('✅ Session cleared');

    if (mounted) {
      debugPrint('💬 Showing account deletion dialog...');
      // Show dialog instead of SnackBar for better user awareness
      showDialog(
        context: context,
        barrierDismissible: false, // User must click OK
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text(
              'Account Removed',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
            content: const Text(
              'Your account has been removed from the system by an administrator. You will be redirected to the login page.',
              style: TextStyle(fontSize: 16),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  // Close dialog first
                  Navigator.of(dialogContext).pop();
                  // Then redirect to login
                  Navigator.of(
                    context,
                    rootNavigator: true, // Ensure we exit any sub-routes
                  ).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                },
                style: TextButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      );
    }
  }

  @override
  void dispose() {
    if (_userChannel != null)
      SupabaseConfig.supabase.removeChannel(_userChannel!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
