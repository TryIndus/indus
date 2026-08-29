BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(48);

SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.favorites'::regclass),
  'favorites has row-level security enabled'
);
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.reports'::regclass),
  'reports has row-level security enabled'
);
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.metric_explanations'::regclass),
  'shared metric explanations have row-level security enabled'
);
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.ai_usage_windows'::regclass),
  'AI usage data has row-level security enabled'
);

SELECT is(
  (SELECT count(*)::integer FROM pg_policies WHERE schemaname = 'public' AND tablename = 'favorites'),
  3,
  'favorites exposes only explicit read, create, and delete policies'
);
SELECT is(
  (SELECT count(*)::integer FROM pg_policies WHERE schemaname = 'public' AND tablename = 'reports'),
  4,
  'reports exposes explicit CRUD policies'
);
SELECT is(
  (SELECT count(*)::integer FROM pg_policies WHERE schemaname = 'public' AND tablename = 'metric_explanations'),
  1,
  'metric explanations expose a read-only authenticated policy'
);
SELECT is(
  (SELECT count(*)::integer FROM pg_policies WHERE schemaname = 'public' AND tablename = 'ai_usage_windows'),
  0,
  'AI usage rows are inaccessible through direct user policies'
);

SELECT is(
  (
    SELECT string_agg(
      policyname || ':' || cmd || ':' || array_to_string(roles, ','),
      ',' ORDER BY policyname
    )
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'favorites'
  ),
  'Users can create their own favorites:INSERT:authenticated,Users can delete their own favorites:DELETE:authenticated,Users can read their own favorites:SELECT:authenticated',
  'favorites policies retain their exact commands and authenticated role'
);
SELECT is(
  (
    SELECT string_agg(
      policyname || ':' || cmd || ':' || array_to_string(roles, ','),
      ',' ORDER BY policyname
    )
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'reports'
  ),
  'Users can create their own reports:INSERT:authenticated,Users can delete their own reports:DELETE:authenticated,Users can read their own reports:SELECT:authenticated,Users can update their own reports:UPDATE:authenticated',
  'report policies retain their exact commands and authenticated role'
);
SELECT is(
  (
    SELECT string_agg(
      policyname || ':' || cmd || ':' || array_to_string(roles, ','),
      ',' ORDER BY policyname
    )
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'metric_explanations'
  ),
  'Authenticated users can read metric explanations:SELECT:authenticated',
  'metric explanations retain their authenticated read-only policy'
);

SELECT ok(
  NOT (
    has_table_privilege('anon', 'public.favorites', 'SELECT')
    OR has_table_privilege('anon', 'public.favorites', 'INSERT')
    OR has_table_privilege('anon', 'public.favorites', 'UPDATE')
    OR has_table_privilege('anon', 'public.favorites', 'DELETE')
  ),
  'anonymous users have no favorites privileges'
);
SELECT ok(
  NOT (
    has_table_privilege('anon', 'public.reports', 'SELECT')
    OR has_table_privilege('anon', 'public.reports', 'INSERT')
    OR has_table_privilege('anon', 'public.reports', 'UPDATE')
    OR has_table_privilege('anon', 'public.reports', 'DELETE')
  ),
  'anonymous users have no reports privileges'
);
SELECT ok(
  NOT (
    has_table_privilege('anon', 'public.metric_explanations', 'SELECT')
    OR has_table_privilege('anon', 'public.metric_explanations', 'INSERT')
    OR has_table_privilege('anon', 'public.metric_explanations', 'UPDATE')
    OR has_table_privilege('anon', 'public.metric_explanations', 'DELETE')
  ),
  'anonymous users have no metric explanation privileges'
);
SELECT ok(
  NOT (
    has_table_privilege('anon', 'public.ai_usage_windows', 'SELECT')
    OR has_table_privilege('anon', 'public.ai_usage_windows', 'INSERT')
    OR has_table_privilege('anon', 'public.ai_usage_windows', 'UPDATE')
    OR has_table_privilege('anon', 'public.ai_usage_windows', 'DELETE')
  ),
  'anonymous users have no quota storage privileges'
);
SELECT ok(
  has_table_privilege('authenticated', 'public.favorites', 'SELECT')
    AND has_table_privilege('authenticated', 'public.favorites', 'INSERT')
    AND NOT has_table_privilege('authenticated', 'public.favorites', 'UPDATE')
    AND has_table_privilege('authenticated', 'public.favorites', 'DELETE'),
  'authenticated users receive only the required favorites privileges'
);
SELECT ok(
  has_table_privilege('authenticated', 'public.reports', 'SELECT')
    AND has_table_privilege('authenticated', 'public.reports', 'INSERT')
    AND has_table_privilege('authenticated', 'public.reports', 'UPDATE')
    AND has_table_privilege('authenticated', 'public.reports', 'DELETE'),
  'authenticated users receive the required reports privileges'
);
SELECT ok(
  has_table_privilege('authenticated', 'public.metric_explanations', 'SELECT')
    AND NOT has_table_privilege('authenticated', 'public.metric_explanations', 'INSERT')
    AND NOT has_table_privilege('authenticated', 'public.metric_explanations', 'UPDATE')
    AND NOT has_table_privilege('authenticated', 'public.metric_explanations', 'DELETE'),
  'authenticated users receive read-only metric explanation access'
);
SELECT ok(
  NOT (
    has_table_privilege('authenticated', 'public.ai_usage_windows', 'SELECT')
    OR has_table_privilege('authenticated', 'public.ai_usage_windows', 'INSERT')
    OR has_table_privilege('authenticated', 'public.ai_usage_windows', 'UPDATE')
    OR has_table_privilege('authenticated', 'public.ai_usage_windows', 'DELETE')
  ),
  'authenticated users have no direct quota storage privileges'
);
SELECT ok(
  (
    SELECT bool_and(has_table_privilege('service_role', table_name, privilege_name))
    FROM (
      VALUES
        ('public.favorites'),
        ('public.reports'),
        ('public.metric_explanations'),
        ('public.ai_usage_windows')
    ) AS tables(table_name)
    CROSS JOIN (
      VALUES
        ('SELECT'),
        ('INSERT'),
        ('UPDATE'),
        ('DELETE'),
        ('TRUNCATE'),
        ('REFERENCES'),
        ('TRIGGER')
    ) AS privileges(privilege_name)
  ),
  'service role retains all table privileges required for trusted operations'
);

SELECT ok(
  (
    SELECT prosecdef
    FROM pg_proc
    WHERE oid = 'public.consume_ai_quota(text)'::regprocedure
  ),
  'quota consumption runs as a security-definer function'
);
SELECT ok(
  (
    SELECT 'search_path=""' = ANY (proconfig)
    FROM pg_proc
    WHERE oid = 'public.consume_ai_quota(text)'::regprocedure
  ),
  'quota consumption pins an empty search path'
);
SELECT ok(
  has_function_privilege('authenticated', 'public.consume_ai_quota(text)', 'EXECUTE')
    AND has_function_privilege('service_role', 'public.consume_ai_quota(text)', 'EXECUTE')
    AND NOT has_function_privilege('anon', 'public.consume_ai_quota(text)', 'EXECUTE')
    AND NOT EXISTS (
      SELECT 1
      FROM pg_proc AS routine
      CROSS JOIN LATERAL aclexplode(routine.proacl) AS privilege
      WHERE routine.oid = 'public.consume_ai_quota(text)'::regprocedure
        AND privilege.grantee = 0
        AND privilege.privilege_type = 'EXECUTE'
    ),
  'only authenticated and service roles can execute quota consumption'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_constraint
    WHERE connamespace = 'public'::regnamespace
      AND conname IN (
        'favorites_symbol_format',
        'reports_symbol_format',
        'reports_company_name_length',
        'reports_status_values',
        'metric_explanations_symbol_format',
        'metric_explanations_metric_length'
      )
      AND convalidated
  ),
  6,
  'all persisted-value constraints are validated'
);

INSERT INTO auth.users (id, email)
VALUES
  ('33333333-3333-4333-8333-333333333333', 'tenant-one@example.test'),
  ('44444444-4444-4444-8444-444444444444', 'tenant-two@example.test');

INSERT INTO public.favorites (user_id, symbol)
VALUES
  ('33333333-3333-4333-8333-333333333333', 'AAPL'),
  ('44444444-4444-4444-8444-444444444444', 'MSFT');
INSERT INTO public.reports (user_id, symbol, company_name)
VALUES
  ('33333333-3333-4333-8333-333333333333', 'AAPL', 'Apple Inc.'),
  ('44444444-4444-4444-8444-444444444444', 'MSFT', 'Microsoft Corporation');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', true);

SELECT is(
  (SELECT count(*)::integer FROM public.favorites),
  1,
  'a user sees only their own favorites'
);
SELECT throws_ok(
  $$ INSERT INTO public.favorites (user_id, symbol) VALUES ('44444444-4444-4444-8444-444444444444', 'NVDA') $$,
  '42501',
  'new row violates row-level security policy for table "favorites"',
  'a user cannot create a favorite for another tenant'
);
SELECT is_empty(
  $$ DELETE FROM public.favorites
     WHERE user_id = '44444444-4444-4444-8444-444444444444'
     RETURNING 1 $$,
  'a user cannot delete another tenant favorite'
);
SELECT throws_ok(
  $$ INSERT INTO public.favorites (user_id, symbol) VALUES ('33333333-3333-4333-8333-333333333333', 'bad symbol!') $$,
  '23514',
  'new row for relation "favorites" violates check constraint "favorites_symbol_format"',
  'invalid persisted symbols are rejected'
);
SELECT throws_ok(
  $$ INSERT INTO public.favorites (user_id, symbol) VALUES ('33333333-3333-4333-8333-333333333333', repeat('A', 21)) $$,
  '23514',
  'new row for relation "favorites" violates check constraint "favorites_symbol_format"',
  'favorite symbols longer than 20 characters are rejected'
);
SELECT lives_ok(
  $$ INSERT INTO public.favorites (user_id, symbol) VALUES ('33333333-3333-4333-8333-333333333333', repeat('F', 20)) $$,
  'a user can create their own favorite at the symbol length boundary'
);
SELECT lives_ok(
  $$ DELETE FROM public.favorites WHERE user_id = '33333333-3333-4333-8333-333333333333' AND symbol = repeat('F', 20) $$,
  'a user can delete their own favorite'
);

SELECT is(
  (SELECT count(*)::integer FROM public.reports),
  1,
  'a user sees only their own reports'
);
SELECT throws_ok(
  $$ INSERT INTO public.reports (user_id, symbol, company_name) VALUES ('44444444-4444-4444-8444-444444444444', 'NVDA', 'NVIDIA') $$,
  '42501',
  'new row violates row-level security policy for table "reports"',
  'a user cannot create a report for another tenant'
);
SELECT is_empty(
  $$ UPDATE public.reports SET summary = 'tampered'
     WHERE user_id = '44444444-4444-4444-8444-444444444444'
     RETURNING 1 $$,
  'a user cannot update another tenant report'
);
SELECT is_empty(
  $$ DELETE FROM public.reports
     WHERE user_id = '44444444-4444-4444-8444-444444444444'
     RETURNING 1 $$,
  'a user cannot delete another tenant report'
);
SELECT throws_ok(
  $$ INSERT INTO public.reports (user_id, symbol, company_name) VALUES ('33333333-3333-4333-8333-333333333333', 'bad symbol!', 'Invalid') $$,
  '23514',
  'new row for relation "reports" violates check constraint "reports_symbol_format"',
  'invalid report symbols are rejected'
);
SELECT throws_ok(
  $$ INSERT INTO public.reports (user_id, symbol, company_name) VALUES ('33333333-3333-4333-8333-333333333333', 'NVDA', '') $$,
  '23514',
  'new row for relation "reports" violates check constraint "reports_company_name_length"',
  'empty report company names are rejected'
);
SELECT throws_ok(
  $$ INSERT INTO public.reports (user_id, symbol, company_name) VALUES ('33333333-3333-4333-8333-333333333333', 'NVDA', repeat('C', 201)) $$,
  '23514',
  'new row for relation "reports" violates check constraint "reports_company_name_length"',
  'report company names longer than 200 characters are rejected'
);
SELECT throws_ok(
  $$ INSERT INTO public.reports (user_id, symbol, company_name, status) VALUES ('33333333-3333-4333-8333-333333333333', 'NVDA', 'NVIDIA', 'unknown') $$,
  '23514',
  'new row for relation "reports" violates check constraint "reports_status_values"',
  'unknown persisted report statuses are rejected'
);
SELECT lives_ok(
  $$ INSERT INTO public.reports (user_id, symbol, company_name) VALUES ('33333333-3333-4333-8333-333333333333', repeat('R', 20), repeat('C', 200)) $$,
  'a user can create their own report at persisted length boundaries'
);
SELECT lives_ok(
  $$ UPDATE public.reports SET status = 'completed' WHERE user_id = '33333333-3333-4333-8333-333333333333' AND symbol = repeat('R', 20) $$,
  'a user can update their own report'
);
SELECT lives_ok(
  $$ DELETE FROM public.reports WHERE user_id = '33333333-3333-4333-8333-333333333333' AND symbol = repeat('R', 20) $$,
  'a user can delete their own report'
);
SELECT throws_ok(
  $$ INSERT INTO public.metric_explanations (symbol, metric, explanation) VALUES ('AAPL', 'price', '{}'::jsonb) $$,
  '42501',
  'permission denied for table metric_explanations',
  'authenticated users cannot insert shared explanations'
);
SELECT throws_ok(
  $$ SELECT * FROM public.ai_usage_windows $$,
  '42501',
  'permission denied for table ai_usage_windows',
  'authenticated users cannot read quota storage directly'
);

RESET ROLE;

SELECT throws_ok(
  $$ INSERT INTO public.metric_explanations (symbol, metric, explanation) VALUES ('bad symbol!', 'price', '{}'::jsonb) $$,
  '23514',
  'new row for relation "metric_explanations" violates check constraint "metric_explanations_symbol_format"',
  'invalid metric explanation symbols are rejected'
);
SELECT throws_ok(
  $$ INSERT INTO public.metric_explanations (symbol, metric, explanation) VALUES ('AAPL', '', '{}'::jsonb) $$,
  '23514',
  'new row for relation "metric_explanations" violates check constraint "metric_explanations_metric_length"',
  'empty metric explanation names are rejected'
);
SELECT throws_ok(
  $$ INSERT INTO public.metric_explanations (symbol, metric, explanation) VALUES ('AAPL', repeat('M', 81), '{}'::jsonb) $$,
  '23514',
  'new row for relation "metric_explanations" violates check constraint "metric_explanations_metric_length"',
  'metric explanation names longer than 80 characters are rejected'
);
SELECT lives_ok(
  $$ INSERT INTO public.metric_explanations (symbol, metric, explanation) VALUES (repeat('M', 20), repeat('K', 80), '{}'::jsonb) $$,
  'metric explanation persisted fields accept their maximum lengths'
);

SELECT * FROM finish();
ROLLBACK;
