import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../supabase_config.dart';
import '../auth/session_manager.dart';
import 'edit_profile.dart';
import 'ratings_widget.dart';
import 'report_modal.dart';

import '../widgets/map_picker.dart';
import '../widgets/safe_network_image.dart';
import '../orders/provider_orders.dart';
import '../orders/provider_earnings_page.dart';
import '../auth/login.dart';
import '../orders/user_orders.dart';
import 'settings_page.dart';
import '../marketplace/my_products_page.dart';

class ProfilePage extends StatefulWidget {
  final String userId;
  final VoidCallback? onBackToHome;
  const ProfilePage({super.key, required this.userId, this.onBackToHome});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? _userData;
  Map<String, dynamic>? _stats;
  bool _isLoading = true;
  bool _isOwner = false;

  String? _viewerId;

  // Modern Color Palette
  final Color _primaryColor = const Color(0xFF6366F1); // Indigo
  final Color _secondaryColor = const Color(0xFF8B5CF6); // Violet

  final Color _backgroundColor = const Color(0xFFF3F4F6); // Cool Gray
  final Color _cardColor = Colors.white;
  final Color _textColor = const Color(0xFF1F2937); // Gray 800

  @override
  void initState() {
    super.initState();
    _fetchProfileData();
  }

  Future<void> _fetchProfileData() async {
    try {
      _viewerId = await SessionManager.getUserId();
      _isOwner = _viewerId == widget.userId;

      // 1. Fetch User Data with Service Name
      final userResponse = await SupabaseConfig.supabase
          .from('users')
          .select('*, services(name)')
          .eq('id', widget.userId)
          .single();

      // 2. Service Type Name (service_type column stores the NAME as TEXT, not an ID)
      String? serviceTypeName;
      if (userResponse['service_type'] != null) {
        // The service_type column already contains the name directly
        serviceTypeName = userResponse['service_type'] as String?;
      }

      // Add service type name to user data
      if (serviceTypeName != null) {
        userResponse['_service_type_name'] = serviceTypeName;
      }

      // Get rating and review count
      double avgRating =
          (userResponse['average_rating'] as num?)?.toDouble() ?? 0.0;
      int reviewCount = (userResponse['total_reviews'] as int?) ?? 0;

      // 3. Check Subscription Status for Providers
      if (userResponse['is_provider'] == true) {
        final isSubscribed = userResponse['is_subscribed'] ?? false;
        final expiryStr = userResponse['subscription_expiry'];

        bool subscriptionActive = false;
        if (isSubscribed && expiryStr != null) {
          try {
            final expiry = DateTime.parse(expiryStr);
            subscriptionActive = expiry.isAfter(DateTime.now());
          } catch (e) {
            debugPrint('Error parsing expiry date: $e');
          }
        }
        // Add custom flag to user data
        userResponse['_subscription_active'] = subscriptionActive;
      }

      if (mounted) {
        setState(() {
          _userData = userResponse;
          _stats = {'rating': avgRating, 'count': reviewCount};
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching profile: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: _backgroundColor,
        body: Center(child: CircularProgressIndicator(color: _primaryColor)),
      );
    }
    if (_userData == null) {
      return Scaffold(
        backgroundColor: _backgroundColor,
        appBar: AppBar(title: const Text('Profile Not Found')),
        body: const Center(child: Text('User not found')),
      );
    }

    final user = _userData!;
    // Display sub-service type if available, otherwise fall back to main service
    final serviceName = user['_service_type_name'] != null
        ? (user['_service_type_name'] as String)
        : (user['services'] != null
              ? (user['services']['name'] as String? ?? 'Community Member')
              : 'Community Member');
    final isProvider = user['is_provider'] == true;
    final rating = _stats!['rating'] as double;
    final reviewCount = _stats!['count'] as int;
    final fullName = user['full_name'] ?? 'No Name';
    final bio = user['bio'] ?? 'No biography provided yet.';
    final price = user['price'];

    return Scaffold(
      backgroundColor: _backgroundColor,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildModernAppBar(user, fullName, serviceName, isProvider),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),

                  // Bio/About Section (Providers only)
                  if (isProvider) ...[
                    _buildSectionHeader('About'),
                    _buildGlassCard(
                      child: Text(
                        bio,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.6,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Location Section
                  _buildSectionHeader('Location'),
                  _buildLocationCard(user['location'] ?? 'Unknown Location'),
                  const SizedBox(height: 24),

                  // Provider Specific: Stats & Reviews
                  if (isProvider) ...[
                    _buildSectionHeader('Performance'),
                    _buildStatsGrid(rating, reviewCount, price),
                    const SizedBox(height: 24),

                    _buildSectionHeader('Reviews'),
                    Container(
                      decoration: BoxDecoration(
                        color: _cardColor,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(20),
                      child: RatingsWidget(
                        profileId: widget.userId,
                        isOwner: _isOwner,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Settings Section (for everyone, but differs for owner/visitor)
                  if (_isOwner) ...[
                    _buildSectionHeader('Settings'),
                    _buildSettingsList(isProvider),
                    const SizedBox(height: 40),
                  ] else if (_viewerId != null) ...[
                    // Only show for logged in viewers viewing others
                    _buildSectionHeader('Actions'),
                    _buildVisitorActions(),
                    const SizedBox(height: 40),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: !_isOwner && isProvider
          ? _buildBottomAction(user, fullName)
          : null,
    );
  }

  Widget _buildModernAppBar(
    Map<String, dynamic> user,
    String fullName,
    String subtitle,
    bool isProvider,
  ) {
    return SliverAppBar(
      expandedHeight: 320,
      pinned: true,
      stretch: true,
      backgroundColor: _backgroundColor, // Matches body color
      elevation: 0,
      leading: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.2),
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              // There's a previous screen, go back to it
              Navigator.of(context).pop();
            } else if (widget.onBackToHome != null) {
              // No previous screen but we have a callback to go home
              widget.onBackToHome!();
            }
          },
        ),
      ),
      actions: [
        if (!_isOwner && _viewerId != null)
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.flag_rounded, color: Colors.white),
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent, // For custom shape
                builder: (_) => Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: ReportModal(reportedProfileId: widget.userId),
                ),
              ),
            ),
          ),
        if (_isOwner)
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.edit_rounded, color: Colors.white),
              onPressed: () async {
                bool? result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditProfilePage(userData: user),
                  ),
                );
                if (result == true) _fetchProfileData();
              },
            ),
          ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [
          StretchMode.zoomBackground,
          StretchMode.blurBackground,
        ],
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Background Image/Gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_primaryColor, _secondaryColor],
                ),
              ),
            ),
            // Pattern Overlay (Optional) - uses CachedNetworkImage for stability
            Opacity(
              opacity: 0.1,
              child: CachedNetworkImage(
                imageUrl:
                    "https://www.transparenttextures.com/patterns/cubes.png",
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorWidget: (_, __, ___) => const SizedBox(),
                placeholder: (_, __) => const SizedBox(),
              ),
            ),

            // Profile Content
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Avatar with Glass Border
                  Container(
                    width: 120,
                    height: 120,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.2),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.5),
                        width: 1,
                      ),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: SafeAvatar(
                        imageUrl: user['avatar_url'],
                        radius: 54,
                        backgroundColor: Colors.white,
                        fallbackIcon: Icon(
                          Icons.person_rounded,
                          size: 60,
                          color: Colors.grey.shade300,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Name and Badge
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        fullName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      if (isProvider &&
                          (user['_subscription_active'] == true)) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.blueAccent,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
                            size: 12,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Subtitle Pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade500,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(color: Colors.white),
      ),
      child: child,
    );
  }

  Widget _buildLocationCard(String location) {
    return _buildGlassCard(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.location_on_rounded,
              color: _primaryColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              location,
              style: TextStyle(
                fontSize: 16,
                color: _textColor,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(double rating, int count, dynamic price) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            rating.toStringAsFixed(1),
            'Rating',
            Icons.star_rounded,
            Colors.amber,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            count.toString(),
            'Reviews',
            Icons.people_alt_rounded,
            Colors.blueAccent,
          ),
        ),
        if (price != null) ...[
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              '₹$price',
              'Per Hour',
              Icons.payments_rounded,
              Colors.green,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatCard(
    String value,
    String label,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _textColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsList(bool isProvider) {
    return Container(
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          if (isProvider) ...[
            _buildSettingsTile(
              'My Orders',
              'Manage your incoming jobs',
              Icons.assignment_rounded,
              Colors.orange,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProviderOrdersPage()),
              ),
            ),
            _buildDivider(),
            _buildSettingsTile(
              'My Products',
              'Manage your marketplace listings',
              Icons.storefront_rounded,
              Colors.purple,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MyProductsPage()),
              ),
            ),
            _buildDivider(),
            _buildSettingsTile(
              'My Earnings',
              'Check your revenue',
              Icons.account_balance_wallet_rounded,
              Colors.green,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProviderEarningsPage()),
              ),
            ),
            _buildDivider(),
          ],
          _buildSettingsTile(
            'Settings',
            'Profile & Preferences',
            Icons.settings_rounded,
            Colors.grey,
            () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsPage(userData: _userData!),
                ),
              );
              _fetchProfileData();
            },
          ),
          if (!isProvider) ...[
            _buildDivider(),
            _buildSettingsTile(
              'My Bookings',
              'Track your service requests',
              Icons.calendar_today_rounded,
              Colors.blue,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const UserOrdersPage()),
              ),
            ),
          ],
          _buildDivider(),
          _buildSettingsTile(
            'Sign Out',
            'Log out of your account',
            Icons.logout_rounded,
            Colors.red,
            _handleLogout,
            isDestructive: true,
          ),
        ],
      ),
    );
  }

  Widget _buildVisitorActions() {
    return _buildSettingsTile(
      'Sign Out',
      'Log out of your account',
      Icons.logout_rounded,
      Colors.red,
      _handleLogout,
      isDestructive: true,
    );
  }

  Widget _buildSettingsTile(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap, {
    bool isDestructive = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (isDestructive ? Colors.red : color).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  color: isDestructive ? Colors.red : color,
                  size: 22,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDestructive ? Colors.red : _textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: Colors.grey.shade300,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      height: 1,
      thickness: 1,
      color: Colors.grey.shade100,
      indent: 76,
    );
  }

  // BOTTOM FLOATING ACTION BUTTON FOR HIRING
  Widget? _buildBottomAction(Map<String, dynamic> user, String fullName) {
    final subscriptionActive = user['_subscription_active'] ?? false;

    return Container(
      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20),
      decoration: BoxDecoration(
        color: _backgroundColor.withOpacity(0.0), // Transparent to blend
      ),
      child: subscriptionActive
          ? ElevatedButton(
              onPressed: () => _showHireDialog(user, fullName),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                elevation: 8,
                shadowColor: _primaryColor.withOpacity(0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Hire Now',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded),
                ],
              ),
            )
          : Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: Colors.orange.shade700,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'This provider is currently unavailable for new jobs.',
                      style: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // DIALOGS REMAIN SAME LOGIC, NEW UI
  Future<void> _showHireDialog(
    Map<String, dynamic> provider,
    String providerName,
  ) async {
    final _locController = TextEditingController();
    final _descController = TextEditingController();
    final _priceController = TextEditingController();
    final _formKey = GlobalKey<FormState>();
    double? _lat;
    double? _lng;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Hire $providerName',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _textColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Fill in the details to send a request.',
                  style: TextStyle(color: Colors.grey.shade500),
                ),
                const SizedBox(height: 24),

                // Location Input - Map picker only
                GestureDetector(
                  onTap: () async {
                    final res = await MapPicker.checkLocationAndOpen(context);
                    if (res != null) {
                      _locController.text = res['address'] as String;
                      _lat = res['lat'] as double;
                      _lng = res['lng'] as double;
                      // Trigger rebuild to show updated location
                      (ctx as Element).markNeedsBuild();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _locController.text.isEmpty
                            ? Colors.grey.shade300
                            : _primaryColor.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _locController.text.isEmpty
                                ? Colors.grey.shade200
                                : _primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.map_rounded,
                            color: _locController.text.isEmpty
                                ? Colors.grey.shade500
                                : _primaryColor,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Service Location',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _locController.text.isEmpty
                                    ? 'Tap to pick location on map'
                                    : _locController.text,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: _locController.text.isEmpty
                                      ? FontWeight.w400
                                      : FontWeight.w600,
                                  color: _locController.text.isEmpty
                                      ? Colors.grey.shade400
                                      : _textColor,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.grey.shade400,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Description Input
                TextFormField(
                  controller: _descController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Job Description',
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.description_outlined),
                  ),
                  validator: (v) => v!.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 16),

                // Price Input
                TextFormField(
                  controller: _priceController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Offer Amount',
                    prefixText: '₹ ',
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.currency_rupee_rounded),
                  ),
                  validator: (v) => v!.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 32),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          foregroundColor: Colors.grey,
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () {
                          if (_locController.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please pick a service location from the map',
                                ),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }
                          if (_formKey.currentState!.validate()) {
                            Navigator.pop(ctx);
                            String sid = 'unknown';
                            if (provider['service_id'] != null) {
                              sid = provider['service_id'].toString();
                            } else if (provider['services'] != null &&
                                provider['services']['id'] != null) {
                              sid = provider['services']['id'].toString();
                            }

                            _submitHireRequest(
                              provider['id'],
                              sid,
                              _locController.text.trim(),
                              _descController.text.trim(),
                              double.parse(_priceController.text.trim()),
                              lat: _lat,
                              lng: _lng,
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Send Request',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submitHireRequest(
    String providerId,
    String? serviceId,
    String location,
    String description,
    double price, {
    double? lat,
    double? lng,
  }) async {
    setState(() => _isLoading = true);
    try {
      final userId = await SessionManager.getUserId();
      if (userId == null) throw "User not logged in";

      await SupabaseConfig.supabase.from('orders').insert({
        'buyer_id': userId,
        'provider_id': providerId,
        'service_id': serviceId,
        'location_id': null,
        'address_gps': location,
        'latitude': lat,
        'longitude': lng,
        'description': description,
        'user_price': price,
        'status': 'negotiating',
        'last_offer_by': 'user',
        'provider_price': null,
      });

      // Notification to Provider
      await SupabaseConfig.supabase.from('notifications').insert({
        'user_id': providerId,
        'message': 'New Direct Job Request! Offer: ₹$price',
        'is_read': false,
      });

      if (mounted) {
        // Custom Success SnackBar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 12),
                const Text(
                  'Request Sent to Provider!',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error sending request: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleLogout() async {
    // Show confirmation
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await SessionManager.clearSession();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }
}
