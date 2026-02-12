INSERT INTO public.clickstream_events
  (id, ts, user_id, event_type, url, referrer, user_agent, session_id, event_name, revenue)
SELECT
  gen_random_uuid(),
  now() - (i * interval '2 seconds'),
  'user_' || (i % 25),
  'page_view',
  '/product/' || (i % 20),
  'https://example.com',
  'demo-agent',
  'sess_' || (i % 50),
  'view',
  0
FROM generate_series(1, 300) AS i;

SELECT
  now() AS now_utc,
  max(ts) AS last_event_ts,
  now() - max(ts) AS age,
  count(*) FILTER (WHERE ts > now() - interval '15 minutes') AS events_last_15m
FROM public.clickstream_events;
