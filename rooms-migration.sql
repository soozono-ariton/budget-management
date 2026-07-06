-- ============================================
-- 部屋（合言葉）機能 移行SQL（適用済み・記録用）
-- 各グループは「部屋名＋合言葉」で自分の部屋のデータだけにアクセスできる。
-- テーブルへの直接アクセスは遮断し、すべて下記のRPC関数経由。
-- 合言葉はbcryptでハッシュ化して保存。
-- ============================================

create extension if not exists pgcrypto;

create table rooms (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  pass_hash text not null,
  created_at timestamptz not null default now()
);
alter table rooms enable row level security;

alter table projects add column room_id uuid references rooms(id) on delete cascade;

-- 全開放ポリシーを削除（RLS有効・ポリシーなし＝直接アクセス不可）
drop policy "anyone_projects" on projects;
drop policy "anyone_donations" on donations;
drop policy "anyone_expenses" on expenses;
drop policy "anyone_budgets" on budgets;

-- 既存データの移行（部屋名: テスト部屋 / 合言葉: test）
insert into rooms (name, pass_hash) values ('テスト部屋', crypt('test', gen_salt('bf')));
update projects set room_id = (select id from rooms where name = 'テスト部屋') where room_id is null;

-- ===== 認証 =====
create or replace function room_ok(rid uuid, p_pass text) returns boolean language sql security definer set search_path = public, extensions as $$ select exists (select 1 from rooms where id = rid and pass_hash = crypt(p_pass, pass_hash)); $$;

create or replace function create_room(p_name text, p_pass text) returns uuid language plpgsql security definer set search_path = public, extensions as $$ declare v uuid; begin if exists (select 1 from rooms where name = p_name) then return null; end if; insert into rooms (name, pass_hash) values (p_name, crypt(p_pass, gen_salt('bf'))) returning id into v; return v; end; $$;

create or replace function open_room(p_name text, p_pass text) returns uuid language sql security definer set search_path = public, extensions as $$ select id from rooms where name = p_name and pass_hash = crypt(p_pass, pass_hash); $$;

-- ===== データ取得 =====
create or replace function room_data(rid uuid, p_pass text) returns json language sql security definer set search_path = public, extensions as $$ select case when room_ok(rid, p_pass) then json_build_object('projects', (select coalesce(json_agg(t), '[]'::json) from (select * from projects where room_id = rid order by created_at) t), 'donations', (select coalesce(json_agg(t), '[]'::json) from (select d.* from donations d join projects p on p.id = d.project_id where p.room_id = rid order by d.date desc, d.created_at desc) t), 'expenses', (select coalesce(json_agg(t), '[]'::json) from (select e.* from expenses e join projects p on p.id = e.project_id where p.room_id = rid order by e.date desc, e.created_at desc) t), 'budgets', (select coalesce(json_agg(t), '[]'::json) from (select b.* from budgets b join projects p on p.id = b.project_id where p.room_id = rid order by b.created_at) t)) else null end; $$;

-- ===== 登録・更新・削除 =====
create or replace function room_add_project(rid uuid, p_pass text, pname text) returns uuid language plpgsql security definer set search_path = public, extensions as $$ declare v uuid; begin if not room_ok(rid, p_pass) then raise exception 'unauthorized'; end if; insert into projects (name, room_id) values (pname, rid) returning id into v; return v; end; $$;

create or replace function room_set_goal(rid uuid, p_pass text, pid uuid, goal integer) returns void language plpgsql security definer set search_path = public, extensions as $$ begin if not room_ok(rid, p_pass) then raise exception 'unauthorized'; end if; update projects set goal_amount = goal where id = pid and room_id = rid; end; $$;

create or replace function room_add_donation(rid uuid, p_pass text, pid uuid, pname text, pusername text, pamount integer, pmethod text, precipient text, pmemo text, pdate date) returns void language plpgsql security definer set search_path = public, extensions as $$ begin if not room_ok(rid, p_pass) then raise exception 'unauthorized'; end if; if not exists (select 1 from projects where id = pid and room_id = rid) then raise exception 'invalid project'; end if; insert into donations (project_id, name, username, amount, method, recipient, memo, date) values (pid, pname, pusername, pamount, pmethod, precipient, pmemo, coalesce(pdate, current_date)); end; $$;

create or replace function room_del_donation(rid uuid, p_pass text, did uuid) returns void language plpgsql security definer set search_path = public, extensions as $$ begin if not room_ok(rid, p_pass) then raise exception 'unauthorized'; end if; delete from donations d using projects p where d.id = did and p.id = d.project_id and p.room_id = rid; end; $$;

create or replace function room_add_expense(rid uuid, p_pass text, pid uuid, pname text, pamount integer, phandler text, pmemo text, pdate date) returns void language plpgsql security definer set search_path = public, extensions as $$ begin if not room_ok(rid, p_pass) then raise exception 'unauthorized'; end if; if not exists (select 1 from projects where id = pid and room_id = rid) then raise exception 'invalid project'; end if; insert into expenses (project_id, name, amount, handler, memo, date) values (pid, pname, pamount, phandler, pmemo, coalesce(pdate, current_date)); end; $$;

create or replace function room_del_expense(rid uuid, p_pass text, eid uuid) returns void language plpgsql security definer set search_path = public, extensions as $$ begin if not room_ok(rid, p_pass) then raise exception 'unauthorized'; end if; delete from expenses e using projects p where e.id = eid and p.id = e.project_id and p.room_id = rid; end; $$;

create or replace function room_add_budget(rid uuid, p_pass text, pid uuid, pname text, pamount integer, pmemo text) returns void language plpgsql security definer set search_path = public, extensions as $$ begin if not room_ok(rid, p_pass) then raise exception 'unauthorized'; end if; if not exists (select 1 from projects where id = pid and room_id = rid) then raise exception 'invalid project'; end if; insert into budgets (project_id, name, amount, memo) values (pid, pname, pamount, pmemo); end; $$;

create or replace function room_del_budget(rid uuid, p_pass text, bid uuid) returns void language plpgsql security definer set search_path = public, extensions as $$ begin if not room_ok(rid, p_pass) then raise exception 'unauthorized'; end if; delete from budgets b using projects p where b.id = bid and p.id = b.project_id and p.room_id = rid; end; $$;
