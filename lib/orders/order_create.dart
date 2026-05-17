import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_config.dart';
import '../auth/session_manager.dart';
import 'user_orders.dart';
import '../widgets/map_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class OrderCreatePage extends StatefulWidget {
  final String providerId;
  final String providerName;

  const OrderCreatePage({
    super.key,
    required this.providerId,
    required this.providerName,
  });

  @override
  State<OrderCreatePage> createState() => _OrderCreatePageState();
}

class _OrderCreatePageState extends State<OrderCreatePage> {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();
  final _priceController = TextEditingController();

  // Dropdown Data
  List<Map<String, dynamic>> _services = [];
  List<Map<String, dynamic>> _locations = [];

  // Selections
  String? _selectedServiceId;
  String? _selectedLocationId;
  XFile? _selectedImage;

  // GPS Location State
  double? _latitude;
  double? _longitude;
  String? _gpsAddress;
  bool _isGettingLocation = false;

  bool _isLoading = false;
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _fetchDropdownData();
  }

  Future<void> _fetchDropdownData() async {
    try {
      final servicesFuture = SupabaseConfig.supabase.from('services').select();
      final locationsFuture = SupabaseConfig.supabase
          .from('locations')
          .select();

      final results = await Future.wait([servicesFuture, locationsFuture]);

      setState(() {
        _services = List<Map<String, dynamic>>.from(results[0]);
        _locations = List<Map<String, dynamic>>.from(results[1]);
        _isInitializing = false;
      });
    } catch (e) {
      debugPrint('Error fetching data: $e');
      setState(() => _isInitializing = false);
    }
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
    ); // Can be camera too
    if (image != null) {
      setState(() {
        _selectedImage = image;
      });
    }
  }

  Future<void> _pickLocationOnMap() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const MapPicker()),
    );

    if (result != null && result is Map) {
      setState(() {
        _latitude = result['lat'];
        _longitude = result['lng'];
        _gpsAddress = result['address'];
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isGettingLocation = true);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw 'Location services are disabled. Please enable GPS.';
      }

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw 'Location permissions are denied.';
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Location Permission Needed'),
              content: const Text(
                'We need location access. Please enable it in settings.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Geolocator.openAppSettings();
                  },
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          );
        }
        setState(() => _isGettingLocation = false);
        return;
      }

      Position position =
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
            ),
          ).timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw 'Location request timed out. Please try again.';
            },
          );

      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      ).timeout(const Duration(seconds: 10), onTimeout: () => []);

      String address = '';
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        address =
            '${place.street}, ${place.subLocality}, ${place.locality}, ${place.postalCode}';
      }

      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _gpsAddress = address;
        _isGettingLocation = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location captured successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
      setState(() => _isGettingLocation = false);
    }
  }

  Future<void> _submitOrder() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedServiceId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a service')));
      return;
    }

    // Validate location is provided
    if (_latitude == null || _longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide your location using GPS or map'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final buyerId = await SessionManager.getUserId();
      if (buyerId == null) throw Exception('User not logged in');

      // 1. Insert Order
      final orderRes = await SupabaseConfig.supabase
          .from('orders')
          .insert({
            'buyer_id': buyerId,
            'provider_id': widget.providerId,
            'service_id': _selectedServiceId,
            'location_id': _selectedLocationId,
            'user_price': double.tryParse(_priceController.text.trim()) ?? 0,
            'message': _messageController.text,
            'image_path': _selectedImage?.path, // Local path for now
            'status': 'pending',
            'latitude': _latitude,
            'longitude': _longitude,
            'address_gps': _gpsAddress,
          })
          .select()
          .single();

      final orderId = orderRes['id'];

      // Notification is automatically handled by database trigger
      // See: supabase/migrations/20241225221002_fix_provider_matching.sql
      // The 'on_new_order_notify' trigger sends notifications to matching providers
      // with proper subscription status and expiry validation.
      debugPrint(
        '✅ Order $orderId created. Database trigger will handle notifications.',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order placed successfully!')),
        );
        // Navigate to User Orders Page
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const UserOrdersPage()),
        );
      }
    } on PostgrestException catch (e) {
      debugPrint('Error placing order: $e');
      if (mounted) {
        String msg = 'Error: ${e.message}';
        if (e.code == '23514') {
          msg = 'Database Constraint Error. Ensure your DB schema is updated.';
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      debugPrint('Error placing order: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Hire ${widget.providerName}')),
      body: _isInitializing
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Service Dropdown
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Select Service',
                        border: OutlineInputBorder(),
                      ),
                      value: _selectedServiceId,
                      items: _services.map((s) {
                        return DropdownMenuItem<String>(
                          value: s['id'],
                          child: Text(s['name']),
                        );
                      }).toList(),
                      onChanged: (val) =>
                          setState(() => _selectedServiceId = val),
                    ),
                    const SizedBox(height: 16),

                    // Location Section with Map Picker
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.orange.shade50,
                            Colors.deepOrange.shade50,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.orange.shade200,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade600,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.location_on,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Your Location',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange.shade800,
                                        fontSize: 15,
                                      ),
                                    ),
                                    Text(
                                      'Required for service delivery',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.orange.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_gpsAddress != null)
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _isGettingLocation
                                      ? null
                                      : _getCurrentLocation,
                                  icon: _isGettingLocation
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.gps_fixed_rounded,
                                          size: 18,
                                        ),
                                  label: Text(
                                    _isGettingLocation
                                        ? 'Locating...'
                                        : 'Use GPS',
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _pickLocationOnMap,
                                  icon: const Icon(Icons.map_rounded, size: 18),
                                  label: const Text('Pick on Map'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.indigo,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_gpsAddress != null)
                            Container(
                              margin: const EdgeInsets.only(top: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.green.shade200,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    color: Colors.green.shade600,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _gpsAddress!,
                                      style: TextStyle(
                                        color: Colors.green.shade800,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    size: 16,
                                    color: Colors.orange.shade700,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Please provide your location',
                                    style: TextStyle(
                                      color: Colors.orange.shade700,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Location Dropdown (City/Region)
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'City / Region',
                        border: OutlineInputBorder(),
                        helperText: 'Select your city or region',
                      ),
                      value: _selectedLocationId,
                      items: _locations.map((l) {
                        return DropdownMenuItem<String>(
                          value: l['id'],
                          child: Text(l['name']),
                        );
                      }).toList(),
                      onChanged: (val) =>
                          setState(() => _selectedLocationId = val),
                    ),
                    const SizedBox(height: 16),

                    // Price
                    TextFormField(
                      controller: _priceController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Budget (₹)',
                        helperText: 'Min ₹50',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.currency_rupee),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        final val = double.tryParse(v);
                        if (val == null) return 'Invalid amount';
                        if (val < 50) return 'Min ₹50 required';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Message
                    TextFormField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        labelText: 'Message / Requirements',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      maxLines: 4,
                      validator: (val) => val == null || val.isEmpty
                          ? 'Please enter a message'
                          : null,
                    ),
                    const SizedBox(height: 16),

                    // Image Picker
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _pickImage,
                            icon: const Icon(Icons.image),
                            label: const Text('Add Image (Optional)'),
                          ),
                        ),
                      ],
                    ),
                    if (_selectedImage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Image.file(
                          File(_selectedImage!.path),
                          height: 150,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),

                    const SizedBox(height: 24),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submitOrder,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : const Text('Place Order'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
