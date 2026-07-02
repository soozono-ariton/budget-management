# カンパ管理アプリ（budget-management）

アイドルの生誕祭やファン有志企画のための、カンパ・経費の登録＆集計アプリ。

## 構成

| ファイル | 内容 |
|---|---|
| `kanpa-app.html` | アプリ本体（単一HTML）。Supabaseに接続してデータを保存 |
| `setup.sql` | Supabaseのテーブル作成SQL（projects / donations / expenses） |

## セットアップ

1. [Supabase](https://supabase.com) で無料プロジェクトを作成（Region: Tokyo推奨）
2. SQL Editor で `setup.sql` を実行
3. Project Settings → API の「Project URL」と「anon public」キーを `kanpa-app.html` 冒頭の設定欄に貼り付け
4. `kanpa-app.html` をブラウザで開く

## 機能

- 企画（生誕祭・フラスタ企画など）の作成・切替
- カンパの登録・一覧・削除
- 経費の登録・一覧・削除
- 集計（人別カンパ内訳・経費内訳・全企画サマリー）

## 今後の予定

- ログイン認証（管理者のみ編集可）
- 領収書画像のアップロード
- 目標金額の設定と達成率表示
- Web公開（Vercel / Netlify）

## ブランチ運用

- `main` … 安定版
- `review` … 修正・作りこみ用。動作確認後にmainへマージ
