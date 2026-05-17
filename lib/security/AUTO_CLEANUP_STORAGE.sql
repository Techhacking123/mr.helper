-- ============================================
-- AUTOMATIC STORAGE CLEANUP TRIGGERS
-- ============================================
-- This script creates database triggers to automatically
-- delete images from Supabase storage when:
-- 1. An ad is deleted or expires
-- 2. A user/provider account is deleted
-- ============================================

-- ============================================
-- 1. CLEANUP AD IMAGES ON DELETE
-- ============================================

-- Function to delete ad image from storage when ad is deleted
CREATE OR REPLACE FUNCTION cleanup_ad_image()
RETURNS TRIGGER AS $$
DECLARE
  image_path TEXT;
  bucket_name TEXT := 'ads';
BEGIN
  -- Extract the image filename from the full URL
  -- URL format: https://[PROJECT].supabase.co/storage/v1/object/public/ads/[filename]
  IF OLD.image_url IS NOT NULL AND OLD.image_url != '' THEN
    -- Extract just the filename from the URL
    -- Split by '/' and get the last part
    image_path := substring(OLD.image_url from '[^/]+$');
    
    -- Delete from storage using the storage.objects table
    -- Note: This requires the postgres role to have access to storage schema
    DELETE FROM storage.objects 
    WHERE bucket_id = bucket_name 
    AND name = image_path;
    
    RAISE NOTICE 'Deleted ad image from storage: %', image_path;
  END IF;
  
  RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger for ad deletion
DROP TRIGGER IF EXISTS trigger_cleanup_ad_image ON ads;
CREATE TRIGGER trigger_cleanup_ad_image
  BEFORE DELETE ON ads
  FOR EACH ROW
  EXECUTE FUNCTION cleanup_ad_image();

COMMENT ON FUNCTION cleanup_ad_image() IS 'Automatically deletes ad image from storage when ad is deleted';
COMMENT ON TRIGGER trigger_cleanup_ad_image ON ads IS 'Triggers automatic cleanup of ad images on deletion';

-- ============================================
-- 2. CLEANUP EXPIRED ADS (Scheduled Job)
-- ============================================

-- Function to delete expired ads and their images
CREATE OR REPLACE FUNCTION cleanup_expired_ads()
RETURNS void AS $$
DECLARE
  expired_count INTEGER;
BEGIN
  -- Delete expired ads (the trigger will handle image cleanup)
  WITH deleted AS (
    DELETE FROM ads
    WHERE end_date < NOW()
    AND is_active = false
    RETURNING id
  )
  SELECT COUNT(*) INTO expired_count FROM deleted;
  
  RAISE NOTICE 'Cleaned up % expired ads', expired_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION cleanup_expired_ads() IS 'Deletes expired ads and triggers automatic image cleanup';

-- Note: To run this automatically, you would need to set up a cron job
-- Example using pg_cron extension:
-- SELECT cron.schedule('cleanup-expired-ads', '0 2 * * *', 'SELECT cleanup_expired_ads()');

-- ============================================
-- 3. CLEANUP USER/PROVIDER AVATAR ON DELETE
-- ============================================

-- Function to delete user avatar from storage when user is deleted
CREATE OR REPLACE FUNCTION cleanup_user_avatar()
RETURNS TRIGGER AS $$
DECLARE
  avatar_path TEXT;
  bucket_name TEXT := 'avatars';
BEGIN
  -- Extract the avatar filename from the full URL
  IF OLD.avatar_url IS NOT NULL AND OLD.avatar_url != '' THEN
    -- Extract just the filename from the URL
    avatar_path := substring(OLD.avatar_url from '[^/]+$');
    
    -- Delete from storage
    DELETE FROM storage.objects 
    WHERE bucket_id = bucket_name 
    AND name = avatar_path;
    
    RAISE NOTICE 'Deleted user avatar from storage: % (User: %)', avatar_path, OLD.full_name;
  END IF;
  
  RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger for user deletion
DROP TRIGGER IF EXISTS trigger_cleanup_user_avatar ON users;
CREATE TRIGGER trigger_cleanup_user_avatar
  BEFORE DELETE ON users
  FOR EACH ROW
  EXECUTE FUNCTION cleanup_user_avatar();

COMMENT ON FUNCTION cleanup_user_avatar() IS 'Automatically deletes user/provider avatar from storage when account is deleted';
COMMENT ON TRIGGER trigger_cleanup_user_avatar ON users IS 'Triggers automatic cleanup of user avatars on account deletion';

-- ============================================
-- 4. MANUAL CLEANUP FUNCTION (Optional)
-- ============================================

-- Function to manually cleanup orphaned images
CREATE OR REPLACE FUNCTION cleanup_orphaned_images()
RETURNS TABLE(bucket TEXT, filename TEXT, action TEXT) AS $$
BEGIN
  -- This is a placeholder for manual cleanup
  -- You can extend this to find and remove orphaned images
  
  RETURN QUERY
  SELECT 
    'ads'::TEXT as bucket,
    name::TEXT as filename,
    'Would delete'::TEXT as action
  FROM storage.objects
  WHERE bucket_id = 'ads'
  AND name NOT IN (
    SELECT substring(image_url from '[^/]+$')
    FROM ads
    WHERE image_url IS NOT NULL
  );
  
  RETURN QUERY
  SELECT 
    'avatars'::TEXT as bucket,
    name::TEXT as filename,
    'Would delete'::TEXT as action
  FROM storage.objects
  WHERE bucket_id = 'avatars'
  AND name NOT IN (
    SELECT substring(avatar_url from '[^/]+$')
    FROM users
    WHERE avatar_url IS NOT NULL
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION cleanup_orphaned_images() IS 'Lists orphaned images that can be manually cleaned up';

-- ============================================
-- 5. VERIFICATION QUERIES
-- ============================================

-- Check if triggers are created
SELECT 
  trigger_name,
  event_manipulation,
  event_object_table,
  action_statement
FROM information_schema.triggers
WHERE trigger_name IN (
  'trigger_cleanup_ad_image',
  'trigger_cleanup_user_avatar'
)
ORDER BY event_object_table, trigger_name;

-- ============================================
-- USAGE INSTRUCTIONS
-- ============================================

/*
=== AUTOMATIC CLEANUP ===

1. AD IMAGE CLEANUP:
   - Trigger: Runs automatically when an ad is deleted
   - DELETE FROM ads WHERE id = 'some-id';
   - The image will be automatically removed from storage

2. EXPIRED ADS CLEANUP:
   - Manual: SELECT cleanup_expired_ads();
   - This will delete all expired inactive ads
   - Images will be automatically cleaned up via trigger

3. USER/PROVIDER AVATAR CLEANUP:
   - Trigger: Runs automatically when a user is deleted
   - DELETE FROM users WHERE id = 'some-id';
   - The avatar will be automatically removed from storage

=== MANUAL CLEANUP ===

To find orphaned images (images without database references):
   SELECT * FROM cleanup_orphaned_images();

To manually delete orphaned images, you would need to:
   1. Run the cleanup_orphaned_images() function
   2. Manually delete the files from storage bucket

=== TESTING ===

1. Test ad image cleanup:
   -- Create a test ad with image
   INSERT INTO ads (title, image_url, end_date, is_active)
   VALUES ('Test Ad', 'https://your-project.supabase.co/storage/v1/object/public/ads/test.jpg', NOW() + INTERVAL '1 day', true);
   
   -- Delete it (image should be cleaned up)
   DELETE FROM ads WHERE title = 'Test Ad';
   
   -- Check storage.objects to confirm deletion

2. Test user avatar cleanup:
   -- Delete a test user
   DELETE FROM users WHERE id = 'test-user-id';
   
   -- Check storage.objects to verify avatar deletion

=== IMPORTANT NOTES ===

1. The SECURITY DEFINER allows these functions to access storage.objects
2. Triggers run BEFORE DELETE so we can still access OLD.image_url
3. For expired ads, you can set up a cron job or run manually
4. Orphaned image cleanup is informational only - manual deletion required
5. Make sure the storage buckets exist: 'ads' and 'avatars'

*/

-- ============================================
-- END OF SCRIPT
-- ============================================

-- Final verification
SELECT 'Automatic storage cleanup triggers installed successfully!' AS status;
