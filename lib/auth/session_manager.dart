import 'package:shared_preferences/shared_preferences.dart';
import '../firebase/fcm_service.dart';

class SessionManager {
  static const String keyUserId = 'user_id';
  static const String keyUsername = 'username';
  static const String keyRole = 'role';
  static const String keyIsLoggedIn = 'is_logged_in';

  static Future<void> saveUserSession(
    String userId,
    String username,
    String role,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyUserId, userId);
    await prefs.setString(keyUsername, username);
    await prefs.setString(keyRole, role);
    await prefs.setBool(keyIsLoggedIn, true);
  }

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyIsLoggedIn) ?? false;
  }

  static Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyRole);
  }

  static Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyUsername);
  }

  static Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyUserId);
  }

  static Future<void> clearSession() async {
    // IMPORTANT: Clear FCM token from database BEFORE clearing session
    // This prevents notifications from being sent to this device after logout
    await FCMService.clearTokenForCurrentUser();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyUserId);
    await prefs.remove(keyUsername);
    await prefs.remove(keyRole);
    await prefs.remove(keyIsLoggedIn);
    // Do NOT clear 'hasSeenOnboarding' or other app-wide settings
  }
}
