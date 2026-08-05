BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(19);

INSERT INTO auth.users (id, email)
VALUES
  ('11111111-1111-4111-8111-111111111111', 'quota-one@example.test'),
  ('22222222-2222-4222-8222-222222222222', 'quota-two@example.test'),
  ('55555555-5555-4555-8555-555555555555', 'quota-daily@example.test');

INSERT INTO public.ai_usage_windows
  (user_id, function_name, window_type, window_start, request_count)
VALUES
  (
    '55555555-5555-4555-8555-555555555555',
    'generate-report',
    'day',
    date_trunc('day', statement_timestamp(), 'UTC'),
    20
  );

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);

SELECT results_eq(
  $$ SELECT allowed, remaining, reset_at FROM public.consume_ai_quota('generate-report') $$,
  $$ SELECT true, 4, date_trunc('hour', statement_timestamp()) + interval '1 hour' $$,
  'first report request returns the remaining hourly allowance and reset boundary'
);
SELECT is((SELECT allowed FROM public.consume_ai_quota('generate-report')), true, 'second request is allowed');
SELECT is((SELECT allowed FROM public.consume_ai_quota('generate-report')), true, 'third request is allowed');
SELECT is((SELECT allowed FROM public.consume_ai_quota('generate-report')), true, 'fourth request is allowed');
SELECT is((SELECT allowed FROM public.consume_ai_quota('generate-report')), true, 'fifth request is allowed');
SELECT is(
  (SELECT allowed FROM public.consume_ai_quota('generate-report')),
  false,
  'sixth hourly report request is denied'
);
SELECT is(
  (SELECT remaining FROM public.consume_ai_quota('generate-report')),
  0,
  'exhausted quota reports zero remaining requests'
);
SELECT is(
  (SELECT reset_at FROM public.consume_ai_quota('generate-report')),
  date_trunc('hour', statement_timestamp()) + interval '1 hour',
  'hourly exhaustion reports the next hour as its reset boundary'
);

SELECT results_eq(
  $$ SELECT allowed, remaining FROM public.consume_ai_quota('batch-explain') $$,
  $$ VALUES (true, 19) $$,
  'batch explanations have an independent 20-request hourly quota'
);
SELECT results_eq(
  $$ SELECT allowed, remaining FROM public.consume_ai_quota('context-chat') $$,
  $$ VALUES (true, 29) $$,
  'context chat has an independent 30-request hourly quota'
);

RESET ROLE;

SELECT results_eq(
  $$
    SELECT window_type, request_count
    FROM public.ai_usage_windows
    WHERE user_id = '11111111-1111-4111-8111-111111111111'
      AND function_name = 'generate-report'
    ORDER BY window_type
  $$,
  $$ VALUES ('day'::text, 5), ('hour'::text, 5) $$,
  'denied report requests do not increment stored quota windows'
);
SELECT results_eq(
  $$
    SELECT function_name, window_type, request_count
    FROM public.ai_usage_windows
    WHERE user_id = '11111111-1111-4111-8111-111111111111'
      AND function_name IN ('batch-explain', 'context-chat')
    ORDER BY function_name, window_type
  $$,
  $$
    VALUES
      ('batch-explain'::text, 'day'::text, 1),
      ('batch-explain'::text, 'hour'::text, 1),
      ('context-chat'::text, 'day'::text, 1),
      ('context-chat'::text, 'hour'::text, 1)
  $$,
  'quota storage remains isolated by AI function'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);
SELECT results_eq(
  $$ SELECT allowed, remaining FROM public.consume_ai_quota('generate-report') $$,
  $$ VALUES (true, 4) $$,
  'quota windows are isolated per user'
);

SELECT throws_ok(
  $$ SELECT public.consume_ai_quota('unsupported-function') $$,
  '22023',
  'Unsupported AI function',
  'unsupported quota names fail closed'
);

RESET ROLE;
SELECT is(
  (SELECT count(*)::integer FROM public.ai_usage_windows WHERE function_name = 'unsupported-function'),
  0,
  'unsupported quota requests never create usage rows'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT throws_ok(
  $$ SELECT public.consume_ai_quota('generate-report') $$,
  '42501',
  'Authentication required',
  'quota consumption fails closed without an authenticated user'
);

SELECT set_config('request.jwt.claim.sub', '55555555-5555-4555-8555-555555555555', true);
SELECT results_eq(
  $$ SELECT allowed, remaining FROM public.consume_ai_quota('generate-report') $$,
  $$ VALUES (false, 0) $$,
  'daily exhaustion denies requests even when hourly capacity remains'
);
SELECT is(
  (SELECT reset_at FROM public.consume_ai_quota('generate-report')),
  date_trunc('day', statement_timestamp(), 'UTC') + interval '1 day',
  'daily exhaustion reports the next UTC day as its reset boundary'
);

RESET ROLE;
SELECT is(
  (
    SELECT request_count
    FROM public.ai_usage_windows
    WHERE user_id = '55555555-5555-4555-8555-555555555555'
      AND function_name = 'generate-report'
      AND window_type = 'day'
  ),
  20,
  'daily denied requests do not increment stored quota usage'
);

SELECT * FROM finish();
ROLLBACK;
