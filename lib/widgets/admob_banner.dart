import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdMobBanner extends StatefulWidget {
  const AdMobBanner({super.key});

  @override
  State<AdMobBanner> createState() => _AdMobBannerState();
}

class _AdMobBannerState extends State<AdMobBanner> {
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadBannerAd();
  }

  void _loadBannerAd() {
    debugPrint('AdMobBanner: Starting to load banner ad...');

    // Production Banner Ad Unit ID
    const String adUnitId = 'ca-app-pub-8333163485636480/3424545504';

    debugPrint('AdMobBanner: Using Ad Unit ID: $adUnitId');

    _bannerAd = BannerAd(
      adUnitId: adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          debugPrint('✅ AdMobBanner: Banner ad loaded successfully!');
          if (mounted) {
            setState(() {
              _isAdLoaded = true;
            });
          }
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('❌ AdMobBanner: Banner ad FAILED to load');
          debugPrint('Error Code: ${error.code}');
          debugPrint('Error Domain: ${error.domain}');
          debugPrint('Error Message: ${error.message}');
          debugPrint('Response Info: ${error.responseInfo}');
          ad.dispose();
        },
        onAdOpened: (ad) {
          debugPrint('AdMobBanner: Banner ad opened');
        },
        onAdClosed: (ad) {
          debugPrint('AdMobBanner: Banner ad closed');
        },
        onAdImpression: (ad) {
          debugPrint('💰 AdMobBanner: Ad impression recorded');
        },
      ),
    );

    debugPrint('AdMobBanner: Calling load() on banner ad...');
    _bannerAd?.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show loading indicator while ad is loading
    if (!_isAdLoaded && _bannerAd != null) {
      debugPrint('AdMobBanner: Ad is loading...');
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 16),
        height: 60,
        child: const Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text(
                'Loading ad...',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    // Return empty space if ad failed to load or hasn't started
    if (!_isAdLoaded || _bannerAd == null) {
      debugPrint(
        'AdMobBanner: No ad to display (loaded: $_isAdLoaded, banner: ${_bannerAd != null})',
      );
      return const SizedBox.shrink();
    }

    debugPrint('AdMobBanner: Displaying ad successfully');
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: _bannerAd!.size.width.toDouble(),
          height: _bannerAd!.size.height.toDouble(),
          child: AdWidget(ad: _bannerAd!),
        ),
      ),
    );
  }
}
