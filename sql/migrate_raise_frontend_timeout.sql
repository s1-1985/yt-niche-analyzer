-- ============================================================
-- フロントエンド(anon)クエリの境界タイムアウト対策
--
-- 実測: anon ロールの statement_timeout が約3秒しかなく、
--       多くのRPC/ビュー(fn_topic_summary, video_ranking 等)が
--       1〜5秒かかるため、境界で時々 500 (57014 statement timeout) になる。
--       （「まれに表示される」の正体）
--
-- 対策: anon / authenticated の statement_timeout を 15秒に引き上げる。
--       対象クエリは実測1〜5秒で完了するため十分な余裕。
--
-- 注意: 公開ダッシュボード(低トラフィック)なので15秒は許容。
--       本来は重いクエリのMV化が望ましいが、日付/国フィルタ付きRPCは
--       事前計算が困難なため、まずタイムアウト緩和で実用復旧させる。
-- ============================================================
ALTER ROLE anon          SET statement_timeout = '15s';
ALTER ROLE authenticated SET statement_timeout = '15s';

-- PostgREST に設定リロードを通知（Supabase 推奨手順）
NOTIFY pgrst, 'reload config';
