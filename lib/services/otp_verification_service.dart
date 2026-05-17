import 'dart:async';
import 'package:flutter/foundation.dart';
import '../supabase_config.dart';
import '../firebase/fcm_service.dart';

/// Service to manage the 24-hour OTP verification deadline.
///
/// When a provider accepts/is approved for an order, a 24-hour countdown begins.
/// If OTP is NOT verified within that window, a red star penalty is applied.
///
/// This runs alongside the existing OrderExpiryService.
class OtpVerificationService {
  static Timer? _timer;
  static bool _isRunning = false;

  /// Start periodic checking for OTP verification deadlines.
  /// Checks every 10 minutes.
  static void startPeriodicCheck() {
    if (_isRunning) {
      debugPrint('⏰ OtpVerificationService already running');
      return;
    }

    debugPrint('✅ OtpVerificationService started - checking every 10 minutes');
    _isRunning = true;

    // Run immediately on start
    checkOtpDeadlines();

    // Then run every 10 minutes
    _timer = Timer.periodic(const Duration(minutes: 10), (timer) {
      checkOtpDeadlines();
    });
  }

  /// Stop the periodic checker
  static void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    debugPrint('❌ OtpVerificationService stopped');
  }

  /// Check all orders for expired OTP verification deadlines.
  /// Calls the Supabase RPC function which handles red star assignment.
  static Future<Map<String, dynamic>> checkOtpDeadlines() async {
    try {
      debugPrint('🔍 Checking OTP verification deadlines...');

      final result = await SupabaseConfig.supabase.rpc(
        'check_otp_verification_deadlines',
      );

      debugPrint('✅ OTP Deadline Check Result: $result');

      return {'success': true, 'result': result};
    } catch (e) {
      debugPrint('❌ Error checking OTP deadlines: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Set the 24-hour OTP verification deadline for an order.
  /// Called when a provider accepts or is approved for an order.
  static Future<void> setOtpDeadline(String orderId) async {
    try {
      final deadline = DateTime.now()
          .toUtc()
          .add(const Duration(hours: 24))
          .toIso8601String();

      await SupabaseConfig.supabase
          .from('orders')
          .update({'otp_verification_deadline': deadline})
          .eq('id', orderId);

      debugPrint('✅ OTP verification deadline set for order: $orderId (24hr from now)');
    } catch (e) {
      debugPrint('❌ Error setting OTP deadline: $e');
    }
  }

  /// Clear the OTP verification deadline (called when OTP is verified).
  static Future<void> clearOtpDeadline(String orderId) async {
    try {
      await SupabaseConfig.supabase
          .from('orders')
          .update({'otp_verification_deadline': null})
          .eq('id', orderId);

      debugPrint('✅ OTP verification deadline cleared for order: $orderId');
    } catch (e) {
      debugPrint('❌ Error clearing OTP deadline: $e');
    }
  }

  /// Send a 1-hour warning notification to the provider.
  /// Called from the client-side periodic check when deadline is < 1 hour away.
  static Future<void> sendWarningNotification({
    required String orderId,
    required String providerId,
  }) async {
    try {
      await FCMService.sendPushNotificationToUser(
        userId: providerId,
        title: '⚠️ OTP Verification Deadline',
        message:
            'You have less than 1 hour to verify OTP for order #${orderId.substring(0, 8)}. Failure will result in a red star penalty!',
        screen: 'order_detail',
        orderId: orderId,
      );

      debugPrint('⚠️ 1-hour warning sent to provider: $providerId for order: $orderId');
    } catch (e) {
      debugPrint('❌ Error sending warning notification: $e');
    }
  }

  /// Check orders approaching OTP deadline for warnings (client-side).
  /// Sends a 1-hour warning push notification to the provider.
  static Future<void> checkAndSendWarnings() async {
    try {
      // Fetch orders that have OTP deadline within the next 1 hour
      // and status is still accepted/confirmed (not yet verified)
      final now = DateTime.now().toUtc();
      final oneHourFromNow = now.add(const Duration(hours: 1)).toIso8601String();

      final orders = await SupabaseConfig.supabase
          .from('orders')
          .select('id, provider_id, otp_verification_deadline')
          .not('otp_verification_deadline', 'is', null)
          .lte('otp_verification_deadline', oneHourFromNow)
          .gt('otp_verification_deadline', now.toIso8601String())
          .inFilter('status', ['accepted', 'confirmed']);

      for (final order in (orders as List)) {
        final providerId = order['provider_id'];
        if (providerId != null) {
          await sendWarningNotification(
            orderId: order['id'],
            providerId: providerId,
          );
        }
      }

      if ((orders as List).isNotEmpty) {
        debugPrint('⚠️ Sent ${orders.length} OTP deadline warnings');
      }
    } catch (e) {
      debugPrint('❌ Error checking for OTP deadline warnings: $e');
    }
  }

  /// Get remaining time until OTP verification deadline for an order.
  static Duration? getRemainingTime(Map<String, dynamic> order) {
    try {
      final deadlineStr = order['otp_verification_deadline'];
      if (deadlineStr == null) return null;

      final deadline = DateTime.parse(deadlineStr);
      final remaining = deadline.difference(DateTime.now());

      return remaining.isNegative ? Duration.zero : remaining;
    } catch (e) {
      debugPrint('Error getting OTP deadline remaining time: $e');
      return null;
    }
  }
}
