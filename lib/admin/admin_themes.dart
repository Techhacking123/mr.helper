import 'package:flutter/material.dart';
import '../models/festival_theme.dart';
import '../services/theme_service.dart';
import '../supabase_config.dart';
import 'theme_form_page.dart';

class AdminThemesPage extends StatefulWidget {
  const AdminThemesPage({super.key});

  @override
  State<AdminThemesPage> createState() => _AdminThemesPageState();
}

class _AdminThemesPageState extends State<AdminThemesPage> {
  final ThemeService _themeService = ThemeService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadThemes();
  }

  Future<void> _loadThemes() async {
    setState(() => _isLoading = true);
    await _themeService.fetchAllThemes();
    setState(() => _isLoading = false);
  }

  Future<void> _toggleTheme(FestivalTheme theme) async {
    final newState = !theme.isActive;

    debugPrint('👆 AdminThemes: Toggle requested for ${theme.displayName}');
    debugPrint('👆 AdminThemes: Theme ID: ${theme.id}');
    debugPrint(
      '👆 AdminThemes: Current state: ${theme.isActive}, New state: $newState',
    );

    // Show loading dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    bool success;
    if (newState) {
      // Activate this theme
      debugPrint('👆 AdminThemes: Calling activateTheme...');
      success = await _themeService.activateTheme(theme.id);
    } else {
      // Deactivate (fall back to default)
      debugPrint('👆 AdminThemes: Calling deactivateAllThemes...');
      success = await _themeService.deactivateAllThemes();
    }

    debugPrint('👆 AdminThemes: Operation success: $success');

    if (!mounted) return;
    Navigator.of(context).pop(); // Close loading dialog

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newState
                ? '${theme.displayName} theme activated!'
                : 'Switched to default theme',
          ),
          backgroundColor: Colors.green,
        ),
      );
      await _loadThemes();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update theme'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _fixAssetPaths() async {
    try {
      debugPrint('🔧 Fixing asset paths...');

      // Fix Sankranti banner extension
      await SupabaseConfig.adminClient
          .from('festival_themes')
          .update({'banner_image_url': 'assets/themes/sankranti_banner.jpg'})
          .eq('name', 'sankranti');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Asset paths fixed successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      await _loadThemes();
    } catch (e) {
      debugPrint('❌ Error fixing asset paths: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteTheme(FestivalTheme theme) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange.shade700, size: 28),
            const SizedBox(width: 12),
            const Text('Delete Theme'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete "${theme.displayName}"?',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.red.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'This will also delete all related images from storage.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Show loading dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Delete image from storage if it's a Supabase URL
      if (theme.bannerImageUrl != null &&
          theme.bannerImageUrl!.contains('supabase')) {
        try {
          final uri = Uri.parse(theme.bannerImageUrl!);
          final pathSegments = uri.pathSegments;
          final fileName = pathSegments
              .sublist(pathSegments.indexOf('theme-assets') + 1)
              .join('/');

          await SupabaseConfig.adminClient.storage.from('theme-assets').remove([
            fileName,
          ]);

          debugPrint('🗑️ Deleted image: $fileName');
        } catch (e) {
          debugPrint('⚠️ Error deleting image: $e');
        }
      }

      // Delete theme from database
      final success = await _themeService.deleteTheme(theme.id);

      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading dialog

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${theme.displayName} deleted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadThemes();
      } else {
        throw Exception('Failed to delete theme');
      }
    } catch (e) {
      debugPrint('❌ Error deleting theme: $e');
      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading dialog

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Festival Themes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.build),
            tooltip: 'Fix Asset Paths',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Fix Asset Paths'),
                  content: const Text(
                    'This will fix any incorrect asset file extensions in the database. Continue?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _fixAssetPaths();
                      },
                      child: const Text('Fix Now'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
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
          : RefreshIndicator(onRefresh: _loadThemes, child: _buildThemeList()),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ThemeFormPage()),
          );
          if (result == true) {
            await _loadThemes();
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Create Theme'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Widget _buildThemeList() {
    final themes = _themeService.allThemes;

    if (themes.isEmpty) {
      return const Center(child: Text('No themes available'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: themes.length,
      itemBuilder: (context, index) {
        final theme = themes[index];
        return _buildThemeCard(theme);
      },
    );
  }

  Widget _buildThemeCard(FestivalTheme theme) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: theme.isActive ? 8 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.isActive ? theme.primaryColor : Colors.grey.shade300,
          width: theme.isActive ? 2 : 1,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: theme.isActive
              ? LinearGradient(
                  colors: [
                    theme.primaryColor.withOpacity(0.1),
                    theme.secondaryColor.withOpacity(0.05),
                  ],
                )
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with title and status
              Row(
                children: [
                  // Theme icon/preview
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        colors: [theme.primaryColor, theme.secondaryColor],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: theme.isActive
                        ? const Icon(
                            Icons.check_circle,
                            color: Colors.white,
                            size: 30,
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),

                  // Theme info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              theme.displayName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (theme.isActive) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'ACTIVE',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (theme.description != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            theme.description!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Toggle switch
                  Switch(
                    value: theme.isActive,
                    onChanged: theme.name == 'default'
                        ? null // Can't disable default theme directly
                        : (_) => _toggleTheme(theme),
                    activeColor: theme.primaryColor,
                  ),
                ],
              ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),

              // Color palette
              Row(
                children: [
                  const Text(
                    'Colors:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 12),
                  _buildColorCircle(theme.primaryColor, 'Primary'),
                  const SizedBox(width: 8),
                  _buildColorCircle(theme.secondaryColor, 'Secondary'),
                  const SizedBox(width: 8),
                  _buildColorCircle(theme.accentColor, 'Accent'),
                ],
              ),

              // Banner preview (if available)
              if (theme.bannerImageUrl != null) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    height: 80,
                    decoration: BoxDecoration(color: Colors.grey.shade200),
                    child: Image.asset(
                      theme.bannerImageUrl!,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.grey.shade300,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.image_not_supported,
                                  color: Colors.grey.shade600,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Banner not found',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],

              // Decorative elements count
              if (theme.decorativeElements.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 14,
                      color: theme.accentColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${theme.decorativeElements.length} decorative elements',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],

              // Actions Row
              if (theme.name != 'default') ...[
                const SizedBox(height: 12),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ThemeFormPage(existingTheme: theme),
                          ),
                        );
                        if (result == true) {
                          await _loadThemes();
                        }
                      },
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('Edit'),
                      style: TextButton.styleFrom(foregroundColor: Colors.blue),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => _deleteTheme(theme),
                      icon: const Icon(Icons.delete, size: 18),
                      label: const Text('Delete'),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColorCircle(Color color, String label) {
    return Tooltip(
      message: label,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }
}
