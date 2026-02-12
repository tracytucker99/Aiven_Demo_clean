-- Ensure we can auto-generate UUIDs for clickstream_events.id

-- Try pgcrypto first (gen_random_uuid), common in managed Postgres
create extension if not exists pgcrypto;

-- Set default on id if missing
do $$
begin
  -- if column exists, set a default UUID generator
  if exists (
    select 1
    from information_schema.columns
    where table_schema='public' and table_name='clickstream_events' and column_name='id'
  ) then
    begin
      execute 'alter table clickstream_events alter column id set default gen_random_uuid()';
    exception when undefined_function then
      -- fallback: uuid-ossp if pgcrypto isn't available
      execute 'create extension if not exists "uuid-ossp"';
      execute 'alter table clickstream_events alter column id set default uuid_generate_v4()';
    end;
  end if;
end $$;

-- show the default so we can verify it took
select column_default
from information_schema.columns
where table_schema='public' and table_name='clickstream_events' and column_name='id';
