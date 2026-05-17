# Auto-Sliding Ads Carousel Implementation

## Replace lines 749-851 in `user_home.dart`

Replace the existing ads SizedBox with this code:

```dart
                Column(
                  children: [
                    SizedBox(
                      height: 180,
                      child: PageView.builder(
                        controller: _adsPageController,  // ← Use our controller
                        itemCount: _ads.length,
                        onPageChanged: (index) {  // ← Track page changes
                          setState(() {
                            _currentAdPage = index;
                          });
                        },
                        itemBuilder: (context, index) {
                          final ad = _ads[index];
                          return GestureDetector(  // ← Make ads clickable
                            onTap: () {
                              if (ad['link'] != null && ad['link'].toString().isNotEmpty) {
                                final Uri url = Uri.parse(ad['link']);
                                launchUrl(url, mode: LaunchMode.externalApplication);
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
                                        ad['image_url'],
                                        fit: BoxFit.cover,
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
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white24,
                                              borderRadius: BorderRadius.circular(8),
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
                  ],
                ),
```

## Key Changes:

1. **Auto-Sliding**: Timer in `_startAdAutoSlide()` changes page every 4 seconds
2. **Page Indicators**: Animated dots show current page
3. **Clickable Ads**: Tapping opens the ad's link
4. **Smooth Transitions**: Uses `animateToPage()` with easing curve
5. **Looping**: Uses modulo operator to loop back to first ad

## Features:

✅ Auto-slides every 4 seconds
✅ Loops infinitely
✅ Page indicators with animation
✅ Manuel swipe stops auto-slide temporarily
✅ Smooth transitions
✅ Clickable ads
