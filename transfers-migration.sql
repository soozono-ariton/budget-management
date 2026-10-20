-- ============================================
-- 預かり金の付け替え（Aさん→Bさん）移行SQL（2026-10-20）
-- 受取者ごとの預かり金 = 受け取ったカンパ + 受け取った付け替え − 渡した付け替え − 支払った経費（対応者）
-- テーブルへの直接アクセスは不可（RLS有効・ポリシーなし）。すべてRPC経由。
-- ============================================

create table if not exists transfers (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  from_name text not null default '',
  to_name text not null,
  amount integer not null,
  memo text,
  date date not null default current_date,
  created_at timestamptz not null default now()
);
alter table transfers enable row level security;

create or replace function room_transfer_list(rid uuid, p_pass text) returns json language sql security definer set search_path = public, extensions as $$
  select case when room_ok(rid, p_pass) then (
    select coalesce(json_agg(t), '[]'::json) from (
      select x.* from transfers x join projects p on p.id = x.project_id
      where p.room_id = rid order by x.date desc, x.created_at desc
    ) t
  ) else null end;
$$;

create or replace function room_add_transfer(rid uuid, p_pass text, pid uuid, pfrom text, pto text, pamount integer, pmemo text, pdate date) returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not room_ok(rid, p_pass) then raise exception 'unauthorized'; end if;
  if not exists (select 1 from projects where id = pid and room_id = rid) then raise exception 'invalid project'; end if;
  pfrom := trim(coalesce(pfrom, ''));
  pto := trim(coalesce(pto, ''));
  if length(pto) = 0 then raise exception 'invalid to'; end if;
  if pfrom = pto then raise exception 'same person'; end if;
  if pamount is null or pamount < 1 then raise exception 'invalid amount'; end if;
  insert into transfers (project_id, from_name, to_name, amount, memo, date)
    values (pid, pfrom, pto, pamount, trim(coalesce(pmemo, '')), coalesce(pdate, (now() at time zone 'Asia/Tokyo')::date));
end; $$;

create or replace function room_del_transfer(rid uuid, p_pass text, tid uuid) returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not room_ok(rid, p_pass) then raise exception 'unauthorized'; end if;
  delete from transfers x using projects p where x.id = tid and p.id = x.project_id and p.room_id = rid;
end; $$;
