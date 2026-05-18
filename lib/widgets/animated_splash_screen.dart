import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/session_manager.dart';
import '../auth/session_monitor.dart';
import '../auth/login.dart';
import '../home/user_home.dart';
import '../home/provider_home.dart';
import '../admin/admin_dashboard.dart';
import '../supabase_config.dart';
import '../firebase/fcm_service.dart';
import '../screens/get_started_page.dart';
import '../call/call_signaling_service.dart';

class AnimatedSplashScreen extends StatefulWidget {
  const AnimatedSplashScreen({super.key});

  @override
  State<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<AnimatedSplashScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;

  bool _isCheckingLocation = false;
  String _statusText = '';
  bool _waitingForLocationSettings = false;
  bool _hasTriedLocationSettings =
      false; // Track if user already went to settings
  bool _waitingForInternetSettings = false;
  bool _hasTriedInternetSettings = false;

  @override
  void initState() {
    super.initState();

    // Add lifecycle observer to detect when user comes back from settings
    WidgetsBinding.instance.addObserver(this);

    // Setup animations
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    // Pulse animation: 1.0 -> 1.15 -> 1.0 (logo pops then settles)
    // This creates seamless transition from native splash
    _pulseAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 1.18,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.18,
          end: 0.95,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.95,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 30,
      ),
    ]).animate(_controller);

    // Fade animation for text and other elements
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 1.0, curve: Curves.easeIn),
      ),
    );

    // Remove native splash and start animations
    _initializeSplash();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // When user comes back from settings, recheck
    if (state == AppLifecycleState.resumed) {
      if (_waitingForInternetSettings) {
        _waitingForInternetSettings = false;
        _checkInternetAndProceed();
      } else if (_waitingForLocationSettings) {
        _waitingForLocationSettings = false;
        _checkLocationAndProceed();
      }
    }
  }

  Future<void> _initializeSplash() async {
    // Small delay to ensure Flutter is ready, then remove native splash
    await Future.delayed(const Duration(milliseconds: 100));

    // Remove the native splash screen
    FlutterNativeSplash.remove();

    // Start the pulse animation immediately
    _controller.forward();

    // Wait for animation to complete, then check internet first
    await Future.delayed(const Duration(milliseconds: 1200));

    if (mounted) {
      await _checkInternetAndProceed();
    }
  }

  Future<void> _checkInternetAndProceed() async {
    setState(() {
      _isCheckingLocation = true;
      _statusText = 'Checking connection...';
    });

    // Check internet connectivity
    final connectivityResult = await Connectivity().checkConnectivity();
    final hasInternet =
        connectivityResult.isNotEmpty &&
        !connectivityResult.contains(ConnectivityResult.none);

    if (!hasInternet) {
      // If user already tried settings and came back without enabling, just proceed
      // (app may have limited functionality but at least won't be stuck)
      if (_hasTriedInternetSettings) {
        if (mounted) {
          await _checkLocationAndProceed();
        }
        return;
      }

      // Show bottom sheet to ask user to enable internet
      if (mounted) {
        await _showInternetBottomSheet();
      }
      return;
    }

    // Internet is available, proceed to check location
    if (mounted) {
      await _checkLocationAndProceed();
    }
  }

  Future<void> _showInternetBottomSheet() async {
    await showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),

            // Internet icon
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                size: 48,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 20),

            // Title
            const Text(
              'No Internet Connection',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),

            // Description
            Text(
              'Mr.Helper needs an internet connection to find and connect you with service providers.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),

            // Enable Internet Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);

                  // Set flags
                  _waitingForInternetSettings = true;
                  _hasTriedInternetSettings = true;

                  // Open WiFi settings (works on Android)
                  // On iOS, this will open general settings
                  try {
                    await launchUrl(Uri.parse('app-settings:'));
                  } catch (_) {
                    // Fallback - just wait for user to manually enable
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Open Settings',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Retry button
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _checkInternetAndProceed();
              },
              child: Text(
                'Try Again',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _checkLocationAndProceed() async {
    setState(() {
      _isCheckingLocation = true;
      _statusText = 'Finding services near you...';
    });

    // Check if location service is enabled
    bool isLocationEnabled = await Geolocator.isLocationServiceEnabled();

    if (!isLocationEnabled) {
      // If user already tried settings and came back without enabling, just proceed
      if (_hasTriedLocationSettings) {
        if (mounted) {
          await _initializeApp();
        }
        return;
      }

      // Show bottom sheet to ask user to enable location
      if (mounted) {
        await _showLocationBottomSheet();
      }
      return;
    }

    // Location is enabled, check permission
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      // Show a message and proceed anyway
      if (mounted) {
        setState(() {
          _statusText = 'Location permission denied. Continuing...';
        });
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    // Proceed with app initialization
    if (mounted) {
      await _initializeApp();
    }
  }

  Future<void> _showLocationBottomSheet() async {
    await showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),

            // Location icon
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_on_rounded,
                size: 48,
                color: Colors.deepPurple,
              ),
            ),
            const SizedBox(height: 20),

            // Title
            const Text(
              'Enable Location',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),

            // Description
            Text(
              'Mr.Helper needs your location to find nearby service providers and give you the best experience.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),

            // Enable Location Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);

                  // Set flags
                  _waitingForLocationSettings = true;
                  _hasTriedLocationSettings =
                      true; // Mark that user tried settings

                  // Open location settings
                  await Geolocator.openLocationSettings();

                  // The lifecycle observer will handle recheck when user returns
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Enable Location',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Skip button
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _initializeApp();
              },
              child: Text(
                'Skip for now',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _updateUserLocation({required String? uid}) async {
    if (uid == null) return;
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );

      await SupabaseConfig.supabase
          .from('users')
          .update({'latitude': pos.latitude, 'longitude': pos.longitude})
          .eq('id', uid);
    } catch (e) {
      debugPrint('Background location update error: $e');
    }
  }

  Future<void> _initializeApp() async {
    setState(() {
      _statusText = 'Connecting you to helpers...';
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final hasSeenOnboarding = prefs.getBool('hasSeenOnboarding') ?? false;

      if (!hasSeenOnboarding) {
        _navigateTo(const GetStartedPage());
        return;
      }

      final isLoggedIn = await SessionManager.isLoggedIn();

      if (!isLoggedIn) {
        _navigateTo(const LoginScreen());
        return;
      }

      final role = await SessionManager.getRole();
      final username = await SessionManager.getUsername();

      // Initialize FCM in background
      try {
        FCMService.saveTokenForCurrentUser();
      } catch (_) {}

      // Start listening for real-time calls
      try {
        CallSignalingService.instance.startListening();
      } catch (_) {}

      if (username == 'adime') {
        _navigateTo(const SessionMonitor(child: AdminDashboard()));
      } else if (role == 'provider') {
        _navigateTo(const SessionMonitor(child: ProviderHome()));
      } else {
        // It is a USER - update location and prefetch data
        setState(() {
          _statusText = 'Bringing services to your doorstep...';
        });

        try {
          _updateUserLocation(uid: await SessionManager.getUserId());
        } catch (e) {
          debugPrint('Failed to update background location: $e');
        }

        // Try to pre-fetch data
        try {
          final uid = await SessionManager.getUserId();
          if (uid == null) {
            _navigateTo(const SessionMonitor(child: UserHome()));
            return;
          }

          setState(() {
            _statusText = 'Your service partner is ready!';
          });

          // Parallel Fetching
          final userDataFuture = SupabaseConfig.supabase
              .from('users')
              .select('id, full_name, location, avatar_url')
              .eq('id', uid)
              .single();

          final servicesFuture = SupabaseConfig.supabase
              .from('services')
              .select('id, name, image_url');

          final adsFuture = SupabaseConfig.supabase
              .from('ads')
              .select()
              .eq('is_active', true)
              .gt('end_date', DateTime.now().toIso8601String());

          final results = await Future.wait<dynamic>([
            userDataFuture,
            servicesFuture,
            adsFuture,
          ]);

          final userData = results[0] as Map<String, dynamic>;
          final services = List<Map<String, dynamic>>.from(results[1] as List);
          final ads = List<Map<String, dynamic>>.from(results[2] as List);

          services.shuffle();

          _navigateTo(
            SessionMonitor(
              child: UserHome(
                preloadedUserData: userData,
                preloadedServices: services,
                preloadedAds: ads,
              ),
            ),
          );
        } catch (fetchError) {
          debugPrint(
            'Pre-fetch failed, falling back to basic home: $fetchError',
          );
          _navigateTo(const SessionMonitor(child: UserHome()));
        }
      }
    } catch (e) {
      debugPrint('Splash Init General Error: $e');
      _navigateTo(const LoginScreen());
    }
  }

  void _navigateTo(Widget screen) {
    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => screen,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated Logo with pulse effect
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/logo.jpg',
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: Colors.deepPurple,
                          child: const Icon(
                            Icons.handyman,
                            size: 80,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 32),

            // App Name with fade animation
            FadeTransition(
              opacity: _fadeAnimation,
              child: const Text(
                'Mr.Helper',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                  letterSpacing: 1.5,
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Tagline
            FadeTransition(
              opacity: _fadeAnimation,
              child: Text(
                'Your Service Partner',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  letterSpacing: 0.5,
                ),
              ),
            ),

            const SizedBox(height: 60),

            // Loading indicator and status text
            if (_isCheckingLocation) ...[
              FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.deepPurple.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _statusText,
                      style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
