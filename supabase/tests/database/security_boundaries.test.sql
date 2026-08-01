BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(12);

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

SELECT * FROM finish();
ROLLBACK;
