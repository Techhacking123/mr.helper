import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_config.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geocoding/geocoding.dart';
import 'login.dart';
import '../widgets/map_picker.dart';
import 'package:flutter/services.dart';

class SignupScreen extends StatefulWidget {
  final bool initialIsProvider;
  final bool isRoleLocked;

  const SignupScreen({
    super.key,
    this.initialIsProvider = false,
    this.isRoleLocked = false,
  });

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _mobileController = TextEditingController(); // Added Mobile Controller
  final _bioController = TextEditingController();
  final _priceController = TextEditingController();

  // State variables
  late bool _isProvider;
  String? _selectedBusinessType;
  String? _selectedLocation;
  double? _latitude;
  double? _longitude;

  List<Map<String, dynamic>> _services = [];
  List<Map<String, dynamic>> _locations = [];
  List<Map<String, dynamic>> _subServices = []; // Dynamic sub-services
  bool _isLoadingData = false;
  bool _isLoadingSubServices = false;

  String? _selectedServiceType;

  bool _isLoading = false;
  String? _errorMessage;
  bool _isPasswordVisible = false;
  bool _isDuplicateEmail = false;
  bool _isDuplicateName = false;
  bool _isCheckingDuplicate = false;
  bool _acceptedTerms = false; // T&C acceptance for providers
  bool _acceptedUserTerms = false; // T&C acceptance for regular users

  // Image Upload
  XFile? _pickedImage;
  XFile? _aadharImage;
  XFile? _panImage;
  final ImagePicker _picker = ImagePicker();

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Tab Controller for Provider Signup
  late TabController _tabController;
  int _currentTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _isProvider = widget.initialIsProvider;
    _fetchData();

    // Animation Init
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
          CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
        );

    _animationController.forward();

    // Initialize Tab Controller for provider signup
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _currentTabIndex = _tabController.index;
      });
    });

    // Add listeners for real-time duplicate checking (only for providers)
    _emailController.addListener(_checkForDuplicateUser);
    _fullNameController.addListener(_checkForDuplicateUser);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    _mobileController.dispose();
    _bioController.dispose();
    _priceController.dispose();
    _animationController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchSubServices(String serviceId) async {
    setState(() {
      _isLoadingSubServices = true;
      _subServices = [];
      _selectedServiceType = null;
    });

    try {
      final response = await SupabaseConfig.supabase
          .from('service_types')
          .select('id, name')
          .eq('service_id', serviceId)
          .order('name');

      if (mounted) {
        setState(() {
          _subServices = List<Map<String, dynamic>>.from(response);
          _isLoadingSubServices = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching sub-services: $e');
      if (mounted) setState(() => _isLoadingSubServices = false);
    }
  }

  Future<void> _fetchData() async {
    setState(() => _isLoadingData = true);
    try {
      final servicesData = await SupabaseConfig.supabase
          .from('services')
          .select('id, name');
      final locationsData = await SupabaseConfig.supabase
          .from('locations')
          .select('name');

      setState(() {
        _services = List<Map<String, dynamic>>.from(servicesData);
        _locations = List<Map<String, dynamic>>.from(locationsData);
      });
    } catch (e) {
      debugPrint('Error fetching data: $e');
    } finally {
      if (mounted) setState(() => _isLoadingData = false);
    }
  }

  // Debounce timer for duplicate checking
  Timer? _debounce;

  Future<void> _checkForDuplicateUser() async {
    // Check for everyone since login now uses full name
    // if (!_isProvider) return;

    // Cancel previous timer
    _debounce?.cancel();

    // Debounce for 500ms
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final email = _emailController.text.trim().toLowerCase();
      final fullName = _fullNameController.text.trim();

      // Reset if fields are empty
      if (email.isEmpty && fullName.isEmpty) {
        if (mounted) {
          setState(() {
            _isDuplicateEmail = false;
            _isDuplicateName = false;
            _isCheckingDuplicate = false;
          });
        }
        return;
      }

      if (mounted) {
        setState(() => _isCheckingDuplicate = true);
      }

      try {
        bool emailExists = false;
        bool nameExists = false;

        // Check email separately if not empty
        if (email.isNotEmpty) {
          // Check in users table
          final emailResponse = await SupabaseConfig.supabase
              .from('users')
              .select('id')
              .eq('email', email)
              .maybeSingle();
          emailExists = emailResponse != null;

          // Also check in pending_providers table
          if (!emailExists) {
            final pendingEmailResponse = await SupabaseConfig.supabase
                .from('pending_providers')
                .select('id')
                .eq('email', email)
                .eq('status', 'pending')
                .maybeSingle();
            emailExists = pendingEmailResponse != null;
          }
        }

        // Check full name separately if not empty
        if (fullName.isNotEmpty) {
          // Check in users table
          final nameResponse = await SupabaseConfig.supabase
              .from('users')
              .select('id')
              .eq('full_name', fullName)
              .maybeSingle();
          nameExists = nameResponse != null;

          // Also check in pending_providers table
          if (!nameExists) {
            final pendingNameResponse = await SupabaseConfig.supabase
                .from('pending_providers')
                .select('id')
                .eq('full_name', fullName)
                .eq('status', 'pending')
                .maybeSingle();
            nameExists = pendingNameResponse != null;
          }
        }

        if (mounted) {
          setState(() {
            _isDuplicateEmail = emailExists;
            _isDuplicateName = nameExists;
            _isCheckingDuplicate = false;
          });
        }
      } catch (e) {
        debugPrint('Error checking duplicate user: $e');
        if (mounted) {
          setState(() => _isCheckingDuplicate = false);
        }
      }
    });
  }

  Future<void> _pickImage() async {
    await _showImageSourceModal((source) => _pickImageFromSource(source));
  }

  Future<void> _pickAadharImage() async {
    await _showImageSourceModal((source) async {
      try {
        final XFile? image = await _picker.pickImage(
          source: source,
          imageQuality: 50,
        );
        if (image != null) {
          setState(() {
            _aadharImage = image;
          });
        }
      } catch (e) {
        debugPrint('Error picking Aadhar image: $e');
      }
    });
  }

  Future<void> _pickPanImage() async {
    await _showImageSourceModal((source) async {
      try {
        final XFile? image = await _picker.pickImage(
          source: source,
          imageQuality: 50,
        );
        if (image != null) {
          setState(() {
            _panImage = image;
          });
        }
      } catch (e) {
        debugPrint('Error picking Pan image: $e');
      }
    });
  }

  Future<void> _showImageSourceModal(
    Function(ImageSource) onSourceSelected,
  ) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.photo_library,
                  color: Colors.deepPurple,
                ),
                title: const Text('Gallery'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await onSourceSelected(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_camera,
                  color: Colors.deepPurple,
                ),
                title: const Text('Camera'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await onSourceSelected(ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickImageFromSource(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 50,
      );
      if (image != null) {
        setState(() {
          _pickedImage = image;
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  Future<void> _pickLocationOnMap() async {
    double? initialLat;
    double? initialLng;

    // Try to geocode the selected dropdown location to center the map
    if (_selectedLocation != null && _selectedLocation!.isNotEmpty) {
      try {
        List<Location> locations = await locationFromAddress(
          _selectedLocation!,
        );
        if (locations.isNotEmpty) {
          initialLat = locations.first.latitude;
          initialLng = locations.first.longitude;
        }
      } catch (e) {
        debugPrint('Error geocoding selected location: $e');
      }
    }

    if (!mounted) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MapPicker(
          initialLat: initialLat ?? _latitude,
          initialLng: initialLng ?? _longitude,
        ),
      ),
    );

    if (result != null && result is Map) {
      setState(() {
        _latitude = result['lat'];
        _longitude = result['lng'];
      });

      // Optional: Update dropdown if the map returned a specific address that matches our list?
      // For now, we keep the dropdown as the general area and these coords as specific pin.
    }
  }

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<String?> _uploadFile(XFile file, String userId, String prefix) async {
    try {
      final fileExt = file.name.split('.').last.toLowerCase();
      final fileName =
          '$prefix-$userId-${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      // Use a subfolder 'provider_docs' for docs, or just root for simplicity if policy allows.
      // Assuming 'avatars' bucket is public/accessible for now as per previous logic.
      // We will put everything in 'avatars' but maybe prefix filename.
      final filePath = fileName;

      String contentType = 'application/octet-stream';
      if (fileExt == 'jpg' || fileExt == 'jpeg') {
        contentType = 'image/jpeg';
      } else if (fileExt == 'png') {
        contentType = 'image/png';
      }

      if (kIsWeb) {
        final bytes = await file.readAsBytes();
        await SupabaseConfig.supabase.storage
            .from('avatars')
            .uploadBinary(
              filePath,
              bytes,
              fileOptions: FileOptions(contentType: contentType, upsert: true),
            );
      } else {
        await SupabaseConfig.supabase.storage
            .from('avatars')
            .upload(
              filePath,
              File(file.path),
              fileOptions: FileOptions(contentType: contentType, upsert: true),
            );
      }

      final imageUrl = SupabaseConfig.supabase.storage
          .from('avatars')
          .getPublicUrl(filePath);
      return imageUrl;
    } catch (e) {
      debugPrint('File upload failed: $e');
      throw e;
    }
  }

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;

    if (_pickedImage == null) {
      setState(() => _errorMessage = 'Please upload a profile picture');
      return;
    }

    if (_isProvider) {
      // Check profile picture for providers
      if (_selectedBusinessType == null) {
        setState(() => _errorMessage = 'Please select a business type');
        return;
      }
      if (_selectedServiceType == null) {
        setState(() => _errorMessage = 'Please select a service type');
        return;
      }
      if (_aadharImage == null) {
        setState(() => _errorMessage = 'Please upload Aadhar Card');
        return;
      }
      if (_panImage == null) {
        setState(() => _errorMessage = 'Please upload Pan Card');
        return;
      }
      // Check Terms & Conditions acceptance
      if (!_acceptedTerms) {
        setState(
          () => _errorMessage = 'Please accept the Terms and Conditions',
        );
        return;
      }
    }

    // Check Terms & Conditions for regular users
    if (!_isProvider && !_acceptedUserTerms) {
      setState(() => _errorMessage = 'Please accept the Terms and Conditions');
      return;
    }

    if (_selectedLocation == null) {
      setState(() => _errorMessage = 'Please select a location');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();
    final hashedPassword = _hashPassword(password);
    final fullName = _fullNameController.text.trim();
    final mobile = _mobileController.text.trim();
    final bio = _bioController.text.trim();
    final price = _priceController.text.trim();

    try {
      String? avatarUrl;
      String? aadharUrl;
      String? panUrl;
      final tempId = DateTime.now().millisecondsSinceEpoch.toString();

      // Automatically clear rejected users so they can sign up again
      try {
        await SupabaseConfig.supabase.rpc(
          'clear_rejected_user',
          params: {'email_input': email},
        );
      } catch (e) {
        // If the function doesn't exist or fails, we continue.
        // The unique constraint will catch duplicates if they weren't deleted.
        debugPrint('Note: clear_rejected_user RPC might be missing: $e');
      }

      // Prepare for NEW Insert
      if (_pickedImage != null) {
        avatarUrl = await _uploadFile(_pickedImage!, tempId, 'avatar');
      }

      if (_isProvider) {
        if (_aadharImage != null) {
          aadharUrl = await _uploadFile(_aadharImage!, tempId, 'aadhar');
        }
        if (_panImage != null) {
          panUrl = await _uploadFile(_panImage!, tempId, 'pan');
        }
      }

      // PROVIDERS: Save to pending_providers table for KYC approval
      if (_isProvider) {
        final Map<String, dynamic> providerData = {
          'email': email,
          'password': hashedPassword,
          'full_name': fullName,
          'phone_number': mobile,
          'bio': bio,
          'location': _selectedLocation,
          'latitude': _latitude,
          'longitude': _longitude,
          'avatar_url': avatarUrl,
          'service_id': _selectedBusinessType,
          'service_type': _selectedServiceType,
          'aadhar_card_url': aadharUrl,
          'pan_card_url': panUrl,
          'status': 'pending',
        };

        if (price.isNotEmpty) {
          providerData['price'] = double.tryParse(price);
        }

        // Insert into pending_providers table
        await SupabaseConfig.supabase
            .from('pending_providers')
            .insert(providerData)
            .select()
            .maybeSingle();
      } else {
        // REGULAR USERS: Save directly to users table
        final Map<String, dynamic> userData = {
          'email': email,
          'password': hashedPassword,
          'full_name': fullName,
          'phone_number': mobile,
          'is_provider': false,
          'location': _selectedLocation,
          'latitude': _latitude,
          'longitude': _longitude,
          'avatar_url': avatarUrl,
          'status': 'active',
        };

        final response = await SupabaseConfig.supabase
            .from('users')
            .insert(userData)
            .select()
            .maybeSingle();

        if (response != null) {
          final newUserId = response['id'];
          try {
            final fcmToken = await FirebaseMessaging.instance.getToken();
            if (fcmToken != null && newUserId != null) {
              // Use adminClient to bypass RLS (no Supabase Auth session after custom signup)
              await SupabaseConfig.adminClient
                  .from('users')
                  .update({'fcm_token': fcmToken})
                  .eq('id', newUserId);
            }
          } catch (e) {
            debugPrint('Error saving FCM token on signup: $e');
          }
        }
      }

      if (mounted) {
        final message = _isProvider
            ? 'Signup Successful! Your account is under review by Admin.'
            : 'Signup Successful! Please login.';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: _isProvider ? Colors.orange : Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('Signup Error: $e');
      if (mounted) {
        setState(() {
          // Check for unique key violation if not caught by existing user check
          if (e.toString().contains('23505') ||
              e.toString().contains('already exists')) {
            _errorMessage = 'Email already registered.';
          } else {
            _errorMessage = 'Error: $e';
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  InputDecoration _buildInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
      prefixIcon: Icon(icon, color: const Color(0xFF1565C0), size: 22),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey.shade300, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF1565C0), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.red.shade400, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.red.shade400, width: 2),
      ),
      filled: true,
      fillColor: Colors.grey.shade50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  void _showTermsDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Terms & Conditions',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTermSection('I. GENERAL COVENANTS', [
                        'Age & Eligibility: You confirm you are 18+ and not legally barred from providing services.',
                        'Accuracy: You warrant that all information (ID, bank details) provided is true.',
                        'Authorization: You authorize Mr. Helper to conduct police verification and background checks.',
                      ]),
                      _buildTermSection('II. REGISTRATION AND OPERATION', [
                        'Account Security: You are solely responsible for your login credentials.',
                        'Device: You must use a compatible smartphone.',
                        'Communication: You consent to receive notifications via SMS, WhatsApp, and Push Notifications regarding leads.',
                      ]),
                      _buildTermSection('III. HELPER CONDUCT', [
                        'Professionalism: You agree not to cause nuisance or annoyance to Users.',
                        'Prohibited Acts: No consumption of alcohol/drugs before or during service.',
                        'Discrimination: Zero tolerance for discrimination based on religion, caste, or gender.',
                      ]),
                      _buildTermSection('IV. PAYMENT TERMS', [
                        'Subscription/Fees: Mr. Helper may charge a lead generation or subscription fee.',
                        'Direct Settlement: In many cases, you will collect the "Task Fee" directly from the User.',
                        'Taxes: You are responsible for your own GST and income tax filings.',
                      ]),
                      _buildTermSection('V. REPRESENTATIONS AND WARRANTIES', [
                        'Compliance: You warrant you comply with all local laws and possess necessary trade licenses.',
                        'No Convictions: You confirm you have no criminal record in the past 3 years.',
                      ]),
                      _buildTermSection('VI. RELATIONSHIP BETWEEN PARTIES', [
                        'Independent Contractor: This is a Principal-to-Principal relationship.',
                        'No Employment: You are NOT an employee, agent, or partner of Mr. Helper.',
                      ]),
                      _buildTermSection('VII. HELPER INFORMATION (KYC)', [
                        'Data Collection: We collect Helper Information (Identity proof, selfies, location data).',
                        'Usage: We may share this with Users or government authorities in case of disputes or accidents.',
                      ]),
                      _buildTermSection('VIII. CONFIDENTIALITY', [
                        'Data Protection: You must keep all User data confidential.',
                        'Trade Secrets: You shall not disclose non-public information about Mr. Helper.',
                      ]),
                      _buildTermSection('IX. PROPRIETARY RIGHTS', [
                        'Ownership: Mr. Helper owns all rights to the App and software.',
                        'License: Limited, revocable license granted.',
                        'Restrictions: No reverse engineering or copying.',
                      ]),
                      _buildTermSection('X. INDEMNITY', [
                        'You agree to indemnify and hold Mr. Helper harmless from damages caused by your actions.',
                      ]),
                      _buildTermSection(
                        'XI. DISCLAIMER & LIMITATION OF LIABILITY',
                        [
                          'As-Is: Platform provided without warranties.',
                          'Liability Cap: Total liability limited to INR 1,000/-.',
                          'No Responsibility: Mr. Helper not responsible for User behavior.',
                        ],
                      ),
                      _buildTermSection('XII. TERMINATION & DISPUTE RESOLUTION', [
                        'Termination: Account may be disabled for misconduct or fraud.',
                        'Governing Law: Laws of India apply.',
                        'Arbitration: Sole arbitrator in the specified city.',
                      ]),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() => _acceptedTerms = true);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Accept & Close',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTermSection(String title, List<String> points) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
            ),
          ),
          const SizedBox(height: 8),
          ...points.map(
            (point) => Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '• ',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  Expanded(
                    child: Text(
                      point,
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showUserTermsDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'User Terms & Conditions',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'THIS DOCUMENT IS AN ELECTRONIC RECORD IN TERMS OF THE INFORMATION TECHNOLOGY ACT, 2000. BY DOWNLOADING, INSTALLING, OR USING THE MR. HELPER APP, YOU AGREE TO THESE TERMS.',
                        style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildTermSection('I. THE PLATFORM', [
                        'Intermediary Role: Mr. Helper ("Company") provides a technology platform that connects you ("User") with independent service providers ("Helpers").',
                        'No Employment: Helpers are not employees or agents of Mr. Helper. They are independent third-party contractors.',
                        'No Warranty: The Company does not guarantee the quality, suitability, or ability of the Helpers. The decision to hire a Helper is at your own risk.',
                      ]),
                      _buildTermSection('II. USER ELIGIBILITY & REGISTRATION', [
                        'Age: You must be at least 18 years of age to book a service.',
                        'Account: You are responsible for all activity that occurs under your account. You must provide accurate info (name, phone number, address).',
                      ]),
                      _buildTermSection('III. BOOKING AND SERVICES', [
                        'Service Requests: When you make a booking, the App will share your location and task details with available Helpers.',
                        'Acceptance: A contract is formed between you and the Helper only when the Helper accepts your request.',
                        'Accuracy of Task: You must provide clear and accurate details of the work required. If the work differs from the booking description, the Helper may adjust the price or decline the service.',
                      ]),
                      _buildTermSection('IV. PAYMENT TERMS', [
                        'Quoted Price: The App may show an "Estimated Fare." The final price is settled between you and the Helper based on the work done.',
                        'Convenience Fee: The Company may charge a non-refundable "Platform/Convenience Fee" for every successful booking.',
                        'Payment Method: You may pay the Helper directly (Cash/Online) or through the App\'s integrated payment gateway (if available).',
                        'Taxes: All applicable taxes (GST) on the service fee are to be handled as per the invoice provided by the Helper.',
                      ]),
                      _buildTermSection('V. CANCELLATION POLICY', [
                        'User Cancellation: You may cancel a request at any time. However, if a Helper has already reached your location, a Cancellation Fee may be charged to your account.',
                        'Helper Cancellation: While we discourage this, Helpers may cancel due to emergencies. In such cases, the Company will attempt to find a replacement but does not guarantee one.',
                      ]),
                      _buildTermSection('VI. USER CONDUCT & SAFETY', [
                        'Safe Environment: You must provide a safe and professional environment for the Helper to work.',
                        'Prohibited Acts: You shall not abuse, harass, or misbehave with the Helper. You shall not request the Helper to perform illegal acts.',
                        'Valuables: You are advised to supervise the Helper and secure your valuables. The Company is not responsible for any loss or theft.',
                      ]),
                      _buildTermSection('VII. CONFIDENTIALITY & PRIVACY', [
                        'Data Usage: We collect your location and contact data to facilitate the service as per our Privacy Policy.',
                        'Helper Privacy: You shall not use the Helper\'s contact information for any purpose other than the specific task booked.',
                      ]),
                      _buildTermSection('VIII. INTELLECTUAL PROPERTY', [
                        'Mr. Helper owns all rights to the App, including its software, design, and branding. You may not copy or distribute any part of the App.',
                      ]),
                      _buildTermSection('IX. INDEMNITY', [
                        'You agree to indemnify and hold Mr. Helper harmless from any claims or damages arising from your breach of these terms or your interactions with a Helper.',
                      ]),
                      _buildTermSection('X. DISCLAIMER OF WARRANTIES', [
                        '"As-Is": The service is provided "as-is." We do not warrant that the App will always be functional or that a Helper will always be available.',
                        'Third-Party Acts: Mr. Helper is not liable for the behavior, actions, or omissions of any Helper.',
                      ]),
                      _buildTermSection('XI. LIMITATION OF LIABILITY', [
                        'To the maximum extent permitted by law, Mr. Helper\'s total liability to you for any dispute shall not exceed INR 1,000/-.',
                      ]),
                      _buildTermSection(
                        'XII. GOVERNING LAW & DISPUTE RESOLUTION',
                        [
                          'These terms are governed by the laws of India.',
                          'Any disputes shall be settled through arbitration or the exclusive jurisdiction of the local courts.',
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() => _acceptedUserTerms = true);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Accept & Close',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // If the user is a provider, show the tabbed interface
    if (_isProvider) {
      return _buildProviderSignupWithTabs(context);
    }

    // Otherwise, show the original single-form interface for regular users
    return _buildRegularUserSignup(context);
  }

  // Provider Signup with Tabs
  Widget _buildProviderSignupWithTabs(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0D47A1),
                  Color(0xFF1565C0),
                  Color(0xFF42A5F5),
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // Modern Header with Step Indicator
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: IconButton(
                                icon: const Icon(
                                  Icons.arrow_back_ios_new,
                                  color: Colors.white,
                                ),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ),
                            const Expanded(
                              child: Text(
                                'Provider Signup',
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(width: 56),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Modern Circular Progress Indicator
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(5, (index) {
                            final isCompleted = index < _currentTabIndex;
                            final isCurrent = index == _currentTabIndex;
                            return Row(
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  width: isCurrent ? 40 : 32,
                                  height: isCurrent ? 40 : 32,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isCompleted || isCurrent
                                        ? Colors.white
                                        : Colors.white.withOpacity(0.3),
                                    boxShadow: isCurrent
                                        ? [
                                            BoxShadow(
                                              color: Colors.white.withOpacity(
                                                0.5,
                                              ),
                                              blurRadius: 8,
                                              spreadRadius: 2,
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Center(
                                    child: isCompleted
                                        ? const Icon(
                                            Icons.check,
                                            color: Color(0xFF1565C0),
                                            size: 18,
                                          )
                                        : Text(
                                            '${index + 1}',
                                            style: TextStyle(
                                              color: isCurrent
                                                  ? const Color(0xFF1565C0)
                                                  : Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: isCurrent ? 16 : 14,
                                            ),
                                          ),
                                  ),
                                ),
                                if (index < 4)
                                  Container(
                                    width: 30,
                                    height: 2,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    color: index < _currentTabIndex
                                        ? Colors.white
                                        : Colors.white.withOpacity(0.3),
                                  ),
                              ],
                            );
                          }),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _getStepTitle(_currentTabIndex),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Tab Bar
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      indicatorColor: Colors.white,
                      indicatorWeight: 3,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white60,
                      labelStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                      unselectedLabelStyle: const TextStyle(fontSize: 12),
                      tabs: const [
                        Tab(text: '1. Personal'),
                        Tab(text: '2. Location'),
                        Tab(text: '3. Service'),
                        Tab(text: '4. Documents'),
                        Tab(text: '5. Review'),
                      ],
                    ),
                  ),

                  // Tab Content with Modern Card
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(30),
                          topRight: Radius.circular(30),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(30),
                          topRight: Radius.circular(30),
                        ),
                        child: Form(
                          key: _formKey,
                          child: TabBarView(
                            controller: _tabController,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              _buildPersonalInfoTab(),
                              _buildLocationBioTab(),
                              _buildServiceDetailsTab(),
                              _buildDocumentsTab(),
                              _buildReviewCreateTab(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Modern Navigation Buttons
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, -5),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        if (_currentTabIndex > 0)
                          Expanded(
                            child: Container(
                              height: 54,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.grey.shade300,
                                    Colors.grey.shade400,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    _tabController.animateTo(
                                      _currentTabIndex - 1,
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(16),
                                  child: const Center(
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.arrow_back,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Previous',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (_currentTabIndex > 0) const SizedBox(width: 12),
                        Expanded(
                          flex: _currentTabIndex > 0 ? 2 : 1,
                          child: Container(
                            height: 54,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF1565C0,
                                  ).withOpacity(0.4),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  if (_currentTabIndex < 4) {
                                    _tabController.animateTo(
                                      _currentTabIndex + 1,
                                    );
                                  } else {
                                    // Validate all information before showing KYC dialog
                                    _validateAndShowKYC();
                                  }
                                },
                                borderRadius: BorderRadius.circular(16),
                                child: Center(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        _currentTabIndex < 4
                                            ? 'Continue'
                                            : 'Request for KYC',
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(
                                        Icons.arrow_forward,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Loading Overlay
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: Center(
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF1565C0),
                          ),
                          strokeWidth: 4,
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Uploading your details...',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1565C0),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Please wait while we process your KYC',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _getStepTitle(int index) {
    switch (index) {
      case 0:
        return 'Personal Information';
      case 1:
        return 'Location & Bio';
      case 2:
        return 'Service Details';
      case 3:
        return 'Upload Documents';
      case 4:
        return 'Review & Create';
      default:
        return '';
    }
  }

  void _validateAndShowKYC() {
    List<String> missingItems = [];

    // Check profile picture
    if (_pickedImage == null) {
      missingItems.add('Profile Picture');
    }

    // Validate form fields
    if (!_formKey.currentState!.validate()) {
      missingItems.add('Complete all form fields');
    }

    // Check specific required fields
    if (_fullNameController.text.trim().isEmpty) {
      missingItems.add('Full Name');
    }
    if (_emailController.text.trim().isEmpty) {
      missingItems.add('Email');
    }
    if (_mobileController.text.trim().isEmpty) {
      missingItems.add('Mobile Number');
    }
    if (_passwordController.text.trim().isEmpty) {
      missingItems.add('Password');
    }
    if (_selectedLocation == null) {
      missingItems.add('Location');
    }
    if (_latitude == null || _longitude == null) {
      missingItems.add('Map Location (Pick exact location on map)');
    }
    if (_bioController.text.trim().isEmpty) {
      missingItems.add('Bio');
    }
    if (_selectedBusinessType == null) {
      missingItems.add('Business Type');
    }
    if (_selectedServiceType == null) {
      missingItems.add('Service Type');
    }
    if (_priceController.text.trim().isEmpty) {
      missingItems.add('Starting Price');
    }

    // Check documents
    if (_aadharImage == null) {
      missingItems.add('Aadhar Card');
    }
    if (_panImage == null) {
      missingItems.add('PAN Card');
    }

    // Check terms acceptance
    if (!_acceptedTerms) {
      missingItems.add('Accept Terms & Conditions');
    }

    // If there are missing items, show error dialog
    if (missingItems.isNotEmpty) {
      _showMissingInfoDialog(missingItems);
    } else {
      // All information is complete, show KYC confirmation
      _showKYCConfirmationDialog();
    }
  }

  void _showMissingInfoDialog(List<String> missingItems) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.error_outline,
                  color: Colors.red.shade600,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Incomplete Information',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Please provide the following information:',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                constraints: const BoxConstraints(maxHeight: 300),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: missingItems.map((item) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.circle,
                              size: 8,
                              color: Colors.red.shade600,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                item,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'OK, I\'ll Complete It',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showKYCConfirmationDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.verified_user,
                  color: Color(0xFF1565C0),
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'KYC Verification',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1565C0),
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF1565C0).withOpacity(0.2),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: Color(0xFF1565C0),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Our team will contact you for KYC verification through video call or audio call.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade800,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Please make sure:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              _buildKYCCheckItem('Your documents are ready'),
              _buildKYCCheckItem('You are available for verification call'),
              _buildKYCCheckItem('All information provided is accurate'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                // Close dialog and trigger signup with loading
                Navigator.pop(context);
                // Small delay to ensure dialog is closed before showing loading
                Future.delayed(const Duration(milliseconds: 100), () {
                  _signup(); // Execute signup with loading animation
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Do KYC',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildKYCCheckItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF1565C0), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }

  // Regular User Signup (Original Form)
  Widget _buildRegularUserSignup(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.deepPurple.shade900,
              Colors.deepPurple.shade500,
              Colors.purple.shade300,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 20,
              ),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Column(
                    children: [
                      // Back Button
                      Align(
                        alignment: Alignment.topLeft,
                        child: IconButton(
                          icon: const Icon(
                            Icons.arrow_back_ios,
                            color: Colors.white,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),

                      const Text(
                        'Create Account',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Join us and explore services',
                        style: TextStyle(
                          fontSize: 16,
                          color: Color.fromRGBO(255, 255, 255, 0.8),
                        ),
                      ),
                      const SizedBox(height: 30),

                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Color.fromRGBO(0, 0, 0, 0.1),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_errorMessage != null)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.red.shade200,
                                    ),
                                  ),
                                  child: Text(
                                    _errorMessage!,
                                    style: TextStyle(
                                      color: Colors.red.shade800,
                                    ),
                                  ),
                                ),

                              // Profile Picture
                              Center(
                                child: Column(
                                  children: [
                                    GestureDetector(
                                      onTap: _pickImage,
                                      child: Stack(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color:
                                                    _isProvider &&
                                                        _pickedImage == null
                                                    ? Colors.red.shade300
                                                    : Colors
                                                          .deepPurple
                                                          .shade200,
                                                width: 2,
                                              ),
                                            ),
                                            child: CircleAvatar(
                                              radius: 50,
                                              backgroundColor:
                                                  Colors.grey.shade100,
                                              backgroundImage:
                                                  _pickedImage != null
                                                  ? (kIsWeb
                                                            ? NetworkImage(
                                                                _pickedImage!
                                                                    .path,
                                                              )
                                                            : FileImage(
                                                                File(
                                                                  _pickedImage!
                                                                      .path,
                                                                ),
                                                              ))
                                                        as ImageProvider
                                                  : null,
                                              child: _pickedImage == null
                                                  ? Icon(
                                                      Icons.person,
                                                      size: 50,
                                                      color:
                                                          Colors.grey.shade400,
                                                    )
                                                  : null,
                                            ),
                                          ),
                                          Positioned(
                                            bottom: 0,
                                            right: 0,
                                            child: Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: const BoxDecoration(
                                                color: Colors.deepPurple,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.camera_alt,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Profile Picture *',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _pickedImage == null
                                            ? Colors.red.shade700
                                            : Colors.grey.shade600,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 30),

                              // Form Fields
                              TextFormField(
                                controller: _fullNameController,
                                decoration: _buildInputDecoration(
                                  'Full Name',
                                  Icons.person_outline,
                                ),
                                validator: (val) {
                                  if (val == null || val.isEmpty) {
                                    return 'Required';
                                  }
                                  if (val.trim().length < 2) {
                                    return 'Name too short';
                                  }
                                  return null;
                                },
                              ),

                              // Duplicate Name Warning (For everyone)
                              if (_isDuplicateName) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.red.shade300,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        color: Colors.red.shade700,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'This name is already registered. Please use a different name.',
                                          style: TextStyle(
                                            color: Colors.red.shade900,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),

                              TextFormField(
                                controller: _emailController,
                                decoration: _buildInputDecoration(
                                  'Email',
                                  Icons.email_outlined,
                                ),
                                keyboardType: TextInputType.emailAddress,
                                validator: (val) {
                                  if (val == null || val.isEmpty) {
                                    return 'Required';
                                  }
                                  // Email format validation
                                  final emailRegex = RegExp(
                                    r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                                  );
                                  if (!emailRegex.hasMatch(val)) {
                                    return 'Enter valid email';
                                  }
                                  return null;
                                },
                              ),

                              // Duplicate Email Warning
                              if (_isDuplicateEmail) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: Colors.red.shade300,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        color: Colors.red.shade700,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'This email is already registered. Please use a different email.',
                                          style: TextStyle(
                                            color: Colors.red.shade900,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              if (_isCheckingDuplicate) ...[
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.deepPurple,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Checking availability...',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 16),

                              // Mobile Number Field
                              TextFormField(
                                controller: _mobileController,
                                decoration: _buildInputDecoration(
                                  'Mobile Number',
                                  Icons.phone_android,
                                ),
                                maxLength: 10,
                                buildCounter:
                                    (
                                      context, {
                                      required currentLength,
                                      required isFocused,
                                      required maxLength,
                                    }) => null,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                keyboardType: TextInputType.phone,
                                validator: (val) {
                                  if (val == null || val.isEmpty)
                                    return 'Required';
                                  if (val.length < 10) return 'Invalid number';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),

                              TextFormField(
                                controller: _passwordController,
                                obscureText: !_isPasswordVisible,
                                decoration:
                                    _buildInputDecoration(
                                      'Password',
                                      Icons.lock_outline,
                                    ).copyWith(
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _isPasswordVisible
                                              ? Icons.visibility
                                              : Icons.visibility_off,
                                          color: Colors.grey,
                                        ),
                                        onPressed: () => setState(
                                          () => _isPasswordVisible =
                                              !_isPasswordVisible,
                                        ),
                                      ),
                                    ),
                                validator: (val) =>
                                    val == null || val.length < 6
                                    ? 'Min 6 chars'
                                    : null,
                              ),
                              const SizedBox(height: 16),

                              _isLoadingData
                                  ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  : DropdownButtonFormField<String>(
                                      value: _selectedLocation,
                                      items: _locations.map((l) {
                                        return DropdownMenuItem<String>(
                                          value: l['name'] as String,
                                          child: Text(l['name'] as String),
                                        );
                                      }).toList(),
                                      onChanged: (val) => setState(
                                        () => _selectedLocation = val,
                                      ),
                                      decoration: _buildInputDecoration(
                                        'Location',
                                        Icons.location_on_outlined,
                                      ),
                                      validator: (val) =>
                                          val == null ? 'Required' : null,
                                    ),
                              const SizedBox(height: 8),

                              const SizedBox(height: 8),
                              // Only show map picker for Providers
                              if (_isProvider)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: _pickLocationOnMap,
                                    icon: const Icon(
                                      Icons.map,
                                      color: Colors.deepPurple,
                                    ),
                                    label: Text(
                                      _latitude != null
                                          ? 'Location Selected on Map ✅'
                                          : 'Pick Exact Location on Map',
                                      style: TextStyle(
                                        color: _latitude != null
                                            ? Colors.green
                                            : Colors.deepPurple,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 16),

                              // Terms and Conditions for Regular Users (Non-Providers)
                              if (!_isProvider) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.deepPurple.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _acceptedUserTerms
                                          ? Colors.deepPurple.shade200
                                          : Colors.red.shade200,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Checkbox(
                                            value: _acceptedUserTerms,
                                            onChanged: (val) {
                                              setState(() {
                                                _acceptedUserTerms =
                                                    val ?? false;
                                              });
                                            },
                                            activeColor: Colors.deepPurple,
                                          ),
                                          Expanded(
                                            child: GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  _acceptedUserTerms =
                                                      !_acceptedUserTerms;
                                                });
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 12,
                                                ),
                                                child: RichText(
                                                  text: TextSpan(
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      color: Colors.black87,
                                                    ),
                                                    children: [
                                                      const TextSpan(
                                                        text: 'I accept the ',
                                                      ),
                                                      TextSpan(
                                                        text:
                                                            'Terms and Conditions',
                                                        style: TextStyle(
                                                          color: Colors
                                                              .deepPurple
                                                              .shade700,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          decoration:
                                                              TextDecoration
                                                                  .underline,
                                                        ),
                                                      ),
                                                      const TextSpan(
                                                        text: ' *',
                                                        style: TextStyle(
                                                          color: Colors.red,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      TextButton.icon(
                                        onPressed: _showUserTermsDialog,
                                        icon: Icon(
                                          Icons.article_outlined,
                                          size: 18,
                                          color: Colors.deepPurple.shade700,
                                        ),
                                        label: Text(
                                          'Read Full Terms & Conditions',
                                          style: TextStyle(
                                            color: Colors.deepPurple.shade700,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],

                              if (!widget.isRoleLocked)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                    horizontal: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    color: Colors.grey.shade50,
                                  ),
                                  child: SwitchListTile(
                                    title: const Text(
                                      'Register as Service Provider',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    value: _isProvider,
                                    activeColor: Colors.deepPurple,
                                    contentPadding: EdgeInsets.zero,
                                    onChanged: (val) =>
                                        setState(() => _isProvider = val),
                                  ),
                                ),

                              if (_isProvider) ...[
                                const SizedBox(height: 16),
                                if (_isLoadingData)
                                  const CircularProgressIndicator()
                                else
                                  DropdownButtonFormField<String>(
                                    value: _selectedBusinessType,
                                    items: _services.map((s) {
                                      return DropdownMenuItem<String>(
                                        value: s['id'] as String,
                                        child: Text(s['name'] as String),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() {
                                          _selectedBusinessType = val;
                                          _selectedServiceType =
                                              null; // Reset sub-service when business type changes
                                        });
                                        _fetchSubServices(val);
                                      }
                                    },
                                    decoration: _buildInputDecoration(
                                      'Business Type',
                                      Icons.work_outline,
                                    ),
                                    validator: (val) =>
                                        _isProvider && val == null
                                        ? 'Required'
                                        : null,
                                  ),
                                const SizedBox(height: 16),

                                // Service Type Dropdown (Dependent)
                                if (_selectedBusinessType != null)
                                  _isLoadingSubServices
                                      ? const Center(
                                          child: CircularProgressIndicator(),
                                        )
                                      : DropdownButtonFormField<String>(
                                          value: _selectedServiceType,
                                          items: _subServices.map((sub) {
                                            return DropdownMenuItem<String>(
                                              value: sub['name'] as String,
                                              child: Text(
                                                sub['name'] as String,
                                              ),
                                            );
                                          }).toList(),
                                          onChanged: (val) {
                                            setState(() {
                                              _selectedServiceType = val;
                                            });
                                          },
                                          decoration: _buildInputDecoration(
                                            'Service Type',
                                            Icons.category_outlined,
                                          ),
                                          validator: (val) =>
                                              _isProvider && val == null
                                              ? 'Required'
                                              : null,
                                        ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _priceController,
                                  decoration: _buildInputDecoration(
                                    'Starting Price (₹)',
                                    Icons.currency_rupee,
                                  ),
                                  keyboardType: TextInputType.number,
                                  validator: (val) {
                                    if (_isProvider &&
                                        (val == null || val.isEmpty)) {
                                      return 'Required';
                                    }
                                    if (_isProvider &&
                                        double.tryParse(val!) == null) {
                                      return 'Enter valid amount';
                                    }
                                    if (_isProvider &&
                                        double.parse(val!) <= 0) {
                                      return 'Price must be greater than 0';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),

                                // Document Upload Section
                                const Text(
                                  'Provider Documents',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 12),

                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildDocUploadButton(
                                        'Aadhar Card',
                                        _aadharImage,
                                        _pickAadharImage,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _buildDocUploadButton(
                                        'Pan Card',
                                        _panImage,
                                        _pickPanImage,
                                      ),
                                    ),
                                  ],
                                ),
                              ],

                              // Terms and Conditions (Providers Only)
                              if (_isProvider) ...[
                                const SizedBox(height: 24),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.deepPurple.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _acceptedTerms
                                          ? Colors.deepPurple.shade200
                                          : Colors.red.shade200,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Checkbox(
                                            value: _acceptedTerms,
                                            onChanged: (val) {
                                              setState(() {
                                                _acceptedTerms = val ?? false;
                                              });
                                            },
                                            activeColor: Colors.deepPurple,
                                          ),
                                          Expanded(
                                            child: GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  _acceptedTerms =
                                                      !_acceptedTerms;
                                                });
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 12,
                                                ),
                                                child: RichText(
                                                  text: TextSpan(
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      color: Colors.black87,
                                                    ),
                                                    children: [
                                                      const TextSpan(
                                                        text: 'I accept the ',
                                                      ),
                                                      TextSpan(
                                                        text:
                                                            'Terms and Conditions',
                                                        style: TextStyle(
                                                          color: Colors
                                                              .deepPurple
                                                              .shade700,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          decoration:
                                                              TextDecoration
                                                                  .underline,
                                                        ),
                                                      ),
                                                      const TextSpan(
                                                        text:
                                                            ' for providers *',
                                                        style: TextStyle(
                                                          color: Colors.red,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      TextButton.icon(
                                        onPressed: _showTermsDialog,
                                        icon: Icon(
                                          Icons.article_outlined,
                                          size: 18,
                                          color: Colors.deepPurple.shade700,
                                        ),
                                        label: Text(
                                          'Read Full Terms & Conditions',
                                          style: TextStyle(
                                            color: Colors.deepPurple.shade700,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              const SizedBox(height: 30),

                              SizedBox(
                                height: 50,
                                child: _isLoading
                                    ? const Center(
                                        child: CircularProgressIndicator(),
                                      )
                                    : ElevatedButton(
                                        onPressed: _signup,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.deepPurple,
                                          foregroundColor: Colors.white,
                                          elevation: 2,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                        child: const Text(
                                          'CREATE ACCOUNT',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 1.5,
                                          ),
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDocUploadButton(
    String label,
    XFile? file,
    VoidCallback onPressed,
  ) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
          color: Colors.grey.shade50,
        ),
        child: file != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: kIsWeb
                    ? Image.network(file.path, fit: BoxFit.cover)
                    : Image.file(File(file.path), fit: BoxFit.cover),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.upload_file, color: Colors.deepPurple),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
      ),
    );
  }

  // Tab 1: Personal Info
  Widget _buildPersonalInfoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Personal Information',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Let\'s start with your basic details',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 24),

          // Error Message
          if (_errorMessage != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(
                _errorMessage!,
                style: TextStyle(color: Colors.red.shade800),
              ),
            ),

          // Profile Picture
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: _pickImage,
                  child: Stack(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _pickedImage == null
                                ? Colors.red.shade300
                                : Colors.deepPurple.shade200,
                            width: 3,
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 60,
                          backgroundColor: Colors.grey.shade100,
                          backgroundImage: _pickedImage != null
                              ? (kIsWeb
                                        ? NetworkImage(_pickedImage!.path)
                                        : FileImage(File(_pickedImage!.path)))
                                    as ImageProvider
                              : null,
                          child: _pickedImage == null
                              ? Icon(
                                  Icons.person,
                                  size: 60,
                                  color: Colors.grey.shade400,
                                )
                              : null,
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF1565C0).withOpacity(0.4),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Profile Picture *',
                  style: TextStyle(
                    fontSize: 14,
                    color: _pickedImage == null
                        ? Colors.red.shade700
                        : const Color(0xFF1565C0),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),

          // Full Name
          TextFormField(
            controller: _fullNameController,
            decoration: _buildInputDecoration(
              'Full Name',
              Icons.person_outline,
            ),
            validator: (val) {
              if (val == null || val.isEmpty) return 'Required';
              if (val.trim().length < 2) return 'Name too short';
              return null;
            },
          ),

          // Duplicate Name Warning
          if (_isDuplicateName) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade300),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Colors.red.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This name is already registered. Please use a different name.',
                      style: TextStyle(
                        color: Colors.red.shade900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Email
          TextFormField(
            controller: _emailController,
            decoration: _buildInputDecoration('Email', Icons.email_outlined),
            keyboardType: TextInputType.emailAddress,
            validator: (val) {
              if (val == null || val.isEmpty) return 'Required';
              final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
              if (!emailRegex.hasMatch(val)) return 'Enter valid email';
              return null;
            },
          ),

          // Duplicate Email Warning
          if (_isDuplicateEmail) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade300),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Colors.red.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This email is already registered.',
                      style: TextStyle(
                        color: Colors.red.shade900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_isCheckingDuplicate) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.deepPurple,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Checking availability...',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),

          // Mobile Number
          TextFormField(
            controller: _mobileController,
            decoration: _buildInputDecoration(
              'Mobile Number',
              Icons.phone_android,
            ),
            maxLength: 10,
            buildCounter:
                (
                  context, {
                  required currentLength,
                  required isFocused,
                  required maxLength,
                }) => null,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            keyboardType: TextInputType.phone,
            validator: (val) {
              if (val == null || val.isEmpty) return 'Required';
              if (val.length < 10) return 'Invalid number';
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Password
          TextFormField(
            controller: _passwordController,
            obscureText: !_isPasswordVisible,
            decoration: _buildInputDecoration('Password', Icons.lock_outline)
                .copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isPasswordVisible
                          ? Icons.visibility
                          : Icons.visibility_off,
                      color: Colors.grey,
                    ),
                    onPressed: () => setState(
                      () => _isPasswordVisible = !_isPasswordVisible,
                    ),
                  ),
                ),
            validator: (val) =>
                val == null || val.length < 6 ? 'Min 6 chars' : null,
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // Tab 2: Location & Bio
  Widget _buildLocationBioTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 28,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Location & Bio',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1565C0),
                    ),
                  ),
                  Text(
                    'Tell us where you operate and about yourself',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Location Dropdown
          _isLoadingData
              ? const Center(child: CircularProgressIndicator())
              : DropdownButtonFormField<String>(
                  value: _selectedLocation,
                  items: _locations.map((l) {
                    return DropdownMenuItem<String>(
                      value: l['name'] as String,
                      child: Text(l['name'] as String),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedLocation = val),
                  decoration: _buildInputDecoration(
                    'Location',
                    Icons.location_on_outlined,
                  ),
                  validator: (val) => val == null ? 'Required' : null,
                ),
          const SizedBox(height: 16),

          // Map Picker Button
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _pickLocationOnMap,
              icon: const Icon(Icons.map, color: Color(0xFF1565C0)),
              label: Text(
                _latitude != null
                    ? 'Location Selected on Map ✅'
                    : 'Pick Exact Location on Map',
                style: TextStyle(
                  color: _latitude != null
                      ? Colors.green.shade600
                      : const Color(0xFF1565C0),
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Bio
          TextFormField(
            controller: _bioController,
            decoration: _buildInputDecoration('Bio', Icons.info_outline),
            maxLines: 5,
            validator: (val) {
              if (val == null || val.isEmpty) return 'Required for providers';
              return null;
            },
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // Tab 3: Service Details
  Widget _buildServiceDetailsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 28,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Service Details',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1565C0),
                    ),
                  ),
                  Text(
                    'What services will you provide?',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Business Type
          _isLoadingData
              ? const CircularProgressIndicator()
              : DropdownButtonFormField<String>(
                  value: _selectedBusinessType,
                  items: _services.map((s) {
                    return DropdownMenuItem<String>(
                      value: s['id'] as String,
                      child: Text(s['name'] as String),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedBusinessType = val;
                        _selectedServiceType = null;
                      });
                      _fetchSubServices(val);
                    }
                  },
                  decoration: _buildInputDecoration(
                    'Business Type',
                    Icons.work_outline,
                  ),
                  validator: (val) => val == null ? 'Required' : null,
                ),
          const SizedBox(height: 16),

          // Service Type
          if (_selectedBusinessType != null)
            _isLoadingSubServices
                ? const Center(child: CircularProgressIndicator())
                : DropdownButtonFormField<String>(
                    value: _selectedServiceType,
                    items: _subServices.map((sub) {
                      return DropdownMenuItem<String>(
                        value: sub['name'] as String,
                        child: Text(sub['name'] as String),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedServiceType = val;
                      });
                    },
                    decoration: _buildInputDecoration(
                      'Service Type',
                      Icons.category_outlined,
                    ),
                    validator: (val) => val == null ? 'Required' : null,
                  ),
          const SizedBox(height: 16),

          // Starting Price
          TextFormField(
            controller: _priceController,
            decoration: _buildInputDecoration(
              'Starting Price (₹)',
              Icons.currency_rupee,
            ),
            keyboardType: TextInputType.number,
            validator: (val) {
              if (val == null || val.isEmpty) return 'Required';
              if (double.tryParse(val) == null) return 'Enter valid amount';
              if (double.parse(val) <= 0) return 'Price must be greater than 0';
              return null;
            },
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // Tab 4: Documents
  Widget _buildDocumentsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 28,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Provider Documents',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1565C0),
                    ),
                  ),
                  Text(
                    'Upload your identity documents',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Aadhar Card
          const Text(
            'Aadhar Card *',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          _buildDocUploadButton(
            'Upload Aadhar Card',
            _aadharImage,
            _pickAadharImage,
          ),
          const SizedBox(height: 24),

          // PAN Card
          const Text(
            'PAN Card *',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          _buildDocUploadButton('Upload PAN Card', _panImage, _pickPanImage),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // Tab 5: Review & Create Account
  Widget _buildReviewCreateTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 28,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Review & Create Account',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1565C0),
                    ),
                  ),
                  Text(
                    'Review your information and accept terms',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Summary Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Summary',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1565C0),
                  ),
                ),
                const Divider(),
                _buildReviewRow('Name', _fullNameController.text),
                _buildReviewRow('Email', _emailController.text),
                _buildReviewRow('Mobile', _mobileController.text),
                _buildReviewRow(
                  'Location',
                  _selectedLocation ?? 'Not selected',
                ),
                _buildReviewRow('Bio', _bioController.text),
                if (_selectedBusinessType != null)
                  _buildReviewRow(
                    'Business Type',
                    _services.firstWhere(
                      (s) => s['id'] == _selectedBusinessType,
                      orElse: () => {'name': 'N/A'},
                    )['name'],
                  ),
                _buildReviewRow(
                  'Service Type',
                  _selectedServiceType ?? 'Not selected',
                ),
                _buildReviewRow('Price', '₹${_priceController.text}'),
                _buildReviewRow(
                  'Profile Picture',
                  _pickedImage != null ? '✅ Uploaded' : '❌ Missing',
                ),
                _buildReviewRow(
                  'Aadhar Card',
                  _aadharImage != null ? '✅ Uploaded' : '❌ Missing',
                ),
                _buildReviewRow(
                  'PAN Card',
                  _panImage != null ? '✅ Uploaded' : '❌ Missing',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Terms & Conditions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _acceptedTerms
                    ? Colors.deepPurple.shade200
                    : Colors.red.shade200,
              ),
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: _acceptedTerms,
                      onChanged: (val) {
                        setState(() {
                          _acceptedTerms = val ?? false;
                        });
                      },
                      activeColor: const Color(0xFF1565C0),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _acceptedTerms = !_acceptedTerms;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.black87,
                              ),
                              children: [
                                const TextSpan(text: 'I accept the '),
                                TextSpan(
                                  text: 'Terms and Conditions',
                                  style: TextStyle(
                                    color: const Color(0xFF1565C0),
                                    fontWeight: FontWeight.bold,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                                const TextSpan(
                                  text: ' for providers *',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _showTermsDialog,
                  icon: const Icon(
                    Icons.article_outlined,
                    size: 18,
                    color: const Color(0xFF1565C0),
                  ),
                  label: const Text(
                    'Read Full Terms & Conditions',
                    style: TextStyle(
                      color: Color(0xFF1565C0),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // Helper for Review Rows
  Widget _buildReviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? 'Not provided' : value,
              style: TextStyle(
                color: value.isEmpty ? Colors.red.shade700 : Colors.black54,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
