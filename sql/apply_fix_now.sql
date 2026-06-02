-- ============================================================
-- これ1ファイルをそのまま SQL Editor に貼って Run でOK
--   ・STEP1（関数修正）は一瞬で終わる
--   ・STEP2 は「snapshot_base だけ」を更新（軽いのでタイムアウトしない）
--     → 総動画数がすぐ復旧する
--   ・残り5つの重いMVは今夜の自動収集(cron)が個別に更新するので放置でOK
-- ============================================================

-- STEP1: リフレッシュ関数の修正（statement_timeout=120s 付与＋非CONCURRENTLY化）
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

ALTER FUNCTION refresh_derived_mvs()       SET statement_timeout = '120s';
ALTER FUNCTION refresh_analytics_mvs()     SET statement_timeout = '120s';
ALTER FUNCTION refresh_type_base_mvs()     SET statement_timeout = '120s';
ALTER FUNCTION refresh_type_overlap_mvs()  SET statement_timeout = '120s';
ALTER FUNCTION refresh_type_keyword_mvs()  SET statement_timeout = '120s';
ALTER FUNCTION refresh_latest_snapshots()  SET statement_timeout = '120s';

-- STEP2: 総動画数を即時復旧（これだけは軽いので一括でも安全）
SELECT refresh_snapshot_base();

-- STEP3: 確認（videos_table_count ≒ mv_snapshot_count になれば復旧）
SELECT
    (SELECT COUNT(*) FROM videos)                   AS videos_table_count,
    (SELECT COUNT(*) FROM mv_latest_video_snapshot) AS mv_snapshot_count,
    (SELECT SUM(total_videos) FROM topic_summary WHERE parent_id IS NOT NULL) AS dashboard_total_videos;
