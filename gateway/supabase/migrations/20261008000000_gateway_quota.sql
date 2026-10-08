-- Doddy gateway: anonymous device sessions + quotas. No personal content is stored here.
create table public.devices (
  id uuid primary key default gen_random_uuid(),
  token_hash text not null unique,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create table public.device_usage (
  device_id uuid not null references public.devices(id) on delete cascade,
  day date not null,
  requests integer not null default 0 check (requests >= 0),
  primary key (device_id, day)
);

create table public.daily_totals (
  day date primary key,
  requests integer not null default 0 check (requests >= 0),
  registrations integer not null default 0 check (registrations >= 0)
);

-- Service role only: RLS on, no policies, no grants to anon/authenticated.
alter table public.devices enable row level security;
alter table public.device_usage enable row level security;
alter table public.daily_totals enable row level security;
revoke all on public.devices, public.device_usage, public.daily_totals from anon, authenticated;

-- Atomically count a registration against the global daily cap.
create function public.register_device(p_token_hash text, p_max_registrations integer)
returns uuid
language plpgsql security definer set search_path = public as $$
declare v_day date := (now() at time zone 'utc')::date; v_regs integer; v_id uuid;
begin
  insert into daily_totals(day, registrations) values (v_day, 1)
    on conflict (day) do update set registrations = daily_totals.registrations + 1
    returning registrations into v_regs;
  if v_regs > p_max_registrations then
    update daily_totals set registrations = registrations - 1 where day = v_day;
    return null;
  end if;
  insert into devices(token_hash) values (p_token_hash) returning id into v_id;
  return v_id;
end $$;

-- Atomically spend one request: returns 'ok' | 'unknown_device' | 'device_limit' | 'global_limit'.
create function public.consume_quota(p_token_hash text, p_device_limit integer, p_global_limit integer)
returns text
language plpgsql security definer set search_path = public as $$
declare v_day date := (now() at time zone 'utc')::date; v_dev uuid; v_dev_n integer; v_glob_n integer;
begin
  select id into v_dev from devices where token_hash = p_token_hash;
  if v_dev is null then return 'unknown_device'; end if;
  insert into daily_totals(day, requests) values (v_day, 1)
    on conflict (day) do update set requests = daily_totals.requests + 1
    returning requests into v_glob_n;
  if v_glob_n > p_global_limit then
    update daily_totals set requests = requests - 1 where day = v_day;
    return 'global_limit';
  end if;
  insert into device_usage(device_id, day, requests) values (v_dev, v_day, 1)
    on conflict (device_id, day) do update set requests = device_usage.requests + 1
    returning requests into v_dev_n;
  if v_dev_n > p_device_limit then
    update device_usage set requests = requests - 1 where device_id = v_dev and day = v_day;
    update daily_totals set requests = requests - 1 where day = v_day;
    return 'device_limit';
  end if;
  update devices set last_seen_at = now() where id = v_dev;
  return 'ok';
end $$;

revoke all on function public.register_device(text, integer), public.consume_quota(text, integer, integer) from public, anon, authenticated;
grant execute on function public.register_device(text, integer), public.consume_quota(text, integer, integer) to service_role;
