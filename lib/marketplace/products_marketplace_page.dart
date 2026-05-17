import 'package:flutter/material.dart';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_config.dart';
import '../auth/session_manager.dart';
import '../widgets/safe_network_image.dart';
import 'product_detail_page.dart';

class ProductsMarketplacePage extends StatefulWidget {
  const ProductsMarketplacePage({super.key});

  @override
  State<ProductsMarketplacePage> createState() =>
      _ProductsMarketplacePageState();
}

class _ProductsMarketplacePageState extends State<ProductsMarketplacePage> {
  List<Map<String, dynamic>> _products = [];
  bool _isLoading = true;
  double? _userLat;
  double? _userLng;
  String _sortBy = 'distance'; // distance, price_low, price_high, newest
  RealtimeChannel? _productsSubscription;

  @override
  void initState() {
    super.initState();
    _loadLocationAndProducts();
    _subscribeToProducts();
  }

  @override
  void dispose() {
    if (_productsSubscription != null) {
      SupabaseConfig.supabase.removeChannel(_productsSubscription!);
    }
    super.dispose();
  }

  void _subscribeToProducts() {
    _productsSubscription =
        SupabaseConfig.supabase.channel('public:products_marketplace');
    _productsSubscription!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'products',
          callback: (payload) {
            debugPrint('Products updated - refreshing marketplace');
            _fetchProducts();
          },
        )
        .subscribe();
  }

  Future<void> _loadLocationAndProducts() async {
    await _getUserLocation();
    await _fetchProducts();
  }

  Future<void> _getUserLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );

      _userLat = position.latitude;
      _userLng = position.longitude;
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  double _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const double earthRadius = 6371; // km
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * pi / 180;

  Future<void> _fetchProducts() async {
    try {
      final userId = await SessionManager.getUserId();

      final response = await SupabaseConfig.supabase
          .from('products')
          .select(
            '*, provider:users!provider_id(id, full_name, avatar_url, location, latitude, longitude, is_provider)',
          )
          .eq('is_active', true)
          .order('created_at', ascending: false);

      List<Map<String, dynamic>> products =
          List<Map<String, dynamic>>.from(response);

      // Filter out own products if user is a provider
      if (userId != null) {
        products =
            products.where((p) => p['provider_id'] != userId).toList();
      }

      // Calculate distance for each product
      for (var product in products) {
        final provider = product['provider'];
        if (provider != null &&
            _userLat != null &&
            _userLng != null &&
            provider['latitude'] != null &&
            provider['longitude'] != null) {
          final dist = _calculateDistance(
            _userLat!,
            _userLng!,
            (provider['latitude'] as num).toDouble(),
            (provider['longitude'] as num).toDouble(),
          );
          product['_distance'] = dist;
        } else {
          product['_distance'] = double.infinity;
        }
      }

      // Sort
      _sortProducts(products);

      if (mounted) {
        setState(() {
          _products = products;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching products: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _sortProducts(List<Map<String, dynamic>> products) {
    switch (_sortBy) {
      case 'distance':
        products.sort((a, b) =>
            (a['_distance'] as double).compareTo(b['_distance'] as double));
        break;
      case 'price_low':
        products.sort((a, b) =>
            ((a['price'] as num)).compareTo((b['price'] as num)));
        break;
      case 'price_high':
        products.sort((a, b) =>
            ((b['price'] as num)).compareTo((a['price'] as num)));
        break;
      case 'newest':
        // Already sorted by created_at desc from the query
        break;
    }
  }

  String _formatDistance(double distance) {
    if (distance == double.infinity) return 'Unknown';
    if (distance < 1) {
      return '${(distance * 1000).toInt()}m away';
    }
    return '${distance.toStringAsFixed(1)} km away';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.storefront_rounded, color: Color(0xFF6366F1)),
            SizedBox(width: 8),
            Text(
              'Marketplace',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          // Sort button
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort_rounded),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (value) {
              setState(() {
                _sortBy = value;
                _sortProducts(_products);
              });
            },
            itemBuilder: (context) => [
              _buildSortItem('distance', 'Nearest First', Icons.near_me),
              _buildSortItem(
                  'price_low', 'Price: Low to High', Icons.arrow_upward),
              _buildSortItem(
                  'price_high', 'Price: High to Low', Icons.arrow_downward),
              _buildSortItem('newest', 'Newest First', Icons.schedule),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _products.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadLocationAndProducts,
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.68,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _products.length,
                    itemBuilder: (context, index) =>
                        _buildProductCard(_products[index]),
                  ),
                ),
    );
  }

  PopupMenuItem<String> _buildSortItem(
      String value, String label, IconData icon) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: _sortBy == value ? const Color(0xFF6366F1) : Colors.grey,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontWeight:
                  _sortBy == value ? FontWeight.bold : FontWeight.normal,
              color: _sortBy == value ? const Color(0xFF6366F1) : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.storefront_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No Products Nearby',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Products from nearby providers will appear here',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final provider = product['provider'] as Map<String, dynamic>?;
    final distance = product['_distance'] as double;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProductDetailPage(product: product),
          ),
        ).then((_) => _fetchProducts());
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Image
            Expanded(
              flex: 3,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: SafeNetworkImage(
                      imageUrl: product['image_url'],
                      width: double.infinity,
                      height: double.infinity,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      errorWidget: Container(
                        color: Colors.grey.shade100,
                        child: const Center(
                          child: Icon(Icons.image, color: Colors.grey, size: 40),
                        ),
                      ),
                    ),
                  ),
                  // Distance badge
                  if (distance != double.infinity)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.location_on,
                              size: 12,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              _formatDistance(distance),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Product Info
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product['name'] ?? 'Product',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    // Provider name
                    if (provider != null)
                      Text(
                        provider['full_name'] ?? 'Provider',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const Spacer(),
                    // Price
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '₹${product['price']}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF6366F1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
