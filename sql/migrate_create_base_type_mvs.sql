-- ============================================================
-- ベースMV作成（short/normal フィルタ用）
--
-- このファイルだけ実行すれば video_type=short/normal が動く。
-- 前提: mv_video_topics, mv_latest_video_snapshot が存在すること。
--
-- 作成するMV（6個）:
--   mv_topic_video_short / mv_topic_video_normal
--   mv_active_ch_short   / mv_active_ch_normal
--   mv_topic_overlap_short / mv_topic_overlap_normal
-- ============================================================

-- ============================================================
-- 1. mv_topic_video_short / mv_topic_video_normal
--    topic×video 結合済みMV（short/normal 版）
-- ============================================================
DROP MATERIALIZED VIEW IF EXISTS mv_topic_video_short CASCADE;
CREATE MATERIALIZED VIEW mv_topic_video_short AS
SELECT
    vt.topic_id,
    vt.video_id,
    vt.channel_id,
    vt.published_at,
    vt.has_ai_keywords,
    vt.duration_seconds,
    vs.view_count,
    vs.like_count,
    vs.comment_count
FROM mv_video_topics vt
JOIN mv_latest_video_snapshot vs ON vt.video_id = vs.video_id
WHERE vt.duration_seconds <= 60;

CREATE INDEX ON mv_topic_video_short(topic_id);
CREATE INDEX ON mv_topic_video_short(channel_id);
CREATE INDEX ON mv_topic_video_short(video_id);
GRANT SELECT ON mv_topic_video_short TO anon, authenticated;

DROP MATERIALIZED VIEW IF EXISTS mv_topic_video_normal CASCADE;
CREATE MATERIALIZED VIEW mv_topic_video_normal AS
SELECT
    vt.topic_id,
    vt.video_id,
    vt.channel_id,
    vt.published_at,
    vt.has_ai_keywords,
    vt.duration_seconds,
    vs.view_count,
    vs.like_count,
    vs.comment_count
FROM mv_video_topics vt
JOIN mv_latest_video_snapshot vs ON vt.video_id = vs.video_id
WHERE vt.duration_seconds > 60;

CREATE INDEX ON mv_topic_video_normal(topic_id);
CREATE INDEX ON mv_topic_video_normal(channel_id);
CREATE INDEX ON mv_topic_video_normal(video_id);
GRANT SELECT ON mv_topic_video_normal TO anon, authenticated;

-- ============================================================
-- 2. mv_active_ch_short / mv_active_ch_normal
--    チャンネルIDのみの軽量MV（channel系RPCのJOIN用）
-- ============================================================
DROP MATERIALIZED VIEW IF EXISTS mv_active_ch_short CASCADE;
CREATE MATERIALIZED VIEW mv_active_ch_short AS
SELECT DISTINCT channel_id FROM mv_video_topics WHERE duration_seconds <= 60;
CREATE INDEX ON mv_active_ch_short(channel_id);
GRANT SELECT ON mv_active_ch_short TO anon, authenticated;

DROP MATERIALIZED VIEW IF EXISTS mv_active_ch_normal CASCADE;
CREATE MATERIALIZED VIEW mv_active_ch_normal AS
SELECT DISTINCT channel_id FROM mv_video_topics WHERE duration_seconds > 60;
CREATE INDEX ON mv_active_ch_normal(channel_id);
GRANT SELECT ON mv_active_ch_normal TO anon, authenticated;

-- ============================================================
-- 3. mv_topic_overlap_short / mv_topic_overlap_normal
--    fn_topic_overlap の short/normal 版（重いself-JOINを事前計算）
-- ============================================================
DROP MATERIALIZED VIEW IF EXISTS mv_topic_overlap_short CASCADE;
CREATE MATERIALIZED VIEW mv_topic_overlap_short AS
SELECT
    t1.id    AS topic_a,
    t1.name_ja AS name_a,
    t2.id    AS topic_b,
    t2.name_ja AS name_b,
    COUNT(DISTINCT c.id)::BIGINT AS shared_channels
FROM channels c
JOIN mv_active_ch_short ac ON c.id = ac.channel_id
JOIN topics t1 ON t1.id = ANY(c.topic_ids) AND t1.parent_id IS NOT NULL
JOIN topics t2 ON t2.id = ANY(c.topic_ids) AND t2.parent_id IS NOT NULL
WHERE t1.id < t2.id
GROUP BY t1.id, t1.name_ja, t2.id, t2.name_ja
HAVING COUNT(DISTINCT c.id) >= 2;
GRANT SELECT ON mv_topic_overlap_short TO anon, authenticated;

DROP MATERIALIZED VIEW IF EXISTS mv_topic_overlap_normal CASCADE;
CREATE MATERIALIZED VIEW mv_topic_overlap_normal AS
SELECT
    t1.id    AS topic_a,
    t1.name_ja AS name_a,
    t2.id    AS topic_b,
    t2.name_ja AS name_b,
    COUNT(DISTINCT c.id)::BIGINT AS shared_channels
FROM channels c
JOIN mv_active_ch_normal ac ON c.id = ac.channel_id
JOIN topics t1 ON t1.id = ANY(c.topic_ids) AND t1.parent_id IS NOT NULL
JOIN topics t2 ON t2.id = ANY(c.topic_ids) AND t2.parent_id IS NOT NULL
WHERE t1.id < t2.id
GROUP BY t1.id, t1.name_ja, t2.id, t2.name_ja
HAVING COUNT(DISTINCT c.id) >= 2;
GRANT SELECT ON mv_topic_overlap_normal TO anon, authenticated;
