-- Enable Realtime for the users table
-- This allows the SessionMonitor to listen for DELETE events in real-time

-- Enable realtime on the users table
ALTER PUBLICATION supabase_realtime ADD TABLE users;

-- Verify realtime is enabled (run this to check)
-- SELECT schemaname, tablename 
-- FROM pg_publication_tables 
-- WHERE pubname = 'supabase_realtime';
