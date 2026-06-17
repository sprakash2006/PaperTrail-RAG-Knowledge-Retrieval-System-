-- ════════════════════════════════════════════════════════════════════════════
--  Ignisia26 — FULL CLEANUP / TEARDOWN
-- ════════════════════════════════════════════════════════════════════════════
--  Paste this in the Supabase SQL Editor and run it to wipe everything this
--  project created (tables, functions, triggers, policies, storage, demo users).
--  Afterwards, run 0000_complete_setup.sql to rebuild from scratch.
--
--  Safe to run even if some objects are already gone (IF EXISTS everywhere).
-- ════════════════════════════════════════════════════════════════════════════

-- 1) Remove the auth trigger FIRST so deleting/recreating users can't re-fire it.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- 2) Storage: drop our policies. (We do NOT delete storage.objects/buckets
--    directly — Supabase blocks that with a protect_delete() trigger. The
--    bucket is harmless and the rebuild re-uses it via ON CONFLICT DO NOTHING.
--    To actually remove uploaded files, empty the "documents" bucket from the
--    dashboard Storage UI.)
DROP POLICY IF EXISTS "Users can upload documents"            ON storage.objects;
DROP POLICY IF EXISTS "Users can read documents in their org" ON storage.objects;

-- 3) Drop all application tables (CASCADE clears their indexes, policies, FKs).
DROP TABLE IF EXISTS ticket_notes  CASCADE;
DROP TABLE IF EXISTS tickets       CASCADE;
DROP TABLE IF EXISTS audit_log     CASCADE;
DROP TABLE IF EXISTS email_configs CASCADE;
DROP TABLE IF EXISTS messages      CASCADE;
DROP TABLE IF EXISTS conversations CASCADE;
DROP TABLE IF EXISTS chunks        CASCADE;
DROP TABLE IF EXISTS documents     CASCADE;
DROP TABLE IF EXISTS profiles      CASCADE;
DROP TABLE IF EXISTS organizations CASCADE;

-- 4) Drop our functions.
DROP FUNCTION IF EXISTS handle_new_user()                                     CASCADE;
DROP FUNCTION IF EXISTS match_chunks(vector, int, float, uuid, uuid)          CASCADE;
DROP FUNCTION IF EXISTS get_all_subordinates(uuid)                            CASCADE;
DROP FUNCTION IF EXISTS update_updated_at()                                   CASCADE;

-- 5) Delete the demo + test auth users we created.
--    (Their auth.identities rows cascade automatically.)
DELETE FROM auth.users
WHERE email IN (
    'arjun@ignisia.com',
    'meera@ignisia.com',
    'priya@ignisia.com',
    'rahul@ignisia.com',
    'triggertest@example.com',
    'manualtest@example.com'
);

-- OPTIONAL — wipe EVERY auth user (uncomment for a totally blank auth table).
-- Only do this if you have no real accounts you want to keep.
-- DELETE FROM auth.users;

-- ════════════════════════════════════════════════════════════════════════════
--  Cleanup complete. Now run 0000_complete_setup.sql.
-- ════════════════════════════════════════════════════════════════════════════
