import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import '../supabase_config.dart';

import 'package:firebase_core/firebase_core.dart';
import '../firebase/fcm_service.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../widgets/animated_splash_screen.dart';
import '../call/call_signaling_service.dart';
import '../services/theme_service.dart';
import '../services/google_billing_service.dart';

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // Preserve native splash until Flutter is ready
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Initialize Firebase
  await Firebase.initializeApp();

  // Initialize Supabase
  await SupabaseConfig.initialize();

  // Initialize FCM
  await FCMService.initialize();

  // Initialize Call Signaling Service Listeners
  CallSignalingService.instance.setupCallKitListeners();

  // Initialize Google Mobile Ads
  await MobileAds.instance.initialize();

  // Initialize Theme Service
  await ThemeService().initialize();

  // Initialize Google Play Billing
  await GoogleBillingService().initialize();

  runApp(const ProviderScope(child: MyApp()));
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    // Initialize ScreenUtil for responsive UI
    return ScreenUtilInit(
      designSize: const Size(375, 812), // Standard design size
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          title: 'Mr.Helper',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color.fromARGB(255, 251, 153, 41),
            ),
            useMaterial3: true,
          ),
          home: const AnimatedSplashScreen(),
        );
      },
    );
  }
}
