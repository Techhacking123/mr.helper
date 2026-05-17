import 'package:flutter/material.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import '../auth/login.dart';
import '../auth/session_manager.dart';
import '../supabase_config.dart';
import '../orders/provider_orders.dart';
import '../orders/provider_requests.dart';
import '../orders/provider_earnings_page.dart';
import '../notifications/notifications_page.dart';
import '../profile/profile_page.dart';
import '../widgets/badge_icon.dart';
import '../widgets/themed_widgets.dart'; // Festival theme widgets
import '../widgets/safe_network_image.dart';
import '../subscription/subscription_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async'; // For Timer
import 'package:supabase_flutter/supabase_flutter.dart';
import '../orders/order_timer_manager.dart';
import '../services/otp_verification_service.dart';
import '../marketplace/product_orders_page.dart'; // Product Orders

import 'package:geocoding/geocoding.dart';

class ProviderHome extends StatefulWidget {
  const ProviderHome({super.key});

  @override
  State<ProviderHome> createState() => _ProviderHomeState();
}

class _ProviderHomeState extends State<ProviderHome>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  String? _userId;
  bool _isLoadingUser = true;
  bool _hasNewRequests = false;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _checkNewRequests();

    // Auto-check for expired orders and red stars on startup
    OrderTimerManager.runGlobalExpiryCheck();
    // Start periodic OTP verification deadline checker
    OtpVerificationService.startPeriodicCheck();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('App resumed - refreshing provider home badges...');
      _checkNewRequests();
      OrderTimerManager.runGlobalExpiryCheck(); // Good to re-check timers too
      OtpVerificationService.checkOtpDeadlines(); // Check OTP deadlines too
    }
  }

  Future<void> _checkNewRequests() async {
    try {
      final uid = await SessionManager.getUserId();
      if (uid == null) return;

      // 1. Check for Direct Offers (Negotiations)
      final negotiations = await SupabaseConfig.supabase
          .from('orders')
          .select('id')
          .eq('status', 'negotiating')
          .eq('provider_id', uid)
          .limit(1);

      if ((negotiations as List).isNotEmpty) {
        if (mounted) setState(() => _hasNewRequests = true);
        return;
      }

      // 2. Check for Open Broadcasts
      final user = await SupabaseConfig.supabase
          .from('users')
          .select('service_id')
          .eq('id', uid)
          .single();
      final serviceId = user['service_id'];

      if (serviceId != null) {
        final response = await SupabaseConfig.supabase
            .from('orders')
            .select('id')
            .eq('status', 'request_open')
            .eq('service_id', serviceId)
            .limit(1);

        if (mounted) {
          setState(() {
            _hasNewRequests = (response as List).isNotEmpty;
          });
        }
      }
    } catch (e) {
      debugPrint('Error checking requests: $e');
    }
  }

  Future<void> _loadUser() async {
    final uid = await SessionManager.getUserId();
    if (mounted) {
      setState(() {
        _userId = uid;
        _isLoadingUser = false;
      });
    }
  }

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
      if (index == 1) {
        _hasNewRequests = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingUser) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final List<Widget> pages = [
      // 0: Dashboard Tab
      const ProviderDashboardTab(),

      // 1: New Requests Tab (NEW)
      const ProviderRequestsPage(),

      // 2: Orders Tab
      const ProviderOrdersPage(),

      // 3: Product Orders Tab
      const ProductOrdersPage(),

      // 4: Profile Tab
      _userId != null
          ? ProfilePage(
              userId: _userId!,
              onBackToHome: () => setState(() => _currentIndex = 0),
            )
          : const Center(child: Text('User not logged in')),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(blurRadius: 20, color: Colors.black.withOpacity(.1)),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8),
            child: GNav(
              rippleColor: Colors.grey[300]!,
              hoverColor: Colors.grey[100]!,
              gap: 4,
              activeColor: Colors.blueAccent,
              iconSize: 24,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              duration: const Duration(milliseconds: 400),
              tabBackgroundColor: Colors.blueAccent.withOpacity(0.1),
              color: Colors.grey[600],
              tabs: [
                const GButton(icon: Icons.dashboard_rounded, text: 'Dashboard'),
                GButton(
                  icon: Icons.new_releases_rounded,
                  text: 'Requests',
                  leading: BadgeIcon(
                    showBadge: _hasNewRequests,
                    icon: Icon(
                      Icons.new_releases_rounded,
                      color: _currentIndex == 1
                          ? Colors.blueAccent
                          : Colors.grey[600],
                    ),
                  ),
                ),
                const GButton(icon: Icons.list_alt_rounded, text: 'Orders'),
                const GButton(icon: Icons.storefront_rounded, text: 'Products'),
                const GButton(icon: Icons.person_rounded, text: 'Profile'),
              ],
              selectedIndex: _currentIndex,
              onTabChange: (index) {
                _onTabTapped(index);
              },
            ),
          ),
        ),
      ),
    );
  }
}

// --- EXTRACTED DASHBOARD CONTENT ---

class ProviderDashboardTab extends StatefulWidget {
  const ProviderDashboardTab({super.key});

  @override
  State<ProviderDashboardTab> createState() => _ProviderDashboardTabState();
}

class _ProviderDashboardTabState extends State<ProviderDashboardTab>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _providerData;
  Map<String, dynamic> _stats = {
    'total_orders': 0,
    'pending_orders': 0,
    'avg_rating': 0.0,
  };
  bool _isLoading = true;
  List<Map<String, dynamic>> _ads = [];
  bool _hasUnreadNotifications = false;

  // Auto-sliding ads variables
  late PageController _adsPageController;
  Timer? _adTimer;
  int _currentAdPage = 0;
  RealtimeChannel? _adsSubscription;
  RealtimeChannel? _userSubscription;
  RealtimeChannel? _notificationSubscription;

  @override
  void initState() {
    super.initState();
    _fetchProviderData();
    _fetchAds();
    _checkUnreadNotifications();

    // Initialize ads carousel
    _adsPageController = PageController(viewportFraction: 0.92);
    _startAdAutoSlide();
    _subscribeToAds();
    _subscribeToUserUpdates();
    _subscribeToNotifications();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('App resumed - refreshing dashboard...');
      _fetchProviderData();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _adTimer?.cancel();
    _adsPageController.dispose();
    if (_adsSubscription != null) {
      SupabaseConfig.supabase.removeChannel(_adsSubscription!);
    }
    if (_userSubscription != null) {
      SupabaseConfig.supabase.removeChannel(_userSubscription!);
    }
    if (_notificationSubscription != null) {
      SupabaseConfig.supabase.removeChannel(_notificationSubscription!);
    }
    super.dispose();
  }

  void _startAdAutoSlide() {
    _adTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (_ads.isEmpty || !mounted) return;

      final nextPage = (_currentAdPage + 1) % _ads.length;

      if (_adsPageController.hasClients) {
        _adsPageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }

      setState(() {
        _currentAdPage = nextPage;
      });
    });
  }

  void _subscribeToAds() {
    _adsSubscription = SupabaseConfig.supabase.channel('public:provider_ads');
    _adsSubscription!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'ads',
          callback: (payload) {
            debugPrint('Realtime update received for ads');
            _fetchAds();
            _adTimer?.cancel();
            _startAdAutoSlide();
          },
        )
        .subscribe();
  }

  Future<void> _checkUnreadNotifications() async {
    try {
      final uid = await SessionManager.getUserId();
      if (uid == null) return;

      final response = await SupabaseConfig.supabase
          .from('notifications')
          .select('id')
          .eq('user_id', uid)
          .eq('is_read', false)
          .limit(1);

      if (mounted) {
        setState(() {
          _hasUnreadNotifications = (response as List).isNotEmpty;
        });
      }
    } catch (e) {
      debugPrint('Error checking notifications: $e');
      if (mounted) {
        setState(() => _hasUnreadNotifications = false);
      }
    }
  }

  Future<void> _fetchAds() async {
    try {
      final response = await SupabaseConfig.supabase
          .from('ads')
          .select()
          .eq('is_active', true)
          .gt('end_date', DateTime.now().toIso8601String());
      if (mounted) {
        setState(() {
          _ads = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      debugPrint('Error fetching ads: $e');
    }
  }

  Future<void> _subscribeToNotifications() async {
    final uid = await SessionManager.getUserId();
    if (uid == null) return;

    // Listen to ALL notifications and filter locally
    // This is more robust against UUID/String mismatch in Supabase Realtime filters
    _notificationSubscription = SupabaseConfig.supabase
        .channel('public:notifications:global')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          callback: (payload) {
            final newRecord = payload.newRecord;
            debugPrint('Realtime Event: $newRecord');

            // Verify notification belongs to current user (Double check)
            if (newRecord['user_id'] != uid) return;

            if (mounted) {
              setState(() => _hasUnreadNotifications = true);
            }

            // NOTE: We do NOT show a local notification here anymore.
            // FCMService handles foreground messages via onMessage stream.
            // Showing it here causes DUPLICATE notifications.
          },
        )
        .subscribe();
  }

  void _subscribeToUserUpdates() {
    SessionManager.getUserId().then((uid) {
      if (uid == null) return;

      _userSubscription = SupabaseConfig.supabase
          .channel('public:users:$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'users',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: uid,
            ),
            callback: (payload) {
              debugPrint('User update received! Refreshing dashboard...');
              _fetchProviderData();
            },
          )
          .subscribe();
    });
  }

  Future<void> _fetchProviderData() async {
    try {
      final userId = await SessionManager.getUserId();
      debugPrint('Provider Dashboard: Fetching data for userId: $userId');
      if (userId == null) {
        debugPrint('Provider Dashboard: userId is null');
        return;
      }

      // 1. Fetch Basic Info & Service Name & Subscription & Rating
      final userResponse = await SupabaseConfig.supabase
          .from('users')
          .select(
            'full_name, location, avatar_url, services(name), service_type, is_subscribed, subscription_status, subscription_expiry, subscription_start_date, average_rating, total_reviews, total_earnings, latitude, longitude, red_stars, is_blocked',
          )
          .eq('id', userId)
          .single();

      debugPrint(
        'Provider Dashboard: User data fetched: ${userResponse.toString()}',
      );

      // Fetch Service Type Name
      // Logic: The 'service_type' column might contain a UUID (referencing service_types table)
      // OR a raw string name (legacy data).
      if (userResponse['service_type'] != null) {
        final String rawType = userResponse['service_type'].toString();
        // Simple regex for rudimentary UUID check: 8-4-4-4-12 hex chars
        final bool isUuid = RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(rawType);

        if (isUuid) {
          try {
            final serviceTypeResponse = await SupabaseConfig.supabase
                .from('service_types')
                .select('name')
                .eq('id', rawType)
                .maybeSingle(); // Use maybeSingle to avoid exception if not found

            if (serviceTypeResponse != null) {
              userResponse['service_type_name'] = serviceTypeResponse['name'];
            } else {
              // Fallback if ID not found? Just usage rawType or ignore?
              // keeping null is safer than showing a raw ID.
            }
          } catch (e) {
            debugPrint('Error fetching service type name: $e');
          }
        } else {
          // It's likely a direct name string (e.g. 'Kitchen Cleaning')
          userResponse['service_type_name'] = rawType;
        }
      }
      // ... (geocoding logic remains same)

      // Attempt reverse geocoding if lat/long are present
      try {
        if (userResponse['latitude'] != null &&
            userResponse['longitude'] != null) {
          final double lat = (userResponse['latitude'] as num).toDouble();
          final double lng = (userResponse['longitude'] as num).toDouble();

          debugPrint(
            'Provider Dashboard: Reverse geocoding lat:$lat, lng:$lng',
          );

          final List<Placemark> placemarks = await placemarkFromCoordinates(
            lat,
            lng,
          );

          if (placemarks.isNotEmpty) {
            final Placemark place = placemarks.first;
            debugPrint(
              'Provider Dashboard: Placemark found: name=${place.name}, street=${place.street}, subLocality=${place.subLocality}, locality=${place.locality}, administrativeArea=${place.administrativeArea}',
            );

            // Construct precise address using Set to automatically handle duplicates
            final Set<String> addressParts = {};

            // 1. Street / Thoroughfare / Name
            // 'name' often contains house number or specific building name
            if (place.name != null && place.name!.isNotEmpty) {
              addressParts.add(place.name!);
            }

            // 'thoroughfare' is the street name
            if (place.thoroughfare != null && place.thoroughfare!.isNotEmpty) {
              addressParts.add(place.thoroughfare!);
            } else if (place.street != null && place.street!.isNotEmpty) {
              // Fallback to 'street' if thoroughfare is empty
              addressParts.add(place.street!);
            }

            // 2. Sub-Locality (Neighborhood/Area)
            if (place.subLocality != null && place.subLocality!.isNotEmpty) {
              addressParts.add(place.subLocality!);
            }

            // 3. Locality (City)
            if (place.locality != null && place.locality!.isNotEmpty) {
              addressParts.add(place.locality!);
            }

            // 4. State (Administrative Area) - optional, adding for context if list is short
            if (addressParts.length < 2 &&
                place.administrativeArea != null &&
                place.administrativeArea!.isNotEmpty) {
              addressParts.add(place.administrativeArea!);
            }

            // Join with commas
            String exactLocation = addressParts.join(', ');
            debugPrint(
              'Provider Dashboard: Constructed exactLocation: $exactLocation',
            );

            if (exactLocation.isNotEmpty) {
              userResponse['location'] = exactLocation;
            }
          } else {
            debugPrint(
              'Provider Dashboard: No placemarks found for these coordinates.',
            );
          }
        } else {
          debugPrint(
            'Provider Dashboard: Latitude or Longitude is null in DB.',
          );
        }
      } catch (e) {
        debugPrint('Error reverse geocoding provider location: $e');
      }

      // 2. Fetch Orders Count (Assigned to me)
      final ordersResponse = await SupabaseConfig.supabase
          .from('orders')
          .select('status, price, updated_at, created_at')
          .eq('provider_id', userId);

      final orders = ordersResponse as List;
      final int total = orders.length;
      final int myPendingOrders = orders
          .where((o) => o['status'] == 'pending' || o['status'] == 'accepted')
          .length;

      // Calculate Monthly Earnings
      double monthlyEarnings = 0;
      try {
        DateTime now = DateTime.now();
        DateTime monthStart;
        DateTime monthEnd;

        // Use Subscription Start Date for Alignment if available
        if (userResponse['subscription_start_date'] != null) {
          DateTime subStart = DateTime.parse(
            userResponse['subscription_start_date'],
          ).toLocal();

          final Duration diff = now.difference(subStart);
          if (diff.isNegative) {
            monthStart = subStart;
          } else {
            int monthsPassed = (diff.inDays / 30).floor();
            monthStart = subStart.add(Duration(days: monthsPassed * 30));
          }
        } else {
          // Fallback: Standard Calendar Month Start
          monthStart = DateTime(now.year, now.month, 1);
        }

        monthEnd = monthStart.add(const Duration(days: 30));

        for (var o in orders) {
          if (o['status'] == 'completed') {
            final dateStr = o['updated_at'] ?? o['created_at'];
            if (dateStr != null) {
              final date = DateTime.parse(dateStr).toLocal();
              // Filter for Current Aligned Month
              if (!date.isBefore(monthStart) && date.isBefore(monthEnd)) {
                monthlyEarnings += (o['price'] as num?)?.toDouble() ?? 0.0;
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Error calc monthly earnings: $e');
      }

      // Get rating from user data (auto-calculated by database)
      double avg = (userResponse['average_rating'] as num?)?.toDouble() ?? 0.0;

      if (mounted) {
        setState(() {
          _providerData = userResponse;

          _stats = {
            'total_orders': total,
            'pending_orders': myPendingOrders,
            'avg_rating': avg,
            'monthly_earnings': monthlyEarnings,
          };
          _isLoading = false;
        });
        debugPrint('Provider Dashboard: State updated successfully');
      }
    } catch (e, stackTrace) {
      debugPrint('Error fetching provider data: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logout(BuildContext context) async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.blueAccent,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Logging out...',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    // Wait a moment for the animation to show
    await Future.delayed(const Duration(milliseconds: 800));

    // Clear session
    await SessionManager.clearSession();

    // Close the loading dialog and navigate to login
    if (context.mounted) {
      Navigator.of(
        context,
        rootNavigator: true,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final String fullName = _providerData?['full_name'] ?? 'Provider';
    final String location = _providerData?['location'] ?? 'Unknown';
    final String? avatarUrl = _providerData?['avatar_url'];
    final serviceData = _providerData?['services'];
    final String serviceName = serviceData != null
        ? serviceData['name']
        : 'Unknown Service';
    final String? serviceTypeName = _providerData?['service_type_name'];

    final String displayService =
        (serviceTypeName != null && serviceTypeName.isNotEmpty)
        ? '$serviceName • $serviceTypeName'
        : serviceName;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: PopupMenuButton<String>(
          offset: const Offset(0, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          onSelected: (value) async {
            final userId = await SessionManager.getUserId();
            if (value == 'profile') {
              if (userId != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfilePage(userId: userId),
                  ),
                );
              }
            } else if (value == 'earnings') {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProviderEarningsPage()),
              );
            } else if (value == 'subscription') {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SubscriptionPage()),
              ).then((_) => _fetchProviderData());
            } else if (value == 'logout') {
              _logout(context);
            }
          },
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            const PopupMenuItem<String>(
              value: 'profile',
              child: Row(
                children: [
                  Icon(Icons.person_outline, color: Colors.blueAccent),
                  SizedBox(width: 12),
                  Text(
                    'My Profile',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const PopupMenuItem<String>(
              value: 'earnings',
              child: Row(
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    color: Colors.blueAccent,
                  ),
                  SizedBox(width: 12),
                  Text(
                    'My Earnings',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const PopupMenuItem<String>(
              value: 'subscription',
              child: Row(
                children: [
                  Icon(Icons.subscriptions_outlined, color: Colors.blueAccent),
                  SizedBox(width: 12),
                  Text(
                    'Subscription',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem<String>(
              value: 'logout',
              child: Row(
                children: [
                  Icon(Icons.logout, color: Colors.redAccent),
                  SizedBox(width: 12),
                  Text(
                    'Logout',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SafeAvatar(imageUrl: avatarUrl, radius: 18),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        fullName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.location_on,
                            size: 10,
                            color: Colors.blueAccent,
                          ),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              location,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_drop_down, color: Colors.black54),
              ],
            ),
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: () async {
                final Uri launchUri = Uri(scheme: 'tel', path: '9381728045');
                try {
                  await launchUrl(launchUri);
                } catch (e) {
                  debugPrint('Could not launch helpline: $e');
                }
              },
              icon: const Icon(Icons.headset_mic, color: Colors.blueAccent),
              tooltip: 'Helpline',
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NotificationsPage()),
                );
                _checkUnreadNotifications();
              },
              icon: BadgeIcon(
                showBadge: _hasUnreadNotifications,
                icon: const Icon(
                  Icons.notifications_outlined,
                  color: Colors.black87,
                ),
              ),
              tooltip: 'Notifications',
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Festival Banner (auto-shown when festival theme is active)
            const FestivalBanner(height: 140),

            // SUBSCRIPTION WARNING
            Builder(
              builder: (context) {
                final isSubscribed = _providerData?['is_subscribed'] == true;
                final subscriptionStatus = _providerData?['subscription_status'];
                final expiryStr = _providerData?['subscription_expiry'];

                bool isActive = false;
                if ((isSubscribed || subscriptionStatus == 'active') && expiryStr != null) {
                  final expiry = DateTime.tryParse(expiryStr.toString());
                  if (expiry != null && expiry.isAfter(DateTime.now())) {
                    isActive = true;
                  }
                }

                if (isActive) return const SizedBox.shrink();

                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 24),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.red.shade100),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.red.shade700,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Subscription Inactive",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade900,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "Renew to receive orders.",
                              style: TextStyle(
                                color: Colors.red.shade800,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SubscriptionPage(),
                            ),
                          ).then((_) => _fetchProviderData());
                        },
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: const Text(
                          "Renew",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // ACCOUNT BLOCKED BANNER
            Builder(
              builder: (context) {
                final isBlocked = _providerData?['is_blocked'] == true;
                final redStars = (_providerData?['red_stars'] as int?) ?? 0;

                if (!isBlocked && redStars < 3) return const SizedBox.shrink();

                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 24),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.red.shade800, Colors.red.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.block_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Account Blocked',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Your account has been blocked due to violation of our guidelines. Please visit the following link to request unblocking:',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () async {
                          final uid = await SessionManager.getUserId();
                          if (uid == null) return;
                          final siteUrl = 'https://red-star.onrender.com?id=$uid';
                          final uri = Uri.parse(siteUrl);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Center(
                            child: Text(
                              'Request Unblocking',
                              style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // RED STAR PENALTY CARD
            Builder(
              builder: (context) {
                final redStars = (_providerData?['red_stars'] as int?) ?? 0;
                final isBlocked = _providerData?['is_blocked'] == true;

                if (redStars <= 0 || isBlocked) return const SizedBox.shrink();

                return GestureDetector(
                  onTap: () async {
                    final uid = await SessionManager.getUserId();
                    if (uid == null) return;
                    final siteUrl = 'https://red-star.onrender.com?id=$uid';
                    final uri = Uri.parse(siteUrl);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 24),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: redStars >= 2
                          ? Colors.red.shade200
                          : Colors.orange.shade200,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (redStars >= 2 ? Colors.red : Colors.orange)
                            .withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(
                            3,
                            (index) => Padding(
                              padding: EdgeInsets.only(
                                right: index < 2 ? 2 : 0,
                              ),
                              child: Icon(
                                Icons.star_rounded,
                                size: 20,
                                color: index < redStars
                                    ? Colors.red.shade600
                                    : Colors.grey.shade300,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$redStars Red Star${redStars > 1 ? 's' : ''}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade800,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              redStars >= 2
                                  ? 'Warning: 1 more and your account will be blocked!'
                                  : 'Complete services on time to avoid penalties.',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                );
              },
            ),

            // WELCOME HEADER
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getGreeting(),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      fullName,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.location_on,
                        color: Colors.deepPurple.shade400,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 100),
                        child: Text(
                          location,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // EARNINGS CARD (Modern Wallet Style)
            // EARNINGS CARD (Modern Wallet Style)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF1A1A2E), // Dark Navy
                    Colors.deepPurple.shade800,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepPurple.withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.star,
                              color: Colors.amber,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              displayService,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.contactless_outlined,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Monthly Earnings',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 14,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₹${(_stats['monthly_earnings'] ?? 0).toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ProviderEarningsPage(),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'My Earnings',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const Text(
                        'Active',
                        style: TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Auto-Sliding Ads Carousel (moved here, above overview)
            if (_ads.isNotEmpty) ...[
              Column(
                children: [
                  SizedBox(
                    height: 180,
                    child: PageView.builder(
                      controller: _adsPageController,
                      itemCount: _ads.length,
                      onPageChanged: (index) {
                        setState(() {
                          _currentAdPage = index;
                        });
                      },
                      itemBuilder: (context, index) {
                        final ad = _ads[index];
                        return GestureDetector(
                          onTap: () async {
                            final link = ad['link'];
                            if (link == null ||
                                link.toString().trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('This ad has no link'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                              return;
                            }

                            try {
                              String urlString = link.toString().trim();

                              // Add https:// if no scheme is present
                              if (!urlString.startsWith('http://') &&
                                  !urlString.startsWith('https://')) {
                                urlString = 'https://$urlString';
                              }

                              final Uri url = Uri.parse(urlString);

                              // Check if the URL can be launched
                              final bool canLaunch = await canLaunchUrl(url);

                              if (canLaunch) {
                                await launchUrl(
                                  url,
                                  mode: LaunchMode.externalApplication,
                                );
                              } else {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Cannot open URL: $urlString',
                                      ),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                }
                              }
                            } catch (e) {
                              debugPrint('Error launching ad URL: $e');
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Failed to open link: ${e.toString()}',
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          child: Container(
                            margin: const EdgeInsets.only(right: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blue.withOpacity(0.2),
                                  blurRadius: 10,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (ad['image_url'] != null)
                                    Image.network(
                                      SupabaseConfig.proxyImageUrl(
                                        ad['image_url'],
                                      ),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.blue.shade400,
                                              Colors.blue.shade800,
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                        ),
                                        child: const Center(
                                          child: Icon(
                                            Icons.broken_image,
                                            size: 60,
                                            color: Colors.white24,
                                          ),
                                        ),
                                      ),
                                    )
                                  else
                                    Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.blue.shade400,
                                            Colors.blue.shade800,
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.campaign_outlined,
                                        size: 60,
                                        color: Colors.white24,
                                      ),
                                    ),
                                  Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.transparent,
                                          Colors.black.withOpacity(0.8),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 16,
                                    left: 16,
                                    right: 16,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white24,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: const Text(
                                            'FEATURED',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          ad['title'] ?? 'Special Offer',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Page Indicators
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _ads.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        height: 8,
                        width: _currentAdPage == index ? 24 : 8,
                        decoration: BoxDecoration(
                          color: _currentAdPage == index
                              ? Colors.deepPurple
                              : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],

            // QUICK STATS GRID
            const Text(
              "Overview",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.4,
              children: [
                _buildStatCard(
                  title: 'Total Orders',
                  value: _stats['total_orders'].toString(),
                  icon: Icons.assignment_turned_in,
                  color: Colors.blue,
                ),
                _buildStatCard(
                  title: 'Pending',
                  value: _stats['pending_orders'].toString(),
                  icon: Icons.pending_actions,
                  color: Colors.orange,
                ),
                _buildStatCard(
                  title: 'Rating',
                  value: _stats['avg_rating'].toStringAsFixed(1),
                  icon: Icons.star_rounded,
                  color: Colors.amber,
                ),
                _buildStatCard(
                  title: 'Reviews',
                  value: (_providerData?['total_reviews'] ?? 0).toString(),
                  icon: Icons.feedback,
                  color: Colors.purple,
                ),
              ],
            ),

            const SizedBox(height: 24),

            const SizedBox(height: 40),
            Center(
              child: Text(
                'Mr.Helper',
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning,';
    if (hour < 17) return 'Good Afternoon,';
    return 'Good Evening,';
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    bool isRating = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              if (isRating)
                const Icon(Icons.star, color: Colors.amber, size: 16),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
}
