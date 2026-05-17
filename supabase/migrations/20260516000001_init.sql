-- =============================================
-- ClaudeCodeMobile: Full Database Schema
-- =============================================

-- 1. messages — основная таблица коммуникации iOS ↔ Bridge
CREATE TABLE IF NOT EXISTS public.messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    role TEXT NOT NULL,
    content TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    session_id UUID,
    model TEXT,
    user_id TEXT,
    client_type TEXT,
    parent_message_id UUID,
    pair_id UUID,
    sender TEXT,
    processed_by_mac_at TIMESTAMPTZ,
    is_cancelled BOOLEAN NOT NULL DEFAULT false,
    cancelled_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_messages_user_id ON public.messages (user_id);
CREATE INDEX IF NOT EXISTS idx_messages_status ON public.messages (status);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON public.messages (created_at);
CREATE INDEX IF NOT EXISTS idx_messages_user_client ON public.messages (user_id, client_type);

-- 2. device_pairs — связь iOS устройства с macOS bridge
CREATE TABLE IF NOT EXISTS public.device_pairs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    pair_code TEXT,
    ios_device_id TEXT,
    mac_device_id TEXT,
    paired_at TIMESTAMPTZ,
    is_active BOOLEAN NOT NULL DEFAULT false
);

CREATE INDEX IF NOT EXISTS idx_device_pairs_pair_code ON public.device_pairs (pair_code);
CREATE INDEX IF NOT EXISTS idx_device_pairs_ios_device ON public.device_pairs (ios_device_id);

-- 3. bridge_sessions — сессии между iOS и bridge
CREATE TABLE IF NOT EXISTS public.bridge_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at TIMESTAMPTZ,
    pair_id UUID REFERENCES public.device_pairs(id),
    is_active BOOLEAN NOT NULL DEFAULT true,
    client_type TEXT,
    project_name TEXT
);

CREATE INDEX IF NOT EXISTS idx_bridge_sessions_pair_id ON public.bridge_sessions (pair_id);
CREATE INDEX IF NOT EXISTS idx_bridge_sessions_active ON public.bridge_sessions (is_active);

-- 4. ide_presence — heartbeat от bridge
CREATE TABLE IF NOT EXISTS public.ide_presence (
    user_id TEXT PRIMARY KEY,
    workspace_name TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 5. agent_messages — чат с Gemini AI (без bridge)
CREATE TABLE IF NOT EXISTS public.agent_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    role TEXT NOT NULL,
    content TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    session_id UUID,
    model TEXT,
    user_id TEXT,
    client_type TEXT
);

CREATE INDEX IF NOT EXISTS idx_agent_messages_user_id ON public.agent_messages (user_id);
CREATE INDEX IF NOT EXISTS idx_agent_messages_created_at ON public.agent_messages (created_at);

-- 6. rating_feedback — отзывы пользователей
CREATE TABLE IF NOT EXISTS public.rating_feedback (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    user_id TEXT,
    feedback TEXT,
    app_version TEXT,
    source TEXT
);

-- =============================================
-- Row Level Security
-- =============================================

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.device_pairs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bridge_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ide_presence ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rating_feedback ENABLE ROW LEVEL SECURITY;

-- Permissive policies for authenticated users (including anonymous)
DROP POLICY IF EXISTS "Allow all for authenticated" ON public.messages;
CREATE POLICY "Allow all for authenticated" ON public.messages
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow all for authenticated" ON public.device_pairs;
CREATE POLICY "Allow all for authenticated" ON public.device_pairs
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow all for authenticated" ON public.bridge_sessions;
CREATE POLICY "Allow all for authenticated" ON public.bridge_sessions
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow all for authenticated" ON public.ide_presence;
CREATE POLICY "Allow all for authenticated" ON public.ide_presence
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow all for authenticated" ON public.agent_messages;
CREATE POLICY "Allow all for authenticated" ON public.agent_messages
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow all for authenticated" ON public.rating_feedback;
CREATE POLICY "Allow all for authenticated" ON public.rating_feedback
    FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Also allow anon role (bridge uses anon key without auth)
DROP POLICY IF EXISTS "Allow all for anon" ON public.messages;
CREATE POLICY "Allow all for anon" ON public.messages
    FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow all for anon" ON public.device_pairs;
CREATE POLICY "Allow all for anon" ON public.device_pairs
    FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow all for anon" ON public.bridge_sessions;
CREATE POLICY "Allow all for anon" ON public.bridge_sessions
    FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow all for anon" ON public.ide_presence;
CREATE POLICY "Allow all for anon" ON public.ide_presence
    FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow all for anon" ON public.agent_messages;
CREATE POLICY "Allow all for anon" ON public.agent_messages
    FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow all for anon" ON public.rating_feedback;
CREATE POLICY "Allow all for anon" ON public.rating_feedback
    FOR ALL TO anon USING (true) WITH CHECK (true);

-- =============================================
-- Realtime (safe idempotent add)
-- =============================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'device_pairs'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.device_pairs;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'bridge_sessions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.bridge_sessions;
  END IF;
END;
$$;
