import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// AdMob Banner that shows production ads and hides gracefully on failure
class SmartAdMobBanner extends StatefulWidget {
  const SmartAdMobBanner({super.key});

  @override
  State<SmartAdMobBanner> createState() => _SmartAdMobBannerState();
}

class _SmartAdMobBannerState extends State<SmartAdMobBanner> {
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;
  bool _loadingFailed = false;
  int _retryCount = 0;
  static const int _maxRetries = 2;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  void _loadAd() {
    debugPrint(
      'SmartAdMob: Attempting to load ad (attempt ${_retryCount + 1})...',
    );

    _bannerAd?.dispose();
    _bannerAd = BannerAd(
      adUnitId: 'ca-app-pub-8333163485636480/3424545504',
      size: AdSize.mediumRectangle,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          debugPrint('✅ SmartAdMob: Ad loaded successfully!');
          if (mounted) {
            setState(() {
              _isAdLoaded = true;
              _loadingFailed = false;
            });
          }
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('❌ SmartAdMob: Ad failed to load');
          debugPrint('Error Code: ${error.code}');
          debugPrint('Error Message: ${error.message}');

          ad.dispose();

          if (_retryCount < _maxRetries) {
            // Retry with exponential backoff
            _retryCount++;
            final delay = Duration(seconds: _retryCount * 2);
            debugPrint(
              '🔄 SmartAdMob: Retrying in ${delay.inSeconds}s (attempt $_retryCount/$_maxRetries)...',
            );
            Future.delayed(delay, () {
              if (mounted) {
                _loadAd();
              }
            });
          } else {
            // All retries exhausted, hide the ad space
            debugPrint(
              '⚠️ SmartAdMob: All retries exhausted. Hiding ad space.',
            );
            if (mounted) {
              setState(() {
                _loadingFailed = true;
                _isAdLoaded = false;
              });
            }
          }
        },
        onAdImpression: (ad) {
          debugPrint('💰 SmartAdMob: Ad impression');
        },
      ),
    );

    _bannerAd?.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Hide completely if loading failed
    if (_loadingFailed) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Ad Header Label
          if (_isAdLoaded)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'SPONSORED',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade400,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),

          // Main Ad Container
          Container(
            constraints: const BoxConstraints(minHeight: 250, minWidth: 300),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade100),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: !_isAdLoaded
                ? SizedBox(
                    height: 250,
                    width: 300,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.blue.shade200,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Loading...',
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: _bannerAd!.size.width.toDouble(),
                      height: _bannerAd!.size.height.toDouble(),
                      child: AdWidget(ad: _bannerAd!),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
