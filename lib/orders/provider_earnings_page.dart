import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../supabase_config.dart';
import '../auth/session_manager.dart';

class ProviderEarningsPage extends StatefulWidget {
  const ProviderEarningsPage({super.key});

  @override
  State<ProviderEarningsPage> createState() => _ProviderEarningsPageState();
}

class _ProviderEarningsPageState extends State<ProviderEarningsPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _monthlyEarnings = [];
  double _totalEarnings = 0;

  @override
  void initState() {
    super.initState();
    _fetchEarningsData();
  }

  Future<void> _fetchEarningsData() async {
    try {
      final userId = await SessionManager.getUserId();
      if (userId == null) return;

      // 1. Fetch Subscription Start Date
      DateTime? subStart;
      try {
        final userResponse = await SupabaseConfig.supabase
            .from('users')
            .select('subscription_start_date')
            .eq('id', userId)
            .single();

        if (userResponse['subscription_start_date'] != null) {
          subStart = DateTime.parse(userResponse['subscription_start_date']);
        }
      } catch (e) {
        debugPrint('Error fetching subscription start: $e');
      }

      // 2. Fetch Completed Orders
      final response = await SupabaseConfig.supabase
          .from('orders')
          .select('id, price, updated_at, created_at')
          .eq('provider_id', userId)
          .eq('status', 'completed')
          .order('updated_at', ascending: false);

      final orders = List<Map<String, dynamic>>.from(response);

      // 3. Aggregate
      _processEarnings(orders, subStart);
    } catch (e) {
      debugPrint('Error fetching earnings: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _processEarnings(List<Map<String, dynamic>> orders, DateTime? subStart) {
    if (orders.isEmpty) {
      if (mounted) {
        setState(() {
          _monthlyEarnings = [];
          _totalEarnings = 0;
        });
      }
      return;
    }

    DateTime now = DateTime.now();
    DateTime currentMonthStart;
    DateTime? anchorDate;

    // Logic: Month starts on the day of the month of 'subStart'.
    // e.g. if SubStart was Wed Jan 1st, then weeks are Wed-Wed.
    if (subStart != null) {
      anchorDate = subStart.toLocal();
      // Calculate how many full months have passed since start
      final Duration diff = now.difference(anchorDate);

      if (diff.isNegative) {
        // Weird edge case: NOW is before subscription start (maybe device time wrong?)
        // Just Use subStart as the "Current" month start.
        currentMonthStart = anchorDate;
      } else {
        int monthsPassed = (diff.inDays / 28).floor();
        // The current month started 'monthsPassed' months after the anchor
        currentMonthStart = anchorDate.add(Duration(days: monthsPassed * 28));
      }
    } else {
      // Fallback: Standard Calendar Month Start
      currentMonthStart = DateTime(now.year, now.month, 1);
    }

    List<Map<String, dynamic>> weeks = [];
    double grandTotal = 0;

    // Keep all valid orders. WE DO NOT FILTER by date > subStart
    // because user complained about "previous month earnings showing 0".
    // We just want to bucket them according to the cycle.
    final validOrders = orders.where((o) {
      return o['updated_at'] != null || o['created_at'] != null;
    }).toList();

    for (var order in validOrders) {
      grandTotal += (order['price'] as num?)?.toDouble() ?? 0.0;
    }

    /*
      BUCKET LOGIC:
      We generate 12 buckets backwards from 'currentMonthStart'.
      Each bucket is 28 days long. 
      Aligned to Subscription Day if available.
    */
    for (int i = 0; i < 12; i++) {
      DateTime start = currentMonthStart.subtract(Duration(days: 28 * i));
      DateTime comparisonEnd = start.add(const Duration(days: 28));

      double monthTotal = 0;
      int count = 0;

      for (var order in validOrders) {
        final dateStr = order['updated_at'] ?? order['created_at'];
        if (dateStr == null) continue;
        final date = DateTime.parse(dateStr).toLocal();

        // strict: date >= start && date < comparisonEnd
        if (!date.isBefore(start) && date.isBefore(comparisonEnd)) {
          monthTotal += (order['price'] as num?)?.toDouble() ?? 0.0;
          count++;
        }
      }

      // Display Label
      String label;
      if (i == 0) {
        label = 'Current Month';
      } else {
        DateTime displayEnd = start.add(const Duration(days: 27));
        label =
            '${DateFormat('MMM d').format(start)} - ${DateFormat('MMM d').format(displayEnd)}';
      }

      weeks.add({
        'start': start,
        'end': comparisonEnd,
        'total': monthTotal,
        'count': count,
        'label': label,
      });
    }

    if (mounted) {
      setState(() {
        _monthlyEarnings = weeks;
        _totalEarnings = grandTotal;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('My Earnings'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Total Summary Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.deepPurple.shade800,
                          Colors.deepPurple.shade500,
                        ],
                        begin: Alignment.bottomLeft,
                        end: Alignment.topRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.deepPurple.withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Lifetime Earnings',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '₹${_totalEarnings.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Based on completed orders',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),
                  const Text(
                    'Monthly History',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),

                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _monthlyEarnings.length,
                    itemBuilder: (context, index) {
                      final item = _monthlyEarnings[index];
                      final isCurrent = index == 0;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: isCurrent
                              ? Border.all(
                                  color: Colors.green.shade200,
                                  width: 1.5,
                                )
                              : null,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 8,
                          ),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? Colors.green.shade50
                                  : Colors.blue.shade50,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.calendar_today_rounded,
                              color: isCurrent
                                  ? Colors.green.shade700
                                  : Colors.blue.shade700,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            item['label'],
                            style: TextStyle(
                              fontWeight: isCurrent
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: isCurrent
                                  ? Colors.green.shade900
                                  : Colors.black87,
                            ),
                          ),
                          subtitle: Text(
                            '${item['count']} orders',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          trailing: Text(
                            '₹${(item['total'] as double).toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isCurrent
                                  ? Colors.green.shade700
                                  : Colors.black87,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }
}
