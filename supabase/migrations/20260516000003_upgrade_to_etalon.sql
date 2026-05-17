-- =============================================
-- ClaudeCodeMobile: Upgrade schema to match etalon
-- Adds secure pairing (claim_pair RPC), per-user RLS,
-- broadcast trigger for private channels, project_path support.
-- =============================================

-- ── Add missing columns to device_pairs ──────────────────────────────────
ALTER TABLE public.device_pairs ADD COLUMN IF NOT EXISTS ios_auth_user_id UUID;
ALTER TABLE public.device_pairs ADD COLUMN IF NOT EXISTS bridge_auth_user_id UUID;
ALTER TABLE public.device_pairs ADD COLUMN IF NOT EXISTS pairing_token TEXT;
ALTER TABLE public.device_pairs ADD COLUMN IF NOT EXISTS pairing_token_expires_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_device_pairs_ios_auth ON public.device_pairs(ios_auth_user_id);
CREATE INDEX IF NOT EXISTS idx_device_pairs_bridge_auth ON public.device_pairs(bridge_auth_user_id);

-- ── Add project_path to bridge_sessions ──────────────────────────────────
ALTER TABLE public.bridge_sessions ADD COLUMN IF NOT EXISTS project_path TEXT;
ALTER TABLE public.bridge_sessions ADD COLUMN IF NOT EXISTS started_at TIMESTAMPTZ NOT NULL DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_bridge_sessions_pair_active
  ON public.bridge_sessions (pair_id, is_active, started_at DESC);

CREATE INDEX IF NOT EXISTS idx_bridge_sessions_pair_project_path
  ON public.bridge_sessions (pair_id, project_path)
  WHERE is_active = true AND project_path IS NOT NULL;

-- One active bridge session per device pair
CREATE UNIQUE INDEX IF NOT EXISTS uniq_bridge_sessions_one_active_per_pair
  ON public.bridge_sessions (pair_id)
  WHERE is_active = true;

-- ── RPC: claim_pair ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.claim_pair(p_pair_id UUID, p_pairing_token TEXT)
RETURNS TABLE(pair_id UUID, ios_auth_user_id UUID)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
  v_pair public.device_pairs%rowtype;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authenticated session required';
  END IF;

  SELECT * INTO v_pair FROM public.device_pairs WHERE id = p_pair_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'pair not found';
  END IF;

  IF v_pair.pairing_token IS NULL OR v_pair.pairing_token <> p_pairing_token THEN
    RAISE EXCEPTION 'invalid pairing token';
  END IF;

  IF v_pair.pairing_token_expires_at IS NOT NULL AND v_pair.pairing_token_expires_at < now() THEN
    RAISE EXCEPTION 'pairing token expired';
  END IF;

  UPDATE public.device_pairs
    SET bridge_auth_user_id = auth.uid(),
        is_active = true,
        paired_at = now(),
        pairing_token = NULL,
        pairing_token_expires_at = NULL
    WHERE id = p_pair_id;

  RETURN QUERY SELECT v_pair.id, v_pair.ios_auth_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_pair(UUID, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.claim_pair(UUID, TEXT) TO authenticated;

-- ── Broadcast trigger for private channels ───────────────────────────────
CREATE OR REPLACE FUNCTION public.broadcast_message_changes()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
  v_pair_id UUID;
BEGIN
  v_pair_id := coalesce(NEW.pair_id, OLD.pair_id);
  IF v_pair_id IS NULL THEN
    RETURN NULL;
  END IF;
  PERFORM realtime.broadcast_changes(
    'pair:' || v_pair_id::text,
    TG_OP,
    TG_OP,
    TG_TABLE_NAME,
    TG_TABLE_SCHEMA,
    NEW,
    OLD
  );
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS broadcast_messages ON public.messages;
CREATE TRIGGER broadcast_messages
AFTER INSERT OR UPDATE OR DELETE ON public.messages
FOR EACH ROW
EXECUTE FUNCTION public.broadcast_message_changes();

-- ── Drop old permissive RLS policies ─────────────────────────────────────
DROP POLICY IF EXISTS "Allow all for authenticated" ON public.messages;
DROP POLICY IF EXISTS "Allow all for authenticated" ON public.device_pairs;
DROP POLICY IF EXISTS "Allow all for authenticated" ON public.bridge_sessions;
DROP POLICY IF EXISTS "Allow all for authenticated" ON public.ide_presence;
DROP POLICY IF EXISTS "Allow all for authenticated" ON public.agent_messages;
DROP POLICY IF EXISTS "Allow all for authenticated" ON public.rating_feedback;
DROP POLICY IF EXISTS "Allow all for anon" ON public.messages;
DROP POLICY IF EXISTS "Allow all for anon" ON public.device_pairs;
DROP POLICY IF EXISTS "Allow all for anon" ON public.bridge_sessions;
DROP POLICY IF EXISTS "Allow all for anon" ON public.ide_presence;
DROP POLICY IF EXISTS "Allow all for anon" ON public.agent_messages;
DROP POLICY IF EXISTS "Allow all for anon" ON public.rating_feedback;

-- ── Per-user RLS policies ────────────────────────────────────────────────

-- device_pairs: owner-based access
DROP POLICY IF EXISTS "device_pairs_select" ON public.device_pairs;
CREATE POLICY "device_pairs_select" ON public.device_pairs
  FOR SELECT TO authenticated
  USING (auth.uid() = ios_auth_user_id OR auth.uid() = bridge_auth_user_id);

DROP POLICY IF EXISTS "device_pairs_insert" ON public.device_pairs;
CREATE POLICY "device_pairs_insert" ON public.device_pairs
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = ios_auth_user_id);

DROP POLICY IF EXISTS "device_pairs_update" ON public.device_pairs;
CREATE POLICY "device_pairs_update" ON public.device_pairs
  FOR UPDATE TO authenticated
  USING (auth.uid() = ios_auth_user_id OR auth.uid() = bridge_auth_user_id)
  WITH CHECK (auth.uid() = ios_auth_user_id OR auth.uid() = bridge_auth_user_id);

DROP POLICY IF EXISTS "device_pairs_delete" ON public.device_pairs;
CREATE POLICY "device_pairs_delete" ON public.device_pairs
  FOR DELETE TO authenticated
  USING (auth.uid() = ios_auth_user_id);

-- bridge_sessions: access via pair ownership
DROP POLICY IF EXISTS "bridge_sessions_select" ON public.bridge_sessions;
CREATE POLICY "bridge_sessions_select" ON public.bridge_sessions
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.device_pairs p
    WHERE p.id = bridge_sessions.pair_id
      AND (auth.uid() = p.ios_auth_user_id OR auth.uid() = p.bridge_auth_user_id)
  ));

DROP POLICY IF EXISTS "bridge_sessions_write" ON public.bridge_sessions;
CREATE POLICY "bridge_sessions_write" ON public.bridge_sessions
  FOR ALL TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.device_pairs p
    WHERE p.id = bridge_sessions.pair_id
      AND (auth.uid() = p.ios_auth_user_id OR auth.uid() = p.bridge_auth_user_id)
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.device_pairs p
    WHERE p.id = bridge_sessions.pair_id
      AND (auth.uid() = p.ios_auth_user_id OR auth.uid() = p.bridge_auth_user_id)
  ));

-- messages: access via pair ownership
DROP POLICY IF EXISTS "messages_select" ON public.messages;
CREATE POLICY "messages_select" ON public.messages
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.device_pairs p
    WHERE p.id = messages.pair_id
      AND (auth.uid() = p.ios_auth_user_id OR auth.uid() = p.bridge_auth_user_id)
  ));

DROP POLICY IF EXISTS "messages_write" ON public.messages;
CREATE POLICY "messages_write" ON public.messages
  FOR ALL TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.device_pairs p
    WHERE p.id = messages.pair_id
      AND (auth.uid() = p.ios_auth_user_id OR auth.uid() = p.bridge_auth_user_id)
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.device_pairs p
    WHERE p.id = messages.pair_id
      AND (auth.uid() = p.ios_auth_user_id OR auth.uid() = p.bridge_auth_user_id)
  ));

-- ide_presence: authenticated access
DROP POLICY IF EXISTS "ide_presence_authenticated" ON public.ide_presence;
CREATE POLICY "ide_presence_authenticated" ON public.ide_presence
  FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

-- agent_messages: keep permissive
DROP POLICY IF EXISTS "agent_messages_auth" ON public.agent_messages;
CREATE POLICY "agent_messages_auth" ON public.agent_messages
  FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

-- rating_feedback: keep permissive
DROP POLICY IF EXISTS "rating_feedback_auth" ON public.rating_feedback;
CREATE POLICY "rating_feedback_auth" ON public.rating_feedback
  FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

-- ── Private channel RLS on realtime.messages ─────────────────────────────
DROP POLICY IF EXISTS "pair_channel_select" ON realtime.messages;
DROP POLICY IF EXISTS "pair_channel_insert" ON realtime.messages;

CREATE POLICY "pair_channel_select"
ON realtime.messages
FOR SELECT
TO authenticated
USING (
  realtime.messages.extension IN ('broadcast', 'presence')
  AND realtime.topic() LIKE 'pair:%'
  AND EXISTS (
    SELECT 1
    FROM public.device_pairs p
    WHERE p.id::text = split_part(realtime.topic(), ':', 2)
      AND (auth.uid() = p.ios_auth_user_id OR auth.uid() = p.bridge_auth_user_id)
  )
);

CREATE POLICY "pair_channel_insert"
ON realtime.messages
FOR INSERT
TO authenticated
WITH CHECK (
  realtime.messages.extension IN ('broadcast', 'presence')
  AND realtime.topic() LIKE 'pair:%'
  AND EXISTS (
    SELECT 1
    FROM public.device_pairs p
    WHERE p.id::text = split_part(realtime.topic(), ':', 2)
      AND (auth.uid() = p.ios_auth_user_id OR auth.uid() = p.bridge_auth_user_id)
  )
);

-- ── Add paired_at to device_pairs ────────────────────────────────────────
ALTER TABLE public.device_pairs ADD COLUMN IF NOT EXISTS paired_at TIMESTAMPTZ;

-- ── Add pair-aware columns to messages ───────────────────────────────────
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS pair_id UUID
  REFERENCES public.device_pairs(id) ON DELETE SET NULL;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS parent_message_id UUID;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS is_cancelled BOOLEAN DEFAULT false;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_messages_pair_id ON public.messages(pair_id);
CREATE INDEX IF NOT EXISTS idx_messages_parent ON public.messages(parent_message_id);

-- ── Fallback policy: messages by user_id ─────────────────────────────────
DROP POLICY IF EXISTS "messages_user_select" ON public.messages;
CREATE POLICY "messages_user_select" ON public.messages
  FOR SELECT TO authenticated
  USING (user_id = auth.uid()::text);

DROP POLICY IF EXISTS "messages_user_write" ON public.messages;
CREATE POLICY "messages_user_write" ON public.messages
  FOR ALL TO authenticated
  USING (user_id = auth.uid()::text)
  WITH CHECK (user_id = auth.uid()::text);

-- ── RPC: rebind_ios_user_by_device ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rebind_ios_user_by_device(p_installation_id TEXT)
RETURNS INTEGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
  v_count INTEGER := 0;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authenticated session required';
  END IF;

  UPDATE public.device_pairs
    SET ios_auth_user_id = auth.uid()
    WHERE ios_device_id = p_installation_id
      AND ios_auth_user_id IS DISTINCT FROM auth.uid();
  GET DIAGNOSTICS v_count = ROW_COUNT;

  UPDATE public.messages m
    SET user_id = auth.uid()::text
    FROM public.device_pairs p
    WHERE p.ios_device_id = p_installation_id
      AND p.ios_auth_user_id = auth.uid()
      AND m.pair_id = p.id
      AND m.user_id IS DISTINCT FROM auth.uid()::text;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.rebind_ios_user_by_device(TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.rebind_ios_user_by_device(TEXT) TO authenticated;
