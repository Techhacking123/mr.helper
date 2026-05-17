import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../supabase_config.dart';
import '../auth/session_manager.dart';
import '../profile/profile_page.dart';
import '../widgets/map_picker.dart';
import '../widgets/safe_network_image.dart';
import '../utils/error_handler.dart'; // Error handling utility

class NearbyServiceProviders extends StatefulWidget {
  const NearbyServiceProviders({super.key});

  @override
  State<NearbyServiceProviders> createState() => _NearbyServiceProvidersState();
}

class _NearbyServiceProvidersState extends State<NearbyServiceProviders> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _nearbyProviders = [];
  String? _currentUserId;
  double? _userLat;
  double? _userLng;

  @override
  void initState() {
    super.initState();
    _fetchNearbyProviders();
  }

  Future<void> _fetchNearbyProviders() async {
    try {
      _currentUserId = await SessionManager.getUserId();
      if (_currentUserId == null) return;

      // 1. Get Current User Location (Fresh)
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      _userLat = position.latitude;
      _userLng = position.longitude;

      // 2. Fetch Providers
      final response = await SupabaseConfig.supabase
          .from('users')
          .select(
            'id, full_name, avatar_url, location, is_provider, services(id, name), service_type, price, average_rating, total_reviews, subscription_expiry, is_subscribed, latitude, longitude',
          )
          .eq('is_provider', true)
          .neq('id', _currentUserId!); // Exclude self if somehow provider

      final List<dynamic> providersData = response as List<dynamic>;
      List<Map<String, dynamic>> calculatedProviders = [];

      for (var p in providersData) {
        final pLat = (p['latitude'] as num?)?.toDouble();
        final pLng = (p['longitude'] as num?)?.toDouble();

        if (pLat != null && pLng != null) {
          final distanceInMeters = Geolocator.distanceBetween(
            _userLat!,
            _userLng!,
            pLat,
            pLng,
          );

          // Check subscription status
          bool isActive = false;
          if (p['is_subscribed'] == true && p['subscription_expiry'] != null) {
            try {
              final expiry = DateTime.parse(p['subscription_expiry']);
              isActive = expiry.isAfter(DateTime.now());
            } catch (_) {}
          }

          // Debug
          debugPrint(
            'Provider: ${p['full_name']}, Dist: $distanceInMeters, Active: $isActive',
          );

          // Add to list regardless of subscription
          final providerMap = Map<String, dynamic>.from(p);
          providerMap['distance_km'] = distanceInMeters / 1000;
          providerMap['is_fully_active'] = isActive;
          calculatedProviders.add(providerMap);
        }
      }

      // 3. Sort by Distance
      calculatedProviders.sort(
        (a, b) =>
            (a['distance_km'] as double).compareTo(b['distance_km'] as double),
      );

      // 4. Take top 10
      if (calculatedProviders.length > 7) {
        calculatedProviders = calculatedProviders.sublist(0, 7);
      }

      if (mounted) {
        setState(() {
          _nearbyProviders = calculatedProviders;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching nearby providers: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        showErrorDialog(
          context,
          e,
          title: 'Unable to Load Nearby Providers',
          onRetry: _fetchNearbyProviders,
        );
      }
    }
  }

  Future<void> _showBookDialog(Map<String, dynamic> provider) async {
    // Check active status
    if (provider['is_fully_active'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This provider is currently unavailable.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final locController = TextEditingController();
    final descController = TextEditingController();
    final priceController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    double? reqLat;
    double? reqLng;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('Book ${provider['full_name']}'),
        content: SizedBox(
          width: double.maxFinite,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${provider['distance_km'].toStringAsFixed(1)} km away',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: locController,
                    decoration: InputDecoration(
                      labelText: 'Service Location',
                      hintText: 'City, Area, or Address',
                      prefixIcon: const Icon(Icons.location_on),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.map, color: Colors.blue),
                        onPressed: () async {
                          final res = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MapPicker(),
                            ),
                          );
                          if (res != null && res is Map) {
                            locController.text = res['address'] as String;
                            reqLat = res['lat'] as double;
                            reqLng = res['lng'] as double;
                          }
                        },
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: descController,
                    decoration: const InputDecoration(
                      labelText: 'Task Description',
                      hintText: 'Describe the job...',
                      prefixIcon: Icon(Icons.description),
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: priceController,
                    decoration: const InputDecoration(
                      labelText: 'Offer Amount',
                      prefixText: '₹ ',
                      prefixIcon: Icon(Icons.currency_rupee),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) => v!.isEmpty ? 'Required' : null,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx);
                _submitBooking(
                  provider,
                  locController.text.trim(),
                  descController.text.trim(),
                  double.parse(priceController.text.trim()),
                  reqLat,
                  reqLng,
                );
              }
            },
            child: const Text('Send Request'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitBooking(
    Map<String, dynamic> provider,
    String location,
    String description,
    double price,
    double? lat,
    double? lng,
  ) async {
    try {
      // Extract Service ID
      String? serviceId;
      if (provider['services'] != null) {
        if (provider['services'] is Map) {
          serviceId = provider['services']['id'].toString();
        } else if (provider['services'] is List &&
            (provider['services'] as List).isNotEmpty) {
          serviceId = provider['services'][0]['id'].toString();
        }
      }

      await SupabaseConfig.supabase.from('orders').insert({
        'buyer_id': _currentUserId,
        'provider_id': provider['id'],
        'service_id': serviceId, // Can be null if generic
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

      // Notification
      await SupabaseConfig.supabase.from('notifications').insert({
        'user_id': provider['id'],
        'message': 'New Nearby Job Request! Offer: ₹$price',
        'is_read': false,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request Sent Successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Booking error: $e');
      if (mounted) {
        showErrorDialog(context, e, title: 'Booking Failed');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const SizedBox.shrink(); // Silent load
    // Show empty state if no providers
    if (_nearbyProviders.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 4.0,
                vertical: 8.0,
              ),
              child: Text(
                'Nearby Service Providers',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  'No providers found nearby.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
          child: Text(
            'Nearby Service Providers',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Using Column instead of ListView to avoid layout constraints issues
        Column(
          children: _nearbyProviders.asMap().entries.map((entry) {
            final i = entry.key;
            final p = entry.value;

            // Safe Service Name Extraction - Prioritize service_type (sub-service)
            String serviceName = 'Service Provider';
            if (p['service_type'] != null &&
                p['service_type'].toString().isNotEmpty) {
              // Use sub-service type if available
              serviceName = p['service_type'].toString();
            } else if (p['services'] != null) {
              // Fallback to main service name
              if (p['services'] is Map) {
                serviceName = p['services']['name'] ?? 'Service Provider';
              } else if (p['services'] is List &&
                  (p['services'] as List).isNotEmpty) {
                serviceName = p['services'][0]['name'] ?? 'Service Provider';
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: i < _nearbyProviders.length - 1 ? 12 : 0,
              ),
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProfilePage(userId: p['id']),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Profile Pic
                      SafeAvatar(
                        imageUrl: p['avatar_url'],
                        radius: 30,
                        userName: p['full_name'],
                      ),
                      const SizedBox(width: 12),
                      // Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p['full_name'] ?? 'Provider',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              serviceName,
                              style: const TextStyle(
                                color: Colors.blueAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.star, size: 14, color: Colors.amber),
                                const SizedBox(width: 4),
                                Text(
                                  '${(p['average_rating'] as num?)?.toDouble().toStringAsFixed(1) ?? "0.0"}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.location_on,
                                  size: 14,
                                  color: Colors.grey,
                                ),
                                Text(
                                  '${p['distance_km'].toStringAsFixed(1)} km',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Book Button
                      ElevatedButton(
                        onPressed: () => _showBookDialog(p),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.blue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        child: const Text('Book'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
