import 'dart:async';
import 'package:flutter/foundation.dart';
import '../supabase_config.dart';

/// Service to check and mark expired orders
/// Runs periodically to ensure orders past deadline are handled with red star penalties
class OrderExpiryService {
  static Timer? _timer;
  static bool _isRunning = false;

  /// Start periodic checking for expired orders
  /// Checks every 15 minutes
  static void startPeriodicCheck() {
    if (_isRunning) {
      debugPrint('⏰ OrderExpiryService already running');
      return;
    }

    debugPrint('✅ OrderExpiryService started - checking every 15 minutes');
    _isRunning = true;

    // Run immediately on start
    checkExpiredOrders();

    // Then run every 15 minutes
    _timer = Timer.periodic(const Duration(minutes: 15), (timer) {
      checkExpiredOrders();
    });
  }

  /// Stop the periodic checker
  static void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    debugPrint('❌ OrderExpiryService stopped');
  }

  /// Manually trigger expiry check
  static Future<Map<String, dynamic>> checkExpiredOrders() async {
    try {
      debugPrint('🔍 Checking for expired orders...');

      final result = await SupabaseConfig.supabase.rpc(
        'check_and_mark_expired_orders',
      );

      debugPrint('✅ Expiry Check Result: $result');

      return {'success': true, 'result': result};
    } catch (e) {
      debugPrint('❌ Error checking expired orders: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Check if an order is expired (client-side check)
  static bool isOrderExpired(Map<String, dynamic> order) {
    try {
      final deadlineStr = order['deadline'];
      if (deadlineStr == null) return false;

      final deadline = DateTime.parse(deadlineStr);
      final now = DateTime.now();
      final status = order['status']?.toString().toLowerCase() ?? '';

      // Order is expired if:
      // 1. Deadline has passed
      // 2. Order is not completed or cancelled
      return now.isAfter(deadline) &&
          status != 'completed' &&
          status != 'cancelled';
    } catch (e) {
      debugPrint('Error checking if order expired: $e');
      return false;
    }
  }

  /// Get remaining time until deadline
  static Duration? getRemainingTime(Map<String, dynamic> order) {
    try {
      final deadlineStr = order['deadline'];
      if (deadlineStr == null) return null;

      final deadline = DateTime.parse(deadlineStr);
      final now = DateTime.now();
      final remaining = deadline.difference(now);

      return remaining.isNegative ? Duration.zero : remaining;
    } catch (e) {
      debugPrint('Error getting remaining time: $e');
      return null;
    }
  }

  /// Format remaining time as human-readable string
  static String formatRemainingTime(Duration duration) {
    if (duration.isNegative || duration == Duration.zero) {
      return 'EXPIRED';
    }

    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;

    if (hours > 24) {
      final days = (hours / 24).floor();
      final remainingHours = hours % 24;
      return '${days}d ${remainingHours}h';
    } else if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }

  /// Extend order deadline (when "Working" clicked)
  static Future<Map<String, dynamic>> extendDeadline(String orderId) async {
    try {
      debugPrint('⏱️ Extending deadline for order: $orderId');

      final result = await SupabaseConfig.supabase.rpc(
        'extend_order_deadline',
        params: {'order_uuid': orderId},
      );

      if (result['success'] == true) {
        debugPrint('✅ Deadline extended: ${result['message']}');
        debugPrint('   New deadline: ${result['new_deadline']}');
        debugPrint('   Extension count: ${result['extension_count']}');
      } else {
        debugPrint('❌ Failed to extend: ${result['error']}');
      }

      return result;
    } catch (e) {
      debugPrint('❌ Error extending deadline: $e');
      return {'success': false, 'error': e.toString()};
    }
  }
}
