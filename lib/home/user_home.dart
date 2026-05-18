import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/login.dart';
import '../auth/session_manager.dart';
import '../supabase_config.dart';
import '../screens/service_result_page.dart';
import '../notifications/notifications_page.dart';
import '../orders/user_orders.dart';
import '../profile/profile_page.dart';
import '../profile/edit_profile.dart'; // Import EditProfilePage
import 'package:google_nav_bar/google_nav_bar.dart';
import '../profile/settings_page.dart';
import '../screens/booking_page.dart';

import '../screens/all_services_page.dart';
import '../screens/search_page.dart';
import '../widgets/badge_icon.dart';
import '../widgets/smart_admob_banner.dart'; // Smart fallback banner
import '../widgets/skeleton_loader.dart';

import '../services/theme_service.dart'; // Theme service
import 'dart:math';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async'; // For Timer
import 'nearby_service_providers.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../utils/error_handler.dart'; // Error handling utility
import '../marketplace/products_marketplace_page.dart'; // Products Marketplace
import '../call/call_signaling_service.dart';

class UserHome extends StatefulWidget {
  final Map<String, dynamic>? preloadedUserData;
  final List<Map<String, dynamic>>? preloadedServices;
  final List<Map<String, dynamic>>? preloadedAds;

  const UserHome({
    super.key,
    this.preloadedUserData,
    this.preloadedServices,
    this.preloadedAds,
  });

  @override
  State<UserHome> createState() => _UserHomeState();
}

class _UserHomeState extends State<UserHome> {
  int _currentIndex = 0;
  String? _userId;
  bool _isLoadingUser = true;

  @override
  void initState() {
    super.initState();
    if (widget.preloadedUserData != null &&
        widget.preloadedUserData!['id'] != null) {
      _userId = widget.preloadedUserData!['id'];
      _isLoadingUser = false;
    } else {
      _loadUser();
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
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingUser) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final List<Widget> pages = [
      UserHomeTab(
        preloadedUserData: widget.preloadedUserData,
        preloadedServices: widget.preloadedServices,
        preloadedAds: widget.preloadedAds,
        onNavigateToTab: (index) => _onTabTapped(index),
      ),
      const ServicesTabPage(),
      const ProductsMarketplacePage(), // Products Marketplace tab
      const UserOrdersPage(),
      _userId != null
          ? ProfilePage(
              userId: _userId!,
              onBackToHome: () => setState(() => _currentIndex = 0),
            )
          : const Center(child: Text('User not logged in')),
    ];

    return Scaffold(
      // We don't put an AppBar here because each page (UserHomeTab, UserOrdersPage, etc.) has its own.
      body: IndexedStack(index: _currentIndex, children: pages),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BookingPage()),
              ),
              label: const Text('Book Service'),
              icon: const Icon(Icons.add_circle),
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
            )
          : null,
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              duration: const Duration(milliseconds: 400),
              tabBackgroundColor: Colors.blueAccent.withValues(alpha: 0.1),
              color: Colors.grey[600],
              tabs: [
                const GButton(icon: Icons.home_rounded, text: 'Home'),
                const GButton(
                  icon: Icons.home_repair_service_rounded,
                  text: 'Services',
                ),
                const GButton(
                  icon: Icons.storefront_rounded,
                  text: 'Products',
                ),
                const GButton(
                  icon: Icons.assignment_rounded,
                  text: 'My Booking',
                ),
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

// --- SERVICES TAB PAGE ---

class ServicesTabPage extends StatefulWidget {
  const ServicesTabPage({super.key});

  @override
  State<ServicesTabPage> createState() => _ServicesTabPageState();
}

class _ServicesTabPageState extends State<ServicesTabPage> {
  List<Map<String, dynamic>> _services = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchServices();
  }

  Future<void> _fetchServices() async {
    try {
      final response = await SupabaseConfig.supabase
          .from('services')
          .select('id, name, image_url');

      if (mounted) {
        setState(() {
          _services = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching services: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return AllServicesPage(services: _services);
  }
}

// --- EXTRACTED HOME CONTENT ---

class UserHomeTab extends StatefulWidget {
  final Map<String, dynamic>? preloadedUserData;
  final List<Map<String, dynamic>>? preloadedServices;
  final List<Map<String, dynamic>>? preloadedAds;
  final Function(int)? onNavigateToTab;

  const UserHomeTab({
    super.key,
    this.preloadedUserData,
    this.preloadedServices,
    this.preloadedAds,
    this.onNavigateToTab,
  });

  @override
  State<UserHomeTab> createState() => _UserHomeTabState();
}

class _UserHomeTabState extends State<UserHomeTab>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _services = [];
  List<Map<String, dynamic>> _ads = [];
  bool _isLoadingServices = true;
  bool _hasUnreadNotifications = false;
  bool _usingGpsLocation = false; // Flag to prioritize GPS location

  // User Data
  String? _userId;
  String _fullName = 'User';
  String _location = 'Location';
  String? _avatarUrl;

  // Auto-sliding ads variables
  late PageController _adsPageController;
  Timer? _adTimer;
  int _currentAdPage = 0;

  // Rotating placeholder for search bar
  Timer? _placeholderTimer;
  int _currentPlaceholderIndex = 0;
  final List<String> _searchPlaceholders = [
    'What service do you need?',
    'Search for Plumbing...',
    'Looking for Electrician?',
    'Need a Carpenter?',
    'Find Cleaning Services...',
    'AC Repair & Maintenance...',
    'Search for Painters...',
    'Home Appliance Repair...',
  ];

  // Scroll controller for parallax effect
  final ScrollController _scrollController = ScrollController();

  RealtimeChannel? _servicesSubscription;
  RealtimeChannel? _adsSubscription;

  // Scroll state for sticky header
  bool _headerPinned = false;

  // Animation for brand text
  AnimationController? _brandAnimationController;
  Animation<double>? _fadeAnimation;
  Animation<double>? _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _initializeData();

    // Start listening for real-time calls
    try {
      CallSignalingService.instance.startListening();
    } catch (_) {}

    // Initialize ads carousel
    _adsPageController = PageController(viewportFraction: 0.92);
    _startAdAutoSlide();
    _getCurrentLocationV2();

    // Start rotating placeholder text
    _startPlaceholderRotation();

    // Add scroll listener for sticky header effect
    _scrollController.addListener(_onScroll);

    // Initialize brand animation
    _brandAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _brandAnimationController!,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _brandAnimationController!,
        curve: const Interval(0.0, 0.8, curve: Curves.easeOutBack),
      ),
    );

    // Start animation
    _brandAnimationController?.forward();
  }

  void _onScroll() {
    // Change to white background when scrolled past a threshold (e.g. 10 pixels)
    final shouldPin =
        _scrollController.hasClients && _scrollController.offset > 10;
    if (shouldPin != _headerPinned) {
      setState(() {
        _headerPinned = shouldPin;
      });
    }
  }

  /// Reload all data - used for retry functionality
  Future<void> _reloadAllData() async {
    if (!mounted) return;

    // Show loading indicator
    setState(() {
      _isLoadingServices = true;
    });

    try {
      // Reload everything in parallel
      await Future.wait([
        _fetchUserData(),
        _fetchAds(),
        _fetchServices(),
        _getCurrentLocationV2(),
      ]);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Data reloaded successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error reloading data: $e');
      // Error will be handled by individual functions
    }
  }

  void _initializeData() {
    // 1. User Data
    if (widget.preloadedUserData != null) {
      _userId = widget.preloadedUserData!['id'];
      _fullName = widget.preloadedUserData!['full_name'] ?? 'User';
      _location = widget.preloadedUserData!['location'] ?? 'Unknown Location';
      _avatarUrl = widget.preloadedUserData!['avatar_url'];
    } else {
      _fetchUserData();
    }

    // 2. Services
    if (widget.preloadedServices != null) {
      _services = widget.preloadedServices!;
      _isLoadingServices = false;
    } else {
      _fetchServices();
    }

    // 3. Ads
    if (widget.preloadedAds != null) {
      _ads = widget.preloadedAds!;
    } else {
      _fetchAds();
    }

    _subscribeToServices();
    _subscribeToAds();
    _checkUnreadNotifications();
  }

  void _startAdAutoSlide() {
    _adTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (_ads.isEmpty || !mounted) return;

      final nextPage = (_currentAdPage + 1) % _ads.length;

      _adsPageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );

      setState(() {
        _currentAdPage = nextPage;
      });
    });
  }

  void _startPlaceholderRotation() {
    _placeholderTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted) return;
      setState(() {
        _currentPlaceholderIndex =
            (_currentPlaceholderIndex + 1) % _searchPlaceholders.length;
      });
    });
  }

  void _subscribeToServices() {
    _servicesSubscription = SupabaseConfig.supabase.channel('public:services');
    _servicesSubscription!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'services',
          callback: (payload) {
            debugPrint('Realtime update received for services');
            _fetchServices();
          },
        )
        .subscribe();
  }

  void _subscribeToAds() {
    _adsSubscription = SupabaseConfig.supabase.channel('public:ads');
    _adsSubscription!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'ads',
          callback: (payload) {
            debugPrint('Realtime update received for ads');
            _fetchAds();
            // Restart auto-slide timer when ads change
            _adTimer?.cancel();
            _startAdAutoSlide();
          },
        )
        .subscribe();
  }

  Future<void> _fetchUserData() async {
    try {
      final uid = await SessionManager.getUserId();
      if (uid != null) {
        final data = await SupabaseConfig.supabase
            .from('users')
            .select('full_name, location, avatar_url')
            .eq('id', uid)
            .single();

        if (mounted) {
          setState(() {
            _userId = uid;
            _fullName = data['full_name'] ?? 'User';
            if (!_usingGpsLocation) {
              _location = data['location'] ?? 'Unknown Location';
            }
            _avatarUrl = data['avatar_url'];
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching user data: $e');
      if (mounted) {
        showErrorDialog(
          context,
          e,
          title: 'Unable to Load Profile',
          onRetry: _reloadAllData,
        );
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
      if (mounted) {
        showErrorDialog(
          context,
          e,
          title: 'Unable to Load Ads',
          onRetry: _reloadAllData,
        );
      }
    }
  }

  Future<void> _checkUnreadNotifications() async {
    final uid = await SessionManager.getUserId();
    if (uid == null) return;

    // 1. Initial Check
    try {
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
    }

    // 2. Realtime Listener for NEW notifications (Badge Only)
    // We do NOT show local notifications here to avoid duplicates with FCM
    SupabaseConfig.supabase
        .channel('public:notifications:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (payload) {
            if (mounted) {
              setState(() {
                _hasUnreadNotifications = true;
              });
            }
          },
        )
        .subscribe();
  }

  Future<void> _fetchServices() async {
    try {
      final response = await SupabaseConfig.supabase
          .from('services')
          .select('id, name, image_url');
      setState(() {
        _services = List<Map<String, dynamic>>.from(response);
        _services.shuffle(); // Randomize the list
        _isLoadingServices = false;
      });
    } catch (e) {
      debugPrint('Error fetching services: $e');
      if (mounted) setState(() => _isLoadingServices = false);
    }
  }

  Future<void> _getCurrentLocationV2() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled.');
        // Fallback to DB location
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('Location permissions are denied');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permissions are permanently denied');
        return;
      }

      // Get position with high accuracy
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );

      // Successfully got coordinates, try geocoding
      String newLocation =
          "${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}";

      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if (placemarks.isNotEmpty) {
          Placemark place = placemarks[0];
          String address = '';

          if (place.subLocality != null && place.subLocality!.isNotEmpty) {
            address = place.subLocality!;
          }

          if (place.locality != null && place.locality!.isNotEmpty) {
            if (address.isNotEmpty) address += ', ';
            address += place.locality!;
          }

          if (address.isEmpty) {
            if (place.subAdministrativeArea != null &&
                place.subAdministrativeArea!.isNotEmpty) {
              address = place.subAdministrativeArea!;
            } else if (place.administrativeArea != null &&
                place.administrativeArea!.isNotEmpty) {
              address = place.administrativeArea!;
            }
          }

          if (address.isNotEmpty) {
            newLocation = address;
          }
        }
      } catch (geoError) {
        debugPrint('Geocoding error: $geoError');
      }

      if (mounted) {
        setState(() {
          _location = newLocation;
          _usingGpsLocation = true;
        });
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
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
  void dispose() {
    _adTimer?.cancel();
    _placeholderTimer?.cancel();
    _adsPageController.dispose();
    _scrollController.removeListener(_onScroll); // Remove listener
    _scrollController.dispose();
    _brandAnimationController?.dispose();
    if (_servicesSubscription != null) {
      SupabaseConfig.supabase.removeChannel(_servicesSubscription!);
    }
    if (_adsSubscription != null) {
      SupabaseConfig.supabase.removeChannel(_adsSubscription!);
    }
    super.dispose();
  }

  // ... (rest of methods until build)

  @override
  Widget build(BuildContext context) {
    final theme = ThemeService().activeTheme ?? ThemeService().defaultTheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      drawer: Drawer(
        child: Column(
          children: [
            // Header with profile info
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [theme.primaryColor, theme.secondaryColor],
                ),
              ),
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 20,
                bottom: 20,
                left: 20,
                right: 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Profile Picture with edit icon
                  Center(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () async {
                        Navigator.pop(context); // Close drawer
                        if (_userId != null) {
                          try {
                            // Show loading indicator or just await
                            // Fetch full user data for editing
                            final fullUserData = await SupabaseConfig.supabase
                                .from('users')
                                .select()
                                .eq('id', _userId!)
                                .single();

                            if (context.mounted) {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      EditProfilePage(userData: fullUserData),
                                ),
                              );

                              // Refresh if profile was updated
                              if (result == true) {
                                _fetchUserData();
                              }
                            }
                          } catch (e) {
                            debugPrint('Error fetching profile for edit: $e');
                          }
                        }
                      },
                      child: Stack(
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child:
                                  _avatarUrl != null && _avatarUrl!.isNotEmpty
                                  ? Image.network(
                                      SupabaseConfig.proxyImageUrl(_avatarUrl),
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                            return Container(
                                              color: Colors.white,
                                              child: Icon(
                                                Icons.person,
                                                color: theme.primaryColor,
                                                size: 40,
                                              ),
                                            );
                                          },
                                    )
                                  : Container(
                                      color: Colors.white,
                                      child: Icon(
                                        Icons.person,
                                        color: theme.primaryColor,
                                        size: 40,
                                      ),
                                    ),
                            ),
                          ),
                          // Pencil icon overlay
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: theme.primaryColor,
                                  width: 2,
                                ),
                              ),
                              child: Icon(
                                Icons.edit,
                                size: 14,
                                color: theme.primaryColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Username
                  Text(
                    _fullName.isNotEmpty ? _fullName : 'Guest',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  // Location
                  if (_location.isNotEmpty)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 16,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            _location,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            // Menu options
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ListTile(
                    leading: Icon(
                      Icons.person_outline,
                      color: theme.primaryColor,
                    ),
                    title: const Text(
                      'My Profile',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 16,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context); // Close drawer
                      if (_userId != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProfilePage(userId: _userId!),
                          ),
                        );
                      }
                    },
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.assignment_outlined,
                      color: theme.primaryColor,
                    ),
                    title: const Text(
                      'My Booking',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 16,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context); // Close drawer
                      widget.onNavigateToTab?.call(
                        2,
                      ); // Navigate to Orders Tab (My Booking)
                    },
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.settings_outlined,
                      color: theme.primaryColor,
                    ),
                    title: const Text(
                      'Settings',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 16,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context); // Close drawer
                      if (_userId != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SettingsPage(
                              userData: {
                                'id': _userId,
                                'full_name': _fullName,
                                'location': _location,
                                'avatar_url': _avatarUrl,
                              },
                            ),
                          ),
                        );
                      }
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.logout, color: Colors.redAccent),
                    title: const Text(
                      'Logout',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w500,
                        fontSize: 16,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context); // Close drawer
                      _logout(context);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      appBar: AppBar(
        // Animate background color change
        backgroundColor: _headerPinned ? Colors.white : Colors.transparent,
        elevation: _headerPinned ? 2 : 0,
        surfaceTintColor: Colors.transparent, // Disable Material 3 pint
        automaticallyImplyLeading: false,
        flexibleSpace: Container(),
        title: Builder(
          builder: (context) => InkWell(
            onTap: () {
              Scaffold.of(context).openDrawer();
            },
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _headerPinned
                    ? Colors.grey.shade100
                    : theme.cardColor.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.menu, color: theme.textColor, size: 24),
                  const SizedBox(width: 12),
                  if (_fadeAnimation != null && _scaleAnimation != null)
                    FadeTransition(
                      opacity: _fadeAnimation!,
                      child: ScaleTransition(
                        scale: _scaleAnimation!,
                        child: Text(
                          'Mr.Helper',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: theme.textColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    )
                  else
                    Text(
                      'Mr.Helper',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: theme.textColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: _headerPinned
                  ? Colors.grey.shade100
                  : theme.cardColor.withValues(alpha: 0.9),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
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
              icon: Icon(Icons.headset_mic, color: theme.textColor),
              tooltip: 'Helpline',
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: _headerPinned
                  ? Colors.grey.shade100
                  : theme.cardColor.withValues(alpha: 0.9),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
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
                icon: Icon(
                  Icons.notifications_outlined,
                  color: theme.textColor,
                ),
              ),
              tooltip: 'Notifications',
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Full background color
          Container(color: theme.backgroundColor),

          // Extended background image layer
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 350,
            child: AnimatedBuilder(
              animation: _scrollController,
              builder: (context, child) {
                final scrollOffset = _scrollController.hasClients
                    ? _scrollController.offset
                    : 0.0;
                return Opacity(
                  opacity: (1 - (scrollOffset / 350)).clamp(
                    0.0,
                    1.0,
                  ), // Fade over 350px
                  child: Container(
                    decoration: BoxDecoration(
                      image: theme.bannerImageUrl != null
                          ? DecorationImage(
                              image: theme.bannerImageUrl!.startsWith('http')
                                  ? CachedNetworkImageProvider(
                                          SupabaseConfig.proxyImageUrl(
                                            theme.bannerImageUrl,
                                          ),
                                        )
                                        as ImageProvider
                                  : AssetImage(theme.bannerImageUrl!),
                              fit: BoxFit.cover,
                              // No fixed opacity - image is 100% visible at top
                            )
                          : null,
                      gradient: LinearGradient(
                        colors: [
                          theme.primaryColor.withOpacity(0.3),
                          theme.backgroundColor,
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Main scrollable content
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              // SliverAppBar with background image that fades on scroll
              SliverAppBar(
                expandedHeight: 76,
                toolbarHeight:
                    0, // Keeps gap minimal regardless of expandedHeight
                floating: false,
                pinned: true,
                backgroundColor: _headerPinned
                    ? Colors.white
                    : Colors.transparent, // Dynamic Color
                elevation: _headerPinned
                    ? 0
                    : 0, // Elevation handled by shadow decoration
                surfaceTintColor: Colors.transparent,
                flexibleSpace:
                    Container(), // Empty - background is in positioned layer
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(76),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                    child: Container(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: theme.primaryColor.withOpacity(0.15),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SearchPage(),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: theme.cardColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.transparent, // No border
                              width: 0,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(Icons.search, color: theme.primaryColor),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ClipRect(
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 400),
                                    transitionBuilder: (child, animation) {
                                      // Check if this is the incoming (new) widget by comparing keys
                                      final childKey =
                                          child.key as ValueKey<int>?;
                                      final isIncoming =
                                          childKey?.value ==
                                          _currentPlaceholderIndex;

                                      // Incoming (animation 0->1): slide from top (-0.5) to center (0)
                                      // Outgoing (animation 1->0): slide from center (0) to bottom (0.5)
                                      final slideAnimation =
                                          Tween<Offset>(
                                            begin: isIncoming
                                                ? const Offset(
                                                    0,
                                                    -0.5,
                                                  ) // incoming: start from top
                                                : const Offset(
                                                    0,
                                                    0.5,
                                                  ), // outgoing: end at bottom
                                            end: Offset
                                                .zero, // both pass through center
                                          ).animate(
                                            CurvedAnimation(
                                              parent: animation,
                                              curve: Curves.easeInOut,
                                            ),
                                          );

                                      return FadeTransition(
                                        opacity: animation,
                                        child: SlideTransition(
                                          position: slideAnimation,
                                          child: child,
                                        ),
                                      );
                                    },
                                    layoutBuilder:
                                        (currentChild, previousChildren) {
                                          return Stack(
                                            alignment: Alignment.centerLeft,
                                            clipBehavior: Clip.hardEdge,
                                            children: [
                                              ...previousChildren,
                                              if (currentChild != null)
                                                currentChild,
                                            ],
                                          );
                                        },
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      key: ValueKey<int>(
                                        _currentPlaceholderIndex,
                                      ),
                                      child: Text(
                                        _searchPlaceholders[_currentPlaceholderIndex],
                                        textAlign: TextAlign.left,
                                        style: TextStyle(
                                          color: Colors.grey.shade400,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              // Mic icon button
                              GestureDetector(
                                onTap: () async {
                                  // Open search page with voice search activated
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const SearchPage(
                                        activateVoiceSearch: true,
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.mic,
                                    color: Colors.blueAccent,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Main content
              SliverToBoxAdapter(
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    theme.bannerImageUrl != null
                        ? 230
                        : 20, // Less gap for default theme
                    20,
                    20,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Ads Carousel
                      if (_ads.isNotEmpty) ...[
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
                                    if (!urlString.startsWith('http')) {
                                      urlString = 'https://$urlString';
                                    }
                                    final Uri url = Uri.parse(urlString);
                                    if (await canLaunchUrl(url)) {
                                      await launchUrl(
                                        url,
                                        mode: LaunchMode.externalApplication,
                                      );
                                    }
                                  } catch (e) {
                                    debugPrint('Error launching ad URL: $e');
                                  }
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(right: 12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.blue.withValues(
                                          alpha: 0.2,
                                        ),
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
                                          CachedNetworkImage(
                                            imageUrl:
                                                SupabaseConfig.proxyImageUrl(
                                                  ad['image_url'],
                                                ),
                                            fit: BoxFit.cover,
                                            placeholder: (context, url) =>
                                                const SkeletonLoader(),
                                            errorWidget:
                                                (context, url, error) =>
                                                    Container(
                                                      color:
                                                          Colors.grey.shade200,
                                                      child: const Icon(
                                                        Icons.error,
                                                        color: Colors.grey,
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
                                              ),
                                            ),
                                            child: const Icon(
                                              Icons.campaign_outlined,
                                              size: 60,
                                              color: Colors.white24,
                                            ),
                                          ),
                                        // Gradient overlay
                                        Container(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                              colors: [
                                                Colors.transparent,
                                                Colors.black.withValues(
                                                  alpha: 0.8,
                                                ),
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
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white24,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
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
                                    ? Colors.blueAccent
                                    : Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // Services Section
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Explore Services',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: theme.textColor,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      AllServicesPage(services: _services),
                                ),
                              );
                            },
                            child: Text(
                              'View All',
                              style: TextStyle(
                                color: theme.primaryColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      _isLoadingServices
                          ? const Center(child: CircularProgressIndicator())
                          : _services.isEmpty
                          ? Container(
                              padding: const EdgeInsets.all(30),
                              alignment: Alignment.center,
                              child: const Text(
                                'No services found yet.',
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : GridView.builder(
                              padding: EdgeInsets.zero,
                              physics: const NeverScrollableScrollPhysics(),
                              shrinkWrap: true,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: 16,
                                    mainAxisSpacing: 16,
                                    childAspectRatio: 0.85,
                                  ),
                              itemCount: min(_services.length, 6),
                              itemBuilder: (context, index) {
                                final service = _services[index];
                                final colorIndex = index % 4;
                                final List<Color> cardColors = [
                                  Colors.blue.shade50,
                                  Colors.purple.shade50,
                                  Colors.orange.shade50,
                                  Colors.green.shade50,
                                ];
                                final List<Color> iconColors = [
                                  Colors.blue,
                                  Colors.purple,
                                  Colors.orange,
                                  Colors.green,
                                ];

                                return GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ServiceResultPage(
                                          serviceId: service['id'],
                                          serviceName: service['name'],
                                        ),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: theme.cardColor,
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.grey.withValues(
                                            alpha: 0.08,
                                          ),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Stack(
                                      children: [
                                        if (service['image_url'] != null)
                                          Positioned.fill(
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              child: CachedNetworkImage(
                                                imageUrl:
                                                    SupabaseConfig.proxyImageUrl(
                                                      service['image_url'],
                                                    ),
                                                fit: BoxFit.cover,
                                                placeholder: (context, url) =>
                                                    const SkeletonLoader(),
                                                errorWidget:
                                                    (
                                                      context,
                                                      error,
                                                      stackTrace,
                                                    ) => Container(
                                                      color:
                                                          cardColors[colorIndex],
                                                    ),
                                              ),
                                            ),
                                          ),
                                        if (service['image_url'] != null)
                                          Positioned.fill(
                                            child: Container(
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                gradient: LinearGradient(
                                                  begin: Alignment.topCenter,
                                                  end: Alignment.bottomCenter,
                                                  colors: [
                                                    Colors.black.withOpacity(
                                                      0.1,
                                                    ),
                                                    Colors.black.withOpacity(
                                                      0.6,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              if (service['image_url'] == null)
                                                Container(
                                                  padding: const EdgeInsets.all(
                                                    12,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        cardColors[colorIndex],
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          15,
                                                        ),
                                                  ),
                                                  child: Icon(
                                                    Icons.build_circle_outlined,
                                                    size: 32,
                                                    color:
                                                        iconColors[colorIndex],
                                                  ),
                                                ),
                                              const Spacer(),
                                              Text(
                                                service['name'],
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                  color:
                                                      service['image_url'] !=
                                                          null
                                                      ? Colors.white
                                                      : Colors.black87,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Available now',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color:
                                                      service['image_url'] !=
                                                          null
                                                      ? Colors.white70
                                                      : Colors.grey,
                                                  fontWeight: FontWeight.w500,
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

                      const SizedBox(height: 16),
                      const SmartAdMobBanner(),

                      const SizedBox(height: 24),
                      const NearbyServiceProviders(),

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
              ),
            ],
          ), // Closing CustomScrollView
        ],
      ), // Closing Stack
    );
  }
}
