import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';

class AdminAdsPage extends StatefulWidget {
  const AdminAdsPage({super.key});

  @override
  State<AdminAdsPage> createState() => _AdminAdsPageState();
}

class _AdminAdsPageState extends State<AdminAdsPage> {
  List<Map<String, dynamic>> _ads = [];
  bool _isLoading = true;

  late final RealtimeChannel _subscription;

  @override
  void initState() {
    super.initState();
    _fetchAds();
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    SupabaseConfig.supabase.removeChannel(_subscription);
    super.dispose();
  }

  void _subscribeToRealtime() {
    _subscription = SupabaseConfig.supabase.channel('admin_ads_list');
    _subscription
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'ads',
          callback: (payload) => _fetchAds(),
        )
        .subscribe();
  }

  Future<void> _fetchAds() async {
    try {
      final response = await SupabaseConfig.supabase
          .from('ads')
          .select()
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _ads = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching ads: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteAd(String adId) async {
    try {
      // 1. Fetch ad details to get image URL for deletion
      final data = await SupabaseConfig.adminClient
          .from('ads')
          .select('image_url')
          .eq('id', adId)
          .maybeSingle();

      if (data != null && data['image_url'] != null) {
        final String imageUrl = data['image_url'];
        // Check if it's a supabase storage URL
        if (imageUrl.contains('/storage/v1/object/public/ads/')) {
          final fileName = imageUrl.split('/ads/').last;
          if (fileName.isNotEmpty) {
            await SupabaseConfig.adminClient.storage.from('ads').remove([
              fileName,
            ]);
          }
        }
      }

      // 2. Delete the record
      await SupabaseConfig.adminClient.from('ads').delete().eq('id', adId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ad deleted successfully')),
        );
        _fetchAds();
      }
    } catch (e) {
      debugPrint('Error deleting ad: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _showAddAdDialog() {
    showDialog(context: context, builder: (_) => const AddAdDialog()).then((
      val,
    ) {
      if (val == true) _fetchAds();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Ads'),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _showAddAdDialog),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _ads.isEmpty
          ? const Center(child: Text('No ads found. Create one!'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _ads.length,
              itemBuilder: (context, index) {
                final ad = _ads[index];
                final isActive = ad['is_active'] == true;
                final endDate = DateTime.parse(ad['end_date']);
                final isExpired = DateTime.now().isAfter(endDate);

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (ad['image_url'] != null)
                        Image.network(
                          SupabaseConfig.proxyImageUrl(ad['image_url']),
                          height: 150,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                                height: 150,
                                color: Colors.grey.shade300,
                                child: const Icon(Icons.broken_image),
                              ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  ad['title'] ?? 'Untitled',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Chip(
                                  label: Text(
                                    isExpired
                                        ? 'Expired'
                                        : (isActive ? 'Active' : 'Hidden'),
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  backgroundColor: isExpired
                                      ? Colors.red
                                      : (isActive ? Colors.green : Colors.grey),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text('Ends: ${DateFormat.yMMMd().format(endDate)}'),
                            if (ad['link'] != null)
                              Text(
                                'Link: ${ad['link']}',
                                style: const TextStyle(color: Colors.blue),
                              ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _deleteAd(ad['id']),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class AddAdDialog extends StatefulWidget {
  const AddAdDialog({super.key});

  @override
  State<AddAdDialog> createState() => _AddAdDialogState();
}

class _AddAdDialogState extends State<AddAdDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _imageUrlController = TextEditingController();
  final _linkController = TextEditingController();
  DateTime _endDate = DateTime.now().add(const Duration(days: 7));
  bool _isLoading = false;
  File? _imageFile;

  Future<void> _pickImage() async {
    // 1. Unfocus to dismiss keyboard and avoid RenderObject errors
    FocusScope.of(context).unfocus();

    // 2. Wait for keyboard dismissal and layout stabilization
    await Future.delayed(const Duration(milliseconds: 300));

    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (pickedFile != null && mounted) {
        debugPrint('Image picked directly: ${pickedFile.path}');

        // 3. Small delay to ensure we are not in the middle of a frame
        await Future.delayed(const Duration(milliseconds: 100));

        if (mounted) {
          setState(() {
            _imageFile = File(pickedFile.path);
            _imageUrlController.clear();
          });
        }
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_imageFile == null && _imageUrlController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide an image URL or pick a file'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      String finalImageUrl = _imageUrlController.text.trim();

      if (_imageFile != null) {
        final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';

        await SupabaseConfig.adminClient.storage
            .from('ads')
            .upload(
              fileName,
              _imageFile!,
              fileOptions: const FileOptions(
                cacheControl: '3600',
                upsert: false,
              ),
            );

        finalImageUrl = SupabaseConfig.adminClient.storage
            .from('ads')
            .getPublicUrl(fileName);
      }

      await SupabaseConfig.adminClient.from('ads').insert({
        'title': _titleController.text.trim(),
        'image_url': finalImageUrl,
        'link': _linkController.text.trim(),
        'start_date': DateTime.now().toIso8601String(),
        'end_date': _endDate.toIso8601String(),
        'is_active': true,
      });

      if (mounted) {
        Navigator.pop(context, true);
        return; // Important: Exit before finally block tries to use context
      }
    } catch (e) {
      debugPrint('Error creating ad: $e');
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
    return AlertDialog(
      title: const Text('Create New Ad'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 10),

              // Image Preview - Fixed with SizedBox (LayoutBuilder doesn't work in AlertDialog)
              if (_imageFile != null)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 150,
                      width:
                          280, // Fixed width - avoids intrinsic calculation issues
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey.shade200,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(
                                _imageFile!,
                                key: ValueKey(_imageFile!.path),
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  debugPrint('Image display error: $error');
                                  return Container(
                                    color: Colors.grey.shade300,
                                    child: const Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.broken_image,
                                            color: Colors.red,
                                            size: 40,
                                          ),
                                          SizedBox(height: 8),
                                          Text(
                                            'Could not display image',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.red,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                              Positioned(
                                right: 4,
                                top: 4,
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: IconButton(
                                    iconSize: 18,
                                    padding: const EdgeInsets.all(4),
                                    constraints: const BoxConstraints(),
                                    icon: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                    ),
                                    onPressed: () {
                                      setState(() => _imageFile = null);
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, color: Colors.green, size: 16),
                        SizedBox(width: 4),
                        Text(
                          'Image selected successfully ✓',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.image),
                      label: const Text('Pick Image'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Center(child: Text('OR')),
              const SizedBox(height: 10),

              TextFormField(
                controller: _imageUrlController,
                decoration: const InputDecoration(
                  labelText: 'Image URL (Optional if file picked)',
                  hintText: 'https://example.com/image.png',
                ),
                // Validator logic handled manually in _submit
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _linkController,
                decoration: const InputDecoration(labelText: 'Target Link'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Expires: '),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _endDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setState(() => _endDate = picked);
                      }
                    },
                    child: Text(DateFormat.yMMMd().format(_endDate)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Publish'),
        ),
      ],
    );
  }
}
