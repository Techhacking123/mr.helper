import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../supabase_config.dart';
import '../auth/session_manager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../widgets/map_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Modern Booking Page with enhanced UI/UX following design principles:
/// - Modern, accessible color palette (slate + indigo accent)
/// - Consistent 8px spacing scale
/// - Clear state feedback and animations
/// - Accessible focus states and ARIA-friendly semantics

class BookingPage extends StatefulWidget {
  const BookingPage({super.key});

  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage>
    with SingleTickerProviderStateMixin {
  // Form & Controllers
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _priceController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _scrollController = ScrollController();

  // Animation Controller
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Selections
  String? _selectedService;
  String? _selectedServiceType;
  String? _selectedLocation;

  // Service location requirements
  bool _requireCurrentLocation = false;
  bool _requireDestinationLocation = false;

  // Data lists
  List<Map<String, dynamic>> _allServiceTypes = [];
  List<Map<String, dynamic>> _services = [];
  List<Map<String, dynamic>> _locations = [];
  bool _isLoading = false;
  bool _isInitializing = true;

  // Current Location State
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

  // Realtime subscription
  RealtimeChannel? _serviceTypesSubscription;

  // Design System Colors - Darker palette
  static const _primaryColor = Color(0xFF3730A3); // Indigo 800
  static const _primaryLight = Color(0xFF4F46E5); // Indigo 600
  static const _successColor = Color(0xFF047857); // Emerald 700
  static const _warningColor = Color(0xFFD97706); // Amber 600
  static const _errorColor = Color(0xFFDC2626); // Red 600
  static const _surfaceColor = Color(0xFFE2E8F0); // Slate 200
  static const _cardColor = Colors.white;
  static const _textPrimary = Color(0xFF0F172A); // Slate 900
  static const _textSecondary = Color(0xFF475569); // Slate 600
  static const _borderColor = Color(0xFFCBD5E1); // Slate 300

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _fetchDropdownData();
    _subscribeToServiceTypes();
  }

  void _initAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scrollController.dispose();
    _phoneController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    if (_serviceTypesSubscription != null) {
      SupabaseConfig.supabase.removeChannel(_serviceTypesSubscription!);
    }
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
      final st = await SupabaseConfig.supabase
          .from('service_types')
          .select('id, name, service_id');

      // Fetch services WITH image_url
      final services = await SupabaseConfig.supabase
          .from('services')
          .select(
            'id, name, image_url, require_current_location, require_destination_location',
          );

      final l = await SupabaseConfig.supabase
          .from('locations')
          .select('id, name');

      final userId = await SessionManager.getUserId();
      if (userId != null) {
        final userData = await SupabaseConfig.supabase
            .from('users')
            .select('phone_number, location')
            .eq('id', userId)
            .maybeSingle();

        if (userData != null && mounted) {
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
                (loc) => loc['name'].toString().trim().toLowerCase() == userLoc,
              );
              _selectedLocation = match['id'] as String;
            } catch (_) {}
          }
        }
      }

      if (mounted) {
        setState(() {
          _allServiceTypes = List<Map<String, dynamic>>.from(st);
          _services = List<Map<String, dynamic>>.from(services);
          _locations = List<Map<String, dynamic>>.from(l);
          _isInitializing = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching dropdowns: $e');
      if (mounted) {
        setState(() => _isInitializing = false);
      }
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
          throw 'Location permissions are denied.';
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          _showLocationPermissionDialog();
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

      _showSuccessSnackbar('Location detected successfully');
    } catch (e) {
      debugPrint('Error getting location: $e');
      if (mounted) {
        _showErrorSnackbar('Could not get location: $e');
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
          _showLocationPermissionDialog();
        }
        setState(() => _isGettingDestLocation = false);
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
        _destLatitude = position.latitude;
        _destLongitude = position.longitude;
        _destAddress = address;
        _isGettingDestLocation = false;
      });

      _showSuccessSnackbar('Destination location set');
    } catch (e) {
      debugPrint('Error getting destination location: $e');
      if (mounted) {
        _showErrorSnackbar('Could not get location: $e');
      }
      setState(() => _isGettingDestLocation = false);
    }
  }

  void _showLocationPermissionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _warningColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.location_off, color: _warningColor),
            ),
            const SizedBox(width: 12),
            const Text('Location Permission'),
          ],
        ),
        content: const Text(
          'Location access is required for this feature. Please enable it in your device settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: _textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Geolocator.openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImages() async {
    if (_selectedImages.length >= 4) {
      _showWarningSnackbar('Maximum 4 images allowed');
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
          _showWarningSnackbar(
            'Only $remaining more images added (max 4 total)',
          );
        } else {
          _showSuccessSnackbar('${imagesToAdd.length} image(s) added');
        }
      }
    } catch (e) {
      debugPrint('Error picking images: $e');
      if (mounted) {
        _showErrorSnackbar('Error selecting images');
      }
    }
  }

  Future<void> _pickImageFromCamera() async {
    if (_selectedImages.length >= 4) {
      _showWarningSnackbar('Maximum 4 images allowed');
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
        _showSuccessSnackbar('Photo added');
      }
    } catch (e) {
      debugPrint('Error taking photo: $e');
      if (mounted) {
        _showErrorSnackbar('Error taking photo');
      }
    }
  }

  void _removeImage(int index) {
    HapticFeedback.lightImpact();
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

      return await Future.wait(uploadFutures);
    } catch (e) {
      debugPrint('Error uploading images: $e');
      throw 'Failed to upload images: $e';
    }
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) {
      _showErrorSnackbar('Please fill in all required fields');
      return;
    }

    if (_selectedServiceType == null || _selectedService == null) {
      _showErrorSnackbar('Please select a Service Type');
      return;
    }

    if (_requireCurrentLocation && (_latitude == null || _longitude == null)) {
      _showWarningSnackbar('Please provide your current location');
      return;
    }

    if (_requireDestinationLocation &&
        (_destLatitude == null || _destLongitude == null)) {
      _showWarningSnackbar('Please provide the destination location');
      return;
    }

    if (_selectedImages.isEmpty) {
      _showWarningSnackbar('Please add at least 1 image of the issue');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userId = await SessionManager.getUserId();
      if (userId == null) throw "User not logged in";

      String description = _descriptionController.text.trim();
      final fullDescription =
          'Service Type: $_selectedServiceType\n$description';

      final response = await SupabaseConfig.supabase
          .from('orders')
          .insert({
            'buyer_id': userId,
            'service_id': _selectedService,
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
        final imageUrls = await _uploadImages(orderId, userId);
        await SupabaseConfig.supabase
            .from('orders')
            .update({'images': imageUrls})
            .eq('id', orderId);
      } catch (e) {
        debugPrint("Image upload failed, rolling back order $orderId");
        await SupabaseConfig.supabase.from('orders').delete().eq('id', orderId);
        rethrow;
      }

      if (mounted) {
        _showSuccessDialog();
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        String msg = 'Error: ${e.message}';
        if (e.code == '23514' || e.message.contains('check constraint')) {
          msg = 'Database Constraint Error: ${e.message}';
        } else if (e.code == '42703') {
          msg = 'Database Update Required: Missing columns.';
        }
        _showErrorSnackbar(msg);
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackbar('Error: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _successColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: _successColor,
                  size: 64,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Request Submitted!',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Your service request has been posted. Matching providers will be notified.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: _textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Text(message),
          ],
        ),
        backgroundColor: _successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showWarningSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: _warningColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: _errorColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showServiceTypeSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.handyman_rounded,
                        color: _primaryColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Select Service",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: _textPrimary,
                          ),
                        ),
                        Text(
                          "Tap a category to see services",
                          style: TextStyle(fontSize: 13, color: _textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _ExpandableServiceList(
                  services: _services,
                  allServiceTypes: _allServiceTypes,
                  onSelect: (parentService, subService) {
                    setState(() {
                      _selectedServiceType = subService['name'];
                      _selectedService = parentService['id'];
                      _requireCurrentLocation =
                          parentService['require_current_location'] ?? false;
                      _requireDestinationLocation =
                          parentService['require_destination_location'] ??
                          false;
                      if (!_requireCurrentLocation) {
                        _latitude = null;
                        _longitude = null;
                        _gpsAddress = null;
                      }
                      if (!_requireDestinationLocation) {
                        _destLatitude = null;
                        _destLongitude = null;
                        _destAddress = null;
                      }
                    });
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return Scaffold(
        backgroundColor: _surfaceColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: _primaryColor),
              const SizedBox(height: 24),
              Text(
                'Loading services...',
                style: TextStyle(color: _textSecondary, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _surfaceColor,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            // Modern App Bar
            SliverAppBar(
              expandedHeight: 160,
              pinned: true,
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_primaryColor, _primaryLight],
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -30,
                        bottom: -30,
                        child: Icon(
                          Icons.home_repair_service_rounded,
                          size: 180,
                          color: Colors.white.withOpacity(0.1),
                        ),
                      ),
                      Positioned(
                        left: 20,
                        bottom: 20,
                        right: 80,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Book a Service',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Get help from verified professionals',
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ),

            // Form Content
            SliverToBoxAdapter(
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),

                      // Service Selection
                      _buildServiceSelectionCard(),

                      const SizedBox(height: 16),

                      // Location
                      _buildLocationCard(),

                      const SizedBox(height: 16),

                      // Details
                      _buildDetailsCard(),

                      const SizedBox(height: 16),

                      // Photos
                      _buildPhotosCard(),

                      const SizedBox(height: 32),

                      // Submit Button
                      _buildSubmitButton(),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceSelectionCard() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Icons.build_rounded,
            title: 'Select Service',
            color: _primaryColor,
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: () {
              _showServiceTypeSheet();
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _selectedServiceType != null
                    ? _successColor.withOpacity(0.05)
                    : _surfaceColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selectedServiceType != null
                      ? _successColor.withOpacity(0.3)
                      : _borderColor,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _selectedServiceType != null
                          ? _successColor.withOpacity(0.1)
                          : _primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _selectedServiceType != null
                          ? Icons.check_circle_rounded
                          : Icons.handyman_rounded,
                      color: _selectedServiceType != null
                          ? _successColor
                          : _primaryColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Service Type',
                          style: TextStyle(
                            fontSize: 12,
                            color: _textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _selectedServiceType ?? 'Tap to select a service',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _selectedServiceType != null
                                ? _textPrimary
                                : _textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: _textSecondary),
                ],
              ),
            ),
          ),
          if (_selectedServiceType == null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: _warningColor),
                  const SizedBox(width: 8),
                  Text(
                    'Required: Please select a service type',
                    style: TextStyle(fontSize: 13, color: _warningColor),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLocationCard() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Icons.location_on_rounded,
            title: 'Location',
            color: Colors.orange,
          ),
          const SizedBox(height: 16),

          // City/Region Dropdown
          Container(
            decoration: BoxDecoration(
              color: _surfaceColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _borderColor),
            ),
            child: DropdownButtonFormField<String>(
              value: _selectedLocation,
              items: _locations.map((l) {
                return DropdownMenuItem(
                  value: l['id'].toString(),
                  child: Text(l['name']),
                );
              }).toList(),
              onChanged: (v) {
                setState(() {
                  _selectedLocation = v;
                });
              },
              decoration: InputDecoration(
                labelText: 'City / Region',
                labelStyle: TextStyle(color: _textSecondary),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                prefixIcon: Container(
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.location_city_rounded,
                    color: Colors.orange,
                    size: 20,
                  ),
                ),
              ),
              validator: (v) => v == null ? 'Please select a location' : null,
            ),
          ),

          // Conditional Current Location
          if (_requireCurrentLocation) ...[
            const SizedBox(height: 20),
            _buildLocationSection(
              title: 'Pickup Location',
              subtitle: 'Required for this service',
              icon: Icons.my_location_rounded,
              color: Colors.blue,
              address: _gpsAddress,
              isLoading: _isGettingLocation,
              onGpsTap: _getCurrentLocation,
              onMapTap: _pickLocationOnMap,
            ),
          ],

          // Conditional Destination Location
          if (_requireDestinationLocation) ...[
            const SizedBox(height: 20),
            _buildLocationSection(
              title: 'Destination',
              subtitle: 'Where should we deliver/drop?',
              icon: Icons.flag_rounded,
              color: _successColor,
              address: _destAddress,
              isLoading: _isGettingDestLocation,
              onGpsTap: _getDestinationLocation,
              onMapTap: _pickDestinationOnMap,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLocationSection({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String? address,
    required bool isLoading,
    required VoidCallback onGpsTap,
    required VoidCallback onMapTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _textPrimary,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: _textSecondary),
                    ),
                  ],
                ),
              ),
              if (address != null)
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _successColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 14),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildLocationActionButton(
                  icon: Icons.gps_fixed_rounded,
                  label: isLoading ? 'Locating...' : 'Use GPS',
                  color: color,
                  isLoading: isLoading,
                  onTap: isLoading ? null : onGpsTap,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildLocationActionButton(
                  icon: Icons.map_rounded,
                  label: 'Pick on Map',
                  color: color,
                  onTap: onMapTap,
                ),
              ),
            ],
          ),
          if (address != null)
            Container(
              margin: const EdgeInsets.only(top: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _successColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _successColor.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: _successColor, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      address,
                      style: TextStyle(
                        color: _textPrimary,
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
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: _warningColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Please provide this location',
                    style: TextStyle(
                      color: _warningColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLocationActionButton({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
    bool isLoading = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
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
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
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
      ),
    );
  }

  Widget _buildDetailsCard() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Icons.edit_note_rounded,
            title: 'Details',
            color: Colors.purple,
          ),
          const SizedBox(height: 16),

          // Budget & Phone Row
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  controller: _priceController,
                  label: 'Budget',
                  hint: 'Min 50',
                  icon: Icons.currency_rupee_rounded,
                  iconColor: _successColor,
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    final val = double.tryParse(v);
                    if (val == null) return 'Invalid';
                    if (val < 50) return 'Min 50';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTextField(
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
          const SizedBox(height: 16),

          // Description
          _buildTextField(
            controller: _descriptionController,
            label: 'Issue Description',
            hint: 'Describe your problem in detail...',
            icon: Icons.description_rounded,
            iconColor: Colors.orange,
            maxLines: 4,
            validator: (v) => v!.isEmpty ? 'Please describe the issue' : null,
          ),
        ],
      ),
    );
  }

  Widget _buildPhotosCard() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildSectionHeader(
                icon: Icons.photo_library_rounded,
                title: 'Photos',
                color: Colors.pink,
              ),
              const Spacer(),
              if (_selectedImages.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _successColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _successColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    '${_selectedImages.length}/4',
                    style: TextStyle(
                      color: _successColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Image Grid
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _selectedImages.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                if (index == _selectedImages.length) {
                  return _buildAddPhotoButton();
                }
                return _buildImageThumbnail(index);
              },
            ),
          ),

          if (_selectedImages.isEmpty)
            Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _warningColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _warningColor.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 20,
                    color: _warningColor,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Add at least 1 photo to help providers understand the issue',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAddPhotoButton() {
    return GestureDetector(
      onTap: () {
        _showImagePickerModal();
      },
      child: Container(
        width: 110,
        decoration: BoxDecoration(
          color: _surfaceColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _borderColor, width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.pink.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.add_a_photo_rounded,
                color: Colors.pink,
                size: 24,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add Photo',
              style: TextStyle(
                color: _textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageThumbnail(int index) {
    return Stack(
      children: [
        Container(
          width: 110,
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
          right: 6,
          top: 6,
          child: GestureDetector(
            onTap: () => _removeImage(index),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _errorColor,
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
  }

  void _showImagePickerModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
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
                color: _borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Add Photo',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 24),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    final isValid =
        _selectedServiceType != null &&
        _selectedLocation != null &&
        _descriptionController.text.isNotEmpty &&
        _priceController.text.isNotEmpty &&
        _selectedImages.isNotEmpty;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: 56,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _isLoading || !isValid
              ? [Colors.grey.shade400, Colors.grey.shade500]
              : [_primaryColor, _primaryLight],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: _isLoading || !isValid
            ? []
            : [
                BoxShadow(
                  color: _primaryColor.withOpacity(0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : _submitRequest,
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: _isLoading
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
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
                        'Submitting...',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.send_rounded, color: Colors.white, size: 22),
                      SizedBox(width: 12),
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
    );
  }

  // Helper Widgets

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 14),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: _textPrimary,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
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
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        validator: validator,
        style: const TextStyle(color: _textPrimary),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(color: _textSecondary),
          hintStyle: TextStyle(color: _textSecondary.withOpacity(0.6)),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: maxLines > 1 ? 16 : 0,
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
}

/// Expandable service list with search - Shows parent services first, then sub-services on tap
class _ExpandableServiceList extends StatefulWidget {
  final List<Map<String, dynamic>> services; // Parent services with image_url
  final List<Map<String, dynamic>> allServiceTypes; // All sub-services
  final Function(
    Map<String, dynamic> parentService,
    Map<String, dynamic> subService,
  )
  onSelect;

  const _ExpandableServiceList({
    required this.services,
    required this.allServiceTypes,
    required this.onSelect,
  });

  @override
  State<_ExpandableServiceList> createState() => _ExpandableServiceListState();
}

class _ExpandableServiceListState extends State<_ExpandableServiceList> {
  String? _expandedServiceId;
  String _searchQuery = '';
  bool _isSearching = false;

  // Get icon based on service name (fallback when no image)
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
    if (name.contains('carpenter') || name.contains('wood'))
      return Icons.carpenter_rounded;
    return Icons.handyman_rounded;
  }

  // Build service image widget with caching
  Widget _buildServiceImage(
    String? imageUrl,
    String serviceName,
    bool isExpanded,
  ) {
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: SupabaseConfig.proxyImageUrl(imageUrl),
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF4F46E5).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF4F46E5),
                ),
              ),
            ),
          ),
          errorWidget: (context, url, error) => Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: isExpanded
                  ? const LinearGradient(
                      colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                    )
                  : null,
              color: isExpanded
                  ? null
                  : const Color(0xFF4F46E5).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _getServiceIcon(serviceName),
              color: isExpanded ? Colors.white : const Color(0xFF4F46E5),
              size: 24,
            ),
          ),
        ),
      );
    }

    // Fallback to icon
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        gradient: isExpanded
            ? const LinearGradient(
                colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
              )
            : null,
        color: isExpanded ? null : const Color(0xFF4F46E5).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        _getServiceIcon(serviceName),
        color: isExpanded ? Colors.white : const Color(0xFF4F46E5),
        size: 24,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Filter both parent services AND sub-services based on search query
    final query = _searchQuery.toLowerCase();

    // Find matching parent services (service types)
    final filteredParentServices = _searchQuery.isEmpty
        ? <Map<String, dynamic>>[]
        : widget.services.where((s) {
            return s['name'].toString().toLowerCase().contains(query);
          }).toList();

    // Find matching sub-services
    final filteredSubServices = _searchQuery.isEmpty
        ? <Map<String, dynamic>>[]
        : widget.allServiceTypes.where((st) {
            return st['name'].toString().toLowerCase().contains(query);
          }).toList();

    return Column(
      children: [
        // Search Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _isSearching
                    ? const Color(0xFF4F46E5)
                    : const Color(0xFFE2E8F0),
                width: _isSearching ? 2 : 1,
              ),
            ),
            child: TextField(
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                  _isSearching = val.isNotEmpty;
                  if (val.isNotEmpty) {
                    _expandedServiceId = null; // Collapse all when searching
                  }
                });
              },
              decoration: InputDecoration(
                hintText: 'Search services or categories...',
                hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Color(0xFF64748B),
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        color: const Color(0xFF64748B),
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                            _isSearching = false;
                          });
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),
        ),

        // Search Results or Service List
        Expanded(
          child: _searchQuery.isNotEmpty
              ? _buildSearchResults(filteredParentServices, filteredSubServices)
              : _buildServiceList(),
        ),
      ],
    );
  }

  // Build search results showing matching parent services AND sub-services
  Widget _buildSearchResults(
    List<Map<String, dynamic>> parentResults,
    List<Map<String, dynamic>> subServiceResults,
  ) {
    final hasParentResults = parentResults.isNotEmpty;
    final hasSubServiceResults = subServiceResults.isNotEmpty;

    if (!hasParentResults && !hasSubServiceResults) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 64,
              color: const Color(0xFFCBD5E1),
            ),
            const SizedBox(height: 16),
            Text(
              'No services found for "$_searchQuery"',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Try a different search term',
              style: TextStyle(color: const Color(0xFF94A3B8), fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      children: [
        // Show matching parent service categories first
        if (hasParentResults) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10, top: 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4F46E5).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.category_rounded,
                    color: Color(0xFF4F46E5),
                    size: 14,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Categories (${parentResults.length})',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          ...parentResults.map(
            (service) => _buildParentServiceSearchResult(service),
          ),
          if (hasSubServiceResults) const SizedBox(height: 20),
        ],

        // Show matching sub-services
        if (hasSubServiceResults) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10, top: 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.handyman_rounded,
                    color: Color(0xFF7C3AED),
                    size: 14,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Services (${subServiceResults.length})',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          ...subServiceResults.map(
            (subService) => _buildSubServiceSearchResult(subService),
          ),
        ],
      ],
    );
  }

  // Build a parent service category search result item
  Widget _buildParentServiceSearchResult(Map<String, dynamic> service) {
    final serviceName = service['name'] ?? 'Service';
    final imageUrl = service['image_url'];
    final serviceId = service['id'];

    // Get sub-services count for this parent
    final subServices = widget.allServiceTypes
        .where((st) => st['service_id'] == serviceId)
        .toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            // When tapping a parent category, expand it in the main list
            setState(() {
              _searchQuery = '';
              _isSearching = false;
              _expandedServiceId = serviceId;
            });
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFF4F46E5).withOpacity(0.3),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4F46E5).withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                _buildServiceImage(imageUrl, serviceName, false),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        serviceName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${subServices.length} services available',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4F46E5).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View',
                        style: TextStyle(
                          color: Color(0xFF4F46E5),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: Color(0xFF4F46E5),
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Build a sub-service search result item
  Widget _buildSubServiceSearchResult(Map<String, dynamic> subService) {
    final serviceId = subService['service_id'];

    // Find parent service
    final parentService = widget.services.firstWhere(
      (s) => s['id'] == serviceId,
      orElse: () => {'name': 'Unknown', 'id': serviceId},
    );
    final parentName = parentService['name'] ?? 'Unknown';
    final imageUrl = parentService['image_url'];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => widget.onSelect(parentService, subService),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                _buildServiceImage(imageUrl, parentName, false),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subService['name'] ?? 'Unknown',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'in $parentName',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4F46E5).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    color: Color(0xFF4F46E5),
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Build expandable service list
  Widget _buildServiceList() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: widget.services.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final service = widget.services[index];
        final serviceId = service['id'];
        final serviceName = service['name'] ?? 'Service';
        final imageUrl = service['image_url'];
        final isExpanded = _expandedServiceId == serviceId;

        // Get sub-services for this parent
        final subServices = widget.allServiceTypes
            .where((st) => st['service_id'] == serviceId)
            .toList();

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isExpanded
                  ? const Color(0xFF4F46E5)
                  : const Color(0xFFE2E8F0),
              width: isExpanded ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isExpanded
                    ? const Color(0xFF4F46E5).withOpacity(0.1)
                    : Colors.black.withOpacity(0.03),
                blurRadius: isExpanded ? 12 : 6,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Parent Service Header - Tap to expand
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    setState(() {
                      if (_expandedServiceId == serviceId) {
                        _expandedServiceId = null;
                      } else {
                        _expandedServiceId = serviceId;
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        _buildServiceImage(imageUrl, serviceName, isExpanded),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                serviceName,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isExpanded
                                      ? const Color(0xFF4F46E5)
                                      : const Color(0xFF1E293B),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${subServices.length} services available',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        AnimatedRotation(
                          turns: isExpanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isExpanded
                                  ? const Color(0xFF4F46E5).withOpacity(0.1)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: isExpanded
                                  ? const Color(0xFF4F46E5)
                                  : const Color(0xFF64748B),
                              size: 22,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Sub-services (shown when expanded)
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(14),
                      bottomRight: Radius.circular(14),
                    ),
                  ),
                  child: Column(
                    children: [
                      const Divider(height: 1, color: Color(0xFFE2E8F0)),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                left: 4,
                                bottom: 10,
                              ),
                              child: Text(
                                'Select a service:',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                            ),
                            ...subServices.map((subService) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () {
                                      widget.onSelect(service, subService);
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 14,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: const Color(0xFFE2E8F0),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: const Color(
                                                0xFF7C3AED,
                                              ).withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: const Icon(
                                              Icons.arrow_forward_rounded,
                                              color: Color(0xFF7C3AED),
                                              size: 18,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              subService['name'] ?? 'Unknown',
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w500,
                                                color: Color(0xFF1E293B),
                                              ),
                                            ),
                                          ),
                                          const Icon(
                                            Icons.chevron_right_rounded,
                                            color: Color(0xFF94A3B8),
                                            size: 20,
                                          ),
                                        ],
                                      ),
                                    ),
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
      },
    );
  }
}
