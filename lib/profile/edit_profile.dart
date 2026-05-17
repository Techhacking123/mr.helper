import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/map_picker.dart';
import '../supabase_config.dart';

class EditProfilePage extends StatefulWidget {
  final Map<String, dynamic> userData;
  const EditProfilePage({super.key, required this.userData});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage>
    with SingleTickerProviderStateMixin {
  final _bioController = TextEditingController();
  final _priceController = TextEditingController();
  final _phoneController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  XFile? _pickedImage;
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;
  late bool _isProvider;

  double? _latitude;
  double? _longitude;

  // Animation
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Modern Color Palette
  final Color _primaryColor = const Color(0xFF6A11CB);
  final Color _backgroundColor = const Color(0xFFF4F6F8);

  @override
  void initState() {
    super.initState();
    _isProvider = widget.userData['is_provider'] == true;
    _bioController.text = widget.userData['bio'] ?? '';
    _priceController.text = widget.userData['price']?.toString() ?? '';
    _phoneController.text = widget.userData['phone_number'] ?? '';

    _latitude = widget.userData['latitude'];
    _longitude = widget.userData['longitude'];

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );

    _animationController.forward();
  }

  @override
  void dispose() {
    _bioController.dispose();
    _priceController.dispose();
    _phoneController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'Change Profile Photo',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSourceOption(
                    Icons.photo_library_rounded,
                    'Gallery',
                    () {
                      Navigator.pop(context);
                      _pickImageFromSource(ImageSource.gallery);
                    },
                  ),
                  _buildSourceOption(Icons.camera_alt_rounded, 'Camera', () {
                    Navigator.pop(context);
                    _pickImageFromSource(ImageSource.camera);
                  }),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSourceOption(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 100,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: _primaryColor, size: 28),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImageFromSource(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 60,
      );
      if (image != null) {
        setState(() => _pickedImage = image);
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  Future<void> _pickLocationOnMap() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            MapPicker(initialLat: _latitude, initialLng: _longitude),
      ),
    );

    if (result != null && result is Map) {
      setState(() {
        _latitude = result['lat'];
        _longitude = result['lng'];
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<String?> _uploadImage(String userId) async {
    if (_pickedImage == null) return null;

    try {
      final fileExt = _pickedImage!.name.split('.').last.toLowerCase();
      final fileName =
          '$userId-${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final filePath = fileName;

      String contentType = 'application/octet-stream';
      if (['jpg', 'jpeg'].contains(fileExt))
        contentType = 'image/jpeg';
      else if (fileExt == 'png')
        contentType = 'image/png';

      if (kIsWeb) {
        final bytes = await _pickedImage!.readAsBytes();
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
              File(_pickedImage!.path),
              fileOptions: FileOptions(contentType: contentType, upsert: true),
            );
      }
      return SupabaseConfig.supabase.storage
          .from('avatars')
          .getPublicUrl(filePath);
    } catch (e) {
      debugPrint('Image upload failed: $e');
      throw e;
    }
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final userId = widget.userData['id'];

      String? avatarUrl = widget.userData['avatar_url'];
      if (_pickedImage != null) {
        final newUrl = await _uploadImage(userId);
        if (newUrl != null) avatarUrl = newUrl;
      }

      final Map<String, dynamic> updates = {
        'phone_number': _phoneController.text.trim(),
        'avatar_url': avatarUrl,
        'latitude': _latitude,
        'longitude': _longitude,
      };

      // Only include bio for providers
      if (_isProvider) {
        updates['bio'] = _bioController.text.trim();
      }

      if (_isProvider) {
        updates['price'] = double.tryParse(_priceController.text.trim());
      }

      await SupabaseConfig.supabase
          .from('users')
          .update(updates)
          .eq('id', userId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.check_circle_rounded, color: Colors.white),
                SizedBox(width: 10),
                Text('Profile Updated Successfully'),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green.shade700,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          color: Colors.black87,
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Edit Profile',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: Column(
              children: [
                const SizedBox(height: 10),
                // Clean Centered Profile Picture
                Center(
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _primaryColor.withOpacity(0.2),
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 65,
                            backgroundColor: Colors.white,
                            backgroundImage: _pickedImage != null
                                ? (kIsWeb
                                          ? NetworkImage(_pickedImage!.path)
                                          : FileImage(File(_pickedImage!.path)))
                                      as ImageProvider
                                : (widget.userData['avatar_url'] != null
                                      ? NetworkImage(
                                          SupabaseConfig.proxyImageUrl(
                                            widget.userData['avatar_url'],
                                          ),
                                        )
                                      : null),
                            child:
                                (_pickedImage == null &&
                                    widget.userData['avatar_url'] == null)
                                ? Icon(
                                    Icons.person_rounded,
                                    size: 60,
                                    color: Colors.grey.shade300,
                                  )
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _pickImage,
                        style: TextButton.styleFrom(
                          foregroundColor: _primaryColor,
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: const Text('Change Profile Photo'),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 30),

                // Form Content
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInputLabel('Full Name'),
                      _buildReadOnlyField(
                        widget.userData['full_name'] ?? 'N/A',
                        Icons.person_outline,
                      ),
                      const SizedBox(height: 20),

                      _buildInputLabel('Phone Number'),
                      _buildEditableField(
                        controller: _phoneController,
                        hint: 'Enter phone number',
                        icon: Icons.phone_iphone_rounded,
                        keyboardType: TextInputType.phone,
                        validator: (val) {
                          if (val == null || val.isEmpty)
                            return 'Phone number is required';
                          if (val.length < 10) return 'Enter a valid number';
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      if (_isProvider) ...[
                        _buildInputLabel('Bio'),
                        _buildEditableField(
                          controller: _bioController,
                          hint: 'Tell us about yourself...',
                          icon: Icons.edit_note_rounded,
                          maxLines: 4,
                        ),
                        const SizedBox(height: 20),
                      ],

                      if (_isProvider) ...[
                        _buildInputLabel('Location'),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                height: 40,
                                child: OutlinedButton.icon(
                                  onPressed: _pickLocationOnMap,
                                  icon: const Icon(Icons.map, size: 18),
                                  label: Text(
                                    _latitude != null
                                        ? 'Update on Map'
                                        : 'Pick on Map',
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _primaryColor,
                                    side: BorderSide(
                                      color: _primaryColor.withOpacity(0.5),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Divider(height: 1),
                        const SizedBox(height: 24),
                        const SizedBox(height: 24),
                        _buildInputLabel('Hourly Rate (₹)'),
                        _buildEditableField(
                          controller: _priceController,
                          hint: '0.00',
                          icon: Icons.currency_rupee_rounded,
                          keyboardType: TextInputType.number,
                          validator: (val) {
                            if (val == null || val.isEmpty)
                              return 'Price is required';
                            if (double.tryParse(val) == null)
                              return 'Invalid price';
                            return null;
                          },
                        ),
                      ],
                      const SizedBox(height: 40),

                      // Save Button
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _saveChanges,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Save Profile',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 30),
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

  Widget _buildInputLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade700,
        ),
      ),
    );
  }

  Widget _buildReadOnlyField(String value, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey.shade500, size: 22),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.01),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        validator: validator,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: _primaryColor.withOpacity(0.6)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400),
        ),
      ),
    );
  }
}
