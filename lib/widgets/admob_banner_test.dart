import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdMobBannerTest extends StatefulWidget {
  final bool useTestAds;

  const AdMobBannerTest({super.key, this.useTestAds = false});

  @override
  State<AdMobBannerTest> createState() => _AdMobBannerTestState();
}

class _AdMobBannerTestState extends State<AdMobBannerTest> {
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadBannerAd();
  }

  void _loadBannerAd() {
    debugPrint('AdMobBanner: Starting to load banner ad...');
    debugPrint('AdMobBanner: Using TEST ads: ${widget.useTestAds}');

    // Test Ad Unit ID or Production ID
    final String adUnitId = widget.useTestAds
        ? 'ca-app-pub-3940256099942544/6300978111' // Google Test ID
        : 'ca-app-pub-8333163485636480/3424545504'; // Your Production ID

    debugPrint('AdMobBanner: Using Ad Unit ID: $adUnitId');

    _bannerAd = BannerAd(
      adUnitId: adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          debugPrint('✅ AdMobBanner: Banner ad loaded successfully!');
          final bannerAd = ad as BannerAd;
          debugPrint('Ad size: ${bannerAd.size.width}x${bannerAd.size.height}');
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

          // Show common error explanations
          if (error.code == 0) {
            debugPrint('💡 Error 0: Internal error or network issue');
          } else if (error.code == 1) {
            debugPrint('💡 Error 1: Invalid request');
          } else if (error.code == 2) {
            debugPrint('💡 Error 2: Network error - check internet');
          } else if (error.code == 3) {
            debugPrint('💡 Error 3: No fill - no ads available');
          }

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
    debugPrint('AdMobBanner: Disposing banner ad');
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              widget.useTestAds ? 'Loading TEST ad...' : 'Loading ad...',
              style: const TextStyle(
                color: Colors.blue,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    // Return empty space if ad failed to load or hasn't started
    if (!_isAdLoaded || _bannerAd == null) {
      debugPrint(
        'AdMobBanner: No ad to display (loaded: $_isAdLoaded, banner: ${_bannerAd != null})',
      );
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: const Column(
          children: [
            Icon(Icons.info_outline, color: Colors.orange, size: 32),
            SizedBox(height: 8),
            Text(
              'Ad not available',
              style: TextStyle(
                color: Colors.orange,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Check console logs for details',
              style: TextStyle(color: Colors.grey, fontSize: 10),
            ),
          ],
        ),
      );
    }

    debugPrint('AdMobBanner: Displaying ad successfully');
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.green.shade300, width: 2),
      ),
      child: Column(
        children: [
          if (widget.useTestAds)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10),
                  topRight: Radius.circular(10),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle,
                    color: Colors.green.shade700,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'TEST AD (Implementation Working!)',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            ),
          ),
        ],
      ),
    );
  }
}
