import '../supabase_config.dart';

/// One-time utility script to fix the Sankranti banner file extension
/// Run this once to update the database from .jpeg to .jpg
Future<void> fixSankrantiBanner() async {
  try {
    print('🔧 Initializing Supabase...');
    await SupabaseConfig.initialize();

    print('🔧 Updating Sankranti banner URL...');
    final response = await SupabaseConfig.supabase
        .from('festival_themes')
        .update({'banner_image_url': 'assets/themes/sankranti_banner.jpg'})
        .eq('name', 'sankranti')
        .select();

    print('✅ Success! Updated: $response');
    print('🔧 Banner URL has been corrected from .jpeg to .jpg');
  } catch (e, stackTrace) {
    print('❌ Error fixing banner: $e');
    print('Stack trace: $stackTrace');
  }
}

void main() async {
  await fixSankrantiBanner();
}
