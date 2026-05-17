-- =============================================
-- system_info: Dynamic model & command catalog
-- Stores JSON-array payloads keyed by (id, user_id).
-- =============================================

CREATE TABLE IF NOT EXISTS public.system_info (
  id TEXT NOT NULL,
  user_id TEXT NOT NULL DEFAULT 'global',
  data JSONB NOT NULL DEFAULT '[]'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (id, user_id)
);

ALTER TABLE public.system_info ENABLE ROW LEVEL SECURITY;

-- Read: everyone (models list is public)
DROP POLICY IF EXISTS "system_info_read" ON public.system_info;
CREATE POLICY "system_info_read" ON public.system_info
  FOR SELECT TO authenticated, anon
  USING (true);

-- Write: authenticated only (admin dashboard)
DROP POLICY IF EXISTS "system_info_write" ON public.system_info;
CREATE POLICY "system_info_write" ON public.system_info
  FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

-- ── Seed data ────────────────────────────────────────────────

INSERT INTO public.system_info (id, user_id, data)
VALUES
  ('available_models', 'global', '[
    {"id": "claude-sonnet-4-6",  "label": "Sonnet 4.6"},
    {"id": "claude-opus-4-6",    "label": "Opus 4.6"},
    {"id": "sonnet",             "label": "Sonnet"},
    {"id": "opus",               "label": "Opus"},
    {"id": "haiku",              "label": "Haiku"}
  ]'::jsonb),
  ('available_commands', 'global', '[
    {"key": "fix",      "label": "Fix",      "prompt": "Find and fix bugs in this code: {{args}}"},
    {"key": "review",   "label": "Review",   "prompt": "Do a thorough code review of: {{args}}"},
    {"key": "test",     "label": "Test",     "prompt": "Write comprehensive tests for: {{args}}"},
    {"key": "refactor", "label": "Refactor", "prompt": "Refactor this code for better readability and performance: {{args}}"}
  ]'::jsonb)
ON CONFLICT (id, user_id) DO UPDATE
  SET data = EXCLUDED.data, updated_at = now();
