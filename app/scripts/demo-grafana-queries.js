console.log(`
=== Grafana-ready SQL (Postgres) ===

-- 1) Events/sec (last 15 minutes)
select
  date_trunc('second', ts) as time,
  count(*) as events_per_sec
from clickstream_events
where ts >= now() - interval '15 minutes'
group by 1
order by 1;

-- 2) Events/min (last 6 hours)
select
  date_trunc('minute', ts) as time,
  count(*) as events_per_min
from clickstream_events
where ts >= now() - interval '6 hours'
group by 1
order by 1;

-- 3) Active users/min (last 6 hours)
select
  date_trunc('minute', ts) as time,
  count(distinct user_id) as active_users
from clickstream_events
where ts >= now() - interval '6 hours'
group by 1
order by 1;

-- 4) Top pages (last 24 hours)
select
  coalesce(page,'(null)') as page,
  count(*) as hits
from clickstream_events
where ts >= now() - interval '24 hours'
group by 1
order by 2 desc
limit 10;

-- 5) Top referrers (last 24 hours)
select
  coalesce(referrer,'(null)') as referrer,
  count(*) as hits
from clickstream_events
where ts >= now() - interval '24 hours'
group by 1
order by 2 desc
limit 10;

-- 6) Device split (last 24 hours)
select
  coalesce(device,'(null)') as device,
  count(*) as hits
from clickstream_events
where ts >= now() - interval '24 hours'
group by 1
order by 2 desc;

-- 7) “Live tail” table (last 50 events)
select ts, user_id, page, referrer, device
from clickstream_events
order by ts desc
limit 50;
`);
