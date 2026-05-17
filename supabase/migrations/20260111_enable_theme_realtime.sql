-- Enable real-time for festival_themes table
BEGIN;
  -- Check if publication exists and add table to it
  DO $$
  BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE festival_themes;
    ELSE
      CREATE PUBLICATION supabase_realtime FOR TABLE festival_themes;
    END IF;
  EXCEPTION
    WHEN duplicate_object THEN
      -- Table might already be in publication
      NULL;
  END $$;
COMMIT;
