import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_config.dart';
import '../models/festival_theme.dart';

class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();

  FestivalTheme? _activeTheme;
  List<FestivalTheme> _allThemes = [];
  bool _isLoading = false;
  RealtimeChannel? _themeSubscription;

  FestivalTheme? get activeTheme => _activeTheme;
  List<FestivalTheme> get allThemes => _allThemes;
  bool get isLoading => _isLoading;

  // Default theme fallback
  FestivalTheme get defaultTheme => FestivalTheme(
    id: 'default',
    name: 'default',
    displayName: 'Default',
    description: 'Default app theme',
    isActive: true,
    priority: 0,
    primaryColor: const Color(0xFF1976D2),
    secondaryColor: const Color(0xFF42A5F5),
    accentColor: const Color(0xFFFF5722),
    backgroundColor: const Color(0xFFF5F5F5),
    textColor: const Color(0xFF212121),
    cardColor: const Color(0xFFFFFFFF),
    iconPack: const {},
    decorativeElements: const [],
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  /// Initialize theme service and load active theme
  Future<void> initialize() async {
    await fetchActiveTheme();
    await fetchAllThemes();
    _subscribeToThemeChanges();
  }

  /// Fetch the active theme from database
  Future<void> fetchActiveTheme() async {
    try {
      _isLoading = true;
      notifyListeners();

      debugPrint('🎨 ThemeService: Fetching active theme...');
      final response = await SupabaseConfig.supabase
          .from('festival_themes')
          .select()
          .eq('is_active', true)
          .maybeSingle();

      if (response != null) {
        _activeTheme = FestivalTheme.fromJson(response);
        debugPrint(
          '🎨 ThemeService: Active theme loaded: ${_activeTheme!.displayName}',
        );
        debugPrint(
          '🎨 ThemeService: Banner URL: ${_activeTheme!.bannerImageUrl}',
        );
      } else {
        // If no active theme, use default
        _activeTheme = defaultTheme;
        debugPrint('🎨 ThemeService: No active theme found, using default');
      }
    } catch (e) {
      debugPrint('Error fetching active theme: $e');
      _activeTheme = defaultTheme;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fetch all themes
  Future<void> fetchAllThemes() async {
    try {
      final response = await SupabaseConfig.supabase
          .from('festival_themes')
          .select()
          .order('priority', ascending: true);

      _allThemes = (response as List)
          .map((theme) => FestivalTheme.fromJson(theme))
          .toList();

      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching all themes: $e');
    }
  }

  /// Subscribe to real-time theme changes
  void _subscribeToThemeChanges() {
    _themeSubscription?.unsubscribe();

    _themeSubscription = SupabaseConfig.supabase
        .channel('festival_themes_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'festival_themes',
          callback: (payload) {
            debugPrint('Theme changed: ${payload.eventType}');
            fetchActiveTheme();
            fetchAllThemes();
          },
        )
        .subscribe();
  }

  /// Activate a theme (admin only)
  Future<bool> activateTheme(String themeId) async {
    try {
      debugPrint('🔧 ThemeService: Activating theme ID: $themeId');

      // Update the theme to active
      final response = await SupabaseConfig.supabase
          .from('festival_themes')
          .update({'is_active': true})
          .eq('id', themeId)
          .select();

      debugPrint('🔧 ThemeService: Update response: $response');

      // Refresh active theme
      await fetchActiveTheme();
      await fetchAllThemes();

      debugPrint('🔧 ThemeService: Theme activated successfully!');
      return true;
    } catch (e, stackTrace) {
      debugPrint('❌ Error activating theme: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      return false;
    }
  }

  /// Deactivate all themes (admin only) - falls back to default
  Future<bool> deactivateAllThemes() async {
    try {
      await SupabaseConfig.supabase
          .from('festival_themes')
          .update({'is_active': false})
          .neq('name', 'default'); // Keep default as is

      // Activate default theme
      await SupabaseConfig.supabase
          .from('festival_themes')
          .update({'is_active': true})
          .eq('name', 'default');

      await fetchActiveTheme();
      return true;
    } catch (e) {
      debugPrint('Error deactivating themes: $e');
      return false;
    }
  }

  /// Create a new theme (admin only)
  Future<bool> createTheme(FestivalTheme theme) async {
    try {
      final themeJson = theme.toJson();
      // Remove id to let database generate UUID
      themeJson.remove('id');

      await SupabaseConfig.supabase.from('festival_themes').insert(themeJson);

      await fetchAllThemes();
      return true;
    } catch (e) {
      debugPrint('Error creating theme: $e');
      return false;
    }
  }

  /// Update a theme (admin only)
  Future<bool> updateTheme(FestivalTheme theme) async {
    try {
      await SupabaseConfig.supabase
          .from('festival_themes')
          .update(theme.toJson())
          .eq('id', theme.id);

      await fetchAllThemes();
      if (theme.isActive) {
        await fetchActiveTheme();
      }
      return true;
    } catch (e) {
      debugPrint('Error updating theme: $e');
      return false;
    }
  }

  /// Delete a theme (admin only)
  Future<bool> deleteTheme(String themeId) async {
    try {
      await SupabaseConfig.supabase
          .from('festival_themes')
          .delete()
          .eq('id', themeId);

      await fetchAllThemes();
      return true;
    } catch (e) {
      debugPrint('Error deleting theme: $e');
      return false;
    }
  }

  /// Dispose subscriptions
  @override
  void dispose() {
    _themeSubscription?.unsubscribe();
    super.dispose();
  }

  /// Get theme by name
  FestivalTheme? getThemeByName(String name) {
    try {
      return _allThemes.firstWhere((theme) => theme.name == name);
    } catch (e) {
      return null;
    }
  }

  /// Check if a specific theme is active
  bool isThemeActive(String themeName) {
    return _activeTheme?.name == themeName;
  }
}
