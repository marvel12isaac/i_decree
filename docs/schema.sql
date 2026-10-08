-- ============================================================
-- iDecree v2 — full schema (corrected)
-- ============================================================

-- PROFILES
create table profiles (
  id           uuid primary key references auth.users on delete cascade,
  display_name text not null default 'Decree Reader',
  fcm_token    text,
  created_at   timestamptz not null default now()
);

create function handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$ begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', 'Decree Reader'));
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- CHANNELS
create table channels (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 60),
  description text check (char_length(description) <= 300),
  join_code   text unique,
  owner_id    uuid not null references profiles(id) on delete cascade,
  created_at  timestamptz not null default now()
);

create index channels_name_idx on channels using gin (to_tsvector('simple', name));

-- MEMBERSHIPS
create table channel_memberships (
  channel_id uuid not null references channels(id) on delete cascade,
  user_id    uuid not null references profiles(id) on delete cascade,
  role       text not null default 'member' check (role in ('owner','admin','member')),
  joined_at  timestamptz not null default now(),
  primary key (channel_id, user_id)
);

create index memberships_user_idx on channel_memberships (user_id);

-- CHANNEL QUOTES
create table channel_quotes (
  id               uuid primary key default gen_random_uuid(),
  channel_id       uuid not null references channels(id) on delete cascade,
  text             text not null check (char_length(text) <= 1000),
  target_per_day   int  not null default 1 check (target_per_day between 1 and 10),
  window_start_min int  not null default 480,
  window_end_min   int  not null default 1200,
  position         int  not null default 0,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index quotes_channel_idx on channel_quotes (channel_id, position);

create function enforce_quote_cap()
returns trigger language plpgsql as $$ begin
  if (select count(*) from channel_quotes where channel_id = new.channel_id) >= 33 then
    raise exception 'A channel can have at most 33 decrees';
  end if;
  return new;
end $$;

create trigger quote_cap before insert on channel_quotes
  for each row execute function enforce_quote_cap();

create function touch_updated_at()
returns trigger language plpgsql as $$ begin
  new.updated_at = now();
  return new;
end $$;

create trigger quotes_touch before update on channel_quotes
  for each row execute function touch_updated_at();

-- READ EVENTS
create table read_events (
  quote_id   uuid not null references channel_quotes(id) on delete cascade,
  channel_id uuid not null references channels(id) on delete cascade,
  user_id    uuid not null references profiles(id) on delete cascade,
  day        date not null,
  read_count int  not null default 0 check (read_count >= 0),
  primary key (quote_id, user_id, day)
);

create index reads_channel_day_idx on read_events (channel_id, day);

-- USER BACKUPS
create table user_backups (
  user_id    uuid primary key references auth.users on delete cascade,
  payload    jsonb not null,
  updated_at timestamptz not null default now()
);

-- REPORTS
create table reports (
  id          uuid primary key default gen_random_uuid(),
  quote_id    uuid references channel_quotes(id) on delete cascade,
  channel_id  uuid references channels(id) on delete cascade,
  reporter_id uuid not null references profiles(id) on delete cascade,
  reason      text not null check (reason in ('spam','inappropriate','other')),
  comment     text check (char_length(comment) <= 500),
  created_at  timestamptz not null default now()
);

-- HELPER FUNCTIONS
create function is_channel_manager(p_channel uuid)
returns boolean language sql stable security definer set search_path = public as $$   select exists (
    select 1 from channel_memberships m
    where m.channel_id = p_channel
      and m.user_id = auth.uid()
      and m.role in ('owner','admin'))
 $$;

create function make_join_code()
returns text language plpgsql as $$ declare
  c text;
begin
  loop
    c := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    exit when not exists (select 1 from channels where join_code = c);
  end loop;
  return c;
end $$;

-- VIEWS (no policies on views — access is gated through the tables' RLS)
create view channel_stats with (security_invoker = true) as
select
  q.channel_id,
  q.id as quote_id,
  count(distinct r.user_id) as participants,
  count(distinct r.user_id) filter (where r.read_count >= q.target_per_day) as full_completions,
  count(distinct r.user_id) filter (where r.read_count > 0
                                     and r.read_count < q.target_per_day) as partial
from channel_quotes q
left join read_events r on r.quote_id = q.id
group by q.channel_id, q.id;

create view channel_member_counts with (security_invoker = true) as
select channel_id, count(*) as member_count
from channel_memberships
group by channel_id;

-- ROW LEVEL SECURITY
alter table profiles            enable row level security;
alter table channels            enable row level security;
alter table channel_memberships enable row level security;
alter table channel_quotes      enable row level security;
alter table read_events         enable row level security;
alter table user_backups        enable row level security;
alter table reports             enable row level security;

create policy "read profiles"  on profiles for select using (true);
create policy "insert profile" on profiles for insert with check (auth.uid() = id);
create policy "update profile" on profiles for update using (auth.uid() = id);

create policy "read channels"   on channels for select using (true);
create policy "create channel"  on channels for insert with check (auth.uid() = owner_id);
create policy "update channel"  on channels for update using (is_channel_manager(id));
create policy "delete channel"  on channels for delete using (
  exists (select 1 from channel_memberships m
          where m.channel_id = id and m.user_id = auth.uid() and m.role = 'owner'));

create policy "read memberships" on channel_memberships for select using (true);
create policy "join"  on channel_memberships for insert with check (auth.uid() = user_id);
create policy "leave" on channel_memberships for delete using (auth.uid() = user_id);
create policy "owner manages roles" on channel_memberships for update
  using (exists (select 1 from channel_memberships m
                 where m.channel_id = channel_memberships.channel_id
                   and m.user_id = auth.uid() and m.role = 'owner'));

create policy "read quotes"   on channel_quotes for select using (true);
create policy "manage quotes" on channel_quotes for all
  using (is_channel_manager(channel_id))
  with check (is_channel_manager(channel_id));

create policy "upload own reads" on read_events for insert
  with check (auth.uid() = user_id
              and exists (select 1 from channel_memberships m
                          where m.channel_id = read_events.channel_id
                            and m.user_id = auth.uid()));
create policy "update own reads" on read_events for update
  using (auth.uid() = user_id);

create policy "own backup" on user_backups for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "file report" on reports for insert
  with check (auth.uid() = reporter_id);