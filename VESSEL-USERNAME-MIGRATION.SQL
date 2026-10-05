-- Run this once in the Supabase SQL Editor before enabling username sign-in.
alter table public.vessel_accounts add column if not exists username text;

update public.vessel_accounts as accounts
set username = coalesce(
  nullif(lower(btrim(users.raw_user_meta_data ->> 'crew_username')), ''),
  'crew_' || substr(replace(accounts.user_id::text, '-', ''), 1, 24)
)
from auth.users as users
where accounts.user_id = users.id and accounts.username is null;

alter table public.vessel_accounts alter column username set not null;
create unique index if not exists vessel_accounts_username_idx
  on public.vessel_accounts (username);
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.vessel_accounts'::regclass
      and conname = 'vessel_accounts_username_format'
  ) then
    alter table public.vessel_accounts
      add constraint vessel_accounts_username_format
      check (username ~ '^[a-z0-9_.-]{3,32}$');
  end if;
end;
$$;

create or replace function public.register_vessel_account()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested_vessel text;
  requested_username text;
begin
  if coalesce(new.raw_user_meta_data ->> 'signup_role', '') <> 'vessel' then
    return new;
  end if;

  requested_vessel := btrim(coalesce(new.raw_user_meta_data ->> 'vessel_name', ''));
  requested_username := lower(btrim(coalesce(new.raw_user_meta_data ->> 'crew_username', '')));
  if requested_username = '' then
    requested_username := 'crew_' || substr(replace(new.id::text, '-', ''), 1, 24);
  end if;
  if requested_username !~ '^[a-z0-9_.-]{3,32}$' then
    raise exception 'Username must be 3-32 characters using letters, numbers, period, underscore, or hyphen';
  end if;
  if requested_vessel not in (
    'LCT 668','LCT 868','LCT 888','LCT 1018','LCT 1020','LCT 1030',
    'LCT 1035','LCT 1060','LCT 1070','LCT 1078','LCT 1080','LCT 1090','LCT 1098'
  ) then
    raise exception 'Select a valid company vessel';
  end if;

  insert into public.vessel_accounts (user_id, email, username, vessel_name)
  values (new.id, lower(new.email), requested_username, requested_vessel);
  return new;
end;
$$;
