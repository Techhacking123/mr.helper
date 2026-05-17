import 'dart:async';
import 'package:flutter/material.dart';
import '../supabase_config.dart';

/// Manages order timers and automatic expiry detection
class OrderTimerManager {
  static const Duration timerDuration = Duration(hours: 24);


  /// Start the 24-hour timer for an order after verification
  static Future<void> startTimer(String orderId) async {
    try {
      await SupabaseConfig.supabase.rpc(
        'start_order_timer',
        params: {'order_id_param': orderId},
      );
      debugPrint('✅ Timer started for order: $orderId');
    } catch (e) {
      debugPrint('❌ Error starting timer: $e');
      rethrow;
    }
  }

  /// Reset the timer when user clicks "Working"
  static Future<void> resetTimer(String orderId) async {
    try {
      await SupabaseConfig.supabase.rpc(
        'reset_order_timer',
        params: {'order_id_param': orderId},
      );
      debugPrint('✅ Timer reset for order: $orderId');
    } catch (e) {
      debugPrint('❌ Error resetting timer: $e');
      rethrow;
    }
  }

  /// Mark order as completed (no red star applied)
  static Future<void> markCompleted(String orderId) async {
    try {
      await _deleteOrderImages(orderId);

      // Update order status to completed
      await SupabaseConfig.supabase
          .from('orders')
          .update({
            'status': 'completed',
            'images': [],
            'timer_started_at': null,
            'timer_expires_at': null,
          })
          .eq('id', orderId);

      debugPrint('✅ Order marked as completed: $orderId');
    } catch (e) {
      debugPrint('❌ Error marking order as completed: $e');
      rethrow;
    }
  }

  /// Complete order and update provider earnings using RPC
  static Future<Map<String, dynamic>> completeOrderWithEarnings(
    String orderId,
    String providerId,
  ) async {
    try {
      // 1. Delete images
      await _deleteOrderImages(orderId);

      // 2. Call RPC
      final response = await SupabaseConfig.supabase.rpc(
        'complete_order_and_pay',
        params: {'p_order_id': orderId, 'p_provider_id': providerId},
      );

      debugPrint('✅ Order completed with earnings update: $response');
      return Map<String, dynamic>.from(response);
    } catch (e) {
      debugPrint('❌ Error in completeOrderWithEarnings: $e');
      rethrow;
    }
  }

  static Future<void> _deleteOrderImages(String orderId) async {
    // Delete images from storage if they exist
    final orderData = await SupabaseConfig.supabase
        .from('orders')
        .select('images')
        .eq('id', orderId)
        .single();

    if (orderData['images'] != null &&
        (orderData['images'] as List).isNotEmpty) {
      for (final imageUrl in (orderData['images'] as List)) {
        try {
          final uri = Uri.parse(imageUrl.toString());
          final pathSegments = uri.pathSegments;
          final bucketIndex = pathSegments.indexOf('order_images');
          if (bucketIndex != -1 && bucketIndex < pathSegments.length - 1) {
            final filePath = pathSegments.sublist(bucketIndex + 1).join('/');
            await SupabaseConfig.supabase.storage.from('order_images').remove([
              filePath,
            ]);
          }
        } catch (e) {
          debugPrint('Error deleting image: $e');
        }
      }
    }
  }

  /// Mark order as cancelled by user (no red star applied)
  static Future<void> markCancelled(String orderId) async {
    try {
      await SupabaseConfig.supabase
          .from('orders')
          .update({
            'status': 'cancelled',
            'timer_started_at': null,
            'timer_expires_at': null,
          })
          .eq('id', orderId);

      debugPrint('✅ Order cancelled: $orderId');
    } catch (e) {
      debugPrint('❌ Error cancelling order: $e');
      rethrow;
    }
  }

  /// Check if order is expired and apply red star if needed
  /// Uses the deadline-based system
  static Future<bool> checkAndApplyExpiry(String orderId) async {
    try {
      // Check the order's deadline from orders table
      final order = await SupabaseConfig.supabase
          .from('orders')
          .select('id, deadline, status, provider_id')
          .eq('id', orderId)
          .maybeSingle();

      if (order == null) return false;

      final deadline = order['deadline'];
      if (deadline == null) return false;

      final deadlineTime = DateTime.parse(deadline);
      final now = DateTime.now();
      final status = order['status']?.toString().toLowerCase() ?? '';

      // Check if order is expired
      final isExpired =
          now.isAfter(deadlineTime) &&
          status != 'completed' &&
          status != 'cancelled' &&
          status != 'expired';

      if (isExpired) {
        // Call the global expiry check which assigns red stars
        await SupabaseConfig.supabase.rpc('check_and_mark_expired_orders');

        debugPrint('⚠️ Order expired, red star assigned: $orderId');
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('❌ Error checking expiry: $e');
      return false;
    }
  }

  /// Get time remaining for an order
  static Future<Duration?> getTimeRemaining(String orderId) async {
    try {
      final result = await SupabaseConfig.supabase
          .from('active_order_timers')
          .select('seconds_remaining')
          .eq('id', orderId)
          .maybeSingle();

      if (result == null) return null;

      final secondsRemaining = result['seconds_remaining'] as num?;
      if (secondsRemaining == null) return null;

      return Duration(seconds: secondsRemaining.toInt());
    } catch (e) {
      debugPrint('❌ Error getting time remaining: $e');
      return null;
    }
  }

  /// Format duration as countdown string
  static String formatTimeRemaining(Duration duration) {
    if (duration.isNegative) return 'Expired';

    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0) {
      return '$hours hr ${minutes} min remaining';
    } else {
      return '$minutes min remaining';
    }
  }

  /// Check if status allows timer actions
  static bool canShowTimerActions(String status) {
    return status == 'verified' || status == 'working';
  }

  /// Run a global check for ALL expired orders and apply red stars
  /// This should be called on app startup/home screen
  static Future<void> runGlobalExpiryCheck() async {
    try {
      final response = await SupabaseConfig.supabase.rpc(
        'check_and_mark_expired_orders',
      );
      debugPrint('🔄 Global expiry check run: $response');
    } catch (e) {
      debugPrint('❌ Error running global expiry check: $e');
    }
  }

  /// Get provider's red star penalty information
  static Future<Map<String, dynamic>> getProviderRedStars(String providerId) async {
    try {
      final result = await SupabaseConfig.supabase.rpc(
        'get_provider_red_stars',
        params: {'p_provider_id': providerId},
      );
      return Map<String, dynamic>.from(result);
    } catch (e) {
      debugPrint('❌ Error getting red stars: $e');
      return {'red_stars': 0, 'is_blocked': false, 'history': []};
    }
  }

  /// Check if provider is blocked (3+ red stars)
  static Future<bool> isProviderBlocked(String providerId) async {
    try {
      final userData = await SupabaseConfig.supabase
          .from('users')
          .select('is_blocked, red_stars')
          .eq('id', providerId)
          .single();
      return userData['is_blocked'] == true || (userData['red_stars'] ?? 0) >= 3;
    } catch (e) {
      debugPrint('❌ Error checking block status: $e');
      return false;
    }
  }
}

/// Widget to display countdown timer
class OrderCountdownTimer extends StatefulWidget {
  final String orderId;
  final DateTime? expiresAt;
  final VoidCallback? onExpired;

  const OrderCountdownTimer({
    super.key,
    required this.orderId,
    this.expiresAt,
    this.onExpired,
  });

  @override
  State<OrderCountdownTimer> createState() => _OrderCountdownTimerState();
}

class _OrderCountdownTimerState extends State<OrderCountdownTimer> {
  Timer? _timer;
  Duration? _remaining;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    if (widget.expiresAt == null) return;

    _updateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRemaining();
    });
  }

  void _updateRemaining() {
    if (widget.expiresAt == null) return;

    final now = DateTime.now();
    final remaining = widget.expiresAt!.difference(now);

    setState(() {
      _remaining = remaining;
    });

    if (remaining.isNegative && widget.onExpired != null) {
      widget.onExpired!();
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_remaining == null) {
      return const SizedBox.shrink();
    }

    final isExpired = _remaining!.isNegative;
    final hours = _remaining!.inHours.abs();
    final minutes = _remaining!.inMinutes.remainder(60).abs();
    final seconds = _remaining!.inSeconds.remainder(60).abs();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isExpired
              ? [Colors.red.shade100, Colors.red.shade200]
              : [Colors.orange.shade100, Colors.orange.shade200],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isExpired ? Colors.red : Colors.orange,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isExpired ? Icons.warning_amber : Icons.timer,
                color: isExpired ? Colors.red : Colors.orange.shade800,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                isExpired ? 'TIMER EXPIRED' : 'Time Remaining',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isExpired ? Colors.red : Colors.orange.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!isExpired)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildTimerSegment(hours.toString().padLeft(2, '0'), 'Hours'),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    ':',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                _buildTimerSegment(
                  minutes.toString().padLeft(2, '0'),
                  'Minutes',
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    ':',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                _buildTimerSegment(
                  seconds.toString().padLeft(2, '0'),
                  'Seconds',
                ),
              ],
            )
          else
            const Text(
              'Please take action immediately',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }

  Widget _buildTimerSegment(String value, String label) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
      ],
    );
  }
}
