-- ============================================================
-- MVリフレッシュの statement timeout 修正
--
-- 【問題】
-- 約1ヶ月前から「総動画数」(topic_summary) が増えなくなった。
-- 原因は mv_latest_video_snapshot 等のMVリフレッシュが
-- Supabase Free プランの statement timeout (8秒) を超えて失敗し続けていたこと。
--
-- collector のログ（GitHub Actions / 2026-06-01 のラン）で確認:
--   refresh failed [Group1: snapshot base]:
--     'canceling statement due to statement timeout', code '57014'
--   （Group2/3/6 も同様にタイムアウト）
--
-- topic_summary は videos を mv_latest_video_snapshot と INNER JOIN している。
-- MVが凍結すると、収集済みの新しい動画がJOINで除外され件数に反映されない。
-- （videos / video_snapshots テーブル自体には毎日正常に書き込まれている＝
--   collection_log の更新履歴は前日分まで出るのに件数だけ増えない、の正体）
--
-- データ増加（約86k動画）で `REFRESH MATERIALIZED VIEW CONCURRENTLY` が
-- 8秒超になったのが引き金。
--
-- 【対策】
-- (A) 各リフレッシュ関数（SECURITY DEFINER）に statement_timeout を個別付与する。
--     関数実行中だけロールレベルの8秒制限を上書きできる
--     （Supabaseで重いメンテRPCを回す定番手法）。余裕として 120s を設定。
-- (B) refresh_snapshot_base() を非CONCURRENTLY化する。
--     - CONCURRENTLY はトランザクションブロック内で実行できないため、
--       このファイルを SQL Editor で一括 Run できるようにする狙いもある。
--     - 非CONCURRENTLY の方が差分計算が無く高速で、Free プランでも安定する。
--     - 代償は更新中の一瞬の読み取りロックのみ（日次・夜間・低トラフィックで許容）。
--
-- 【適用】Supabase SQL Editor にこのファイルを貼って Run（手動適用）。
-- ============================================================

-- ------------------------------------------------------------
-- STEP 1a: snapshot base を非CONCURRENTLY化 + timeout 付与
--   （タイムアウト設定は CREATE OR REPLACE 内の SET 句で同時に行う。
--     ALTER を別途打たなくても定義に焼き込まれる）
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION refresh_snapshot_base()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET statement_timeout = '120s'
AS $fn$
BEGIN
    REFRESH MATERIALIZED VIEW mv_latest_video_snapshot;
    REFRESH MATERIALIZED VIEW mv_latest_channel_snapshot;
END;
$fn$;

-- ------------------------------------------------------------
-- STEP 1b: 残りのリフレッシュ関数にも statement_timeout = 120s を付与
--   （これらは元から非CONCURRENTLY なので定義はそのまま、設定だけ追加）
-- ------------------------------------------------------------
ALTER FUNCTION refresh_derived_mvs()       SET statement_timeout = '120s';  -- Group2
ALTER FUNCTION refresh_analytics_mvs()     SET statement_timeout = '120s';  -- Group3
ALTER FUNCTION refresh_type_base_mvs()     SET statement_timeout = '120s';  -- Group4
ALTER FUNCTION refresh_type_overlap_mvs()  SET statement_timeout = '120s';  -- Group5
ALTER FUNCTION refresh_type_keyword_mvs()  SET statement_timeout = '120s';  -- Group6

-- 後方互換ラッパ（3グループを順番に呼ぶ。手動実行用）
ALTER FUNCTION refresh_latest_snapshots()  SET statement_timeout = '120s';

-- ------------------------------------------------------------
-- STEP 2: 凍結している件数を「今すぐ」復旧させる手動リフレッシュ
--   次の cron（毎日 08:00 UTC）を待たずに反映したい場合に実行する。
--   依存順に Group1 → Group6 で実行すること。
--   ※ 各 SELECT は数十秒かかる場合がある（正常）。
--   ※ 全関数が非CONCURRENTLY なので一括 Run でも問題ない。
-- ------------------------------------------------------------
SET statement_timeout = '120s';  -- このエディタセッションにも余裕を持たせる

SELECT refresh_snapshot_base();    -- mv_latest_video/channel_snapshot（← 総動画数の元）
SELECT refresh_derived_mvs();      -- mv_video_tags / topics / ranking / channel_growth
SELECT refresh_analytics_mvs();    -- mv_ai_penetration / keyword / overlap など
SELECT refresh_type_base_mvs();    -- mv_topic_video_short/normal, mv_active_ch_short/normal
SELECT refresh_type_overlap_mvs(); -- mv_topic_overlap_short/normal
SELECT refresh_type_keyword_mvs(); -- mv_keyword_opp/vir_short/normal

-- ------------------------------------------------------------
-- STEP 3: 復旧確認
--   videos_table_count ≒ mv_snapshot_count になっていれば凍結解消。
--   （以前は mv_snapshot_count だけが約1ヶ月前で止まっていた）
-- ------------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM videos)                       AS videos_table_count,
    (SELECT COUNT(*) FROM mv_latest_video_snapshot)     AS mv_snapshot_count,
    (SELECT SUM(total_videos) FROM topic_summary
        WHERE parent_id IS NOT NULL)                    AS dashboard_total_videos;
