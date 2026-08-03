BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(9);

INSERT INTO auth.users (id, email)
VALUES
  ('11111111-1111-4111-8111-111111111111', 'quota-one@example.test'),
  ('22222222-2222-4222-8222-222222222222', 'quota-two@example.test');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);

SELECT is(
  (SELECT allowed FROM public.consume_ai_quota('generate-report')),
  true,
  'first report generation request is allowed'
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

SELECT set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);
SELECT is(
  (SELECT allowed FROM public.consume_ai_quota('generate-report')),
  true,
  'quota windows are isolated per user'
);

SELECT throws_ok(
  $$ SELECT public.consume_ai_quota('unsupported-function') $$,
  '22023',
  'Unsupported AI function',
  'unsupported quota names fail closed'
);

SELECT * FROM finish();
ROLLBACK;
