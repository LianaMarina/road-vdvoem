-- Дорога вдвоём: private family trip. Run ONCE in Supabase SQL Editor.
-- IMPORTANT: Change the invitation code below BEFORE running this file.
create extension if not exists pgcrypto;
create table if not exists public.family_trips (
 id uuid primary key default gen_random_uuid(),
 invite_hash text not null,
 created_at timestamptz not null default now()
);
create table if not exists public.family_members (
 trip_id uuid not null references public.family_trips(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 primary key (trip_id,user_id)
);
create table if not exists public.family_budget (
 trip_id uuid primary key references public.family_trips(id) on delete cascade,
 content jsonb not null default '{}'::jsonb,
 revision bigint not null default 0,
 changed_at timestamptz not null default now()
);
create index if not exists family_members_user_idx on public.family_members(user_id);
alter table public.family_trips enable row level security;
alter table public.family_members enable row level security;
alter table public.family_budget enable row level security;
revoke all on public.family_trips,public.family_members,public.family_budget from anon,authenticated;
grant select on public.family_budget to authenticated;
create or replace function public.is_family_member(p_trip uuid)
returns boolean language sql security definer stable set search_path = '' as $$
 select auth.uid() is not null and exists(
  select 1 from public.family_members where trip_id=p_trip and user_id=auth.uid()
 );
$$;
revoke execute on function public.is_family_member(uuid) from public,anon;
grant execute on function public.is_family_member(uuid) to authenticated;
create policy "family may read budget" on public.family_budget for select to authenticated
 using (public.is_family_member(trip_id));
-- Function: code checked only on server; no public table access.
create or replace function public.join_family_trip(p_code text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_trip uuid;
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 if length(p_code)<12 then raise exception 'Invalid code'; end if;
 select id into v_trip from public.family_trips
  where invite_hash = crypt(p_code,invite_hash) limit 1;
 if v_trip is null then raise exception 'Invalid invitation code'; end if;
 insert into public.family_members(trip_id,user_id) values (v_trip,auth.uid()) on conflict do nothing;
 return v_trip;
end;$$;
create or replace function public.save_family_budget(p_trip uuid,p_revision bigint,p_content jsonb)
returns bigint language plpgsql security definer set search_path = '' as $$
declare next_rev bigint;
begin
 if auth.uid() is null or not exists(select 1 from public.family_members where trip_id=p_trip and user_id=auth.uid()) then
  raise exception 'Not a member';
 end if;
 if jsonb_typeof(p_content)<>'object' or length(p_content::text)>500000 then raise exception 'Invalid budget data'; end if;
 update public.family_budget set content=p_content, revision=revision+1, changed_at=now()
  where trip_id=p_trip and revision=p_revision returning revision into next_rev;
 return next_rev; -- null on conflict
end;$$;
revoke execute on function public.join_family_trip(text) from public,anon;
revoke execute on function public.save_family_budget(uuid,bigint,jsonb) from public,anon;
grant execute on function public.join_family_trip(text) to authenticated;
grant execute on function public.save_family_budget(uuid,bigint,jsonb) to authenticated;
-- Change this secret to your own long code, e.g. 20+ random characters.
insert into public.family_trips(invite_hash)
values (crypt('REPLACE_WITH_YOUR_PRIVATE_INVITATION_CODE_2026',gen_salt('bf')));
insert into public.family_budget(trip_id)
select id from public.family_trips order by created_at desc limit 1;
