-- ============================================
-- QR受付（カンパした本人が自分で入力）機能 移行SQL
-- 委員が企画ごとに「受付」を開始すると、受付用トークン入りのURL（QRコード）が発行される。
-- 本人の入力は intake_entries（受付待ち）に入り、委員が承認すると donations に移る。
-- テーブルへの直接アクセスは不可（RLS有効・ポリシーなし）。すべてRPC経由。
-- ============================================

alter table projects add column if not exists intake_token text unique;

create table if not exists intake_entries (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  name text not null,
  username text,
  amount integer not null,
  method text,
  memo text,
  created_at timestamptz not null default now()
);
alter table intake_entries enable row level security;

-- ===== 委員側（部屋の合言葉が必要） =====
create or replace function room_intake_start(rid uuid, p_pass text, pid uuid) returns text language plpgsql security definer set search_path = public, extensions as $$
declare v text;
begin
  if not room_ok(rid, p_pass) then raise exception 'unauthorized'; end if;
  update projects set intake_token = encode(gen_random_bytes(16), 'hex') where id = pid and room_id = rid returning intake_token into v;
  return v;
end; $$;

create or replace function room_intake_stop(rid uuid, p_pass text, pid uuid) returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not room_ok(rid, p_pass) then raise exception 'unauthorized'; end if;
  update projects set intake_token = null where id = pid and room_id = rid;
end; $$;

create or replace function room_intake_list(rid uuid, p_pass text) returns json language sql security definer set search_path = public, extensions as $$
  select case when room_ok(rid, p_pass) then (
    select coalesce(json_agg(t), '[]'::json) from (
      select e.* from intake_entries e join projects p on p.id = e.project_id
      where p.room_id = rid order by e.created_at
    ) t
  ) else null end;
$$;

create or replace function room_intake_approve(rid uuid, p_pass text, eid uuid) returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not room_ok(rid, p_pass) then raise exception 'unauthorized'; end if;
  insert into donations (project_id, name, username, amount, method, recipient, memo, date)
    select e.project_id, e.name, e.username, e.amount, e.method, '', coalesce(e.memo, ''), (e.created_at at time zone 'Asia/Tokyo')::date
    from intake_entries e join projects p on p.id = e.project_id
    where e.id = eid and p.room_id = rid;
  delete from intake_entries e using projects p where e.id = eid and p.id = e.project_id and p.room_id = rid;
end; $$;

create or replace function room_intake_reject(rid uuid, p_pass text, eid uuid) returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not room_ok(rid, p_pass) then raise exception 'unauthorized'; end if;
  delete from intake_entries e using projects p where e.id = eid and p.id = e.project_id and p.room_id = rid;
end; $$;

-- ===== 本人側（QRのトークンだけで使える） =====
create or replace function intake_info(tok text) returns json language sql security definer set search_path = public, extensions as $$
  select json_build_object('project', p.name) from projects p
  where tok is not null and length(tok) >= 32 and p.intake_token = tok;
$$;

create or replace function intake_submit(tok text, pname text, pusername text, pamount integer, pmethod text, pmemo text) returns boolean language plpgsql security definer set search_path = public, extensions as $$
declare v uuid;
begin
  if tok is null or length(tok) < 32 then return false; end if;
  select id into v from projects where intake_token = tok;
  if v is null then return false; end if;
  pname := trim(coalesce(pname, ''));
  pusername := trim(coalesce(pusername, ''));
  pmemo := trim(coalesce(pmemo, ''));
  if length(pname) = 0 or length(pname) > 50 then raise exception 'invalid name'; end if;
  if length(pusername) > 50 or length(pmemo) > 200 then raise exception 'too long'; end if;
  if pamount is null or pamount < 1 or pamount > 1000000 then raise exception 'invalid amount'; end if;
  if pmethod not in ('現金', 'PayPay', 'オンライン') then pmethod := '現金'; end if;
  if (select count(*) from intake_entries where project_id = v) >= 300 then raise exception 'too many pending'; end if;
  insert into intake_entries (project_id, name, username, amount, method, memo) values (v, pname, pusername, pamount, pmethod, pmemo);
  return true;
end; $$;

-- ===== 承認前の修正（委員側） =====
create or replace function room_intake_update(rid uuid, p_pass text, eid uuid, pname text, pusername text, pamount integer, pmethod text, pmemo text) returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not room_ok(rid, p_pass) then raise exception 'unauthorized'; end if;
  if length(trim(coalesce(pname, ''))) = 0 then raise exception 'invalid name'; end if;
  if pamount is null or pamount < 1 then raise exception 'invalid amount'; end if;
  update intake_entries e set name = trim(pname), username = trim(coalesce(pusername, '')), amount = pamount, method = pmethod, memo = trim(coalesce(pmemo, ''))
    from projects p where e.id = eid and p.id = e.project_id and p.room_id = rid;
end; $$;
