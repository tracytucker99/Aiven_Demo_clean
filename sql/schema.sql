-- Raw clickstream events
create table if not exists clickstream_events (
  event_id        bigserial primary key,
  ts              timestamptz not null,
  user_id         text not null,
  session_id      text not null,
  event_name      text not null,
  url             text null,
  referrer        text null,
  user_agent      text null,
  revenue         numeric(12,2) null,
  received_at     timestamptz not null default now()
);

create index if not exists ix_clickstream_events_user_ts
  on clickstream_events (user_id, ts desc);

create index if not exists ix_clickstream_events_session_ts
  on clickstream_events (session_id, ts desc);

-- Session-level metrics
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
