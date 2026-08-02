BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(23);

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

SELECT ok(
  NOT has_table_privilege('anon', 'public.favorites', 'SELECT'),
  'anonymous users cannot read favorites'
);
SELECT ok(
  NOT has_table_privilege('anon', 'public.reports', 'SELECT'),
  'anonymous users cannot read reports'
);
SELECT ok(
  has_table_privilege('authenticated', 'public.metric_explanations', 'SELECT'),
  'authenticated users can read shared explanations'
);
SELECT ok(
  NOT has_table_privilege('authenticated', 'public.metric_explanations', 'INSERT'),
  'authenticated users cannot poison shared explanations'
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

SELECT * FROM finish();
ROLLBACK;
