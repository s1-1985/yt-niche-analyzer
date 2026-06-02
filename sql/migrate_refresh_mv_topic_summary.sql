-- ============================================================
-- mv_topic_summary を日次リフレッシュに組み込む（総動画数 凍結の再発防止）
--
-- 経緯:
--   topic_summary ビューの実体は mv_topic_summary（マテビュー）だが、
--   どのリフレッシュ関数にも繋がっておらず、リポジトリSQLにも無かった
--   （過去にSupabase上で直接作られた）。誰も更新しないため作成時点で凍結し、
--   ダッシュボード「総動画数」が約1ヶ月 86,153 で固定されていた。
--
-- 方針:
--   既存のリフレッシュ関数は触らず（drift時の巻き込み防止）、
--   専用の refresh_topic_summary() を追加し、コレクターの呼び出し列に加える
--   （collector/supabase_client.py 側を更新）。
-- ============================================================

-- ------------------------------------------------------------
-- (1) リポジトリ整合用: mv_topic_summary 定義を記録（既存DBでは IF NOT EXISTS でスキップ）
--     ※ 実DBには既に存在するため、ここは fresh setup 用のドキュメント目的。
-- ------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_topic_summary AS
SELECT
    t.id AS topic_id,
    t.name AS topic_name,
    t.name_ja,
    t.parent_id,
    t.category,
    COUNT(DISTINCT v.id) AS total_videos,
    COUNT(DISTINCT v.channel_id) AS total_channels,
    COALESCE(SUM(vs.view_count), 0) AS total_views,
    COALESCE(AVG(vs.view_count), 0)::BIGINT AS avg_views,
    CASE WHEN COUNT(DISTINCT v.channel_id) > 0
        THEN (COALESCE(AVG(vs.view_count), 0) / COUNT(DISTINCT v.channel_id))::BIGINT
        ELSE 0
    END AS gap_score,
    CASE WHEN COALESCE(SUM(vs.view_count), 0) > 0
        THEN ROUND(COALESCE(SUM(vs.like_count), 0)::NUMERIC / SUM(vs.view_count) * 100, 2)
        ELSE 0
    END AS like_rate_pct,
    CASE WHEN COALESCE(SUM(vs.view_count), 0) > 0
        THEN ROUND(COALESCE(SUM(vs.comment_count), 0)::NUMERIC / SUM(vs.view_count) * 100, 4)
        ELSE 0
    END AS comment_rate_pct
FROM topics t
JOIN videos v ON t.id = ANY(v.topic_ids)
JOIN mv_latest_video_snapshot vs ON v.id = vs.video_id
GROUP BY t.id, t.name, t.name_ja, t.parent_id, t.category;

-- 薄いラッパビュー（実DBの現状に合わせる。既存と同一なら no-op）
CREATE OR REPLACE VIEW topic_summary AS
SELECT topic_id, topic_name, name_ja, parent_id, category,
       total_videos, total_channels, total_views, avg_views,
       gap_score, like_rate_pct, comment_rate_pct
FROM mv_topic_summary;

-- ------------------------------------------------------------
-- (2) ★本体: 専用リフレッシュ関数（追加のみ。既存関数は変更しない）
--     mv_topic_summary は mv_latest_video_snapshot に依存するため、
--     コレクターでは Group1(refresh_snapshot_base) の後に呼ぶこと。
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION refresh_topic_summary()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET statement_timeout = '120s'
AS $fn$
BEGIN
    REFRESH MATERIALIZED VIEW mv_topic_summary;
END;
$fn$;

GRANT EXECUTE ON FUNCTION refresh_topic_summary() TO anon, authenticated, service_role;

-- ------------------------------------------------------------
-- (3) 即時リフレッシュ（手動実行済みでも再実行で最新化。安全）
-- ------------------------------------------------------------
SELECT refresh_topic_summary();
