import 'package:flutter/material.dart';
import '../supabase_config.dart';
import '../auth/session_manager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../widgets/map_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';

class PlaceOrderPage extends StatefulWidget {
  const PlaceOrderPage({super.key});

  @override
  State<PlaceOrderPage> createState() => _PlaceOrderPageState();
}

class _PlaceOrderPageState extends State<PlaceOrderPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _priceController = TextEditingController(); // User Budget
  final _descriptionController = TextEditingController();

  String? _selectedService; // Business Type ID (e.g. Cleaning)
  String? _selectedServiceName; // Business Type Name for display
  String? _selectedServiceType; // Sub-service Name (e.g. Bathroom Cleaning)
  String? _selectedServiceTypeId; // Sub-service ID
  String? _selectedLocation;

  // Service location requirements
  bool _requireCurrentLocation = false;
  bool _requireDestinationLocation = false;

  List<Map<String, dynamic>> _allServiceTypes = [];
  List<Map<String, dynamic>> _services =
      []; // Parent services with location settings
  List<Map<String, dynamic>> _locations = [];

  // Filtered sub-services based on selected parent service

  bool _isLoading = false;

  // GPS Location State (Current Location)
  double? _latitude;
  double? _longitude;
  String? _gpsAddress;
  bool _isGettingLocation = false;

  // Destination Location State
  double? _destLatitude;
  double? _destLongitude;
  String? _destAddress;
  bool _isGettingDestLocation = false;

  // Image Upload State
  final List<XFile> _selectedImages = [];
  final ImagePicker _imagePicker = ImagePicker();

  RealtimeChannel? _serviceTypesSubscription;

  @override
  void initState() {
    super.initState();
    _fetchDropdownData();
    _subscribeToServiceTypes();
  }

  @override
  void dispose() {
    if (_serviceTypesSubscription != null) {
      SupabaseConfig.supabase.removeChannel(_serviceTypesSubscription!);
    }
    _phoneController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _subscribeToServiceTypes() {
    _serviceTypesSubscription = SupabaseConfig.supabase.channel(
      'public:service_types',
    );
    _serviceTypesSubscription!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'service_types',
          callback: (payload) {
            debugPrint('Realtime update received for service_types');
            _fetchDropdownData();
          },
        )
        .subscribe();
  }

  Future<void> _fetchDropdownData() async {
    try {
      // Fetch all service types with their parent service_id
      final st = await SupabaseConfig.supabase
          .from('service_types')
          .select('id, name, service_id');

      // Fetch parent services with location settings
      final services = await SupabaseConfig.supabase
          .from('services')
          .select(
            'id, name, require_current_location, require_destination_location',
          );

      final l = await SupabaseConfig.supabase
          .from('locations')
          .select('id, name');

      // Fetch User Phone
      final userId = await SessionManager.getUserId();
      if (userId != null) {
        final userData = await SupabaseConfig.supabase
            .from('users')
            .select('phone_number, location')
            .eq('id', userId)
            .maybeSingle();

        if (userData != null) {
          if (mounted) {
            if (userData['phone_number'] != null) {
              _phoneController.text = userData['phone_number'].toString();
            }
            if (userData['location'] != null) {
              final userLoc = userData['location']
                  .toString()
                  .trim()
                  .toLowerCase();
              try {
                final match = List<Map<String, dynamic>>.from(l).firstWhere(
                  (loc) =>
                      loc['name'].toString().trim().toLowerCase() == userLoc,
                );
                _selectedLocation = match['id'] as String;
              } catch (_) {}
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _allServiceTypes = List<Map<String, dynamic>>.from(st);
          _services = List<Map<String, dynamic>>.from(services);
          _locations = List<Map<String, dynamic>>.from(l);
        });
      }
    } catch (e) {
      debugPrint('Error fetching dropdowns: $e');
    }
  }

  Future<void> _pickLocationOnMap() async {
    final result = await MapPicker.checkLocationAndOpen(context);

    if (result != null) {
      setState(() {
        _latitude = result['lat'];
        _longitude = result['lng'];
        _gpsAddress = result['address'];
      });
    }
  }

  Future<void> _pickDestinationOnMap() async {
    final result = await MapPicker.checkLocationAndOpen(context);

    if (result != null) {
      setState(() {
        _destLatitude = result['lat'];
        _destLongitude = result['lng'];
        _destAddress = result['address'];
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
          throw 'Location permissions are denied. Please enable them to tag your location.';
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Location Permission Needed'),
              content: const Text(
                'We need location access to tag your address for the provider. Please enable it in settings.',
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
        return; // Exit function, don't throw to avoid double snackbar
      }

      // Try to get last known position first (faster)
      Position? lastKnown = await Geolocator.getLastKnownPosition();

      // Get current position with extended timeout
      Position position;
      try {
        position =
            await Geolocator.getCurrentPosition(
              locationSettings: AndroidSettings(
                accuracy: LocationAccuracy.high,
                distanceFilter: 0,
                forceLocationManager: false,
                intervalDuration: const Duration(seconds: 5),
                timeLimit: const Duration(seconds: 30), // Extended timeout
              ),
            ).timeout(
              const Duration(seconds: 35),
              onTimeout: () {
                // If timeout occurs, use last known position if available
                if (lastKnown != null) {
                  return lastKnown;
                }
                throw 'Location request timed out. Please try again or use "Pick on Map".';
              },
            );
      } catch (e) {
        // Fallback to last known position if current position fails
        if (lastKnown != null) {
          position = lastKnown;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Using last known location'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        } else {
          rethrow;
        }
      }

      // Get Address
      String address = 'Location captured';
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        ).timeout(const Duration(seconds: 10));

        if (placemarks.isNotEmpty) {
          Placemark place = placemarks[0];
          address =
              '${place.street}, ${place.subLocality}, ${place.locality}, ${place.postalCode}';
        }
      } catch (e) {
        debugPrint('Geocoding failed, using coordinates: $e');
        address =
            'Lat: ${position.latitude.toStringAsFixed(4)}, Lng: ${position.longitude.toStringAsFixed(4)}';
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
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Use Map',
              textColor: Colors.white,
              onPressed: _pickLocationOnMap,
            ),
          ),
        );
      }
      setState(() => _isGettingLocation = false);
    }
  }

  Future<void> _getDestinationLocation() async {
    setState(() => _isGettingDestLocation = true);

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
                'We need location access to tag destination. Please enable it in settings.',
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
        setState(() => _isGettingDestLocation = false);
        return;
      }

      // Try to get last known position first (faster)
      Position? lastKnown = await Geolocator.getLastKnownPosition();

      // Get current position with extended timeout
      Position position;
      try {
        position =
            await Geolocator.getCurrentPosition(
              locationSettings: AndroidSettings(
                accuracy: LocationAccuracy.high,
                distanceFilter: 0,
                forceLocationManager: false,
                intervalDuration: const Duration(seconds: 5),
                timeLimit: const Duration(seconds: 30),
              ),
            ).timeout(
              const Duration(seconds: 35),
              onTimeout: () {
                if (lastKnown != null) {
                  return lastKnown;
                }
                throw 'Location request timed out. Please use "Pick on Map".';
              },
            );
      } catch (e) {
        if (lastKnown != null) {
          position = lastKnown;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Using last known location'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        } else {
          rethrow;
        }
      }

      // Get Address
      String address = 'Destination captured';
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        ).timeout(const Duration(seconds: 10));

        if (placemarks.isNotEmpty) {
          Placemark place = placemarks[0];
          address =
              '${place.street}, ${place.subLocality}, ${place.locality}, ${place.postalCode}';
        }
      } catch (e) {
        debugPrint('Geocoding failed: $e');
        address =
            'Lat: ${position.latitude.toStringAsFixed(4)}, Lng: ${position.longitude.toStringAsFixed(4)}';
      }

      setState(() {
        _destLatitude = position.latitude;
        _destLongitude = position.longitude;
        _destAddress = address;
        _isGettingDestLocation = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Destination captured successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error getting destination location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Use Map',
              textColor: Colors.white,
              onPressed: _pickDestinationOnMap,
            ),
          ),
        );
      }
      setState(() => _isGettingDestLocation = false);
    }
  }

  Future<void> _pickImages() async {
    if (_selectedImages.length >= 4) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Maximum 4 images allowed')));
      return;
    }

    try {
      final List<XFile> images = await _imagePicker.pickMultiImage(
        imageQuality: 70,
      );

      if (!mounted) return;

      if (images.isNotEmpty) {
        final remaining = 4 - _selectedImages.length;
        final imagesToAdd = images.take(remaining).toList();

        setState(() {
          _selectedImages.addAll(imagesToAdd);
        });

        if (images.length > remaining) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Only $remaining more images can be added (max 4 total)',
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error picking images: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error selecting images: $e')));
      }
    }
  }

  Future<void> _pickImageFromCamera() async {
    if (_selectedImages.length >= 4) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Maximum 4 images allowed')));
      return;
    }

    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
      );

      if (!mounted) return;

      if (photo != null) {
        setState(() {
          _selectedImages.add(photo);
        });
      }
    } catch (e) {
      debugPrint('Error taking photo: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error taking photo: $e')));
      }
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  Future<File> _compressImage(File file) async {
    try {
      final String targetPath = '${file.absolute.path}_compressed.jpg';
      final result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        quality: 70,
        minWidth: 1920,
        minHeight: 1080,
      );
      if (result != null) return File(result.path);
    } catch (e) {
      debugPrint('Compression error: $e');
    }
    return file;
  }

  Future<List<String>> _uploadImages(String orderId, String userId) async {
    final List<Future<String>> uploadFutures = [];

    try {
      for (int i = 0; i < _selectedImages.length; i++) {
        final image = _selectedImages[i];
        final fileName =
            '${userId}_${orderId}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        final filePath = '$userId/$orderId/$fileName';

        // Queue compress + upload
        uploadFutures.add(() async {
          final originalFile = File(image.path);
          final fileToUpload = await _compressImage(originalFile);

          await SupabaseConfig.supabase.storage
              .from('order_images')
              .upload(filePath, fileToUpload);

          return SupabaseConfig.supabase.storage
              .from('order_images')
              .getPublicUrl(filePath);
        }());
      }

      // Execute in parallel
      return await Future.wait(uploadFutures);
    } catch (e) {
      debugPrint('Error uploading images: $e');
      throw 'Failed to upload images: $e';
    }
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedServiceType == null || _selectedService == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a Service Type')),
      );
      return;
    }

    // Validate current location if required
    if (_requireCurrentLocation && (_latitude == null || _longitude == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide your current location'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Validate destination location if required
    if (_requireDestinationLocation &&
        (_destLatitude == null || _destLongitude == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide the destination location'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Validate minimum 1 image
    if (_selectedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least 1 image of the issue'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userId = await SessionManager.getUserId();
      if (userId == null) throw "User not logged in";

      // Insert Order Request
      String description = _descriptionController.text.trim();
      final fullDescription =
          'Service Type: $_selectedServiceType\n$description';

      final response = await SupabaseConfig.supabase
          .from('orders')
          .insert({
            'buyer_id': userId,
            // 'provider_id': null, // Removed: Database column is nullable now, so we can omit it or send null.
            'service_id': _selectedService,
            'sub_service_type': _selectedServiceType,
            'location_id': _selectedLocation,
            'user_phone': _phoneController.text.trim(),
            'user_price': double.tryParse(_priceController.text.trim()),
            'description': fullDescription,
            'status': 'request_open',
            'latitude': _latitude,
            'longitude': _longitude,
            'address_gps': _gpsAddress,
            'destination_latitude': _destLatitude,
            'destination_longitude': _destLongitude,
            'destination_address': _destAddress,
          })
          .select()
          .single();

      final orderId = response['id'].toString();

      try {
        // Upload images
        final imageUrls = await _uploadImages(orderId, userId);

        // Update order with image URLs
        await SupabaseConfig.supabase
            .from('orders')
            .update({'images': imageUrls})
            .eq('id', orderId);
      } catch (e) {
        // ROLLBACK: Delete the incomplete order
        debugPrint("Image upload failed, rolling back order $orderId");
        await SupabaseConfig.supabase.from('orders').delete().eq('id', orderId);
        rethrow;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request Posted! Matching providers notified.'),
          ),
        );
        Navigator.pop(context);
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        String msg = 'Error: ${e.message}';
        if (e.code == '23514' || e.message.contains('check constraint')) {
          msg = 'Database Constraint Error: ${e.message}';
        } else if (e.code == '42703') {
          msg =
              'Database Update Required: Missing columns (latitude/longitude). Please run the update script.';
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
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
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.deepPurple.shade400, Colors.purple.shade600],
            ),
          ),
        ),
        title: const Text(
          'Request Service',
          style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Card
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.deepPurple.shade400,
                      Colors.purple.shade600,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.deepPurple.withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.handyman_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Book a Service',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Fill in the details below to get help from our experts',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              // 1. Service Selection Card - Expandable Accordion Style
              _buildSectionCard(
                icon: Icons.category_rounded,
                title: 'Select Service',
                iconColor: Colors.blue,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Show selected service summary if already selected
                    if (_selectedServiceType != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.green.shade50, Colors.teal.shade50],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.shade300),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.green.shade600,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Selected',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$_selectedServiceName > $_selectedServiceType',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedService = null;
                                  _selectedServiceName = null;
                                  _selectedServiceType = null;
                                  _selectedServiceTypeId = null;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.close_rounded,
                                  color: Colors.red.shade600,
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Service Types - Expandable Cards
                    ..._services.map((service) {
                      final isExpanded = _selectedService == service['id'];
                      final subServices = _allServiceTypes
                          .where((st) => st['service_id'] == service['id'])
                          .toList();

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isExpanded
                                ? Colors.blue.shade400
                                : Colors.grey.shade200,
                            width: isExpanded ? 2 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isExpanded
                                  ? Colors.blue.withOpacity(0.15)
                                  : Colors.grey.withOpacity(0.08),
                              blurRadius: isExpanded ? 12 : 6,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Service Type Header (Tap to expand)
                            InkWell(
                              onTap: () {
                                setState(() {
                                  if (_selectedService == service['id']) {
                                    // Collapse if already expanded
                                    _selectedService = null;
                                    _selectedServiceName = null;
                                  } else {
                                    // Expand this one
                                    _selectedService = service['id'];
                                    _selectedServiceName = service['name'];

                                    _requireCurrentLocation =
                                        service['require_current_location'] ??
                                        false;
                                    _requireDestinationLocation =
                                        service['require_destination_location'] ??
                                        false;
                                  }
                                  // Reset sub-service selection when changing category
                                  _selectedServiceType = null;
                                  _selectedServiceTypeId = null;
                                });
                              },
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        gradient: isExpanded
                                            ? LinearGradient(
                                                colors: [
                                                  Colors.blue.shade500,
                                                  Colors.indigo.shade600,
                                                ],
                                              )
                                            : null,
                                        color: isExpanded
                                            ? null
                                            : Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(
                                        _getServiceIcon(service['name'] ?? ''),
                                        color: isExpanded
                                            ? Colors.white
                                            : Colors.blue.shade600,
                                        size: 26,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            service['name'] ?? 'Service',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: isExpanded
                                                  ? Colors.blue.shade700
                                                  : Colors.grey.shade800,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${subServices.length} services available',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    AnimatedRotation(
                                      turns: isExpanded ? 0.5 : 0,
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: isExpanded
                                              ? Colors.blue.shade50
                                              : Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.keyboard_arrow_down_rounded,
                                          color: isExpanded
                                              ? Colors.blue.shade600
                                              : Colors.grey.shade500,
                                          size: 24,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // Sub-Services List (Expanded Content)
                            AnimatedCrossFade(
                              firstChild: const SizedBox.shrink(),
                              secondChild: Container(
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: const BorderRadius.only(
                                    bottomLeft: Radius.circular(14),
                                    bottomRight: Radius.circular(14),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Divider(
                                      height: 1,
                                      color: Colors.grey.shade200,
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              left: 4,
                                              bottom: 10,
                                            ),
                                            child: Text(
                                              'Tap to select:',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ),
                                          ...subServices.map((subService) {
                                            final isSubSelected =
                                                _selectedServiceTypeId ==
                                                subService['id'];
                                            return GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  _selectedServiceTypeId =
                                                      subService['id'];
                                                  _selectedServiceType =
                                                      subService['name'];
                                                  // Collapse after selection
                                                  // _selectedService = null;
                                                });
                                              },
                                              child: Container(
                                                margin: const EdgeInsets.only(
                                                  bottom: 8,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 14,
                                                      vertical: 14,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: isSubSelected
                                                      ? Colors.green.shade50
                                                      : Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color: isSubSelected
                                                        ? Colors.green.shade400
                                                        : Colors.grey.shade200,
                                                    width: isSubSelected
                                                        ? 2
                                                        : 1,
                                                  ),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            8,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: isSubSelected
                                                            ? Colors
                                                                  .green
                                                                  .shade100
                                                            : Colors
                                                                  .purple
                                                                  .shade50,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              10,
                                                            ),
                                                      ),
                                                      child: Icon(
                                                        isSubSelected
                                                            ? Icons
                                                                  .check_circle_rounded
                                                            : Icons
                                                                  .build_circle_rounded,
                                                        color: isSubSelected
                                                            ? Colors
                                                                  .green
                                                                  .shade600
                                                            : Colors
                                                                  .purple
                                                                  .shade400,
                                                        size: 20,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: Text(
                                                        subService['name'] ??
                                                            'Unknown',
                                                        style: TextStyle(
                                                          fontSize: 15,
                                                          fontWeight:
                                                              isSubSelected
                                                              ? FontWeight.bold
                                                              : FontWeight.w500,
                                                          color: isSubSelected
                                                              ? Colors
                                                                    .green
                                                                    .shade700
                                                              : Colors
                                                                    .grey
                                                                    .shade800,
                                                        ),
                                                      ),
                                                    ),
                                                    if (isSubSelected)
                                                      Icon(
                                                        Icons.check_rounded,
                                                        color: Colors
                                                            .green
                                                            .shade600,
                                                        size: 22,
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              crossFadeState: isExpanded
                                  ? CrossFadeState.showSecond
                                  : CrossFadeState.showFirst,
                              duration: const Duration(milliseconds: 250),
                            ),
                          ],
                        ),
                      );
                    }).toList(),

                    // Validation message if nothing selected
                    if (_selectedServiceType == null)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: Colors.orange.shade700,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Tap on a service type, then select a specific service',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange.shade800,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              // 2. Location Card
              _buildSectionCard(
                icon: Icons.location_on_rounded,
                title: 'Location',
                iconColor: Colors.orange,
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: DropdownButtonFormField<String>(
                        value: _selectedLocation,
                        items: _locations.map((l) {
                          return DropdownMenuItem(
                            value: l['id'].toString(),
                            child: Text(l['name']),
                          );
                        }).toList(),
                        onChanged: (v) => setState(() => _selectedLocation = v),
                        decoration: InputDecoration(
                          labelText: 'City / Region',
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          prefixIcon: Container(
                            margin: const EdgeInsets.all(10),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.location_city_rounded,
                              color: Colors.orange.shade600,
                              size: 20,
                            ),
                          ),
                        ),
                        validator: (v) => v == null ? 'Required' : null,
                      ),
                    ),

                    // Current Location Section (conditional)
                    if (_requireCurrentLocation) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.blue.shade50,
                              Colors.indigo.shade50,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.blue.shade200,
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
                                    color: Colors.blue.shade600,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.my_location,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Pickup Location',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue.shade800,
                                          fontSize: 15,
                                        ),
                                      ),
                                      Text(
                                        'Required for this service',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.blue.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_gpsAddress != null)
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade500,
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
                                  child: _buildLocationButton(
                                    icon: Icons.gps_fixed_rounded,
                                    label: _isGettingLocation
                                        ? 'Locating...'
                                        : 'Use GPS',
                                    isLoading: _isGettingLocation,
                                    onTap: _isGettingLocation
                                        ? null
                                        : _getCurrentLocation,
                                    color: Colors.blue,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _buildLocationButton(
                                    icon: Icons.map_rounded,
                                    label: 'Pick on Map',
                                    onTap: _pickLocationOnMap,
                                    color: Colors.indigo,
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
                                      'Please provide your pickup location',
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
                    ],

                    // Destination Location Section (conditional)
                    if (_requireDestinationLocation) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.green.shade50, Colors.teal.shade50],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.green.shade200,
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
                                    color: Colors.green.shade600,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.flag_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Destination Location',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green.shade800,
                                          fontSize: 15,
                                        ),
                                      ),
                                      Text(
                                        'Where should we deliver/drop?',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.green.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_destAddress != null)
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade500,
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
                                  child: _buildLocationButton(
                                    icon: Icons.gps_fixed_rounded,
                                    label: _isGettingDestLocation
                                        ? 'Locating...'
                                        : 'Use GPS',
                                    isLoading: _isGettingDestLocation,
                                    onTap: _isGettingDestLocation
                                        ? null
                                        : _getDestinationLocation,
                                    color: Colors.green,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _buildLocationButton(
                                    icon: Icons.map_rounded,
                                    label: 'Pick on Map',
                                    onTap: _pickDestinationOnMap,
                                    color: Colors.teal,
                                  ),
                                ),
                              ],
                            ),
                            if (_destAddress != null)
                              Container(
                                margin: const EdgeInsets.only(top: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.green.shade300,
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
                                        _destAddress!,
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
                                      'Please provide the destination location',
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
                    ],
                  ],
                ),
              ),

              // 3. Details Card
              _buildSectionCard(
                icon: Icons.edit_note_rounded,
                title: 'Details',
                iconColor: Colors.purple,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildModernTextField(
                            controller: _priceController,
                            label: 'Budget',
                            hint: 'Min ₹50',
                            icon: Icons.currency_rupee_rounded,
                            iconColor: Colors.green,
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Required';
                              final val = double.tryParse(v);
                              if (val == null) return 'Invalid';
                              if (val < 50) return 'Min ₹50';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildModernTextField(
                            controller: _phoneController,
                            label: 'Phone',
                            hint: 'Your number',
                            icon: Icons.phone_rounded,
                            iconColor: Colors.blue,
                            keyboardType: TextInputType.phone,
                            validator: (v) => v!.isEmpty ? 'Required' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildModernTextField(
                      controller: _descriptionController,
                      label: 'Issue Description',
                      hint: 'Describe your problem...',
                      icon: Icons.description_rounded,
                      iconColor: Colors.orange,
                      maxLines: 4,
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                    ),
                  ],
                ),
              ),

              // 4. Photos Card
              _buildSectionCard(
                icon: Icons.photo_library_rounded,
                title: 'Photos',
                iconColor: Colors.pink,
                trailing: _selectedImages.isNotEmpty
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Text(
                          '${_selectedImages.length}/4',
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      )
                    : null,
                child: Column(
                  children: [
                    Container(
                      height: 100,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: _selectedImages.length + 1,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          if (index == _selectedImages.length) {
                            // Add Photo Button
                            return GestureDetector(
                              onTap: () => _showImagePickerModal(),
                              child: Container(
                                width: 100,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Colors.grey.shade100,
                                      Colors.grey.shade200,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                    width: 2,
                                    style: BorderStyle.solid,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.pink.shade50,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.add_a_photo_rounded,
                                        color: Colors.pink.shade400,
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Add Photo',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          // Image Thumbnail
                          return Stack(
                            children: [
                              Container(
                                width: 100,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image.file(
                                    File(_selectedImages[index].path),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 4,
                                top: 4,
                                child: GestureDetector(
                                  onTap: () => _removeImage(index),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade500,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.close_rounded,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    if (_selectedImages.isEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 18,
                              color: Colors.orange.shade700,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Add at least 1 photo of the issue to help providers understand better',
                                style: TextStyle(
                                  color: Colors.orange.shade800,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              // Submit Button
              Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _isLoading
                          ? [Colors.grey.shade400, Colors.grey.shade500]
                          : [
                              Colors.deepPurple.shade400,
                              Colors.purple.shade600,
                            ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: _isLoading
                        ? []
                        : [
                            BoxShadow(
                              color: Colors.deepPurple.withOpacity(0.4),
                              blurRadius: 15,
                              offset: const Offset(0, 8),
                            ),
                          ],
                  ),
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submitRequest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isLoading
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Processing...',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                              SizedBox(width: 10),
                              Text(
                                'SUBMIT REQUEST',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showImagePickerModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Add Photo',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildPhotoOptionButton(
                    icon: Icons.camera_alt_rounded,
                    label: 'Camera',
                    color: Colors.blue,
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickImageFromCamera();
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildPhotoOptionButton(
                    icon: Icons.photo_library_rounded,
                    label: 'Gallery',
                    color: Colors.purple,
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickImages();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoOptionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    required Color iconColor,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required Color iconColor,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: maxLines > 1 ? 14 : 0,
          ),
          prefixIcon: Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
        ),
      ),
    );
  }

  Widget _buildLocationButton({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
    bool isLoading = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else
              Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to get appropriate icon for service category
  IconData _getServiceIcon(String serviceName) {
    final name = serviceName.toLowerCase();
    if (name.contains('clean')) return Icons.cleaning_services_rounded;
    if (name.contains('electric')) return Icons.electrical_services_rounded;
    if (name.contains('plumb')) return Icons.plumbing_rounded;
    if (name.contains('paint')) return Icons.format_paint_rounded;
    if (name.contains('cook') || name.contains('food'))
      return Icons.restaurant_rounded;
    if (name.contains('transport') || name.contains('delivery'))
      return Icons.local_shipping_rounded;
    if (name.contains('repair')) return Icons.build_rounded;
    if (name.contains('garden') || name.contains('lawn'))
      return Icons.grass_rounded;
    if (name.contains('ac') || name.contains('air'))
      return Icons.ac_unit_rounded;
    if (name.contains('car') || name.contains('auto'))
      return Icons.directions_car_rounded;
    if (name.contains('beauty') || name.contains('salon'))
      return Icons.face_rounded;
    if (name.contains('laundry') || name.contains('cloth'))
      return Icons.local_laundry_service_rounded;
    if (name.contains('pest')) return Icons.bug_report_rounded;
    if (name.contains('security')) return Icons.security_rounded;
    if (name.contains('photo') || name.contains('video'))
      return Icons.camera_alt_rounded;
    if (name.contains('fitness') || name.contains('gym'))
      return Icons.fitness_center_rounded;
    if (name.contains('tutor') || name.contains('teach'))
      return Icons.school_rounded;
    if (name.contains('pet')) return Icons.pets_rounded;
    if (name.contains('shift') || name.contains('moving'))
      return Icons.move_to_inbox_rounded;
    if (name.contains('carpenter') || name.contains('wood'))
      return Icons.carpenter_rounded;
    return Icons.handyman_rounded; // Default icon
  }
}
