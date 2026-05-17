import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../supabase_config.dart';
import '../auth/session_manager.dart';

class RedStarDetailsPage extends StatefulWidget {
  const RedStarDetailsPage({super.key});

  @override
  State<RedStarDetailsPage> createState() => _RedStarDetailsPageState();
}

class _RedStarDetailsPageState extends State<RedStarDetailsPage>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  bool _isUnblocking = false;
  Map<String, dynamic>? _providerData;
  Map<String, dynamic>? _redStarData;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _loadData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final userId = await SessionManager.getUserId();
      if (userId == null) return;

      // Fetch provider profile
      final profile = await SupabaseConfig.supabase
          .from('users')
          .select('full_name, avatar_url, red_stars, is_blocked, services(name)')
          .eq('id', userId)
          .single();

      // Fetch red star history with order details
      final redStarInfo = await SupabaseConfig.supabase.rpc(
        'get_provider_red_stars',
        params: {'p_provider_id': userId},
      );

      if (mounted) {
        setState(() {
          _providerData = profile;
          _redStarData = Map<String, dynamic>.from(redStarInfo);
          _isLoading = false;
        });
        _animationController.forward();
      }
    } catch (e) {
      debugPrint('Error loading red star data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleUnblock() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade600, size: 28),
            const SizedBox(width: 10),
            const Text('Confirm Unblock'),
          ],
        ),
        content: const Text(
          'Are you sure you want to unblock your account?\n\n'
          'All red stars will be reset to 0 and you will be able to receive orders again.\n\n'
          'Please make sure to complete services on time to avoid future penalties.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Yes, Unblock', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isUnblocking = true);

    try {
      final userId = await SessionManager.getUserId();
      if (userId == null) throw 'User not found';

      final result = await SupabaseConfig.supabase.rpc(
        'unblock_provider',
        params: {'p_provider_id': userId},
      );

      if (result['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 10),
                  Expanded(child: Text('Account unblocked! You can now receive orders.')),
                ],
              ),
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.all(16),
            ),
          );
          Navigator.pop(context, true); // Return true to trigger refresh
        }
      } else {
        throw result['message'] ?? 'Unknown error';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text('Error: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUnblocking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Account Status',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // PROVIDER PROFILE CARD
                  _buildProfileCard(),
                  const SizedBox(height: 20),

                  // RED STAR STATUS
                  _buildRedStarStatusCard(),
                  const SizedBox(height: 20),

                  // RED STAR HISTORY
                  _buildRedStarHistory(),
                  const SizedBox(height: 24),

                  // UNBLOCK BUTTON
                  if (_providerData?['is_blocked'] == true ||
                      ((_providerData?['red_stars'] as int?) ?? 0) >= 3)
                    _buildUnblockButton(),
                ],
              ),
            ),
    );
  }

  Widget _buildProfileCard() {
    final name = _providerData?['full_name'] ?? 'Provider';
    final avatarUrl = _providerData?['avatar_url'];
    final serviceName = _providerData?['services']?['name'] ?? 'Service Provider';
    final isBlocked = _providerData?['is_blocked'] == true;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isBlocked
              ? [const Color(0xFF991B1B), const Color(0xFFDC2626)]
              : [const Color(0xFF1E293B), const Color(0xFF334155)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (isBlocked ? Colors.red : Colors.grey).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Avatar
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.3), width: 3),
              image: avatarUrl != null
                  ? DecorationImage(
                      image: NetworkImage(avatarUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
              color: Colors.white.withOpacity(0.15),
            ),
            child: avatarUrl == null
                ? Icon(Icons.person_rounded, color: Colors.white.withOpacity(0.7), size: 40)
                : null,
          ),
          const SizedBox(height: 16),

          // Name
          Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),

          // Service
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              serviceName,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isBlocked
                  ? Colors.white.withOpacity(0.2)
                  : const Color(0xFF10B981).withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isBlocked
                    ? Colors.white.withOpacity(0.3)
                    : const Color(0xFF10B981).withOpacity(0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isBlocked ? Icons.block_rounded : Icons.check_circle_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  isBlocked ? 'ACCOUNT BLOCKED' : 'ACTIVE',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRedStarStatusCard() {
    final redStars = (_redStarData?['red_stars'] as int?) ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'Red Star Penalties',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 16),

          // Star Display
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (index) {
              final isFilled = index < redStars;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: Duration(milliseconds: 400 + (index * 200)),
                      curve: Curves.elasticOut,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isFilled
                            ? Colors.red.shade50
                            : Colors.grey.shade50,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isFilled
                              ? Colors.red.shade300
                              : Colors.grey.shade200,
                          width: 2,
                        ),
                        boxShadow: isFilled
                            ? [
                                BoxShadow(
                                  color: Colors.red.withOpacity(0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : [],
                      ),
                      child: Icon(
                        Icons.star_rounded,
                        size: 32,
                        color: isFilled
                            ? Colors.red.shade600
                            : Colors.grey.shade300,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isFilled
                            ? Colors.red.shade600
                            : Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 16),

          // Status text
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: redStars >= 3
                  ? Colors.red.shade50
                  : redStars >= 2
                      ? Colors.orange.shade50
                      : Colors.green.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  redStars >= 3
                      ? Icons.error_rounded
                      : redStars >= 2
                          ? Icons.warning_amber_rounded
                          : Icons.info_outline_rounded,
                  color: redStars >= 3
                      ? Colors.red.shade700
                      : redStars >= 2
                          ? Colors.orange.shade700
                          : Colors.green.shade700,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    redStars >= 3
                        ? 'Your account is blocked. You cannot receive new orders.'
                        : redStars >= 2
                            ? 'Warning! One more red star and your account will be blocked.'
                            : redStars == 1
                                ? 'You have 1 red star. Complete services on time.'
                                : 'No penalties. Keep up the good work!',
                    style: TextStyle(
                      color: redStars >= 3
                          ? Colors.red.shade800
                          : redStars >= 2
                              ? Colors.orange.shade800
                              : Colors.green.shade800,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRedStarHistory() {
    final history = (_redStarData?['history'] as List?) ?? [];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.history_rounded, color: Colors.red.shade600, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  'Penalty History',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${history.length} record${history.length != 1 ? 's' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (history.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.verified_rounded, color: Colors.green.shade300, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'No penalties recorded',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...history.asMap().entries.map((entry) {
              final index = entry.key;
              final item = Map<String, dynamic>.from(entry.value);
              final orderId = item['order_id']?.toString() ?? 'N/A';
              final reason = item['reason'] ?? 'Service not completed within deadline';
              final createdAt = item['created_at'] != null
                  ? DateFormat('dd MMM yyyy, hh:mm a')
                      .format(DateTime.parse(item['created_at']).toLocal())
                  : 'Unknown date';

              return Column(
                children: [
                  if (index > 0) Divider(height: 1, color: Colors.grey.shade100),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Star icon
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.star_rounded,
                            color: Colors.red.shade500,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                reason,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.receipt_long_rounded,
                                      size: 14, color: Colors.grey.shade400),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Order: ${orderId.length > 8 ? orderId.substring(0, 8).toUpperCase() : orderId}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade500,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(Icons.access_time_rounded,
                                      size: 14, color: Colors.grey.shade400),
                                  const SizedBox(width: 4),
                                  Text(
                                    createdAt,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Star number badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '⭐ ${index + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildUnblockButton() {
    return Column(
      children: [
        // Warning text
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: Colors.amber.shade700, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Clicking "Unblock" will reset all your red stars and allow you to receive orders. '
                  'Future violations will result in penalties again.',
                  style: TextStyle(
                    color: Colors.amber.shade900,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Unblock button
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: _isUnblocking ? null : _handleUnblock,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              elevation: 4,
              shadowColor: const Color(0xFF10B981).withOpacity(0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _isUnblocking
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_open_rounded, size: 22),
                      SizedBox(width: 10),
                      Text(
                        'Unblock My Account',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
