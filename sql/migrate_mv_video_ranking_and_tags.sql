-- ============================================================
-- video_ranking MV化 + keyword系 mv_video_tags 参照化
-- 残存タイムアウト（3件）の完全修正
-- ============================================================

-- ============================================================
-- 1. mv_video_ranking（BUZZ動画ランキング高速化）
--    buzz_scoreを事前計算・indexed化
-- ============================================================
DROP VIEW IF EXISTS video_ranking CASCADE;

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_video_ranking AS
SELECT
    v.id,
    v.title,
    v.channel_id,
    c.title AS channel_title,
    v.published_at,
    v.duration_seconds,
    v.topic_ids,
    v.has_ai_keywords,
    v.thumbnail_url,
    vs.view_count,
    vs.like_count,
    vs.comment_count,
    cs.subscriber_count AS channel_subscribers,
    CASE WHEN cs.subscriber_count > 0
        THEN ROUND(vs.view_count::NUMERIC / cs.subscriber_count, 1)
        ELSE 0
    END AS buzz_score
FROM videos v
JOIN mv_latest_video_snapshot vs ON v.id = vs.video_id
LEFT JOIN channels c ON v.channel_id = c.id
LEFT JOIN mv_latest_channel_snapshot cs ON v.channel_id = cs.channel_id;

CREATE INDEX IF NOT EXISTS idx_mv_video_ranking_published_at
    ON mv_video_ranking(published_at DESC);
CREATE INDEX IF NOT EXISTS idx_mv_video_ranking_buzz_score
    ON mv_video_ranking(buzz_score DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_video_ranking_id
    ON mv_video_ranking(id);

CREATE VIEW video_ranking AS
SELECT * FROM mv_video_ranking;

-- ============================================================
-- 2. mv_video_tags（タグ事前展開、keyword系高速化）
--    ※ 既に存在する場合はスキップされる
-- ============================================================
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_video_tags AS
SELECT
    v.id AS video_id,
    v.channel_id,
    v.published_at,
    v.duration_seconds,
    v.topic_ids,
    LOWER(TRIM(tag)) AS tag
FROM videos v
CROSS JOIN UNNEST(v.tags) AS tag
WHERE v.tags IS NOT NULL AND ARRAY_LENGTH(v.tags, 1) > 0
  AND LENGTH(LOWER(TRIM(tag))) >= 2;

CREATE INDEX IF NOT EXISTS idx_mv_video_tags_tag
    ON mv_video_tags(tag);
CREATE INDEX IF NOT EXISTS idx_mv_video_tags_channel
    ON mv_video_tags(channel_id);
CREATE INDEX IF NOT EXISTS idx_mv_video_tags_published_at
    ON mv_video_tags(published_at DESC);

-- ============================================================
-- 3. keyword_opportunity 静的ビュー（mv_video_tags参照）
-- ============================================================
CREATE OR REPLACE VIEW keyword_opportunity AS
WITH tag_stats AS (
    SELECT
        vt.tag,
        COUNT(*) AS usage_count,
        COUNT(DISTINCT vt.channel_id) AS channel_count,
        COALESCE(AVG(vs.view_count), 0)::BIGINT AS avg_views,
        COALESCE(SUM(vs.view_count), 0)::BIGINT AS total_views,
        COALESCE(AVG(
            CASE WHEN vs.view_count > 0
            THEN (vs.like_count::NUMERIC / vs.view_count * 100) ELSE 0 END
        ), 0)::NUMERIC(5,2) AS avg_like_rate,
        COALESCE(AVG(
            CASE WHEN cs.subscriber_count > 0
            THEN vs.view_count::NUMERIC / cs.subscriber_count ELSE 0 END
        ), 0)::NUMERIC(10,1) AS avg_buzz_score
    FROM mv_video_tags vt
    JOIN mv_latest_video_snapshot vs ON vt.video_id = vs.video_id
    LEFT JOIN mv_latest_channel_snapshot cs ON vt.channel_id = cs.channel_id
    GROUP BY vt.tag
    HAVING COUNT(*) >= 2
),
scored AS (
    SELECT *,
        ROUND(
            (avg_views::NUMERIC / GREATEST(channel_count, 1))
            * (1 + avg_like_rate / 10)
            * LEAST(avg_buzz_score / 10 + 1, 5)
        )::BIGINT AS keyword_score
    FROM tag_stats
)
SELECT
    tag, usage_count, channel_count, avg_views, total_views,
    avg_like_rate, avg_buzz_score, keyword_score,
    ROW_NUMBER() OVER (ORDER BY keyword_score DESC) AS rank
FROM scored
ORDER BY keyword_score DESC
LIMIT 200;

-- ============================================================
-- 4. keyword_virality 静的ビュー（mv_video_tags参照）
-- ============================================================
CREATE OR REPLACE VIEW keyword_virality AS
WITH tag_buzz AS (
    SELECT
        vt.tag,
        COUNT(*) AS video_count,
        COUNT(DISTINCT vt.channel_id) AS channel_count,
        COALESCE(AVG(vs.view_count), 0)::BIGINT AS avg_views,
        COALESCE(AVG(
            CASE WHEN cs.subscriber_count > 0
            THEN vs.view_count::NUMERIC / cs.subscriber_count ELSE 0 END
        ), 0)::NUMERIC(10,1) AS avg_buzz_score,
        COALESCE(AVG(
            CASE WHEN cs.subscriber_count > 0 AND vs.view_count > 0
            THEN (vs.view_count::NUMERIC / cs.subscriber_count)
                 * (1 + vs.like_count::NUMERIC / vs.view_count * 5)
                 * (1 + vs.comment_count::NUMERIC / vs.view_count * 10)
            ELSE 0 END
        ), 0)::NUMERIC(10,1) AS virality_score,
        MAX(vs.view_count) AS max_views,
        ROUND(
            COUNT(*) FILTER (WHERE cs.subscriber_count > 0
                AND vs.view_count::NUMERIC / cs.subscriber_count > 2)
            * 100.0 / GREATEST(COUNT(*), 1), 1
        )::NUMERIC(5,1) AS viral_rate_pct
    FROM mv_video_tags vt
    JOIN mv_latest_video_snapshot vs ON vt.video_id = vs.video_id
    LEFT JOIN mv_latest_channel_snapshot cs ON vt.channel_id = cs.channel_id
    GROUP BY vt.tag
    HAVING COUNT(*) >= 3
)
SELECT
    tag, video_count, channel_count, avg_views, avg_buzz_score,
    virality_score, max_views, viral_rate_pct,
    ROW_NUMBER() OVER (ORDER BY virality_score DESC) AS rank
FROM tag_buzz
ORDER BY virality_score DESC
LIMIT 100;

-- ============================================================
-- 5. fn_keyword_opportunity RPC（mv_video_tags参照）
-- ============================================================
DROP FUNCTION IF EXISTS fn_keyword_opportunity(TIMESTAMPTZ, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION fn_keyword_opportunity(
    p_min_date TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT DEFAULT 'all',
    p_country TEXT DEFAULT NULL,
    p_topic_id TEXT DEFAULT NULL
)
RETURNS TABLE(
    tag TEXT, usage_count BIGINT, channel_count BIGINT,
    avg_views BIGINT, total_views BIGINT,
    avg_like_rate NUMERIC, avg_buzz_score NUMERIC,
    keyword_score BIGINT, rank BIGINT
) AS $$
BEGIN
    RETURN QUERY
    WITH tag_stats AS (
        SELECT
            vt.tag AS vtag,
            COUNT(*)::BIGINT AS cnt,
            COUNT(DISTINCT vt.channel_id)::BIGINT AS ch_cnt,
            COALESCE(AVG(vs.view_count), 0)::BIGINT AS avgv,
            COALESCE(SUM(vs.view_count), 0)::BIGINT AS totv,
            COALESCE(AVG(
                CASE WHEN vs.view_count > 0
                THEN (vs.like_count::NUMERIC / vs.view_count * 100) ELSE 0 END
            ), 0)::NUMERIC(5,2) AS avg_lr,
            COALESCE(AVG(
                CASE WHEN cs.subscriber_count > 0
                THEN vs.view_count::NUMERIC / cs.subscriber_count ELSE 0 END
            ), 0)::NUMERIC(10,1) AS avg_bz
        FROM mv_video_tags vt
        JOIN mv_latest_video_snapshot vs ON vt.video_id = vs.video_id
        LEFT JOIN channels c ON vt.channel_id = c.id
        LEFT JOIN mv_latest_channel_snapshot cs ON vt.channel_id = cs.channel_id
        WHERE (p_min_date IS NULL OR vt.published_at >= p_min_date)
          AND (p_video_type = 'all'
            OR (p_video_type = 'short' AND vt.duration_seconds <= 60)
            OR (p_video_type = 'normal' AND vt.duration_seconds > 60))
          AND (p_country IS NULL OR c.country = p_country)
          AND (p_topic_id IS NULL OR p_topic_id = ANY(vt.topic_ids))
        GROUP BY vt.tag
        HAVING COUNT(*) >= 2
    ),
    scored AS (
        SELECT ts.*,
            ROUND((ts.avgv::NUMERIC / GREATEST(ts.ch_cnt, 1))
                * (1 + ts.avg_lr / 10)
                * LEAST(ts.avg_bz / 10 + 1, 5))::BIGINT AS kscore
        FROM tag_stats ts
    )
    SELECT s.vtag, s.cnt, s.ch_cnt, s.avgv, s.totv, s.avg_lr, s.avg_bz, s.kscore,
        ROW_NUMBER() OVER (ORDER BY s.kscore DESC)::BIGINT AS rk
    FROM scored s ORDER BY s.kscore DESC LIMIT 200;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ============================================================
-- 6. fn_keyword_virality RPC（mv_video_tags参照）
-- ============================================================
DROP FUNCTION IF EXISTS fn_keyword_virality(TIMESTAMPTZ, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION fn_keyword_virality(
    p_min_date TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT DEFAULT 'all',
    p_country TEXT DEFAULT NULL,
    p_topic_id TEXT DEFAULT NULL
)
RETURNS TABLE(
    tag TEXT, video_count BIGINT, channel_count BIGINT,
    avg_views BIGINT, avg_buzz_score NUMERIC,
    virality_score NUMERIC, max_views BIGINT,
    viral_rate_pct NUMERIC, rank BIGINT
) AS $$
BEGIN
    RETURN QUERY
    WITH tag_buzz AS (
        SELECT
            vt.tag AS vtag,
            COUNT(*)::BIGINT AS vcnt,
            COUNT(DISTINCT vt.channel_id)::BIGINT AS ch_cnt,
            COALESCE(AVG(vs.view_count), 0)::BIGINT AS avgv,
            COALESCE(AVG(
                CASE WHEN cs.subscriber_count > 0
                THEN vs.view_count::NUMERIC / cs.subscriber_count ELSE 0 END
            ), 0)::NUMERIC(10,1) AS avg_bz,
            COALESCE(AVG(
                CASE WHEN cs.subscriber_count > 0 AND vs.view_count > 0
                THEN (vs.view_count::NUMERIC / cs.subscriber_count)
                     * (1 + vs.like_count::NUMERIC / vs.view_count * 5)
                     * (1 + vs.comment_count::NUMERIC / vs.view_count * 10)
                ELSE 0 END
            ), 0)::NUMERIC(10,1) AS vir_score,
            MAX(vs.view_count)::BIGINT AS maxv,
            ROUND(COUNT(*) FILTER (WHERE cs.subscriber_count > 0
                AND vs.view_count::NUMERIC / cs.subscriber_count > 2)
                * 100.0 / GREATEST(COUNT(*), 1), 1)::NUMERIC(5,1) AS vir_pct
        FROM mv_video_tags vt
        JOIN mv_latest_video_snapshot vs ON vt.video_id = vs.video_id
        LEFT JOIN channels c ON vt.channel_id = c.id
        LEFT JOIN mv_latest_channel_snapshot cs ON vt.channel_id = cs.channel_id
        WHERE (p_min_date IS NULL OR vt.published_at >= p_min_date)
          AND (p_video_type = 'all'
            OR (p_video_type = 'short' AND vt.duration_seconds <= 60)
            OR (p_video_type = 'normal' AND vt.duration_seconds > 60))
          AND (p_country IS NULL OR c.country = p_country)
          AND (p_topic_id IS NULL OR p_topic_id = ANY(vt.topic_ids))
        GROUP BY vt.tag
        HAVING COUNT(*) >= 3
    )
    SELECT tb.vtag, tb.vcnt, tb.ch_cnt, tb.avgv, tb.avg_bz,
        tb.vir_score, tb.maxv, tb.vir_pct,
        ROW_NUMBER() OVER (ORDER BY tb.vir_score DESC)::BIGINT AS rk
    FROM tag_buzz tb ORDER BY tb.vir_score DESC LIMIT 100;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ============================================================
-- 7. refresh関数を更新（全MV一括リフレッシュ）
-- ============================================================
CREATE OR REPLACE FUNCTION refresh_latest_snapshots()
RETURNS void AS $fn$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_latest_video_snapshot;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_latest_channel_snapshot;
    REFRESH MATERIALIZED VIEW mv_channel_growth_efficiency;
    REFRESH MATERIALIZED VIEW mv_video_tags;
    REFRESH MATERIALIZED VIEW mv_video_ranking;
END;
$fn$ LANGUAGE plpgsql SECURITY DEFINER;
