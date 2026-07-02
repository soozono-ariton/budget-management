-- ============================================
-- カンパ管理アプリ テーブル作成SQL
-- Supabaseの「SQL Editor」に貼り付けて Run してください
-- ============================================

-- 企画（生誕祭、フラスタ企画など）
create table projects (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

-- カンパ
create table donations (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  name text not null,
  amount integer not null check (amount > 0),
  date date not null default current_date,
  memo text default '',
  created_at timestamptz not null default now()
);

-- 経費
create table expenses (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references projects(id) on delete cascade,
  name text not null,
  amount integer not null check (amount > 0),
  date date not null default current_date,
  memo text default '',
  created_at timestamptz not null default now()
);

-- ============================================
-- アクセス権限（RLS）
-- ※ プロトタイプ段階のため「誰でも読み書き可」にしています。
--   URLを知っている人は操作できる状態です。
--   本格運用の前にログイン認証を追加して締めます。
-- ============================================
alter table projects enable row level security;
alter table donations enable row level security;
alter table expenses enable row level security;

create policy "anyone_projects" on projects for all using (true) with check (true);
create policy "anyone_donations" on donations for all using (true) with check (true);
create policy "anyone_expenses" on expenses for all using (true) with check (true);

-- サンプル企画を1件だけ入れておく
insert into projects (name) values ('〇〇ちゃん生誕祭2026');
