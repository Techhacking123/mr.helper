import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:file_picker/file_picker.dart';
import '../models/festival_theme.dart';
import '../services/theme_service.dart';
import '../supabase_config.dart';

class ThemeFormPage extends StatefulWidget {
  final FestivalTheme? existingTheme;

  const ThemeFormPage({super.key, this.existingTheme});

  @override
  State<ThemeFormPage> createState() => _ThemeFormPageState();
}

class _ThemeFormPageState extends State<ThemeFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();

  Color _primaryColor = const Color(0xFF1976D2);
  Color _secondaryColor = const Color(0xFF42A5F5);
  Color _accentColor = const Color(0xFFFF5722);

  File? _selectedImageFile;
  String? _existingImageUrl;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingTheme != null) {
      _titleController.text = widget.existingTheme!.displayName;
      _primaryColor = widget.existingTheme!.primaryColor;
      _secondaryColor = widget.existingTheme!.secondaryColor;
      _accentColor = widget.existingTheme!.accentColor;
      _existingImageUrl = widget.existingTheme!.bannerImageUrl;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'gif'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedImageFile = File(result.files.single.path!);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<String?> _uploadImageToSupabase(
    File imageFile,
    String themeName,
  ) async {
    try {
      // Debug: Check authentication status
      final user = SupabaseConfig.supabase.auth.currentUser;
      debugPrint('🔐 Upload attempt - User authenticated: ${user != null}');
      if (user != null) {
        debugPrint('📧 User email: ${user.email}');
        debugPrint('🆔 User ID: ${user.id}');
        debugPrint('📋 User metadata: ${user.userMetadata}');
      } else {
        debugPrint('❌ No authenticated user found!');
      }

      final extension = imageFile.path.split('.').last.toLowerCase();
      final fileName =
          'theme_banners/${themeName}_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final bytes = await imageFile.readAsBytes();

      debugPrint('📤 Uploading to theme-assets bucket: $fileName');
      debugPrint('📦 File size: ${bytes.length} bytes');

      await SupabaseConfig.adminClient.storage
          .from('theme-assets')
          .uploadBinary(fileName, bytes);

      final publicUrl = SupabaseConfig.adminClient.storage
          .from('theme-assets')
          .getPublicUrl(fileName);

      debugPrint('✅ Upload successful: $publicUrl');
      return publicUrl;
    } catch (e) {
      debugPrint('❌ Error uploading image: $e');
      debugPrint('Error type: ${e.runtimeType}');
      return null;
    }
  }

  Future<void> _deleteImageFromSupabase(String imageUrl) async {
    try {
      // Extract file path from URL
      final uri = Uri.parse(imageUrl);
      final pathSegments = uri.pathSegments;
      final fileName = pathSegments
          .sublist(pathSegments.indexOf('theme-assets') + 1)
          .join('/');

      await SupabaseConfig.adminClient.storage.from('theme-assets').remove([
        fileName,
      ]);
    } catch (e) {
      debugPrint('Error deleting image: $e');
    }
  }

  void _showColorPicker(
    String colorType,
    Color currentColor,
    Function(Color) onColorChanged,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Pick $colorType Color'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ColorPicker(
                pickerColor: currentColor,
                onColorChanged: onColorChanged,
                pickerAreaHeightPercent: 0.8,
              ),
              const SizedBox(height: 16),
              // Color code input
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Hex Color Code',
                  hintText: '#RRGGBB',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  if (value.startsWith('#') && value.length == 7) {
                    try {
                      final color = Color(
                        int.parse(value.substring(1), radix: 16) + 0xFF000000,
                      );
                      onColorChanged(color);
                    } catch (e) {
                      // Invalid color code
                    }
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveTheme() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedImageFile == null && _existingImageUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a banner image'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      String? imageUrl = _existingImageUrl;

      // Upload new image if selected
      if (_selectedImageFile != null) {
        final themeName = _titleController.text.trim().toLowerCase().replaceAll(
          ' ',
          '_',
        );
        imageUrl = await _uploadImageToSupabase(_selectedImageFile!, themeName);

        if (imageUrl == null) {
          throw Exception('Failed to upload image');
        }

        // Delete old image if updating
        if (_existingImageUrl != null &&
            _existingImageUrl!.contains('supabase')) {
          await _deleteImageFromSupabase(_existingImageUrl!);
        }
      }

      final theme = FestivalTheme(
        id:
            widget.existingTheme?.id ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        name: _titleController.text.trim().toLowerCase().replaceAll(' ', '_'),
        displayName: _titleController.text.trim(),
        description: 'Custom festival theme',
        isActive: false,
        priority: 99,
        primaryColor: _primaryColor,
        secondaryColor: _secondaryColor,
        accentColor: _accentColor,
        backgroundColor: const Color(0xFFF5F5F5),
        textColor: const Color(0xFF212121),
        cardColor: const Color(0xFFFFFFFF),
        bannerImageUrl: imageUrl,
        iconPack: const {},
        decorativeElements: const [],
        createdAt: widget.existingTheme?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final themeService = ThemeService();
      bool success;

      if (widget.existingTheme != null) {
        success = await themeService.updateTheme(theme);
      } else {
        success = await themeService.createTheme(theme);
      }

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.existingTheme != null
                  ? 'Theme updated successfully!'
                  : 'Theme created successfully!',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      } else {
        throw Exception('Failed to save theme');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existingTheme != null ? 'Edit Theme' : 'Create Theme',
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1976D2), Color(0xFF42A5F5)],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Title Input
                    TextFormField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        labelText: 'Theme Title',
                        hintText: 'e.g., Diwali, Christmas',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(Icons.title),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a theme title';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 24),

                    // Banner Image Section
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Banner Image',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_selectedImageFile != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  _selectedImageFile!,
                                  height: 150,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              )
                            else if (_existingImageUrl != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: _existingImageUrl!.startsWith('http')
                                    ? Image.network(
                                        SupabaseConfig.proxyImageUrl(
                                          _existingImageUrl!,
                                        ),
                                        height: 150,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                      )
                                    : Image.asset(
                                        _existingImageUrl!,
                                        height: 150,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                      ),
                              )
                            else
                              Container(
                                height: 150,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.image,
                                    size: 64,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: _pickImage,
                              icon: const Icon(Icons.upload),
                              label: Text(
                                _selectedImageFile != null ||
                                        _existingImageUrl != null
                                    ? 'Change Image'
                                    : 'Upload Image',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Color Pickers Section
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Theme Colors',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Primary Color
                            _buildColorSelector(
                              'Primary Color',
                              _primaryColor,
                              (color) => setState(() => _primaryColor = color),
                            ),
                            const SizedBox(height: 12),

                            // Secondary Color
                            _buildColorSelector(
                              'Secondary Color',
                              _secondaryColor,
                              (color) =>
                                  setState(() => _secondaryColor = color),
                            ),
                            const SizedBox(height: 12),

                            // Accent Color
                            _buildColorSelector(
                              'Accent Color',
                              _accentColor,
                              (color) => setState(() => _accentColor = color),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Save Button
                    ElevatedButton(
                      onPressed: _saveTheme,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        widget.existingTheme != null
                            ? 'Update Theme'
                            : 'Create Theme',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildColorSelector(
    String label,
    Color color,
    Function(Color) onColorChanged,
  ) {
    return InkWell(
      onTap: () => _showColorPicker(label, color, onColorChanged),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade400),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    '#${color.value.toRadixString(16).substring(2).toUpperCase()}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            const Icon(Icons.edit, color: Colors.blue),
          ],
        ),
      ),
    );
  }
}
