-- Harden tenant boundaries, constrain persisted values, and atomically limit AI usage.

ALTER TABLE public.favorites
  ADD CONSTRAINT favorites_symbol_format
  CHECK (symbol ~ '^[A-Z0-9][A-Z0-9./_-]{0,19}$') NOT VALID;

ALTER TABLE public.reports
  ADD CONSTRAINT reports_symbol_format
  CHECK (symbol ~ '^[A-Z0-9][A-Z0-9./_-]{0,19}$') NOT VALID,
  ADD CONSTRAINT reports_company_name_length
  CHECK (char_length(company_name) BETWEEN 1 AND 200) NOT VALID,
  ADD CONSTRAINT reports_status_values
  CHECK (status IN ('pending', 'generating', 'completed', 'error')) NOT VALID;

ALTER TABLE public.metric_explanations
  ADD CONSTRAINT metric_explanations_symbol_format
  CHECK (symbol ~ '^[A-Z0-9][A-Z0-9./_-]{0,19}$') NOT VALID,
  ADD CONSTRAINT metric_explanations_metric_length
  CHECK (char_length(metric) BETWEEN 1 AND 80) NOT VALID;

ALTER TABLE public.metric_explanations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can manage their own favorites" ON public.favorites;
CREATE POLICY "Users can read their own favorites"
  ON public.favorites FOR SELECT TO authenticated
  USING ((SELECT auth.uid()) = user_id);
CREATE POLICY "Users can create their own favorites"
  ON public.favorites FOR INSERT TO authenticated
  WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY "Users can delete their own favorites"
  ON public.favorites FOR DELETE TO authenticated
  USING ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can manage their own reports" ON public.reports;
CREATE POLICY "Users can read their own reports"
  ON public.reports FOR SELECT TO authenticated
  USING ((SELECT auth.uid()) = user_id);
CREATE POLICY "Users can create their own reports"
  ON public.reports FOR INSERT TO authenticated
  WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY "Users can update their own reports"
  ON public.reports FOR UPDATE TO authenticated
  USING ((SELECT auth.uid()) = user_id)
  WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY "Users can delete their own reports"
  ON public.reports FOR DELETE TO authenticated
  USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "Authenticated users can read metric explanations"
  ON public.metric_explanations FOR SELECT TO authenticated
  USING (true);

REVOKE ALL ON TABLE public.favorites, public.reports, public.metric_explanations FROM anon;
GRANT SELECT, INSERT, DELETE ON TABLE public.favorites TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.reports TO authenticated;
GRANT SELECT ON TABLE public.metric_explanations TO authenticated;
GRANT ALL ON TABLE public.favorites, public.reports, public.metric_explanations TO service_role;

CREATE TABLE public.ai_usage_windows (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  function_name text NOT NULL CHECK (
    function_name IN ('batch-explain', 'context-chat', 'generate-report')
  ),
  window_type text NOT NULL CHECK (window_type IN ('hour', 'day')),
  window_start timestamptz NOT NULL,
  request_count integer NOT NULL CHECK (request_count > 0),
  PRIMARY KEY (user_id, function_name, window_type, window_start)
);

ALTER TABLE public.ai_usage_windows ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.ai_usage_windows FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.ai_usage_windows TO service_role;

CREATE OR REPLACE FUNCTION public.consume_ai_quota(p_function_name text)
RETURNS TABLE (allowed boolean, remaining integer, reset_at timestamptz)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_now timestamptz := statement_timestamp();
  v_hour_start timestamptz := date_trunc('hour', v_now);
  v_day_start timestamptz := date_trunc('day', v_now, 'UTC');
  v_hour_limit integer;
  v_day_limit integer;
  v_hour_count integer;
  v_day_count integer;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT limits.hour_limit, limits.day_limit
  INTO v_hour_limit, v_day_limit
  FROM (VALUES
    ('batch-explain', 20, 100),
    ('context-chat', 30, 150),
    ('generate-report', 5, 20)
  ) AS limits(function_name, hour_limit, day_limit)
  WHERE limits.function_name = p_function_name;

  IF v_hour_limit IS NULL THEN
    RAISE EXCEPTION 'Unsupported AI function' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(v_user_id::text || ':' || p_function_name, 0));

  SELECT COALESCE(MAX(request_count), 0) INTO v_hour_count
  FROM public.ai_usage_windows
  WHERE user_id = v_user_id
    AND function_name = p_function_name
    AND window_type = 'hour'
    AND window_start = v_hour_start;

  SELECT COALESCE(MAX(request_count), 0) INTO v_day_count
  FROM public.ai_usage_windows
  WHERE user_id = v_user_id
    AND function_name = p_function_name
    AND window_type = 'day'
    AND window_start = v_day_start;

  IF v_hour_count >= v_hour_limit OR v_day_count >= v_day_limit THEN
    RETURN QUERY SELECT
      false,
      GREATEST(LEAST(v_hour_limit - v_hour_count, v_day_limit - v_day_count), 0),
      CASE
        WHEN v_hour_count >= v_hour_limit THEN v_hour_start + interval '1 hour'
        ELSE v_day_start + interval '1 day'
      END;
    RETURN;
  END IF;

  INSERT INTO public.ai_usage_windows AS usage
    (user_id, function_name, window_type, window_start, request_count)
  VALUES
    (v_user_id, p_function_name, 'hour', v_hour_start, 1),
    (v_user_id, p_function_name, 'day', v_day_start, 1)
  ON CONFLICT (user_id, function_name, window_type, window_start)
  DO UPDATE SET request_count = usage.request_count + 1;

  v_hour_count := v_hour_count + 1;
  v_day_count := v_day_count + 1;

  RETURN QUERY SELECT
    true,
    LEAST(v_hour_limit - v_hour_count, v_day_limit - v_day_count),
    LEAST(v_hour_start + interval '1 hour', v_day_start + interval '1 day');
END;
$$;

REVOKE ALL ON FUNCTION public.consume_ai_quota(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.consume_ai_quota(text) TO authenticated, service_role;

CREATE INDEX ai_usage_windows_cleanup_idx ON public.ai_usage_windows(window_start);
