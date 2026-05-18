import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import '../call/call_launcher.dart';
import 'package:url_launcher/url_launcher.dart';
import 'user_offers.dart';
import 'order_chat_page.dart';
import 'package:intl/intl.dart';

import '../call/livekit_service.dart';
import '../call/voice_call_screen.dart';
import '../call/call_signaling_service.dart';
import '../supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'order_timer_manager.dart';
import 'provider_review_dialog.dart';
import '../auth/session_manager.dart';

import '../widgets/deadline_timer.dart';
import '../services/order_expiry_service.dart';
import '../services/otp_verification_service.dart';
import '../firebase/fcm_service.dart';

class _AppTheme {
  // Primary Colors
  static const Color primary = Color(0xFF4F46E5); // Indigo-600
  static const Color primaryLight = Color(0xFF818CF8); // Indigo-400
  static const Color primaryDark = Color(0xFF3730A3); // Indigo-800

  // Status Colors
  static const Color success = Color(0xFF10B981); // Emerald-500
  static const Color successLight = Color(0xFFD1FAE5); // Emerald-100
  static const Color warning = Color(0xFFF59E0B); // Amber-500
  static const Color warningLight = Color(0xFFFEF3C7); // Amber-100
  static const Color error = Color(0xFFEF4444); // Red-500
  static const Color errorLight = Color(0xFFFEE2E2); // Red-100
  static const Color info = Color(0xFF3B82F6); // Blue-500
  static const Color infoLight = Color(0xFFDBEAFE); // Blue-100

  // Neutral Colors
  static const Color background = Color(0xFFF8FAFC); // Slate-50
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF1F5F9); // Slate-100
  static const Color border = Color(0xFFE2E8F0); // Slate-200
  static const Color textPrimary = Color(0xFF1E293B); // Slate-800
  static const Color textSecondary = Color(0xFF64748B); // Slate-500
  static const Color textMuted = Color(0xFF94A3B8); // Slate-400

  // Spacing (8px grid system)
  static const double spacing1 = 4.0;
  static const double spacing2 = 8.0;
  static const double spacing3 = 12.0;
  static const double spacing4 = 16.0;
  static const double spacing5 = 20.0;
  static const double spacing6 = 24.0;
  static const double spacing8 = 32.0;

  // Border Radius
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 20.0;
  static const double radiusFull = 100.0;

  // Shadows
  static List<BoxShadow> get shadowSm => [
    BoxShadow(
      color: Colors.black.withOpacity(0.04),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get shadowMd => [
    BoxShadow(
      color: Colors.black.withOpacity(0.06),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get shadowLg => [
    BoxShadow(
      color: Colors.black.withOpacity(0.08),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];
}

class OrderDetailPage extends StatefulWidget {
  final Map<String, dynamic> order;
  final bool isProvider;

  const OrderDetailPage({
    super.key,
    required this.order,
    required this.isProvider,
  });

  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage>
    with SingleTickerProviderStateMixin {
  late Map<String, dynamic> _order;
  late RealtimeChannel _channel;
  bool _isActionLoading = false;
  final _otpController = TextEditingController();
  late AnimationController _animationController;
  Timer? _otpDeadlineTimer; // Live countdown timer for OTP verification deadline

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animationController.forward();
    _refetchOrder();
    _setupRealtime();
    _startOtpDeadlineTimer();
  }

  void _setupRealtime() {
    _channel = SupabaseConfig.supabase
        .channel('public:orders:detail:${_order['id']}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: _order['id'],
          ),
          callback: (payload) {
            debugPrint("Order detail update received for ID: ${_order['id']}");
            _refetchOrder();
          },
        )
        .subscribe();
  }

  Future<void> _refetchOrder() async {
    try {
      final response = await SupabaseConfig.supabase
          .from('orders')
          .select(
            '*, provider:users!provider_id(full_name, phone_number, avatar_url), buyer:users!buyer_id(full_name, phone_number, avatar_url), service:services(name), location:locations(name)',
          )
          .eq('id', _order['id'])
          .single();

      if (mounted) {
        setState(() {
          _order = response;
        });
      }
    } catch (e) {
      debugPrint('Error refreshing order detail: $e');
    }
  }

  /// Starts a periodic timer to refresh the UI every second for the OTP countdown.
  void _startOtpDeadlineTimer() {
    _otpDeadlineTimer?.cancel();
    _otpDeadlineTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {}); // Trigger rebuild to update countdown
    });
  }

  @override
  void dispose() {
    _otpDeadlineTimer?.cancel();
    SupabaseConfig.supabase.removeChannel(_channel);
    _otpController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // --- PRICE LOGIC ---
  Future<double?> _getApprovedPrice() async {
    try {
      final offers = await SupabaseConfig.supabase
          .from('order_offers')
          .select('price')
          .eq('order_id', _order['id'])
          .eq('status', 'accepted')
          .maybeSingle();

      if (offers != null) {
        return double.tryParse(offers['price'].toString());
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching approved price: $e');
      return null;
    }
  }

  // --- SUB-SERVICE TYPE HELPER ---
  String? _getSubServiceType() {
    // First check if sub_service_type column exists
    if (_order['sub_service_type'] != null &&
        _order['sub_service_type'].toString().isNotEmpty) {
      return _order['sub_service_type'].toString();
    }

    // Fallback: Extract from description for backwards compatibility
    final description = _order['description']?.toString() ?? '';
    if (description.startsWith('Service Type: ')) {
      final lines = description.split('\n');
      if (lines.isNotEmpty) {
        return lines[0].replaceFirst('Service Type: ', '').trim();
      }
    }
    return null;
  }

  // --- OTP LOGIC ---
  Future<void> _generateAndSendOTP() async {
    setState(() => _isActionLoading = true);
    try {
      final otp = (100000 + Random().nextInt(900000)).toString();
      final expiry = DateTime.now()
          .add(const Duration(minutes: 10))
          .toIso8601String();

      await SupabaseConfig.supabase
          .from('orders')
          .update({'otp_code': otp, 'otp_expires_at': expiry})
          .eq('id', _order['id']);

      debugPrint('Sending OTP Notification to Buyer ID: ${_order['buyer_id']}');

      // Send push notification to buyer with OTP
      await FCMService.sendPushNotificationToUser(
        userId: _order['buyer_id'],
        title: 'OTP for Service Verification',
        message:
            'Your Service Verification OTP is: $otp. Share this with the provider to start the job.',
        screen: 'order_detail',
        orderId: _order['id'],
      );

      debugPrint('OTP Notification sent to buyer');

      if (mounted) {
        _showSuccessSnackBar('OTP generated and sent to customer!');
        _showOTPDialog();
      }
    } catch (e) {
      debugPrint('Error generating OTP: $e');
      if (mounted) {
        _showErrorSnackBar('Error: $e');
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  void _showOTPDialog() {
    _otpController.clear();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool verifying = false;
        String? otpError;

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(_AppTheme.radiusLg),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(_AppTheme.spacing2),
                    decoration: BoxDecoration(
                      color: _AppTheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(_AppTheme.radiusSm),
                    ),
                    child: const Icon(
                      Icons.verified_user_rounded,
                      color: _AppTheme.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: _AppTheme.spacing3),
                  const Text(
                    'Verify Customer OTP',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: _AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ask the customer for the 6-digit OTP sent to their app/phone.',
                    style: TextStyle(
                      color: _AppTheme.textSecondary,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: _AppTheme.spacing4),
                  TextField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 8,
                    ),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      labelText: 'Enter OTP',
                      counterText: '',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(_AppTheme.radiusMd),
                        borderSide: const BorderSide(color: _AppTheme.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(_AppTheme.radiusMd),
                        borderSide: const BorderSide(
                          color: _AppTheme.primary,
                          width: 2,
                        ),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(_AppTheme.radiusMd),
                        borderSide: const BorderSide(color: _AppTheme.error),
                      ),
                      errorText: otpError,
                      filled: true,
                      fillColor: _AppTheme.surfaceVariant,
                    ),
                    onChanged: (_) {
                      if (otpError != null) {
                        setState(() => otpError = null);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                    foregroundColor: _AppTheme.textSecondary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: _AppTheme.spacing4,
                      vertical: _AppTheme.spacing3,
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: verifying
                      ? null
                      : () async {
                          setState(() {
                            verifying = true;
                            otpError = null;
                          });

                          try {
                            final inputOtp = _otpController.text.trim();
                            if (inputOtp.isEmpty) {
                              throw "Please enter OTP";
                            }

                            final serverOrder = await SupabaseConfig.supabase
                                .from('orders')
                                .select('otp_code, otp_expires_at')
                                .eq('id', _order['id'])
                                .single();

                            final dbOtp = serverOrder['otp_code'];
                            final expiryStr = serverOrder['otp_expires_at'];

                            if (dbOtp == null || expiryStr == null) {
                              throw "OTP not set on server. Generate again.";
                            }

                            final expiresAt = DateTime.parse(expiryStr);
                            if (DateTime.now().isAfter(expiresAt)) {
                              throw "OTP Expired! Please generate a new one.";
                            }

                            if (dbOtp != inputOtp) {
                              throw "OTP is wrong";
                            }

                            await SupabaseConfig.supabase
                                .from('orders')
                                .update({'status': 'verified'})
                                .eq('id', _order['id']);

                            // Clear the OTP verification deadline (verified in time!)
                            await OtpVerificationService.clearOtpDeadline(_order['id']);

                            await OrderTimerManager.startTimer(_order['id']);

                            // Send push notification to buyer - job verified
                            await FCMService.sendPushNotificationToUser(
                              userId: _order['buyer_id'],
                              title: 'Service Verified!',
                              message:
                                  'The provider is verified and work has started! You have 24 hours to update the status.',
                              screen: 'order_detail',
                              orderId: _order['id'],
                            );

                            if (mounted) {
                              _showSuccessSnackBar(
                                'Verification Successful! Job Started.',
                              );
                              Navigator.pop(ctx);
                              _refetchOrder();
                            }
                          } catch (e) {
                            debugPrint("OTP Error caught: $e");
                            setState(() {
                              String msg = e.toString();
                              if (msg.startsWith("Exception: ")) {
                                msg = msg.substring(11);
                              }
                              otpError = msg;
                            });
                          } finally {
                            if (context.mounted) {
                              setState(() => verifying = false);
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _AppTheme.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: _AppTheme.spacing5,
                      vertical: _AppTheme.spacing3,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(_AppTheme.radiusSm),
                    ),
                  ),
                  child: verifying
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Verify',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleServiceCompleted() async {
    final reviewSubmitted = await showProviderReviewDialog(
      context: context,
      orderId: _order['id'],
      providerId: _order['provider_id'],
      providerName: _order['provider']?['full_name'] ?? 'Provider',
    );

    if (reviewSubmitted == false) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => _buildConfirmDialog(
          title: 'Skip Review?',
          message:
              'Are you sure you want to complete the service without leaving a review?',
          confirmText: 'Yes, Complete',
          confirmColor: _AppTheme.primary,
        ),
      );

      if (confirm != true) return;
    }

    setState(() => _isActionLoading = true);
    try {
      final result = await OrderTimerManager.completeOrderWithEarnings(
        _order['id'],
        _order['provider_id'],
      );

      if (result['success'] == true) {
        final amount = result['amount_added'] ?? 0;
        if (mounted) {
          _showSuccessSnackBar('Earned Rs.$amount! Service Completed.');
        }
      } else {
        throw result['error'] ?? 'Unknown completion error';
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Error completing order: $e');
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _handleCancelled() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _buildConfirmDialog(
        title: 'Cancel Order',
        message:
            'Are you sure you want to cancel this order? This action cannot be undone.',
        confirmText: 'Yes, Cancel',
        confirmColor: _AppTheme.error,
      ),
    );

    if (confirmed != true) return;

    final wantsToReview = await showDialog<bool>(
      context: context,
      builder: (ctx) => _buildConfirmDialog(
        title: 'Leave a Review?',
        message:
            'Even though you\'re cancelling, would you like to leave a review for the provider?',
        confirmText: 'Yes, Review',
        cancelText: 'Skip',
        confirmColor: _AppTheme.primary,
      ),
    );

    bool? reviewSubmitted;
    if (wantsToReview == true) {
      reviewSubmitted = await showProviderReviewDialog(
        context: context,
        orderId: _order['id'],
        providerId: _order['provider_id'],
        providerName: _order['provider']?['full_name'] ?? 'Provider',
      );
    }

    setState(() => _isActionLoading = true);
    try {
      await OrderTimerManager.markCancelled(_order['id']);

      // Send push notification to provider - order cancelled
      await FCMService.sendPushNotificationToUser(
        userId: _order['provider_id'],
        title: 'Order Cancelled',
        message: 'Customer has cancelled the order.',
        screen: 'order_detail',
        orderId: _order['id'],
      );

      if (mounted) {
        _showWarningSnackBar(
          reviewSubmitted == true
              ? 'Order cancelled. Thank you for your feedback!'
              : 'Order cancelled successfully',
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Error cancelling order: $e');
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _handleWorking() async {
    setState(() => _isActionLoading = true);
    try {
      final result = await OrderExpiryService.extendDeadline(_order['id']);

      if (result['success'] == true) {
        await OrderTimerManager.resetTimer(_order['id']);

        // Send push notification to provider - deadline extended
        await FCMService.sendPushNotificationToUser(
          userId: _order['provider_id'],
          title: 'Deadline Extended',
          message:
              'Customer has extended the order deadline by 24 hours. No penalty applied.',
          screen: 'order_detail',
          orderId: _order['id'],
        );

        if (mounted) {
          _showInfoSnackBar('Deadline extended by 24 hours! ${result['message']}');
          _refetchOrder();
        }
      } else {
        throw result['error'] ?? 'Failed to extend deadline';
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Error updating status: $e');
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _handleUserNegotiation(String action, {double? amount}) async {
    setState(() => _isActionLoading = true);
    try {
      if (action == 'accept') {
        final finalPrice = _order['provider_price'] ?? _order['user_price'];

        await SupabaseConfig.supabase
            .from('orders')
            .update({'status': 'confirmed', 'price': finalPrice})
            .eq('id', _order['id']);

        // Set 24-hour OTP verification deadline for the provider
        await OtpVerificationService.setOtpDeadline(_order['id']);

        _notifyProvider('User accepted your offer of Rs.$finalPrice!');
      } else if (action == 'reject') {
        await SupabaseConfig.supabase
            .from('orders')
            .update({'status': 'rejected'})
            .eq('id', _order['id']);
        _notifyProvider('User rejected your counter-offer.');
      } else if (action == 'counter') {
        if (amount == null) return;
        await SupabaseConfig.supabase
            .from('orders')
            .update({'user_price': amount, 'last_offer_by': 'user'})
            .eq('id', _order['id']);
        _notifyProvider('User countered with Rs.$amount');
      }
    } catch (e) {
      debugPrint("Error handling user negotiation: $e");
      if (mounted) {
        _showErrorSnackBar('Error: $e');
      }
    } finally {
      if (mounted) setState(() => _isActionLoading = false);
    }
  }

  Future<void> _notifyProvider(String msg) async {
    final providerId = _order['provider_id'];
    if (providerId == null) return;

    // Send push notification to provider
    await FCMService.sendPushNotificationToUser(
      userId: providerId,
      title: 'Order Update',
      message: msg,
      screen: 'order_detail',
      orderId: _order['id'],
    );
  }

  Future<void> _showUserCounterDialog() async {
    final priceController = TextEditingController();
    final success = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_AppTheme.radiusLg),
        ),
        title: const Text(
          'Counter Offer',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: _AppTheme.textPrimary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter your counter-offer amount:',
              style: TextStyle(color: _AppTheme.textSecondary),
            ),
            const SizedBox(height: _AppTheme.spacing3),
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                prefixText: 'Rs. ',
                prefixStyle: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: _AppTheme.textPrimary,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(_AppTheme.radiusMd),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(_AppTheme.radiusMd),
                  borderSide: const BorderSide(
                    color: _AppTheme.primary,
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: _AppTheme.surfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: _AppTheme.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (priceController.text.isNotEmpty) Navigator.pop(ctx, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Send Offer'),
          ),
        ],
      ),
    );

    if (success == true) {
      final amt = double.tryParse(priceController.text.trim());
      if (amt != null) {
        _handleUserNegotiation('counter', amount: amt);
      }
    }
  }

  // --- SNACKBAR HELPERS ---
  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: _AppTheme.spacing3),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: _AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_AppTheme.radiusSm),
        ),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_rounded, color: Colors.white),
            const SizedBox(width: _AppTheme.spacing3),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: _AppTheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_AppTheme.radiusSm),
        ),
      ),
    );
  }

  void _showWarningSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_rounded, color: Colors.white),
            const SizedBox(width: _AppTheme.spacing3),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: _AppTheme.warning,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_AppTheme.radiusSm),
        ),
      ),
    );
  }

  void _showInfoSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_rounded, color: Colors.white),
            const SizedBox(width: _AppTheme.spacing3),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: _AppTheme.info,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_AppTheme.radiusSm),
        ),
      ),
    );
  }

  Widget _buildConfirmDialog({
    required String title,
    required String message,
    required String confirmText,
    String cancelText = 'Cancel',
    required Color confirmColor,
  }) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_AppTheme.radiusLg),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: _AppTheme.textPrimary,
        ),
      ),
      content: Text(
        message,
        style: TextStyle(color: _AppTheme.textSecondary, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            cancelText,
            style: TextStyle(color: _AppTheme.textSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: confirmColor,
            foregroundColor: Colors.white,
          ),
          child: Text(confirmText),
        ),
      ],
    );
  }

  // --- UI ---
  @override
  Widget build(BuildContext context) {
    String status = (_order['status'] ?? 'pending').toString().toLowerCase();

    if (status == 'request_open' && _order['created_at'] != null) {
      final createdAt = DateTime.parse(_order['created_at']);
      final diff = DateTime.now().difference(createdAt);
      if (diff.inHours >= 24) {
        status = 'expired';
      }
    }

    final serviceName = _order['service']?['name'] ?? 'Service';
    final providerName = _order['provider']?['full_name'] ?? 'Unknown Provider';
    final buyerName = _order['buyer']?['full_name'] ?? 'Unknown User';
    final message = _order['description'] ?? 'No description provided.';
    final imagePath = _order['image_path'];

    String createdAtStr = 'Unknown Date';
    if (_order['created_at'] != null) {
      try {
        final dt = DateTime.parse(_order['created_at']);
        createdAtStr = DateFormat('MMM d, y - hh:mm a').format(dt);
      } catch (e) {
        createdAtStr = _order['created_at'].toString();
      }
    }

    final bool isProvider = widget.isProvider;

    return Scaffold(
      backgroundColor: _AppTheme.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Modern App Bar
          _buildSliverAppBar(serviceName, status),

          // Content
          SliverToBoxAdapter(
            child: AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return FadeTransition(
                  opacity: _animationController,
                  child: child,
                );
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status Header Card
                  _buildStatusCard(status, serviceName),

                  // Loading State
                  if (_isActionLoading) _buildLoadingIndicator(),

                  if (!_isActionLoading) ...[
                    // Action Buttons based on status
                    _buildActionButtons(status, isProvider, serviceName),

                    // OTP Card for User Only (when OTP is available and not yet verified)
                    if (!isProvider &&
                        _order['otp_code'] != null &&
                        status != 'verified' &&
                        status != 'working' &&
                        status != 'completed')
                      _buildUserOTPCard(),

                    // Order Info Section
                    _buildSectionHeader('Order Information'),
                    _buildOrderInfoCard(
                      isProvider,
                      providerName,
                      buyerName,
                      createdAtStr,
                    ),

                    // Price Card
                    _buildPriceCard(),

                    // Communication Section
                    if (_shouldShowCommunication(status, isProvider))
                      _buildCommunicationSection(isProvider, serviceName),

                    // Location Section
                    if (status != 'completed')
                      _buildLocationSection(isProvider),

                    // Requirements Section
                    _buildSectionHeader('Requirements'),
                    _buildRequirementsCard(message),

                    // Images Section
                    if (_order['images'] != null &&
                        (_order['images'] as List).isNotEmpty)
                      _buildImagesSection(),

                    // Legacy single image
                    if (_order['images'] == null &&
                        imagePath != null &&
                        imagePath.isNotEmpty)
                      _buildLegacyImageSection(imagePath),

                    // Timeline Section
                    _buildSectionHeader('Order Timeline'),
                    _buildTimelineCard(status),

                    const SizedBox(height: _AppTheme.spacing8),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar(String serviceName, String status) {
    return SliverAppBar(
      expandedHeight: 120,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: _AppTheme.primary,
      foregroundColor: Colors.white,
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          'Order Details',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            shadows: [
              Shadow(
                color: Colors.black.withOpacity(0.2),
                offset: const Offset(0, 1),
                blurRadius: 2,
              ),
            ],
          ),
        ),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_AppTheme.primaryLight, _AppTheme.primaryDark],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -50,
                top: -50,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.1),
                  ),
                ),
              ),
              Positioned(
                left: -30,
                bottom: -30,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.08),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: _AppTheme.spacing2),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(_AppTheme.radiusSm),
          ),
          child: IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              _refetchOrder();
              _showInfoSnackBar('Refreshing order details...');
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatusCard(String status, String serviceName) {
    final statusInfo = _getStatusInfo(status);

    return Container(
      margin: const EdgeInsets.all(_AppTheme.spacing4),
      padding: const EdgeInsets.all(_AppTheme.spacing5),
      decoration: BoxDecoration(
        color: _AppTheme.surface,
        borderRadius: BorderRadius.circular(_AppTheme.radiusXl),
        boxShadow: _AppTheme.shadowMd,
        border: Border.all(color: _AppTheme.border.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          // Service Icon
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [statusInfo.color.withOpacity(0.8), statusInfo.color],
              ),
              borderRadius: BorderRadius.circular(_AppTheme.radiusLg),
              boxShadow: [
                BoxShadow(
                  color: statusInfo.color.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(statusInfo.icon, color: Colors.white, size: 32),
          ),
          const SizedBox(height: _AppTheme.spacing4),

          // Service Name
          Text(
            serviceName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: _AppTheme.textPrimary,
              letterSpacing: -0.5,
            ),
          ),

          // Sub-service Type
          if (_getSubServiceType() != null) ...[
            const SizedBox(height: _AppTheme.spacing2),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: _AppTheme.spacing3,
                vertical: _AppTheme.spacing1,
              ),
              decoration: BoxDecoration(
                color: _AppTheme.primaryLight.withOpacity(0.15),
                borderRadius: BorderRadius.circular(_AppTheme.radiusFull),
              ),
              child: Text(
                _getSubServiceType()!,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _AppTheme.primary,
                ),
              ),
            ),
          ],
          const SizedBox(height: _AppTheme.spacing3),

          // Status Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: _AppTheme.spacing4,
                  vertical: _AppTheme.spacing2,
                ),
                decoration: BoxDecoration(
                  color: statusInfo.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(_AppTheme.radiusFull),
                  border: Border.all(color: statusInfo.color.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusInfo.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: _AppTheme.spacing2),
                    Text(
                      statusInfo.label,
                      style: TextStyle(
                        color: statusInfo.color,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),

            ],
          ),

          // Deadline Timer
          if (_order['deadline'] != null &&
              status != 'completed' &&
              status != 'cancelled' &&
              status != 'expired') ...[
            const SizedBox(height: _AppTheme.spacing4),
            Container(
              padding: const EdgeInsets.all(_AppTheme.spacing3),
              decoration: BoxDecoration(
                color: _AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(_AppTheme.radiusMd),
              ),
              child: DeadlineTimer(
                deadline: DateTime.parse(_order['deadline']),
                compact: true,
                onExpired: () async {
                  await OrderExpiryService.checkExpiredOrders();
                  _refetchOrder();
                },
              ),
            ),
            if ((_order['extension_count'] ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(top: _AppTheme.spacing2),
                child: Text(
                  'Extended ${_order['extension_count']} time(s)',
                  style: TextStyle(
                    fontSize: 12,
                    color: _AppTheme.textMuted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],

          // Order ID
          const SizedBox(height: _AppTheme.spacing4),
          Text(
            'ID: ${_order['id'].substring(0, 8).toUpperCase()}',
            style: TextStyle(
              color: _AppTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Container(
      margin: const EdgeInsets.all(_AppTheme.spacing4),
      padding: const EdgeInsets.all(_AppTheme.spacing8),
      decoration: BoxDecoration(
        color: _AppTheme.surface,
        borderRadius: BorderRadius.circular(_AppTheme.radiusLg),
        boxShadow: _AppTheme.shadowSm,
      ),
      child: Column(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(_AppTheme.primary),
            ),
          ),
          const SizedBox(height: _AppTheme.spacing4),
          Text(
            'Processing...',
            style: TextStyle(
              color: _AppTheme.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(
    String status,
    bool isProvider,
    String serviceName,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _AppTheme.spacing4),
      child: Column(
        children: [
          // User: View Offers
          if (!isProvider &&
              status != 'expired' &&
              (status == 'request_open' || status == 'pending'))
            _buildPrimaryButton(
              label: 'View Offers from Providers',
              icon: Icons.local_offer_rounded,
              color: _AppTheme.warning,
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UserOffersPage(orderId: _order['id']),
                  ),
                );
                _refetchOrder();
              },
            ),

          // Provider: OTP Verification Timer + Verify Button
          if (isProvider && (status == 'accepted' || status == 'confirmed' || status == 'expired')) ...[
            // Show OTP Verification Deadline Timer
            if (_order['otp_verification_deadline'] != null)
              _buildOtpVerificationTimer(),
            // Only show the Send OTP button if deadline has NOT expired AND order is not expired
            if ((status == 'accepted' || status == 'confirmed') && _isOtpDeadlineActive())
              _buildPrimaryButton(
                label: 'Verify Order (Send OTP)',
                icon: Icons.verified_user_rounded,
                color: _AppTheme.info,
                onPressed: _generateAndSendOTP,
              ),
          ],

          // User: OTP Verification Failed Message
          if (!isProvider && status == 'expired' && _order['otp_verification_deadline'] != null)
            Container(
              margin: const EdgeInsets.only(bottom: _AppTheme.spacing4),
              padding: const EdgeInsets.all(_AppTheme.spacing4),
              decoration: BoxDecoration(
                color: _AppTheme.errorLight,
                borderRadius: BorderRadius.circular(_AppTheme.radiusMd),
                border: Border.all(color: _AppTheme.error.withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded, color: _AppTheme.error, size: 28),
                  const SizedBox(width: _AppTheme.spacing3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order Failed (OTP Timeout)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: _AppTheme.error,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'The provider failed to verify their arrival via OTP in time. A penalty has been applied to their account. Please post a new order to find another provider.',
                          style: TextStyle(
                            fontSize: 13,
                            color: _AppTheme.error,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // User: Timer and Actions
          if (!isProvider && (status == 'verified' || status == 'working')) ...[
            // Timer
            if (_order['timer_expires_at'] != null)
              Container(
                margin: const EdgeInsets.only(bottom: _AppTheme.spacing4),
                padding: const EdgeInsets.all(_AppTheme.spacing4),
                decoration: BoxDecoration(
                  color: _AppTheme.surface,
                  borderRadius: BorderRadius.circular(_AppTheme.radiusLg),
                  boxShadow: _AppTheme.shadowSm,
                ),
                child: OrderCountdownTimer(
                  orderId: _order['id'],
                  expiresAt: DateTime.parse(_order['timer_expires_at']),
                  onExpired: () async {
                    await OrderTimerManager.checkAndApplyExpiry(_order['id']);
                    _refetchOrder();
                  },
                ),
              ),

            // Info Card
            _buildInfoCard(
              icon: Icons.info_outline_rounded,
              message:
                  'Mark as completed, extend deadline (+24h), or cancel the order.',
              color: _AppTheme.info,
            ),
            const SizedBox(height: _AppTheme.spacing4),

            // Action Buttons Row
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    label: 'Cancel',
                    icon: Icons.cancel_rounded,
                    color: _AppTheme.error,
                    onPressed: _handleCancelled,
                  ),
                ),
                const SizedBox(width: _AppTheme.spacing3),
                Expanded(
                  child: _buildActionButton(
                    label: 'Extend Deadline',
                    icon: Icons.schedule_rounded,
                    color: _AppTheme.warning,
                    onPressed: _handleWorking,
                  ),
                ),
              ],
            ),
            const SizedBox(height: _AppTheme.spacing3),

            // Complete Button
            _buildPrimaryButton(
              label: 'Service Completed',
              icon: Icons.check_circle_rounded,
              color: _AppTheme.success,
              onPressed: _handleServiceCompleted,
            ),
          ],

          // Provider: Show Timer and Info
          if (isProvider && (status == 'verified' || status == 'working')) ...[
            if (_order['timer_expires_at'] != null)
              Container(
                margin: const EdgeInsets.only(bottom: _AppTheme.spacing4),
                padding: const EdgeInsets.all(_AppTheme.spacing4),
                decoration: BoxDecoration(
                  color: _AppTheme.surface,
                  borderRadius: BorderRadius.circular(_AppTheme.radiusLg),
                  boxShadow: _AppTheme.shadowSm,
                ),
                child: OrderCountdownTimer(
                  orderId: _order['id'],
                  expiresAt: DateTime.parse(_order['timer_expires_at']),
                  onExpired: () async {
                    await OrderTimerManager.checkAndApplyExpiry(_order['id']);
                    _refetchOrder();
                  },
                ),
              )
            else
              _buildInfoCard(
                icon: Icons.timer_off_rounded,
                message: 'Timer not yet started',
                color: _AppTheme.textMuted,
              ),

            const SizedBox(height: _AppTheme.spacing3),

            // Warning Card
            Container(
              padding: const EdgeInsets.all(_AppTheme.spacing4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _AppTheme.warning.withOpacity(0.9),
                    _AppTheme.warning,
                  ],
                ),
                borderRadius: BorderRadius.circular(_AppTheme.radiusLg),
                boxShadow: [
                  BoxShadow(
                    color: _AppTheme.warning.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(_AppTheme.spacing3),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(_AppTheme.radiusMd),
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: _AppTheme.spacing4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Customer Action Pending',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Waiting for customer to respond',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: _AppTheme.spacing3),

            // Job Status Badge
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(_AppTheme.spacing4),
              decoration: BoxDecoration(
                color: _AppTheme.successLight,
                borderRadius: BorderRadius.circular(_AppTheme.radiusMd),
                border: Border.all(color: _AppTheme.success.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    status == 'working'
                        ? Icons.construction_rounded
                        : Icons.verified_user_rounded,
                    color: _AppTheme.success,
                    size: 22,
                  ),
                  const SizedBox(width: _AppTheme.spacing2),
                  Text(
                    status == 'working'
                        ? "Job In Progress"
                        : "Job Verified & In Progress",
                    style: TextStyle(
                      color: _AppTheme.success,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Negotiation UI
          if (!isProvider && status == 'negotiating') _buildNegotiationCard(),

          const SizedBox(height: _AppTheme.spacing4),
        ],
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: double.infinity,
      height: 56,
      margin: const EdgeInsets.only(bottom: _AppTheme.spacing4),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
        label: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_AppTheme.radiusMd),
          ),
          shadowColor: color.withOpacity(0.3),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_AppTheme.radiusMd),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String message,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(_AppTheme.spacing4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(_AppTheme.radiusMd),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: _AppTheme.spacing3),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 14,
                color: color,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNegotiationCard() {
    final lastBy = _order['last_offer_by'] ?? 'user';
    final bool isUserTurn = lastBy == 'provider';
    final activePrice = lastBy == 'user'
        ? (_order['user_price'] ?? 0)
        : (_order['provider_price'] ?? 0);

    return Container(
      margin: const EdgeInsets.only(top: _AppTheme.spacing2),
      padding: const EdgeInsets.all(_AppTheme.spacing5),
      decoration: BoxDecoration(
        color: _AppTheme.surface,
        borderRadius: BorderRadius.circular(_AppTheme.radiusLg),
        border: Border.all(color: _AppTheme.primary.withOpacity(0.2)),
        boxShadow: _AppTheme.shadowSm,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.handshake_rounded, color: _AppTheme.primary, size: 24),
              const SizedBox(width: _AppTheme.spacing2),
              Text(
                "Negotiation in Progress",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _AppTheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: _AppTheme.spacing4),

          Container(
            padding: const EdgeInsets.all(_AppTheme.spacing4),
            decoration: BoxDecoration(
              color: _AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(_AppTheme.radiusMd),
            ),
            child: Column(
              children: [
                Text(
                  isUserTurn ? "Provider Requested:" : "You Offered:",
                  style: TextStyle(
                    fontSize: 14,
                    color: _AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: _AppTheme.spacing2),
                Text(
                  "Rs.$activePrice",
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: isUserTurn ? _AppTheme.warning : _AppTheme.primary,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: _AppTheme.spacing5),

          if (isUserTurn) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _handleUserNegotiation('reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _AppTheme.error,
                      side: BorderSide(color: _AppTheme.error),
                      padding: const EdgeInsets.symmetric(
                        vertical: _AppTheme.spacing3,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(_AppTheme.radiusSm),
                      ),
                    ),
                    child: const Text("Reject"),
                  ),
                ),
                const SizedBox(width: _AppTheme.spacing3),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _showUserCounterDialog,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _AppTheme.primary,
                      side: BorderSide(color: _AppTheme.primary),
                      padding: const EdgeInsets.symmetric(
                        vertical: _AppTheme.spacing3,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(_AppTheme.radiusSm),
                      ),
                    ),
                    child: const Text("Counter"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: _AppTheme.spacing3),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => _handleUserNegotiation('accept'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _AppTheme.success,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(_AppTheme.radiusSm),
                  ),
                ),
                child: const Text(
                  "ACCEPT PRICE",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ] else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _AppTheme.primary,
                  ),
                ),
                const SizedBox(width: _AppTheme.spacing2),
                Text(
                  "Waiting for provider to respond...",
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: _AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _AppTheme.spacing4,
        _AppTheme.spacing4,
        _AppTheme.spacing4,
        _AppTheme.spacing3,
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: _AppTheme.textPrimary,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildOrderInfoCard(
    bool isProvider,
    String providerName,
    String buyerName,
    String createdAtStr,
  ) {
    // Get avatar URLs
    final providerAvatar = _order['provider']?['avatar_url'] as String?;
    final buyerAvatar = _order['buyer']?['avatar_url'] as String?;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: _AppTheme.spacing4),
      decoration: BoxDecoration(
        color: _AppTheme.surface,
        borderRadius: BorderRadius.circular(_AppTheme.radiusLg),
        boxShadow: _AppTheme.shadowSm,
      ),
      child: Column(
        children: [
          _buildPersonInfoRow(
            label: isProvider ? 'Buyer' : 'Provider',
            name: isProvider ? buyerName : providerName,
            avatarUrl: isProvider ? buyerAvatar : providerAvatar,
            iconColor: _AppTheme.primary,
          ),
          Divider(height: 1, color: _AppTheme.border),
          _buildInfoRow(
            icon: Icons.calendar_today_rounded,
            label: 'Created',
            value: createdAtStr,
            iconColor: _AppTheme.info,
          ),
        ],
      ),
    );
  }

  Widget _buildPersonInfoRow({
    required String label,
    required String name,
    String? avatarUrl,
    required Color iconColor,
  }) {
    return Padding(
      padding: const EdgeInsets.all(_AppTheme.spacing4),
      child: Row(
        children: [
          // Profile Picture
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: iconColor.withOpacity(0.1),
              border: Border.all(color: iconColor.withOpacity(0.3), width: 2),
            ),
            child: ClipOval(
              child: avatarUrl != null && avatarUrl.isNotEmpty
                  ? Image.network(
                      SupabaseConfig.proxyImageUrl(avatarUrl),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(
                          Icons.person_rounded,
                          color: iconColor,
                          size: 28,
                        );
                      },
                    )
                  : Icon(Icons.person_rounded, color: iconColor, size: 28),
            ),
          ),
          const SizedBox(width: _AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: _AppTheme.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required Color iconColor,
  }) {
    return Padding(
      padding: const EdgeInsets.all(_AppTheme.spacing4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(_AppTheme.spacing2),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(_AppTheme.radiusSm),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: _AppTheme.spacing3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: _AppTheme.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Returns true if OTP deadline exists and has NOT expired yet.
  bool _isOtpDeadlineActive() {
    final deadlineStr = _order['otp_verification_deadline'];
    if (deadlineStr == null) return true; // No deadline set, allow button
    final deadline = DateTime.parse(deadlineStr);
    return DateTime.now().isBefore(deadline);
  }

  /// Builds a live countdown timer showing how long the provider has to verify OTP.
  /// If the deadline has passed, it shows an "EXPIRED" warning with red star info.
  Widget _buildOtpVerificationTimer() {
    final deadlineStr = _order['otp_verification_deadline'];
    if (deadlineStr == null) return const SizedBox.shrink();

    final deadline = DateTime.parse(deadlineStr);
    final now = DateTime.now();
    final remaining = deadline.difference(now);
    final isExpired = remaining.isNegative;

    final hours = remaining.inHours.abs();
    final minutes = remaining.inMinutes.remainder(60).abs();
    final seconds = remaining.inSeconds.remainder(60).abs();

    // Determine color scheme based on urgency
    final bool isUrgent = !isExpired && remaining.inMinutes < 5;
    final List<Color> gradientColors = isExpired
        ? [Colors.red.shade50, Colors.red.shade100]
        : isUrgent
            ? [Colors.orange.shade50, Colors.orange.shade100]
            : [Colors.blue.shade50, Colors.blue.shade100];
    final Color borderColor = isExpired
        ? Colors.red.shade300
        : isUrgent
            ? Colors.orange.shade300
            : Colors.blue.shade300;
    final Color iconColor = isExpired
        ? Colors.red.shade700
        : isUrgent
            ? Colors.orange.shade700
            : Colors.blue.shade700;
    final Color titleColor = isExpired
        ? Colors.red.shade800
        : isUrgent
            ? Colors.orange.shade800
            : Colors.blue.shade800;
    final Color subtitleColor = isExpired
        ? Colors.red.shade600
        : isUrgent
            ? Colors.orange.shade600
            : Colors.blue.shade600;

    return Container(
      margin: const EdgeInsets.only(bottom: _AppTheme.spacing3),
      padding: const EdgeInsets.all(_AppTheme.spacing4),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradientColors),
        borderRadius: BorderRadius.circular(_AppTheme.radiusMd),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                isExpired ? Icons.warning_amber_rounded : Icons.timer_outlined,
                color: iconColor,
                size: 28,
              ),
              const SizedBox(width: _AppTheme.spacing3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isExpired
                          ? '⛔ OTP Verification Failed!'
                          : '⏱️ OTP Verification Deadline',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isExpired
                          ? 'Time expired! A Red Star penalty has been applied to your account. The customer has been notified.'
                          : 'Verify OTP before time runs out to avoid a Red Star penalty.',
                      style: TextStyle(
                        fontSize: 12,
                        color: subtitleColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!isExpired) ...[
            const SizedBox(height: 12),
            // Live countdown display
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildTimeUnit(hours.toString().padLeft(2, '0'), 'HRS'),
                  Text(' : ', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: titleColor)),
                  _buildTimeUnit(minutes.toString().padLeft(2, '0'), 'MIN'),
                  Text(' : ', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: titleColor)),
                  _buildTimeUnit(seconds.toString().padLeft(2, '0'), 'SEC'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Helper widget for individual time units in the countdown.
  Widget _buildTimeUnit(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildPriceCard() {
    return FutureBuilder<double?>(
      future: _getApprovedPrice(),
      builder: (context, snapshot) {
        final userPriceCol = (_order['user_price'] as num?)?.toDouble();
        final priceCol = (_order['price'] as num?)?.toDouble();

        double originalPrice = userPriceCol ?? priceCol ?? 0.0;
        double? approvedPrice = snapshot.data;

        if (approvedPrice == null && priceCol != null && userPriceCol != null && priceCol != userPriceCol) {
          approvedPrice = priceCol;
          originalPrice = userPriceCol;
        }

        final displayPrice = approvedPrice ?? originalPrice;
        final isPriceUpdated = approvedPrice != null;

        return Container(
          margin: const EdgeInsets.all(_AppTheme.spacing4),
          padding: const EdgeInsets.all(_AppTheme.spacing5),
          decoration: BoxDecoration(
            color: _AppTheme.surface,
            borderRadius: BorderRadius.circular(_AppTheme.radiusLg),
            border: Border.all(
              color: isPriceUpdated
                  ? _AppTheme.warning.withOpacity(0.3)
                  : _AppTheme.success.withOpacity(0.3),
              width: 1.5,
            ),
            boxShadow: _AppTheme.shadowSm,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(_AppTheme.spacing3),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isPriceUpdated
                        ? [
                            _AppTheme.warning.withOpacity(0.8),
                            _AppTheme.warning,
                          ]
                        : [
                            _AppTheme.success.withOpacity(0.8),
                            _AppTheme.success,
                          ],
                  ),
                  borderRadius: BorderRadius.circular(_AppTheme.radiusMd),
                ),
                child: const Icon(
                  Icons.currency_rupee_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: _AppTheme.spacing4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPriceUpdated ? 'Approved Price' : 'Service Price',
                      style: TextStyle(
                        fontSize: 12,
                        color: _AppTheme.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Rs.$displayPrice',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: isPriceUpdated
                            ? _AppTheme.warning
                            : _AppTheme.success,
                      ),
                    ),
                    if (isPriceUpdated)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Original: Rs.$originalPrice',
                          style: TextStyle(
                            fontSize: 12,
                            color: _AppTheme.textMuted,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // OTP Display Card for User Only
  Widget _buildUserOTPCard() {
    final otpCode = _order['otp_code']?.toString();
    final expiryStr = _order['otp_expires_at'];

    if (otpCode == null || otpCode.isEmpty) {
      return const SizedBox.shrink();
    }

    bool isExpired = false;
    String expiryText = '';

    if (expiryStr != null) {
      try {
        final expiresAt = DateTime.parse(expiryStr);
        isExpired = DateTime.now().isAfter(expiresAt);
        if (!isExpired) {
          final remaining = expiresAt.difference(DateTime.now());
          expiryText = 'Expires in ${remaining.inMinutes} min';
        } else {
          expiryText = 'OTP Expired';
        }
      } catch (e) {
        debugPrint('Error parsing OTP expiry: $e');
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: _AppTheme.spacing4,
        vertical: _AppTheme.spacing2,
      ),
      padding: const EdgeInsets.all(_AppTheme.spacing5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isExpired
              ? [Colors.grey.shade400, Colors.grey.shade500]
              : [_AppTheme.primary.withOpacity(0.9), _AppTheme.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(_AppTheme.radiusLg),
        boxShadow: [
          BoxShadow(
            color: isExpired
                ? Colors.grey.withOpacity(0.3)
                : _AppTheme.primary.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(_AppTheme.spacing2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(_AppTheme.radiusSm),
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: _AppTheme.spacing2),
              const Text(
                'Your Verification OTP',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: _AppTheme.spacing4),

          // OTP Code Display
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: _AppTheme.spacing6,
              vertical: _AppTheme.spacing4,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(_AppTheme.radiusMd),
            ),
            child: Text(
              otpCode,
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                letterSpacing: 12,
                color: isExpired ? Colors.grey : _AppTheme.primary,
              ),
            ),
          ),

          const SizedBox(height: _AppTheme.spacing3),

          // Expiry Info
          if (expiryText.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isExpired ? Icons.timer_off_rounded : Icons.timer_rounded,
                  color: Colors.white.withOpacity(0.8),
                  size: 16,
                ),
                const SizedBox(width: _AppTheme.spacing1),
                Text(
                  expiryText,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),

          const SizedBox(height: _AppTheme.spacing3),

          // Instruction
          Text(
            isExpired
                ? 'Please ask provider to send a new OTP'
                : 'Share this OTP with the provider to verify the service',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }

  bool _shouldShowCommunication(String status, bool isProvider) {
    final validStatuses = ['accepted', 'verified', 'confirmed', 'working'];
    return validStatuses.contains(status);
  }

  Widget _buildCommunicationSection(bool isProvider, String serviceName) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _AppTheme.spacing4,
        vertical: _AppTheme.spacing2,
      ),
      child: Row(
        children: [
          // Voice Call Button
          if (_getPhoneNumber(isProvider) != null)
            Expanded(
              child: _buildCommButton(
                icon: Icons.phone_android,
                label: 'Voice Call',
                color: _AppTheme.success,
                onPressed: () => _startVoiceCall(isProvider),
              ),
            ),
          if (_getPhoneNumber(isProvider) != null)
            const SizedBox(width: _AppTheme.spacing3),
          // Chat Button
          Expanded(
            child: _buildCommButton(
              icon: Icons.chat_bubble_rounded,
              label: 'Chat',
              color: _AppTheme.info,
              onPressed: () {
                final userId = isProvider
                    ? _order['provider_id']
                    : _order['buyer_id'];
                if (userId == null) {
                  _showErrorSnackBar('Unable to start chat');
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OrderChatPage(
                      orderId: _order['id'],
                      orderTitle: '$serviceName Order',
                      isProvider: isProvider,
                      userId: userId,
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

  String? _getPhoneNumber(bool isProvider) {
    if (isProvider) {
      // Provider calling buyer - check user_phone first, then buyer's phone_number
      return _order['user_phone'] ?? _order['buyer']?['phone_number'];
    } else {
      // User calling provider - get provider's phone_number
      return _order['provider']?['phone_number'];
    }
  }

  Widget _buildCommButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_AppTheme.radiusMd),
          ),
        ),
      ),
    );
  }

  /// Start a LiveKit voice call
  Future<void> _startVoiceCall(bool isProvider) async {
    final orderId = _order['id'];
    if (orderId == null) {
      _showErrorSnackBar('Unable to start voice call');
      return;
    }

    // Get current user ID and name
    final isLoggedIn = await SessionManager.isLoggedIn();
    if (!isLoggedIn) {
      _showErrorSnackBar('Please log in to make voice calls');
      return;
    }
    final currentUsername = await SessionManager.getUsername();
    final currentUserId = await SessionManager.getUserId();

    // Get callee name based on user role
    String calleeName;
    String callerName;
    bool isCaller;

    if (isProvider) {
      // Provider is calling the user/buyer
      final buyer = _order['buyer'];
      calleeName = buyer?['name'] ?? 'Customer';
      callerName = currentUsername ?? currentUserId ?? 'Provider';
      isCaller = false; // Provider is the callee in this context
    } else {
      // User is calling the provider
      final provider = _order['provider'];
      if (provider == null) {
        _showErrorSnackBar('Provider information not available');
        return;
      }
      calleeName = provider['name'] ?? 'Provider';
      callerName = currentUsername ?? currentUserId ?? 'Customer';
      isCaller = true; // User is the caller
    }

    // Send instant call signal via Supabase Realtime Broadcast
    final String? calleeId = isProvider ? _order['user_id'] : _order['provider_id'];
    if (calleeId != null && currentUserId != null) {
      // 1. Try real-time broadcast for fast delivery if app is open
      CallSignalingService.instance.sendCallSignal(
        calleeId: calleeId,
        callerName: callerName,
        orderId: orderId,
        callerId: currentUserId,
      );

      // 2. Also trigger FCM Push Notification to wake up the app if it's in the background/closed
      try {
        await http.post(
          Uri.parse('https://mrhelper-livekit-voice-call.onrender.com/sendCallNotification'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'calleeId': calleeId,
            'callerName': callerName,
            'orderId': orderId,
            'callerId': currentUserId,
          }),
        );
      } catch (e) {
        debugPrint('Error triggering FCM call notification: $e');
      }
    }

    // Show loading indicator
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Connecting to voice call...'),
        duration: Duration(seconds: 1),
      ),
    );

    // Navigate to voice call screen
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VoiceCallScreen(
          orderId: orderId,
          callerName: callerName,
          calleeName: calleeName,
          isCaller: isCaller,
          calleeId: calleeId,
        ),
      ),
    );
  }

  /// Get callee name for voice call
  String _getCalleeName(bool isProvider) {
    if (isProvider) {
      final buyer = _order['buyer'];
      return buyer?['name'] ?? 'Customer';
    } else {
      final provider = _order['provider'];
      return provider?['name'] ?? 'Provider';
    }
  }

  Widget _buildLocationSection(bool isProvider) {
    return Padding(
      padding: const EdgeInsets.all(_AppTheme.spacing4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(_AppTheme.spacing2),
                decoration: BoxDecoration(
                  color: _AppTheme.info.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(_AppTheme.radiusSm),
                ),
                child: Icon(
                  Icons.location_on_rounded,
                  color: _AppTheme.info,
                  size: 20,
                ),
              ),
              const SizedBox(width: _AppTheme.spacing2),
              const Text(
                'Location Details',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: _AppTheme.spacing3),

          Container(
            padding: const EdgeInsets.all(_AppTheme.spacing4),
            decoration: BoxDecoration(
              color: _AppTheme.surface,
              borderRadius: BorderRadius.circular(_AppTheme.radiusLg),
              boxShadow: _AppTheme.shadowSm,
            ),
            child: Column(
              children: [
                // Region
                _buildLocationRow(
                  icon: Icons.public_rounded,
                  label: 'Region',
                  value: _order['location']?['name'] ?? 'Unknown Region',
                  color: _AppTheme.primary,
                ),
                const SizedBox(height: _AppTheme.spacing3),

                // Pickup Location
                Container(
                  padding: const EdgeInsets.all(_AppTheme.spacing3),
                  decoration: BoxDecoration(
                    color: _AppTheme.infoLight,
                    borderRadius: BorderRadius.circular(_AppTheme.radiusMd),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.my_location_rounded,
                            size: 16,
                            color: _AppTheme.info,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Pickup Location',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _AppTheme.info,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _order['address_gps'] ?? 'No specific address',
                        style: TextStyle(
                          fontSize: 14,
                          color: _AppTheme.textPrimary,
                        ),
                      ),
                      if (isProvider &&
                          _order['latitude'] != null &&
                          _order['longitude'] != null) ...[
                        const SizedBox(height: _AppTheme.spacing3),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: Icon(
                              Icons.map_rounded,
                              size: 18,
                              color: _AppTheme.info,
                            ),
                            label: Text(
                              'Open in Maps',
                              style: TextStyle(
                                color: _AppTheme.info,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: _AppTheme.info),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  _AppTheme.radiusSm,
                                ),
                              ),
                            ),
                            onPressed: () => _launchMap(
                              _order['latitude'],
                              _order['longitude'],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Destination
                if (_order['destination_address'] != null &&
                    _order['destination_address'].toString().isNotEmpty) ...[
                  const SizedBox(height: _AppTheme.spacing3),
                  Container(
                    padding: const EdgeInsets.all(_AppTheme.spacing3),
                    decoration: BoxDecoration(
                      color: _AppTheme.successLight,
                      borderRadius: BorderRadius.circular(_AppTheme.radiusMd),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.flag_rounded,
                              size: 16,
                              color: _AppTheme.success,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Destination',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _AppTheme.success,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _order['destination_address'] ?? '',
                          style: TextStyle(
                            fontSize: 14,
                            color: _AppTheme.textPrimary,
                          ),
                        ),
                        if (isProvider &&
                            _order['destination_latitude'] != null &&
                            _order['destination_longitude'] != null) ...[
                          const SizedBox(height: _AppTheme.spacing3),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: Icon(
                                Icons.map_rounded,
                                size: 18,
                                color: _AppTheme.success,
                              ),
                              label: Text(
                                'Open in Maps',
                                style: TextStyle(
                                  color: _AppTheme.success,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: _AppTheme.success),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    _AppTheme.radiusSm,
                                  ),
                                ),
                              ),
                              onPressed: () => _launchMap(
                                _order['destination_latitude'],
                                _order['destination_longitude'],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: _AppTheme.spacing2),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: _AppTheme.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRequirementsCard(String message) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: _AppTheme.spacing4),
      padding: const EdgeInsets.all(_AppTheme.spacing4),
      decoration: BoxDecoration(
        color: _AppTheme.surface,
        borderRadius: BorderRadius.circular(_AppTheme.radiusLg),
        boxShadow: _AppTheme.shadowSm,
      ),
      child: Text(
        message,
        style: TextStyle(
          fontSize: 15,
          height: 1.6,
          color: _AppTheme.textPrimary,
        ),
      ),
    );
  }

  Widget _buildImagesSection() {
    final images = _order['images'] as List;

    return Padding(
      padding: const EdgeInsets.all(_AppTheme.spacing4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(_AppTheme.spacing2),
                decoration: BoxDecoration(
                  color: _AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(_AppTheme.radiusSm),
                ),
                child: Icon(
                  Icons.photo_library_rounded,
                  color: _AppTheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: _AppTheme.spacing2),
              const Text(
                'Order Images',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: _AppTheme.spacing2,
                  vertical: _AppTheme.spacing1,
                ),
                decoration: BoxDecoration(
                  color: _AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(_AppTheme.radiusFull),
                ),
                child: Text(
                  '${images.length}',
                  style: TextStyle(
                    color: _AppTheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: _AppTheme.spacing3),
          Wrap(
            spacing: _AppTheme.spacing3,
            runSpacing: _AppTheme.spacing3,
            children: List.generate(images.length, (index) {
              final imageUrl = images[index];
              final screenWidth = MediaQuery.of(context).size.width;
              final imageSize = (screenWidth - 64) / 2;

              return GestureDetector(
                onTap: () => _showImageDialog(imageUrl),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_AppTheme.radiusMd),
                  child: Image.network(
                    SupabaseConfig.proxyImageUrl(imageUrl),
                    width: imageSize,
                    height: imageSize,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: imageSize,
                        height: imageSize,
                        decoration: BoxDecoration(
                          color: _AppTheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(
                            _AppTheme.radiusMd,
                          ),
                        ),
                        child: Icon(
                          Icons.broken_image_rounded,
                          size: 40,
                          color: _AppTheme.textMuted,
                        ),
                      );
                    },
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        width: imageSize,
                        height: imageSize,
                        decoration: BoxDecoration(
                          color: _AppTheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(
                            _AppTheme.radiusMd,
                          ),
                        ),
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _AppTheme.primary,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildLegacyImageSection(String imagePath) {
    return Padding(
      padding: const EdgeInsets.all(_AppTheme.spacing4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Attached Image',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: _AppTheme.spacing3),
          ClipRRect(
            borderRadius: BorderRadius.circular(_AppTheme.radiusMd),
            child: Image.file(
              File(imagePath),
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (ctx, _, __) => Container(
                height: 200,
                color: _AppTheme.surfaceVariant,
                child: Center(
                  child: Text(
                    'Image not found',
                    style: TextStyle(color: _AppTheme.textMuted),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showImageDialog(String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.network(SupabaseConfig.proxyImageUrl(imageUrl)),
              ),
            ),
            Positioned(
              top: 40,
              right: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineCard(String currentStatus) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: _AppTheme.spacing4),
      padding: const EdgeInsets.all(_AppTheme.spacing5),
      decoration: BoxDecoration(
        color: _AppTheme.surface,
        borderRadius: BorderRadius.circular(_AppTheme.radiusLg),
        boxShadow: _AppTheme.shadowSm,
      ),
      child: _buildTimeline(currentStatus),
    );
  }

  Widget _buildTimeline(String currentStatus) {
    if (currentStatus == 'rejected') {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(_AppTheme.spacing4),
          decoration: BoxDecoration(
            color: _AppTheme.errorLight,
            borderRadius: BorderRadius.circular(_AppTheme.radiusMd),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cancel_rounded, color: _AppTheme.error),
              const SizedBox(width: _AppTheme.spacing2),
              Text(
                'This order was rejected',
                style: TextStyle(
                  color: _AppTheme.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Timeline steps for display
    final displayLabels = ['Posted', 'Accepted', 'Verified', 'Done'];
    final icons = [
      Icons.post_add_rounded,
      Icons.thumb_up_rounded,
      Icons.verified_rounded,
      Icons.check_circle_rounded,
    ];

    // Map status to timeline index
    int currentIndex;
    switch (currentStatus) {
      case 'request_open':
      case 'pending':
        currentIndex = 0; // Posted
        break;
      case 'accepted':
      case 'confirmed':
        currentIndex = 1; // Accepted
        break;
      case 'verified':
      case 'working':
        currentIndex = 2; // Verified (work in progress)
        break;
      case 'completed':
        currentIndex = 3; // Done
        break;
      case 'cancelled':
      case 'expired':
        currentIndex = 0; // Show minimal progress for cancelled/expired
        break;
      default:
        currentIndex = 0;
    }

    return Row(
      children: List.generate(displayLabels.length, (index) {
        final isActive = index <= currentIndex;
        final isLast = index == displayLabels.length - 1;

        return Expanded(
          child: Row(
            children: [
              Column(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isActive ? _AppTheme.success : _AppTheme.border,
                      shape: BoxShape.circle,
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                color: _AppTheme.success.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Icon(
                      isActive ? icons[index] : Icons.circle_outlined,
                      size: 16,
                      color: isActive ? Colors.white : _AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: _AppTheme.spacing2),
                  Text(
                    displayLabels[index],
                    style: TextStyle(
                      fontSize: 11,
                      color: isActive ? _AppTheme.success : _AppTheme.textMuted,
                      fontWeight: isActive
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    height: 3,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: index < currentIndex
                          ? _AppTheme.success
                          : _AppTheme.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  Future<void> _launchMap(double lat, double lng) async {
    final Uri googleMapsUrl = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    final Uri geoUrl = Uri.parse('geo:$lat,$lng');

    try {
      if (await canLaunchUrl(googleMapsUrl)) {
        await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(geoUrl)) {
        await launchUrl(geoUrl, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(googleMapsUrl, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Could not open maps: $e');
      }
    }
  }

  _StatusInfo _getStatusInfo(String status) {
    switch (status) {
      case 'pending':
      case 'request_open':
        return _StatusInfo(
          label: 'PENDING',
          color: _AppTheme.warning,
          icon: Icons.hourglass_empty_rounded,
        );
      case 'accepted':
        return _StatusInfo(
          label: 'ACCEPTED',
          color: _AppTheme.info,
          icon: Icons.thumb_up_rounded,
        );
      case 'verified':
        return _StatusInfo(
          label: 'VERIFIED',
          color: _AppTheme.primary,
          icon: Icons.verified_rounded,
        );
      case 'working':
        return _StatusInfo(
          label: 'IN PROGRESS',
          color: _AppTheme.info,
          icon: Icons.construction_rounded,
        );
      case 'confirmed':
        return _StatusInfo(
          label: 'CONFIRMED',
          color: _AppTheme.info,
          icon: Icons.check_rounded,
        );
      case 'completed':
        return _StatusInfo(
          label: 'COMPLETED',
          color: _AppTheme.success,
          icon: Icons.check_circle_rounded,
        );
      case 'rejected':
        return _StatusInfo(
          label: 'REJECTED',
          color: _AppTheme.error,
          icon: Icons.cancel_rounded,
        );
      case 'cancelled':
        return _StatusInfo(
          label: 'CANCELLED',
          color: _AppTheme.textMuted,
          icon: Icons.block_rounded,
        );
      case 'expired':
        return _StatusInfo(
          label: 'EXPIRED',
          color: _AppTheme.error,
          icon: Icons.timer_off_rounded,
        );
      case 'negotiating':
        return _StatusInfo(
          label: 'NEGOTIATING',
          color: _AppTheme.primary,
          icon: Icons.handshake_rounded,
        );
      default:
        return _StatusInfo(
          label: status.toUpperCase(),
          color: _AppTheme.textMuted,
          icon: Icons.help_outline_rounded,
        );
    }
  }
}

class _StatusInfo {
  final String label;
  final Color color;
  final IconData icon;

  _StatusInfo({required this.label, required this.color, required this.icon});
}
