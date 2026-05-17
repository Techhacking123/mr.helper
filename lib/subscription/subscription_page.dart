import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../auth/session_manager.dart';
import '../supabase_config.dart';
import '../services/google_billing_service.dart';


class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  final GoogleBillingService _billingService = GoogleBillingService();

  bool _isLoading = true;
  String _message = '';

  // Subscription State
  bool _isSubscribed = false;
  DateTime? _startDate;
  DateTime? _expiryDate;

  String _statusText = 'Loading...';
  List<Map<String, dynamic>> _subscriptionHistory = [];

  // Dynamic subscription info from service
  String _googleSubscriptionId = GoogleBillingService.defaultSubscriptionProductId;
  String _serviceName = '';

  @override
  void initState() {
    super.initState();
    _initializeBilling();
    _checkSubscriptionStatus();
  }



  Future<void> _initializeBilling() async {
    await _billingService.initialize();

    // Set up callbacks
    _billingService.onSuccess = (message) {
      if (mounted) {
        // Optimistically update UI immediately — no loading spinner needed
        final now = DateTime.now().toUtc();
        final expiry = now.add(const Duration(days: 28));
        setState(() {
          _message = message;
          _isSubscribed = true;
          _startDate = now;
          _expiryDate = expiry;
          _statusText = 'Active';
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.green),
        );

        // Silently refresh from DB in background (no spinner)
        _checkSubscriptionStatus(silent: true);
      }
    };

    _billingService.onError = (error) {
      if (mounted) {
        setState(() {
          _message = error;
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
      }
    };

    _billingService.onLoading = (loading) {
      if (mounted) {
        setState(() => _isLoading = loading);
      }
    };

    // Update UI with product price if available
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _checkSubscriptionStatus({bool silent = false}) async {
    try {
      final userId = await SessionManager.getUserId();
      if (userId == null) return;

      // Fetch user subscription data
      final response = await SupabaseConfig.supabase
          .from('users')
          .select(
            'subscription_status, subscription_start_date, subscription_end_date, is_subscribed, subscription_expiry, service_id, services(name, google_subscription_id)',
          )
          .eq('id', userId)
          .single();

      // Process service data (Google subscription ID + name)
      final serviceData = response['services'];
      if (serviceData != null) {
        final subId = serviceData['google_subscription_id'] as String?;
        final name = serviceData['name'];
        final newProductId = (subId != null && subId.isNotEmpty)
            ? subId
            : GoogleBillingService.defaultSubscriptionProductId;

        if (mounted) {
          setState(() {
            _googleSubscriptionId = newProductId;
            _serviceName = name ?? '';
          });
        }

        _billingService.setActiveProductId(newProductId);

        // Only load from Google Play if not already loaded (avoid redundant network call)
        if (_billingService.getProductById(newProductId) == null) {
          _billingService.loadProductById(newProductId).then((_) {
            if (mounted) setState(() {});
          });
        }
      }

      // Fetch subscription history in parallel (fire-and-forget for silent mode)
      _fetchSubscriptionHistory(userId);

      // Use new subscription_status field (with fallback to old fields)
      final subscriptionStatus =
          response['subscription_status'] ??
          (response['is_subscribed'] == true ? 'active' : 'none');

      final startDateStr = response['subscription_start_date'];
      final endDateStr =
          response['subscription_end_date'] ?? response['subscription_expiry'];

      if (subscriptionStatus == 'active') {
        if (endDateStr != null) {
          final endDate = DateTime.parse(endDateStr);
          final startDate = startDateStr != null
              ? DateTime.parse(startDateStr)
              : null;
          final now = DateTime.now();

          if (endDate.isAfter(now)) {
            if (mounted) {
              setState(() {
                _isSubscribed = true;
                _startDate = startDate;
                _expiryDate = endDate;
                _statusText = 'Active';
                _isLoading = false;
              });
            }
            return;
          } else {
            // Expired (end date has passed)
            if (mounted) {
              setState(() {
                _isSubscribed = false;
                _statusText = 'Expired';
                _isLoading = false;
              });
            }
            return;
          }
        } else {
          // Status is active but dates are missing in DB — still treat as active
          final startDate = startDateStr != null
              ? DateTime.parse(startDateStr)
              : null;
          if (mounted) {
            setState(() {
              _isSubscribed = true;
              _startDate = startDate;
              _expiryDate = null;
              _statusText = 'Active';
              _isLoading = false;
            });
          }
          return;
        }
      } else if (subscriptionStatus == 'expired') {
        if (mounted) {
          setState(() {
            _isSubscribed = false;
            _statusText = 'Expired';
            _isLoading = false;
          });
        }
      } else {
        // No subscription
        if (mounted) {
          setState(() {
            _isSubscribed = false;
            _statusText = 'Not Subscribed';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error checking subscription: $e');
      if (mounted && !silent) {
        setState(() {
          _isLoading = false;
          _statusText = 'Error';
        });
      }
    }
  }

  Future<void> _fetchSubscriptionHistory(String userId) async {
    try {
      // Try to fetch from a subscription_history or payments table
      // If no table exists, we'll create a simple history based on current subscription
      try {
        final history = await SupabaseConfig.supabase
            .from('subscription_payments')
            .select('*')
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(10);

        if (mounted) {
          setState(() {
            _subscriptionHistory = List<Map<String, dynamic>>.from(history);
          });
        }
      } catch (e) {
        // Table might not exist, create a simple history entry from current subscription
        debugPrint('No subscription history table found: $e');
        if (_startDate != null && _expiryDate != null) {
          setState(() {
            _subscriptionHistory = [
              {
                'start_date': _startDate?.toIso8601String(),
                'end_date': _expiryDate?.toIso8601String(),
                'amount': _billingService.subscriptionProduct?.price ?? 'N/A',
                'status': _isSubscribed ? 'active' : 'expired',
                'created_at': _startDate?.toIso8601String(),
              },
            ];
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching subscription history: $e');
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// Start the Google Play subscription purchase flow
  Future<void> _startSubscriptionFlow() async {
    debugPrint('=== Starting Google Play Subscription Flow ===');
    setState(() {
      _isLoading = true;
      _message = '';
    });

    if (!_billingService.isAvailable) {
      setState(() {
        _isLoading = false;
        _message = 'Google Play Store is not available on this device.';
      });
      return;
    }

    if (_billingService.subscriptionProduct == null) {
      setState(() {
        _isLoading = false;
        _message =
            'Subscription product not available. Please try again later.';
      });
      return;
    }

    await _billingService.purchaseSubscription();
  }

  /// Restore previous purchases
  Future<void> _restorePurchases() async {
    setState(() {
      _isLoading = true;
      _message = '';
    });

    await _billingService.restorePurchases();
  }

  @override
  Widget build(BuildContext context) {
    final bool isExpired = _statusText == 'Expired';

    // Get Google Play price if available
    final googlePrice = _billingService.subscriptionProduct?.price;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Subscription"),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          // Restore purchases button
          IconButton(
            onPressed: _isLoading ? null : _restorePurchases,
            icon: const Icon(Icons.restore),
            tooltip: 'Restore Purchases',
          ),
        ],
      ),
      body:
          _isLoading &&
              !_isSubscribed &&
              _statusText != 'Expired' &&
              _statusText != 'Not Subscribed'
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // STATUS CARD
                  _buildStatusCard(),
                  const SizedBox(height: 24),



                  // PLAN CARD (Show if not subscribed or expired or just want to renew)
                  if (!_isSubscribed || isExpired) ...[
                    _buildPlanCard(googlePrice),
                    const SizedBox(height: 20),
                    if (_message.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          _message,
                          style: TextStyle(
                            color:
                                _message.contains('Success') ||
                                    _message.contains('success')
                                ? Colors.green
                                : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _startSubscriptionFlow,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                isExpired
                                    ? "Reactivate Service Access"
                                    : "Activate Service Account",
                                style: const TextStyle(
                                  fontSize: 18,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Google Play branding
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.verified_user,
                          size: 14,
                          color: Colors.grey.shade500,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Secured by Google Play',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    // Active message
                    const Icon(
                      Icons.check_circle_outline,
                      size: 80,
                      color: Colors.green,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "You are a Pro Provider!",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Enjoy unlimited access to order requests and premium support.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],

                  // SUBSCRIPTION HISTORY
                  if (_subscriptionHistory.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Subscription History",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._subscriptionHistory.map((record) {
                      final startDate = record['start_date'] != null
                          ? DateFormat(
                              'dd MMM yyyy',
                            ).format(DateTime.parse(record['start_date']))
                          : 'N/A';
                      final endDate = record['end_date'] != null
                          ? DateFormat(
                              'dd MMM yyyy',
                            ).format(DateTime.parse(record['end_date']))
                          : 'N/A';
                      final status =
                          record['status']?.toString().toUpperCase() ??
                          'UNKNOWN';
                      final amount = record['amount'] ?? (_billingService.subscriptionProduct?.price ?? 'N/A');
                      final isActive = status == 'ACTIVE';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isActive
                              ? Colors.green.shade50
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isActive
                                ? Colors.green.shade200
                                : Colors.grey.shade200,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      isActive
                                          ? Icons.check_circle
                                          : Icons.history,
                                      color: isActive
                                          ? Colors.green
                                          : Colors.grey,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      status,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isActive
                                            ? Colors.green.shade700
                                            : Colors.grey.shade700,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  '$amount',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Started',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        startDate,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 30,
                                  color: Colors.grey.shade300,
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        'Expires',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        endDate,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildStatusCard() {
    Color statusColor = Colors.grey;
    IconData statusIcon = Icons.info_outline;

    if (_isSubscribed) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    } else if (_statusText == 'Expired') {
      statusColor = Colors.red;
      statusIcon = Icons.warning_amber_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(statusIcon, size: 40, color: statusColor),
          const SizedBox(height: 12),
          Text(
            "Status: $_statusText",
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: statusColor,
            ),
          ),
          if (_isSubscribed) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  if (_startDate != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.play_circle_outline,
                              color: Colors.blue,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Started:',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          DateFormat('dd MMM yyyy').format(_startDate!),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  if (_startDate != null && _expiryDate != null)
                    const SizedBox(height: 8),
                  if (_expiryDate != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.event_available,
                              color: Colors.orange,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Expires:',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          DateFormat('dd MMM yyyy').format(_expiryDate!),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  if (_expiryDate != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Builder(
                        builder: (context) {
                          final now = DateTime.now();
                          final diff = _expiryDate!.difference(now);
                          String label;
                          if (diff.inDays >= 1) {
                            label = '${diff.inDays} days remaining';
                          } else if (diff.inHours >= 1) {
                            label = '${diff.inHours} hours remaining';
                          } else {
                            label = '${diff.inMinutes} minutes remaining';
                          }

                          return Text(
                            label,
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlanCard(String? googlePrice) {
    // Use Google Play price fetched via the service's subscription ID
    final displayPrice = googlePrice ?? 'Loading...';

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Text(
              _serviceName.isNotEmpty
                  ? "$_serviceName - Service Access"
                  : "Monthly Service Access",
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  displayPrice,
                  style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const Text(
                  "/ month",
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),

            const SizedBox(height: 20),
            _featureRow("Receive Service Requests"),
            _featureRow("Verified Badge"),
            _featureRow("Priority Support"),

          ],
        ),
      ),
    );
  }

  Widget _featureRow(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          const Icon(Icons.check, color: Colors.green, size: 20),
          const SizedBox(width: 12),
          Text(text, style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}
