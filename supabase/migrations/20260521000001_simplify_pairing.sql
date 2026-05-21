-- =============================================
-- Simplify pairing: one active pair per iOS user
-- When claiming a new pair, deactivate all previous pairs
-- and their bridge sessions for the same iOS user/device.
-- =============================================

CREATE OR REPLACE FUNCTION public.claim_pair(p_pair_id UUID, p_pairing_token TEXT)
RETURNS TABLE(pair_id UUID, ios_auth_user_id UUID)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
DECLARE
  v_pair public.device_pairs%rowtype;
  v_device_id TEXT;
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

  v_device_id := v_pair.ios_device_id;

  -- Deactivate bridge sessions for all other pairs of this iOS user/device
  UPDATE public.bridge_sessions
    SET is_active = false, ended_at = now()
    WHERE is_active = true
      AND pair_id IN (
        SELECT id FROM public.device_pairs
        WHERE id <> p_pair_id
          AND is_active = true
          AND (
            ios_auth_user_id = v_pair.ios_auth_user_id
            OR (v_device_id IS NOT NULL AND ios_device_id = v_device_id)
          )
      );

  -- Deactivate all other active pairs for this iOS user/device
  UPDATE public.device_pairs
    SET is_active = false
    WHERE id <> p_pair_id
      AND is_active = true
      AND (
        ios_auth_user_id = v_pair.ios_auth_user_id
        OR (v_device_id IS NOT NULL AND ios_device_id = v_device_id)
      );

  -- Activate the claimed pair
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
