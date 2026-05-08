-- ============================================================
-- ai_penetration / topic_duration_stats タイムアウト修正
--
-- 根本原因: JOIN videos v ON t.id = ANY(v.topic_ids) は
--   GINインデックスを使えない（変数同士のJOINはインデックス不可）
--
-- 修正方針:
--   1. mv_video_topics: videos×topic_ids を事前展開（mv_video_tagsのtopic版）
--   2. mv_ai_penetration / mv_topic_duration_stats: 静的集計を事前計算
--   3. 静的ビューはMVから読む → タイムアウト解消
--   4. RPCはデフォルト時はMV直読み、フィルタ時はmv_video_topics利用
-- ============================================================

-- ============================================================
-- 1. mv_video_topics: videos × topic_ids を事前展開
--    （JOIN時に idx_mv_video_topics_topic でインデックス利用可能に）
-- ============================================================
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_video_topics AS
SELECT
    v.id             AS video_id,
    v.channel_id,
    v.published_at,
    v.duration_seconds,
    v.has_ai_keywords,
    topic_id
FROM videos v
CROSS JOIN UNNEST(v.topic_ids) AS topic_id
WHERE v.topic_ids IS NOT NULL AND array_length(v.topic_ids, 1) > 0;

CREATE INDEX IF NOT EXISTS idx_mv_video_topics_topic
    ON mv_video_topics(topic_id);
CREATE INDEX IF NOT EXISTS idx_mv_video_topics_published
    ON mv_video_topics(published_at DESC);
CREATE INDEX IF NOT EXISTS idx_mv_video_topics_channel
    ON mv_video_topics(channel_id);

GRANT SELECT ON mv_video_topics TO anon, authenticated;

-- ============================================================
-- 2. mv_ai_penetration: デフォルト時の事前計算
-- ============================================================
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_ai_penetration AS
SELECT
    t.id                                                          AS topic_id,
    t.name                                                        AS topic_name,
    t.name_ja,
    COUNT(*)::BIGINT                                              AS total_videos,
    COUNT(*) FILTER (WHERE vt.has_ai_keywords = TRUE)::BIGINT    AS ai_video_count,
    ROUND(
        COUNT(*) FILTER (WHERE vt.has_ai_keywords = TRUE)::NUMERIC
        / NULLIF(COUNT(*), 0) * 100, 2
    )                                                             AS ai_penetration_pct
FROM topics t
JOIN mv_video_topics vt ON vt.topic_id = t.id
GROUP BY t.id, t.name, t.name_ja;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_ai_penetration_topic
    ON mv_ai_penetration(topic_id);
GRANT SELECT ON mv_ai_penetration TO anon, authenticated;

-- ============================================================
-- 3. mv_topic_duration_stats: デフォルト時の事前計算
-- ============================================================
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_topic_duration_stats AS
WITH topic_videos AS (
    SELECT
        t.id        AS tid,
        t.name      AS tname,
        t.name_ja   AS tname_ja,
        t.parent_id AS tparent,
        vt.duration_seconds AS dur
    FROM topics t
    JOIN mv_video_topics vt ON vt.topic_id = t.id
    WHERE vt.duration_seconds > 0
)
SELECT
    tid                                                          AS topic_id,
    tname                                                        AS topic_name,
    tname_ja                                                     AS name_ja,
    tparent                                                      AS parent_id,
    COUNT(*)::BIGINT                                             AS video_count,
    ROUND(AVG(dur))::INTEGER                                     AS avg_duration,
    PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY dur)::INTEGER  AS median_duration,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY dur)::INTEGER  AS p25_duration,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY dur)::INTEGER  AS p75_duration,
    COUNT(*) FILTER (WHERE dur <= 60)::BIGINT                   AS short_count,
    COUNT(*) FILTER (WHERE dur > 60 AND dur <= 600)::BIGINT     AS medium_count,
    COUNT(*) FILTER (WHERE dur > 600)::BIGINT                   AS long_count
FROM topic_videos
GROUP BY tid, tname, tname_ja, tparent;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_topic_duration_topic
    ON mv_topic_duration_stats(topic_id);
GRANT SELECT ON mv_topic_duration_stats TO anon, authenticated;

-- ============================================================
-- 4. 静的ビューをMVから読むように差し替え
-- ============================================================
CREATE OR REPLACE VIEW ai_penetration AS
SELECT * FROM mv_ai_penetration;

CREATE OR REPLACE VIEW topic_duration_stats AS
SELECT * FROM mv_topic_duration_stats;

-- ============================================================
-- 5. fn_ai_penetration: デフォルト→MV直読み、フィルタ→mv_video_topics使用
-- ============================================================
DROP FUNCTION IF EXISTS fn_ai_penetration(TIMESTAMPTZ, TEXT, TEXT);
CREATE OR REPLACE FUNCTION fn_ai_penetration(
    p_min_date   TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT        DEFAULT 'all',
    p_country    TEXT        DEFAULT NULL
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT,
    total_videos BIGINT, ai_video_count BIGINT, ai_penetration_pct NUMERIC
) AS $fn$
BEGIN
    IF p_min_date IS NULL AND p_video_type = 'all' AND p_country IS NULL THEN
        RETURN QUERY SELECT * FROM mv_ai_penetration;
        RETURN;
    END IF;

    RETURN QUERY
    SELECT
        t.id, t.name, t.name_ja,
        COUNT(*)::BIGINT,
        COUNT(*) FILTER (WHERE vt.has_ai_keywords = TRUE)::BIGINT,
        ROUND(
            COUNT(*) FILTER (WHERE vt.has_ai_keywords = TRUE)::NUMERIC
            / NULLIF(COUNT(*), 0) * 100, 2
        )
    FROM topics t
    JOIN mv_video_topics vt ON vt.topic_id = t.id
    LEFT JOIN channels c ON vt.channel_id = c.id
    WHERE (p_min_date   IS NULL OR vt.published_at >= p_min_date)
      AND (p_video_type = 'all'
        OR (p_video_type = 'short'  AND vt.duration_seconds <= 60)
        OR (p_video_type = 'normal' AND vt.duration_seconds >  60))
      AND (p_country IS NULL OR c.country = p_country)
    GROUP BY t.id, t.name, t.name_ja;
END;
$fn$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ============================================================
-- 6. fn_topic_duration_stats: デフォルト→MV直読み、フィルタ→mv_video_topics使用
-- ============================================================
DROP FUNCTION IF EXISTS fn_topic_duration_stats(TIMESTAMPTZ, TEXT, TEXT);
CREATE OR REPLACE FUNCTION fn_topic_duration_stats(
    p_min_date   TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT        DEFAULT 'all',
    p_country    TEXT        DEFAULT NULL
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT, parent_id TEXT,
    video_count BIGINT, avg_duration INTEGER, median_duration INTEGER,
    p25_duration INTEGER, p75_duration INTEGER,
    short_count BIGINT, medium_count BIGINT, long_count BIGINT
) AS $fn$
BEGIN
    IF p_min_date IS NULL AND p_video_type = 'all' AND p_country IS NULL THEN
        RETURN QUERY SELECT * FROM mv_topic_duration_stats;
        RETURN;
    END IF;

    RETURN QUERY
    WITH topic_videos AS (
        SELECT
            t.id        AS tid,
            t.name      AS tname,
            t.name_ja   AS tname_ja,
            t.parent_id AS tparent,
            vt.duration_seconds AS dur
        FROM topics t
        JOIN mv_video_topics vt ON vt.topic_id = t.id
        LEFT JOIN channels c ON vt.channel_id = c.id
        WHERE vt.duration_seconds > 0
          AND (p_min_date   IS NULL OR vt.published_at >= p_min_date)
          AND (p_video_type = 'all'
            OR (p_video_type = 'short'  AND vt.duration_seconds <= 60)
            OR (p_video_type = 'normal' AND vt.duration_seconds >  60))
          AND (p_country IS NULL OR c.country = p_country)
    )
    SELECT
        tv.tid, tv.tname, tv.tname_ja, tv.tparent,
        COUNT(*)::BIGINT,
        ROUND(AVG(tv.dur))::INTEGER,
        PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY tv.dur)::INTEGER,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY tv.dur)::INTEGER,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY tv.dur)::INTEGER,
        COUNT(*) FILTER (WHERE tv.dur <= 60)::BIGINT,
        COUNT(*) FILTER (WHERE tv.dur > 60 AND tv.dur <= 600)::BIGINT,
        COUNT(*) FILTER (WHERE tv.dur > 600)::BIGINT
    FROM topic_videos tv
    GROUP BY tv.tid, tv.tname, tv.tname_ja, tv.tparent;
END;
$fn$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ============================================================
-- 7. refresh_latest_snapshots() に新規MVを追加
-- ============================================================
CREATE OR REPLACE FUNCTION refresh_latest_snapshots()
RETURNS void AS $fn$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_latest_video_snapshot;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_latest_channel_snapshot;
    REFRESH MATERIALIZED VIEW mv_channel_growth_efficiency;
    REFRESH MATERIALIZED VIEW mv_video_tags;
    REFRESH MATERIALIZED VIEW mv_video_topics;
    REFRESH MATERIALIZED VIEW mv_video_ranking;
    REFRESH MATERIALIZED VIEW mv_ai_penetration;
    REFRESH MATERIALIZED VIEW mv_topic_duration_stats;
    REFRESH MATERIALIZED VIEW mv_keyword_opportunity;
    REFRESH MATERIALIZED VIEW mv_keyword_virality;
    REFRESH MATERIALIZED VIEW mv_topic_overlap;
END;
$fn$ LANGUAGE plpgsql SECURITY DEFINER;
