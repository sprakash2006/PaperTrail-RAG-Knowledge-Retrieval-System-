-- ─────────────────────────────────────────────────────────────
-- PaperTrail — Seed the 4 demo auth users
-- RUN ORDER: after 002_seed_demo_org.sql, before the two 003_* files.
--
-- Inserting into auth.users fires the handle_new_user() trigger
-- (from 001_initial_schema.sql), which auto-creates each profiles row
-- with org_id / full_name / role pulled from raw_user_meta_data.
--
-- All four users share the password:  Password123!
-- Emails are pre-confirmed so you can log in immediately.
-- ─────────────────────────────────────────────────────────────

-- pgcrypto provides crypt() / gen_salt() for password hashing.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1) auth.users — the identities that the trigger turns into profiles
INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data,
    is_super_admin, confirmation_token, recovery_token,
    email_change_token_new, email_change
)
VALUES
    -- Arjun — Director
    ('00000000-0000-0000-0000-000000000000',
     'b0000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
     'arjun@ignisia.com', crypt('Password123!', gen_salt('bf')),
     now(), now(), now(),
     '{"provider":"email","providers":["email"]}',
     '{"org_id":"a0000000-0000-0000-0000-000000000001","full_name":"Arjun","role":"director"}',
     false, '', '', '', ''),

    -- Meera — Manager
    ('00000000-0000-0000-0000-000000000000',
     'b0000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
     'meera@ignisia.com', crypt('Password123!', gen_salt('bf')),
     now(), now(), now(),
     '{"provider":"email","providers":["email"]}',
     '{"org_id":"a0000000-0000-0000-0000-000000000001","full_name":"Meera","role":"manager"}',
     false, '', '', '', ''),

    -- Priya — Employee
    ('00000000-0000-0000-0000-000000000000',
     'b0000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
     'priya@ignisia.com', crypt('Password123!', gen_salt('bf')),
     now(), now(), now(),
     '{"provider":"email","providers":["email"]}',
     '{"org_id":"a0000000-0000-0000-0000-000000000001","full_name":"Priya","role":"employee"}',
     false, '', '', '', ''),

    -- Rahul — Employee
    ('00000000-0000-0000-0000-000000000000',
     'b0000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated',
     'rahul@ignisia.com', crypt('Password123!', gen_salt('bf')),
     now(), now(), now(),
     '{"provider":"email","providers":["email"]}',
     '{"org_id":"a0000000-0000-0000-0000-000000000001","full_name":"Rahul","role":"employee"}',
     false, '', '', '', '')
ON CONFLICT (id) DO NOTHING;

-- 2) auth.identities — required for email/password login to work
INSERT INTO auth.identities (
    id, user_id, provider_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
)
SELECT
    u.id, u.id, u.id::text,
    jsonb_build_object('sub', u.id::text, 'email', u.email),
    'email', now(), now(), now()
FROM auth.users u
WHERE u.id IN (
    'b0000000-0000-0000-0000-000000000001',
    'b0000000-0000-0000-0000-000000000002',
    'b0000000-0000-0000-0000-000000000003',
    'b0000000-0000-0000-0000-000000000004'
)
ON CONFLICT (provider_id, provider) DO NOTHING;
