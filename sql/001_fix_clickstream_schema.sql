-- Make clickstream_events match what the consumer inserts.
-- Safe: adds missing columns only; no drop.

alter table if exists clickstream_events
  add column if not exists ts timestamptz,
  add column if not exists user_id text,
  add column if not exists session_id text,
  add column if not exists event_name text,
  add column if not exists url text,
  add column if not exists referrer text,
  add column if not exists user_agent text,
  add column if not exists revenue numeric(12,2),
  add column if not exists received_at timestamptz not null default now();

-- If your table was created with different names or nullability,
-- enforce not-null for core fields only if the table is empty.
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema='public' and table_name='clickstream_events') then
    if (select count(*) from clickstream_events) = 0 then
      alter table clickstream_events
        alter column ts set not null,
        alter column user_id set not null,
        alter column session_id set not null,
        alter column event_name set not null;
    end if;
  end if;
end $$;

create index if not exists ix_clickstream_events_user_ts
  on clickstream_events (user_id, ts desc);

create index if not exists ix_clickstream_events_session_ts
  on clickstream_events (session_id, ts desc);

-- Ensure session rollup table exists (used by earlier versions of the consumer; optional but useful)
create table if not exists clickstream_sessions (
  session_id      text primary key,
  user_id         text not null,
  session_start   timestamptz not null,
  session_end     timestamptz not null,
  event_count     int not null,
  pageviews       int not null,
  conversions     int not null,
  revenue_total   numeric(12,2) not null,
  last_updated_at timestamptz not null default now()
);

create index if not exists ix_clickstream_sessions_user_end
  on clickstream_sessions (user_id, session_end desc);
