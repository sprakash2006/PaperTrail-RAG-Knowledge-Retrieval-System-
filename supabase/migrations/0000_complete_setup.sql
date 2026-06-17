-- ════════════════════════════════════════════════════════════════════════════
--  Ignisia26 — COMPLETE DATABASE SETUP (single migration)
-- ════════════════════════════════════════════════════════════════════════════
--  Run this ONE file on a fresh Supabase project to create everything:
--  extensions, tables, indexes, functions, RLS policies, triggers, the storage
--  bucket, and the demo seed data (org + 4 demo users + sample documents/chats).
--
--  It supersedes the older split files (001_initial_schema, 002/003 seeds,
--  0025_seed_demo_auth_users). Use EITHER this file OR those — not both.
--
--  Idempotent: safe to run more than once (IF NOT EXISTS / ON CONFLICT /
--  DROP ... IF EXISTS guards throughout).
--
--  Demo login (all 4 users):  password  Password123!
--    arjun@ignisia.com  (director)
--    meera@ignisia.com  (manager,  reports to Arjun)
--    priya@ignisia.com  (employee, reports to Meera)
--    rahul@ignisia.com  (employee, reports to Meera)
--
--  To create a clean DB WITHOUT demo data, delete everything below the
--  "SECTION 9 — DEMO SEED DATA" banner.
-- ════════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────
-- SECTION 1 — Extensions
-- ─────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "vector";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";   -- crypt()/gen_salt() for demo passwords


-- ─────────────────────────────────────────────────────────────
-- SECTION 2 — Tables
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS organizations (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name        TEXT NOT NULL,
    slug        TEXT UNIQUE NOT NULL,
    created_at  TIMESTAMPTZ DEFAULT now(),
    updated_at  TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS profiles (
    id              UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    org_id          UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    full_name       TEXT NOT NULL,
    role            TEXT NOT NULL CHECK (role IN ('director', 'manager', 'employee')),
    reports_to      UUID REFERENCES profiles(id) ON DELETE SET NULL,
    email           TEXT,
    avatar_url      TEXT,
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_profiles_org        ON profiles(org_id);
CREATE INDEX IF NOT EXISTS idx_profiles_reports_to ON profiles(reports_to);
CREATE INDEX IF NOT EXISTS idx_profiles_role       ON profiles(role);

CREATE TABLE IF NOT EXISTS documents (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id          UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    owner_id        UUID REFERENCES profiles(id) ON DELETE SET NULL,
    filename        TEXT NOT NULL,
    file_type       TEXT NOT NULL,
    file_size_bytes BIGINT,
    visibility      TEXT NOT NULL DEFAULT 'shared' CHECK (visibility IN ('shared', 'private')),
    source_type     TEXT NOT NULL DEFAULT 'upload' CHECK (source_type IN ('upload', 'email')),
    storage_path    TEXT,
    chunk_count     INT DEFAULT 0,
    status          TEXT NOT NULL DEFAULT 'processing' CHECK (status IN ('processing', 'ready', 'failed')),
    error_message   TEXT,
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_documents_org    ON documents(org_id);
CREATE INDEX IF NOT EXISTS idx_documents_owner  ON documents(owner_id);
CREATE INDEX IF NOT EXISTS idx_documents_status ON documents(status);

CREATE TABLE IF NOT EXISTS chunks (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    document_id     UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    org_id          UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    content         TEXT NOT NULL,
    embedding       vector(384),
    page_number     INT DEFAULT 1,
    line_number     INT DEFAULT 1,
    section         TEXT DEFAULT '',
    date_added      DATE,
    token_count     INT,
    chunk_index     INT NOT NULL,
    created_at      TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_chunks_document ON chunks(document_id);
CREATE INDEX IF NOT EXISTS idx_chunks_org      ON chunks(org_id);
CREATE INDEX IF NOT EXISTS idx_chunks_embedding ON chunks
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);

CREATE TABLE IF NOT EXISTS conversations (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id          UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    title           TEXT DEFAULT 'New Conversation',
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_conversations_user ON conversations(user_id);

CREATE TABLE IF NOT EXISTS messages (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    role            TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
    content         TEXT NOT NULL,
    sources         JSONB DEFAULT '[]'::jsonb,
    analysis        JSONB DEFAULT '{}'::jsonb,
    created_at      TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_messages_created      ON messages(created_at);

CREATE TABLE IF NOT EXISTS email_configs (
    id                 UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id            UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    org_id             UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    imap_server        TEXT NOT NULL,
    email_address      TEXT NOT NULL,
    encrypted_password TEXT NOT NULL,
    folder             TEXT DEFAULT 'INBOX',
    is_active          BOOLEAN DEFAULT true,
    last_polled_at     TIMESTAMPTZ,
    created_at         TIMESTAMPTZ DEFAULT now(),
    updated_at         TIMESTAMPTZ DEFAULT now(),
    UNIQUE(user_id)
);

CREATE TABLE IF NOT EXISTS audit_log (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id          UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    user_id         UUID REFERENCES profiles(id) ON DELETE SET NULL,
    action          TEXT NOT NULL,
    details         JSONB DEFAULT '{}'::jsonb,
    created_at      TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_audit_org     ON audit_log(org_id);
CREATE INDEX IF NOT EXISTS idx_audit_user    ON audit_log(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_action  ON audit_log(action);
CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_log(created_at);

-- Customer-support ticketing (used by backend/routers/tickets.py)
CREATE TABLE IF NOT EXISTS tickets (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    org_id          UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
    customer_name   TEXT NOT NULL,
    customer_email  TEXT NOT NULL,
    customer_phone  TEXT,
    subject         TEXT NOT NULL,
    query           TEXT NOT NULL,
    category        TEXT,
    priority        TEXT DEFAULT 'medium',
    status          TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'resolved', 'closed')),
    raised_by       UUID REFERENCES profiles(id) ON DELETE SET NULL,
    is_logged_in    BOOLEAN DEFAULT false,
    assigned_to     UUID REFERENCES profiles(id) ON DELETE SET NULL,
    ai_response     TEXT,
    email_body      TEXT,
    resolved_by     UUID REFERENCES profiles(id) ON DELETE SET NULL,
    resolved_at     TIMESTAMPTZ,
    email_sent      BOOLEAN DEFAULT false,
    email_sent_at   TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT now(),
    updated_at      TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_tickets_org    ON tickets(org_id);
CREATE INDEX IF NOT EXISTS idx_tickets_status ON tickets(status);

CREATE TABLE IF NOT EXISTS ticket_notes (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    ticket_id   UUID NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
    user_id     UUID REFERENCES profiles(id) ON DELETE SET NULL,
    content     TEXT NOT NULL,
    created_at  TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ticket_notes_ticket ON ticket_notes(ticket_id);


-- ─────────────────────────────────────────────────────────────
-- SECTION 3 — Functions
-- ─────────────────────────────────────────────────────────────

-- Recursively resolve everyone who (transitively) reports to a manager.
CREATE OR REPLACE FUNCTION get_all_subordinates(manager_id UUID)
RETURNS SETOF UUID
LANGUAGE sql
STABLE
AS $$
    WITH RECURSIVE subordinates AS (
        SELECT id FROM profiles WHERE reports_to = manager_id
        UNION ALL
        SELECT p.id FROM profiles p
        INNER JOIN subordinates s ON p.reports_to = s.id
    )
    SELECT id FROM subordinates;
$$;

-- Cosine-similarity vector search WITH built-in RBAC.
CREATE OR REPLACE FUNCTION match_chunks(
    query_embedding  vector(384),
    match_count      INT DEFAULT 15,
    match_threshold  FLOAT DEFAULT 0.3,
    p_org_id         UUID DEFAULT NULL,
    p_user_id        UUID DEFAULT NULL
)
RETURNS TABLE (
    id              UUID,
    document_id     UUID,
    content         TEXT,
    page_number     INT,
    line_number     INT,
    section         TEXT,
    date_added      DATE,
    similarity      FLOAT,
    filename        TEXT,
    file_type       TEXT,
    owner_id        UUID,
    visibility      TEXT
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    user_role TEXT;
BEGIN
    SELECT p.role INTO user_role FROM profiles p WHERE p.id = p_user_id;

    RETURN QUERY
    SELECT
        c.id,
        c.document_id,
        c.content,
        c.page_number,
        c.line_number,
        c.section,
        c.date_added,
        1 - (c.embedding <=> query_embedding) AS similarity,
        d.filename,
        d.file_type,
        d.owner_id,
        d.visibility
    FROM chunks c
    JOIN documents d ON c.document_id = d.id
    WHERE c.org_id = p_org_id
      AND d.status = 'ready'
      AND 1 - (c.embedding <=> query_embedding) > match_threshold
      AND (
          d.visibility = 'shared'
          OR d.owner_id = p_user_id
          OR user_role = 'director'
          OR (user_role = 'manager' AND d.owner_id IN (SELECT get_all_subordinates(p_user_id)))
      )
    ORDER BY c.embedding <=> query_embedding
    LIMIT match_count;
END;
$$;

-- Bump updated_at on row update.
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Auto-provision a profile whenever a new auth.users row is created.
--   * SECURITY DEFINER + fixed search_path so it runs with the owner's rights
--     when fired by the auth service (supabase_auth_admin), not just postgres.
--   * org_id falls back to the demo org if the signup sent no/empty org_id,
--     so the NOT NULL + FK can never abort the signup transaction.
--   * role falls back to a valid value (avoids the CHECK constraint).
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_org_id UUID;
    v_role   TEXT;
BEGIN
    v_org_id := COALESCE(
        NULLIF(NEW.raw_user_meta_data->>'org_id', '')::UUID,
        'a0000000-0000-0000-0000-000000000001'   -- demo org fallback
    );

    v_role := COALESCE(NULLIF(NEW.raw_user_meta_data->>'role', ''), 'employee');
    IF v_role NOT IN ('director', 'manager', 'employee') THEN
        v_role := 'employee';
    END IF;

    INSERT INTO public.profiles (id, org_id, full_name, role, email)
    VALUES (
        NEW.id,
        v_org_id,
        COALESCE(NULLIF(NEW.raw_user_meta_data->>'full_name', ''), NEW.email),
        v_role,
        NEW.email
    )
    ON CONFLICT (id) DO NOTHING;   -- never double-insert / abort the tx

    RETURN NEW;
END;
$$;

-- The auth service runs as supabase_auth_admin; make sure it can reach the
-- schema/table the trigger writes to (a common cause of "Database error
-- saving new user").
GRANT USAGE ON SCHEMA public TO supabase_auth_admin;
GRANT INSERT, SELECT, UPDATE ON public.profiles TO supabase_auth_admin;


-- ─────────────────────────────────────────────────────────────
-- SECTION 4 — Triggers
-- ─────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS tr_organizations_updated ON organizations;
CREATE TRIGGER tr_organizations_updated BEFORE UPDATE ON organizations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP TRIGGER IF EXISTS tr_profiles_updated ON profiles;
CREATE TRIGGER tr_profiles_updated BEFORE UPDATE ON profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP TRIGGER IF EXISTS tr_documents_updated ON documents;
CREATE TRIGGER tr_documents_updated BEFORE UPDATE ON documents
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP TRIGGER IF EXISTS tr_email_configs_updated ON email_configs;
CREATE TRIGGER tr_email_configs_updated BEFORE UPDATE ON email_configs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP TRIGGER IF EXISTS tr_conversations_updated ON conversations;
CREATE TRIGGER tr_conversations_updated BEFORE UPDATE ON conversations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP TRIGGER IF EXISTS tr_tickets_updated ON tickets;
CREATE TRIGGER tr_tickets_updated BEFORE UPDATE ON tickets
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION handle_new_user();


-- ─────────────────────────────────────────────────────────────
-- SECTION 5 — Row-Level Security
-- ─────────────────────────────────────────────────────────────
ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles      ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents     ENABLE ROW LEVEL SECURITY;
ALTER TABLE chunks        ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages      ENABLE ROW LEVEL SECURITY;
ALTER TABLE email_configs ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log     ENABLE ROW LEVEL SECURITY;
ALTER TABLE tickets       ENABLE ROW LEVEL SECURITY;
ALTER TABLE ticket_notes  ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their organization" ON organizations;
CREATE POLICY "Users can view their organization"
    ON organizations FOR SELECT
    USING (id IN (SELECT org_id FROM profiles WHERE profiles.id = auth.uid()));

DROP POLICY IF EXISTS "Users can view profiles in their org" ON profiles;
CREATE POLICY "Users can view profiles in their org"
    ON profiles FOR SELECT
    USING (org_id IN (SELECT org_id FROM profiles WHERE profiles.id = auth.uid()));

DROP POLICY IF EXISTS "Users can update their own profile" ON profiles;
CREATE POLICY "Users can update their own profile"
    ON profiles FOR UPDATE
    USING (id = auth.uid())
    WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS "Users can view accessible documents" ON documents;
CREATE POLICY "Users can view accessible documents"
    ON documents FOR SELECT
    USING (
        org_id IN (SELECT org_id FROM profiles WHERE profiles.id = auth.uid())
        AND (
            visibility = 'shared'
            OR owner_id = auth.uid()
            OR (SELECT role FROM profiles WHERE id = auth.uid()) = 'director'
            OR (
                (SELECT role FROM profiles WHERE id = auth.uid()) = 'manager'
                AND owner_id IN (SELECT get_all_subordinates(auth.uid()))
            )
        )
    );

DROP POLICY IF EXISTS "Users can insert documents in their org" ON documents;
CREATE POLICY "Users can insert documents in their org"
    ON documents FOR INSERT
    WITH CHECK (org_id IN (SELECT org_id FROM profiles WHERE profiles.id = auth.uid()));

DROP POLICY IF EXISTS "Users can delete their own documents" ON documents;
CREATE POLICY "Users can delete their own documents"
    ON documents FOR DELETE
    USING (owner_id = auth.uid() OR (SELECT role FROM profiles WHERE id = auth.uid()) = 'director');

DROP POLICY IF EXISTS "Users can view chunks of accessible documents" ON chunks;
CREATE POLICY "Users can view chunks of accessible documents"
    ON chunks FOR SELECT
    USING (document_id IN (SELECT id FROM documents));

DROP POLICY IF EXISTS "Users can insert chunks in their org" ON chunks;
CREATE POLICY "Users can insert chunks in their org"
    ON chunks FOR INSERT
    WITH CHECK (org_id IN (SELECT org_id FROM profiles WHERE profiles.id = auth.uid()));

DROP POLICY IF EXISTS "Users can manage their own conversations" ON conversations;
CREATE POLICY "Users can manage their own conversations"
    ON conversations FOR ALL
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can manage messages in their conversations" ON messages;
CREATE POLICY "Users can manage messages in their conversations"
    ON messages FOR ALL
    USING (conversation_id IN (SELECT id FROM conversations WHERE user_id = auth.uid()))
    WITH CHECK (conversation_id IN (SELECT id FROM conversations WHERE user_id = auth.uid()));

DROP POLICY IF EXISTS "Users can manage their own email config" ON email_configs;
CREATE POLICY "Users can manage their own email config"
    ON email_configs FOR ALL
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can view relevant audit logs" ON audit_log;
CREATE POLICY "Users can view relevant audit logs"
    ON audit_log FOR SELECT
    USING (
        user_id = auth.uid()
        OR (SELECT role FROM profiles WHERE id = auth.uid()) = 'director'
    );

DROP POLICY IF EXISTS "System can insert audit logs" ON audit_log;
CREATE POLICY "System can insert audit logs"
    ON audit_log FOR INSERT
    WITH CHECK (org_id IN (SELECT org_id FROM profiles WHERE profiles.id = auth.uid()));

-- Tickets are written/served by the backend via the service-role key (which
-- bypasses RLS); these SELECT policies cover any direct authenticated access.
DROP POLICY IF EXISTS "Users can view tickets in their org" ON tickets;
CREATE POLICY "Users can view tickets in their org"
    ON tickets FOR SELECT
    USING (org_id IN (SELECT org_id FROM profiles WHERE profiles.id = auth.uid()));

DROP POLICY IF EXISTS "Users can view notes for their org tickets" ON ticket_notes;
CREATE POLICY "Users can view notes for their org tickets"
    ON ticket_notes FOR SELECT
    USING (ticket_id IN (
        SELECT id FROM tickets
        WHERE org_id IN (SELECT org_id FROM profiles WHERE profiles.id = auth.uid())
    ));


-- ─────────────────────────────────────────────────────────────
-- SECTION 6 — Storage bucket + policies
-- ─────────────────────────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public)
VALUES ('documents', 'documents', false)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Users can upload documents" ON storage.objects;
CREATE POLICY "Users can upload documents"
    ON storage.objects FOR INSERT
    WITH CHECK (
        bucket_id = 'documents'
        AND (storage.foldername(name))[1] IN (
            SELECT org_id::text FROM profiles WHERE id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Users can read documents in their org" ON storage.objects;
CREATE POLICY "Users can read documents in their org"
    ON storage.objects FOR SELECT
    USING (
        bucket_id = 'documents'
        AND (storage.foldername(name))[1] IN (
            SELECT org_id::text FROM profiles WHERE id = auth.uid()
        )
    );


-- ════════════════════════════════════════════════════════════════════════════
-- SECTION 9 — DEMO SEED DATA   (delete everything below for a clean, empty DB)
-- ════════════════════════════════════════════════════════════════════════════

-- 9.1 — Demo organization
INSERT INTO organizations (id, name, slug)
VALUES ('a0000000-0000-0000-0000-000000000001', 'Ignisia Demo', 'ignisia-demo')
ON CONFLICT (slug) DO NOTHING;

-- 9.2 — Demo auth users (inserting into auth.users fires handle_new_user(),
--        which auto-creates each profiles row). Password: Password123!
INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data,
    is_super_admin, confirmation_token, recovery_token,
    email_change_token_new, email_change
)
VALUES
    ('00000000-0000-0000-0000-000000000000',
     'b0000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
     'arjun@ignisia.com', crypt('Password123!', gen_salt('bf')),
     now(), now(), now(),
     '{"provider":"email","providers":["email"]}',
     '{"org_id":"a0000000-0000-0000-0000-000000000001","full_name":"Arjun","role":"director"}',
     false, '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000',
     'b0000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
     'meera@ignisia.com', crypt('Password123!', gen_salt('bf')),
     now(), now(), now(),
     '{"provider":"email","providers":["email"]}',
     '{"org_id":"a0000000-0000-0000-0000-000000000001","full_name":"Meera","role":"manager"}',
     false, '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000',
     'b0000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
     'priya@ignisia.com', crypt('Password123!', gen_salt('bf')),
     now(), now(), now(),
     '{"provider":"email","providers":["email"]}',
     '{"org_id":"a0000000-0000-0000-0000-000000000001","full_name":"Priya","role":"employee"}',
     false, '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000',
     'b0000000-0000-0000-0000-000000000004', 'authenticated', 'authenticated',
     'rahul@ignisia.com', crypt('Password123!', gen_salt('bf')),
     now(), now(), now(),
     '{"provider":"email","providers":["email"]}',
     '{"org_id":"a0000000-0000-0000-0000-000000000001","full_name":"Rahul","role":"employee"}',
     false, '', '', '', '')
ON CONFLICT (id) DO NOTHING;

-- auth.identities — required for email/password login to work
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

-- 9.3 — Org hierarchy (reports_to)
UPDATE profiles SET reports_to = (SELECT id FROM profiles WHERE email = 'arjun@ignisia.com')
WHERE email = 'meera@ignisia.com';
UPDATE profiles SET reports_to = (SELECT id FROM profiles WHERE email = 'meera@ignisia.com')
WHERE email IN ('priya@ignisia.com', 'rahul@ignisia.com');

-- 9.4 — Sample documents (metadata only; includes processing/failed states)
INSERT INTO documents (id, org_id, owner_id, filename, file_type, file_size_bytes, visibility, source_type, chunk_count, status)
VALUES
  ('ddd00000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', NULL,
   'Company_Policy_Handbook_2025.pdf', 'pdf', 2458000, 'shared', 'upload', 47, 'ready'),
  ('ddd00000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', NULL,
   'Employee_Benefits_Summary.docx', 'docx', 384000, 'shared', 'upload', 18, 'ready'),
  ('ddd00000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', NULL,
   'Q1_2025_Revenue_Report.xlsx', 'xlsx', 712000, 'shared', 'upload', 32, 'ready'),
  ('ddd00000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', NULL,
   'Product_Roadmap_H1_2025.pdf', 'pdf', 1890000, 'shared', 'upload', 25, 'ready'),
  ('ddd00000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000001',
   (SELECT id FROM profiles WHERE email = 'priya@ignisia.com'),
   'Priya_Performance_Review_Q4.pdf', 'pdf', 156000, 'private', 'upload', 8, 'ready'),
  ('ddd00000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000001',
   (SELECT id FROM profiles WHERE email = 'rahul@ignisia.com'),
   'Rahul_Expense_Report_March.xlsx', 'xlsx', 89000, 'private', 'upload', 5, 'ready'),
  ('ddd00000-0000-0000-0000-000000000007', 'a0000000-0000-0000-0000-000000000001',
   (SELECT id FROM profiles WHERE email = 'meera@ignisia.com'),
   'Team_Budget_Allocation_2025.xlsx', 'xlsx', 245000, 'private', 'upload', 12, 'ready'),
  ('ddd00000-0000-0000-0000-000000000008', 'a0000000-0000-0000-0000-000000000001',
   (SELECT id FROM profiles WHERE email = 'arjun@ignisia.com'),
   'Email_Board_Meeting_Notes_2025-03-15.eml', 'eml', 34000, 'private', 'email', 6, 'ready'),
  ('ddd00000-0000-0000-0000-000000000009', 'a0000000-0000-0000-0000-000000000001', NULL,
   'Annual_Report_2024_Draft.pdf', 'pdf', 5200000, 'shared', 'upload', 0, 'processing'),
  ('ddd00000-0000-0000-0000-000000000010', 'a0000000-0000-0000-0000-000000000001', NULL,
   'Corrupted_File.pdf', 'pdf', 1200, 'shared', 'upload', 0, 'failed')
ON CONFLICT (id) DO NOTHING;

-- 9.5 — Sample conversations
INSERT INTO conversations (id, org_id, user_id, title, created_at)
VALUES
  ('ccc00000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001',
   (SELECT id FROM profiles WHERE email = 'arjun@ignisia.com'), 'Q1 Revenue Analysis', now() - interval '2 hours'),
  ('ccc00000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001',
   (SELECT id FROM profiles WHERE email = 'arjun@ignisia.com'), 'Company Policy Questions', now() - interval '1 day'),
  ('ccc00000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001',
   (SELECT id FROM profiles WHERE email = 'meera@ignisia.com'), 'Team Budget Review', now() - interval '3 hours'),
  ('ccc00000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001',
   (SELECT id FROM profiles WHERE email = 'priya@ignisia.com'), 'Benefits Inquiry', now() - interval '5 hours')
ON CONFLICT (id) DO NOTHING;

-- 9.6 — Sample messages (clean answer, conflict-resolution, and duplicate cases)
INSERT INTO messages (conversation_id, role, content, sources, analysis, created_at)
VALUES
  ('ccc00000-0000-0000-0000-000000000001', 'user',
   'What was our total revenue in Q1 2025?', '[]'::jsonb, '{}'::jsonb, now() - interval '2 hours'),
  ('ccc00000-0000-0000-0000-000000000001', 'assistant',
   E'** Final Answer**\nThe total revenue for Q1 2025 was ₹4.82 Crores, a 23% increase over Q1 2024.\n\n** Data Quality Notes**\nNo data quality issues detected.\n\n** Source References**\n- Q1_2025_Revenue_Report.xlsx, Page 1, Row 12\n\n** Reasoning**\nThe revenue figure was found directly in the quarterly report summary sheet.',
   '[{"document": "Q1_2025_Revenue_Report.xlsx", "page": 1, "line": 12, "similarity": 0.9234}]'::jsonb,
   '{"duplicates": [], "conflicts": [], "unique_sources": ["Q1_2025_Revenue_Report.xlsx"]}'::jsonb,
   now() - interval '1 hour 59 minutes'),
  ('ccc00000-0000-0000-0000-000000000001', 'user',
   'How does that compare to the target?', '[]'::jsonb, '{}'::jsonb, now() - interval '1 hour 55 minutes'),
  ('ccc00000-0000-0000-0000-000000000001', 'assistant',
   E'** Final Answer**\nThe Q1 2025 target was ₹4.5 Crores. Actual revenue of ₹4.82 Crores exceeded the target by 7.1%.\n\n** Data Quality Notes**\nNo data quality issues detected.\n\n** Source References**\n- Q1_2025_Revenue_Report.xlsx, Page 1, Row 12 (actual)\n- Product_Roadmap_H1_2025.pdf, Page 3, Section: Revenue Targets (target)\n\n** Reasoning**\nActual revenue from the Q1 report was compared against the target defined in the H1 roadmap.',
   '[{"document": "Q1_2025_Revenue_Report.xlsx", "page": 1, "line": 12, "similarity": 0.9234}, {"document": "Product_Roadmap_H1_2025.pdf", "page": 3, "line": 1, "similarity": 0.8712}]'::jsonb,
   '{"duplicates": [], "conflicts": [], "unique_sources": ["Q1_2025_Revenue_Report.xlsx", "Product_Roadmap_H1_2025.pdf"]}'::jsonb,
   now() - interval '1 hour 54 minutes'),
  ('ccc00000-0000-0000-0000-000000000002', 'user',
   'What is our remote work policy?', '[]'::jsonb, '{}'::jsonb, now() - interval '1 day'),
  ('ccc00000-0000-0000-0000-000000000002', 'assistant',
   E'** Final Answer**\nEmployees may work remotely up to 3 days per week with manager approval. Full-time remote requires director-level approval and a signed remote work agreement.\n\n** Data Quality Notes**\nNo data quality issues detected.\n\n** Source References**\n- Company_Policy_Handbook_2025.pdf, Page 14, Section: Remote Work\n\n** Reasoning**\nThe policy was found in the handbook under the Remote Work section.',
   '[{"document": "Company_Policy_Handbook_2025.pdf", "page": 14, "line": 1, "similarity": 0.9456}]'::jsonb,
   '{"duplicates": [], "conflicts": [], "unique_sources": ["Company_Policy_Handbook_2025.pdf"]}'::jsonb,
   now() - interval '23 hours 59 minutes'),
  ('ccc00000-0000-0000-0000-000000000003', 'user',
   'What is the engineering team budget for Q2?', '[]'::jsonb, '{}'::jsonb, now() - interval '3 hours'),
  ('ccc00000-0000-0000-0000-000000000003', 'assistant',
   E'** Final Answer**\nThe engineering team budget for Q2 2025 is ₹1.2 Crores, allocated across hiring (40%), infrastructure (35%), and training (25%).\n\n** Data Quality Notes**\n CONFLICTING DATA: The roadmap mentions ₹1.35 Crores for engineering in Q2, while the budget sheet shows ₹1.2 Crores. The budget sheet is more recent (March 2025 vs January 2025), so ₹1.2 Crores is used.\n\n** Source References**\n- Team_Budget_Allocation_2025.xlsx, Page 1, Row 8\n- Product_Roadmap_H1_2025.pdf, Page 5, Section: Resource Planning\n\n** Reasoning**\nTwo sources were found with different figures. The budget allocation sheet is the more authoritative and recent source.',
   '[{"document": "Team_Budget_Allocation_2025.xlsx", "page": 1, "line": 8, "similarity": 0.9102}, {"document": "Product_Roadmap_H1_2025.pdf", "page": 5, "line": 1, "similarity": 0.8543}]'::jsonb,
   '{"duplicates": [], "conflicts": [{"field": "engineering_budget_q2", "values": [{"value": "1.2 Crores", "source": "Team_Budget_Allocation_2025.xlsx"}, {"value": "1.35 Crores", "source": "Product_Roadmap_H1_2025.pdf"}]}], "unique_sources": ["Team_Budget_Allocation_2025.xlsx", "Product_Roadmap_H1_2025.pdf"]}'::jsonb,
   now() - interval '2 hours 59 minutes'),
  ('ccc00000-0000-0000-0000-000000000004', 'user',
   'How many paid leaves do I get per year?', '[]'::jsonb, '{}'::jsonb, now() - interval '5 hours'),
  ('ccc00000-0000-0000-0000-000000000004', 'assistant',
   E'** Final Answer**\nAll full-time employees get 24 paid leaves per year: 12 casual leaves, 6 sick leaves, and 6 earned leaves. Unused earned leaves can be carried forward (max 18).\n\n** Data Quality Notes**\nNo data quality issues detected.\n\n** Source References**\n- Employee_Benefits_Summary.docx, Page 2, Section: Leave Policy\n- Company_Policy_Handbook_2025.pdf, Page 22, Section: Leave Entitlement\n\n** Reasoning**\nBoth sources confirm the same leave structure. No conflicts detected.',
   '[{"document": "Employee_Benefits_Summary.docx", "page": 2, "line": 1, "similarity": 0.9321}, {"document": "Company_Policy_Handbook_2025.pdf", "page": 22, "line": 1, "similarity": 0.8876}]'::jsonb,
   '{"duplicates": [{"text_preview": "24 paid leaves per year: 12 casual, 6 sick, 6 earned", "found_in": ["Employee_Benefits_Summary.docx", "Company_Policy_Handbook_2025.pdf"]}], "conflicts": [], "unique_sources": ["Employee_Benefits_Summary.docx", "Company_Policy_Handbook_2025.pdf"]}'::jsonb,
   now() - interval '4 hours 59 minutes');

-- 9.7 — Example email config (replace with a real App Password to actually poll)
INSERT INTO email_configs (user_id, org_id, imap_server, email_address, encrypted_password, folder, is_active, last_polled_at)
VALUES
  ((SELECT id FROM profiles WHERE email = 'arjun@ignisia.com'),
   'a0000000-0000-0000-0000-000000000001', 'imap.gmail.com', 'ignisiahack@gmail.com',
   'replace-with-app-password', 'INBOX', true, now() - interval '6 hours')
ON CONFLICT (user_id) DO NOTHING;

-- 9.8 — Audit log history
INSERT INTO audit_log (org_id, user_id, action, details, created_at)
VALUES
  ('a0000000-0000-0000-0000-000000000001', (SELECT id FROM profiles WHERE email = 'arjun@ignisia.com'),
   'upload', '{"filename": "Company_Policy_Handbook_2025.pdf", "visibility": "shared", "chunk_count": 47}'::jsonb, now() - interval '7 days'),
  ('a0000000-0000-0000-0000-000000000001', (SELECT id FROM profiles WHERE email = 'arjun@ignisia.com'),
   'upload', '{"filename": "Q1_2025_Revenue_Report.xlsx", "visibility": "shared", "chunk_count": 32}'::jsonb, now() - interval '5 days'),
  ('a0000000-0000-0000-0000-000000000001', (SELECT id FROM profiles WHERE email = 'meera@ignisia.com'),
   'upload', '{"filename": "Team_Budget_Allocation_2025.xlsx", "visibility": "private", "chunk_count": 12}'::jsonb, now() - interval '3 days'),
  ('a0000000-0000-0000-0000-000000000001', (SELECT id FROM profiles WHERE email = 'priya@ignisia.com'),
   'query', '{"question": "How many paid leaves do I get per year?", "source_count": 2, "conflict_count": 0}'::jsonb, now() - interval '5 hours'),
  ('a0000000-0000-0000-0000-000000000001', (SELECT id FROM profiles WHERE email = 'arjun@ignisia.com'),
   'email_ingest', '{"email_count": 1, "emails": [{"subject": "Board Meeting Notes", "from": "ceo@ignisia.com"}]}'::jsonb, now() - interval '6 hours'),
  ('a0000000-0000-0000-0000-000000000001', (SELECT id FROM profiles WHERE email = 'arjun@ignisia.com'),
   'query', '{"question": "What was our total revenue in Q1 2025?", "source_count": 1, "conflict_count": 0}'::jsonb, now() - interval '2 hours'),
  ('a0000000-0000-0000-0000-000000000001', (SELECT id FROM profiles WHERE email = 'meera@ignisia.com'),
   'query', '{"question": "What is the engineering team budget for Q2?", "source_count": 2, "conflict_count": 1}'::jsonb, now() - interval '3 hours');

-- ════════════════════════════════════════════════════════════════════════════
--  Setup complete.
-- ════════════════════════════════════════════════════════════════════════════
