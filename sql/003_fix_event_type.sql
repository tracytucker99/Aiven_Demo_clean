-- Make legacy NOT NULL column event_type compatible with event_name inserts.

-- 1) If event_type exists and is NOT NULL, give it a default so inserts won't fail.
do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema='public' and table_name='clickstream_events' and column_name='event_type'
  ) then
    -- Default to event_name when present, else fallback
    execute $$alter table clickstream_events
             alter column event_type set default 'unknown'$$;
  end if;
end $$;

-- 2) Create a trigger to keep event_type in sync with event_name on insert/update.
create or replace function clickstream_events_sync_event_type()
returns trigger as $$
begin
  if new.event_type is null or new.event_type = '' then
    if new.event_name is not null and new.event_name <> '' then
      new.event_type := new.event_name;
    else
      new.event_type := 'unknown';
    end if;
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_clickstream_events_sync_event_type on clickstream_events;

create trigger trg_clickstream_events_sync_event_type
before insert or update on clickstream_events
for each row
execute function clickstream_events_sync_event_type();

-- Show current nullability + default
select
  column_name, is_nullable, column_default
from information_schema.columns
where table_schema='public'
  and table_name='clickstream_events'
  and column_name in ('event_type','event_name','id')
order by column_name;
