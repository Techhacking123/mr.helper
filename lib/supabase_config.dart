import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const String supabaseUrl =
      'https://supabase-deep.phoenixsoftwaresolutions172.workers.dev';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ2cnBzcWRyYndmdmxsZWx5cWhmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUxNTgxOTksImV4cCI6MjA4MDczNDE5OX0.ON2ioqbNJegKOWeGu_eqsgjNxQ6IdHCDuFRqjUfBYHk';

  // Service role key for admin operations (bypasses RLS)
  // TODO: Replace with your actual service role key from Supabase Dashboard > Settings > API
  static const String supabaseServiceRoleKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ2cnBzcWRyYndmdmxsZWx5cWhmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NTE1ODE5OSwiZXhwIjoyMDgwNzM0MTk5fQ.GyckF5tq300NJmV-invzTOLo-eBlv2U9AOoiMJtkMXc';

  static Future<void> initialize() async {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  }

  static final supabase = Supabase.instance.client;

  // Admin client with service role (bypasses RLS for admin operations)
  static SupabaseClient get adminClient {
    return SupabaseClient(supabaseUrl, supabaseServiceRoleKey);
  }

  /// Rewrites old direct Supabase storage URLs to go through the Cloudflare Worker proxy.
  /// Use this when displaying images whose URLs are already stored in the database
  /// with the old `rvrpsqdrbwfvllelyqhf.supabase.co` domain.
  static const String _oldSupabaseUrl =
      'https://rvrpsqdrbwfvllelyqhf.supabase.co';

  static String proxyImageUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.contains(_oldSupabaseUrl)) {
      return url.replaceFirst(_oldSupabaseUrl, supabaseUrl);
    }
    return url;
  }
}
