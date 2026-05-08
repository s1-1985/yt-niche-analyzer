-- ============================================================
-- BUZZ動画ランキング・タイムアウト修正マイグレーション
-- 問題: データ増加(86k動画/46kチャンネル)によりstatement timeout
-- 対策: インデックス追加 + channel_growth_efficiency MV化
-- ============================================================

-- 1. published_at インデックス追加
CREATE INDEX IF NOT EXISTS idx_videos_published_at
    ON videos(published_at DESC);

CREATE INDEX IF NOT EXISTS idx_channels_published_at
    ON channels(published_at DESC);

-- 2. GINインデックス追加（topic_overlap 高速化）
CREATE INDEX IF NOT EXISTS idx_videos_topic_ids
    ON videos USING GIN(topic_ids);

CREATE INDEX IF NOT EXISTS idx_channels_topic_ids
    ON channels USING GIN(topic_ids);

-- ============================================================
-- 3. channel_growth_efficiency をマテリアライズドビュー化
--    (ORDER BY 計算列によるソート遅延を解消)
-- ============================================================
DROP VIEW IF EXISTS channel_growth_efficiency CASCADE;

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_channel_growth_efficiency AS
SELECT
    c.id AS channel_id,
    c.title,
    c.published_at,
    c.country,
    c.topic_ids,
    cs.subscriber_count,
    cs.view_count,
    cs.video_count,
    GREATEST(EXTRACT(EPOCH FROM (NOW() - c.published_at)) / 86400, 1)::INTEGER AS age_days,
    CASE WHEN EXTRACT(EPOCH FROM (NOW() - c.published_at)) > 0
        THEN ROUND(cs.subscriber_count::NUMERIC / GREATEST(EXTRACT(EPOCH FROM (NOW() - c.published_at)) / 86400, 1), 2)
        ELSE 0
    END AS subs_per_day,
    CASE WHEN cs.video_count > 0
        THEN ROUND(cs.view_count::NUMERIC / cs.video_count)
        ELSE 0
    END AS views_per_video
FROM channels c
JOIN mv_latest_channel_snapshot cs ON c.id = cs.channel_id
WHERE c.published_at IS NOT NULL AND cs.subscriber_count > 0;

CREATE INDEX IF NOT EXISTS idx_mv_channel_growth_subs_per_day
    ON mv_channel_growth_efficiency(subs_per_day DESC);

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_channel_growth_channel_id
    ON mv_channel_growth_efficiency(channel_id);

-- ビューとして公開（既存コードとの互換性維持）
CREATE VIEW channel_growth_efficiency AS
SELECT
    channel_id, title, published_at, country, topic_ids,
    subscriber_count, view_count, video_count,
    age_days, subs_per_day, views_per_video
FROM mv_channel_growth_efficiency;

-- ============================================================
-- 4. refresh関数を更新（新MVも一緒にリフレッシュ）
-- ============================================================
CREATE OR REPLACE FUNCTION refresh_latest_snapshots()
RETURNS void AS $fn$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_latest_video_snapshot;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_latest_channel_snapshot;
    REFRESH MATERIALIZED VIEW mv_channel_growth_efficiency;
END;
$fn$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 5. keyword_opportunity ビュー（MV参照に変更）
-- ============================================================
CREATE OR REPLACE VIEW keyword_opportunity AS
WITH tag_stats AS (
    SELECT
        LOWER(TRIM(tag)) AS tag,
        COUNT(*) AS usage_count,
        COUNT(DISTINCT v.channel_id) AS channel_count,
        COALESCE(AVG(vs.view_count), 0)::BIGINT AS avg_views,
        COALESCE(SUM(vs.view_count), 0)::BIGINT AS total_views,
        COALESCE(AVG(
            CASE WHEN vs.view_count > 0
            THEN (vs.like_count::NUMERIC / vs.view_count * 100)
            ELSE 0 END
        ), 0)::NUMERIC(5,2) AS avg_like_rate,
        COALESCE(AVG(
            CASE WHEN cs.subscriber_count > 0
            THEN vs.view_count::NUMERIC / cs.subscriber_count
            ELSE 0 END
        ), 0)::NUMERIC(10,1) AS avg_buzz_score
    FROM videos v
    CROSS JOIN UNNEST(v.tags) AS tag
    JOIN mv_latest_video_snapshot vs ON v.id = vs.video_id
    LEFT JOIN mv_latest_channel_snapshot cs ON v.channel_id = cs.channel_id
    WHERE v.tags IS NOT NULL AND ARRAY_LENGTH(v.tags, 1) > 0
    GROUP BY LOWER(TRIM(tag))
    HAVING COUNT(*) >= 2 AND LENGTH(LOWER(TRIM(tag))) >= 2
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
-- 6. keyword_virality ビュー（MV参照に変更）
-- ============================================================
CREATE OR REPLACE VIEW keyword_virality AS
WITH tag_buzz AS (
    SELECT
        LOWER(TRIM(tag)) AS tag,
        COUNT(*) AS video_count,
        COUNT(DISTINCT v.channel_id) AS channel_count,
        COALESCE(AVG(vs.view_count), 0)::BIGINT AS avg_views,
        COALESCE(AVG(
            CASE WHEN cs.subscriber_count > 0
            THEN vs.view_count::NUMERIC / cs.subscriber_count
            ELSE 0 END
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
    FROM videos v
    CROSS JOIN UNNEST(v.tags) AS tag
    JOIN mv_latest_video_snapshot vs ON v.id = vs.video_id
    LEFT JOIN mv_latest_channel_snapshot cs ON v.channel_id = cs.channel_id
    WHERE v.tags IS NOT NULL AND ARRAY_LENGTH(v.tags, 1) > 0
    GROUP BY LOWER(TRIM(tag))
    HAVING COUNT(*) >= 3 AND LENGTH(LOWER(TRIM(tag))) >= 2
)
SELECT
    tag, video_count, channel_count, avg_views, avg_buzz_score,
    virality_score, max_views, viral_rate_pct,
    ROW_NUMBER() OVER (ORDER BY virality_score DESC) AS rank
FROM tag_buzz
ORDER BY virality_score DESC
LIMIT 100;

-- ============================================================
-- 7. fn_keyword_opportunity RPC（MV参照に変更）
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
            LOWER(TRIM(tg)) AS vtag,
            COUNT(*)::BIGINT AS cnt,
            COUNT(DISTINCT v.channel_id)::BIGINT AS ch_cnt,
            COALESCE(AVG(vs.view_count), 0)::BIGINT AS avgv,
            COALESCE(SUM(vs.view_count), 0)::BIGINT AS totv,
            COALESCE(AVG(
                CASE WHEN vs.view_count > 0
                THEN (vs.like_count::NUMERIC / vs.view_count * 100)
                ELSE 0 END
            ), 0)::NUMERIC(5,2) AS avg_lr,
            COALESCE(AVG(
                CASE WHEN cs.subscriber_count > 0
                THEN vs.view_count::NUMERIC / cs.subscriber_count
                ELSE 0 END
            ), 0)::NUMERIC(10,1) AS avg_bz
        FROM videos v
        CROSS JOIN UNNEST(v.tags) AS tg
        JOIN mv_latest_video_snapshot vs ON v.id = vs.video_id
        LEFT JOIN channels c ON v.channel_id = c.id
        LEFT JOIN mv_latest_channel_snapshot cs ON v.channel_id = cs.channel_id
        WHERE v.tags IS NOT NULL AND ARRAY_LENGTH(v.tags, 1) > 0
          AND (p_min_date IS NULL OR v.published_at >= p_min_date)
          AND (p_video_type = 'all'
            OR (p_video_type = 'short' AND v.duration_seconds <= 60)
            OR (p_video_type = 'normal' AND v.duration_seconds > 60))
          AND (p_country IS NULL OR c.country = p_country)
          AND (p_topic_id IS NULL OR p_topic_id = ANY(v.topic_ids))
        GROUP BY LOWER(TRIM(tg))
        HAVING COUNT(*) >= 2 AND LENGTH(LOWER(TRIM(tg))) >= 2
    ),
    scored AS (
        SELECT ts.*,
            ROUND(
                (ts.avgv::NUMERIC / GREATEST(ts.ch_cnt, 1))
                * (1 + ts.avg_lr / 10)
                * LEAST(ts.avg_bz / 10 + 1, 5)
            )::BIGINT AS kscore
        FROM tag_stats ts
    )
    SELECT s.vtag, s.cnt, s.ch_cnt, s.avgv, s.totv, s.avg_lr, s.avg_bz, s.kscore,
        ROW_NUMBER() OVER (ORDER BY s.kscore DESC)::BIGINT AS rk
    FROM scored s ORDER BY s.kscore DESC LIMIT 200;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ============================================================
-- 8. fn_keyword_virality RPC（MV参照に変更）
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
            LOWER(TRIM(tg)) AS vtag,
            COUNT(*)::BIGINT AS vcnt,
            COUNT(DISTINCT v.channel_id)::BIGINT AS ch_cnt,
            COALESCE(AVG(vs.view_count), 0)::BIGINT AS avgv,
            COALESCE(AVG(
                CASE WHEN cs.subscriber_count > 0
                THEN vs.view_count::NUMERIC / cs.subscriber_count
                ELSE 0 END
            ), 0)::NUMERIC(10,1) AS avg_bz,
            COALESCE(AVG(
                CASE WHEN cs.subscriber_count > 0 AND vs.view_count > 0
                THEN (vs.view_count::NUMERIC / cs.subscriber_count)
                     * (1 + vs.like_count::NUMERIC / vs.view_count * 5)
                     * (1 + vs.comment_count::NUMERIC / vs.view_count * 10)
                ELSE 0 END
            ), 0)::NUMERIC(10,1) AS vir_score,
            MAX(vs.view_count)::BIGINT AS maxv,
            ROUND(
                COUNT(*) FILTER (WHERE cs.subscriber_count > 0
                    AND vs.view_count::NUMERIC / cs.subscriber_count > 2)
                * 100.0 / GREATEST(COUNT(*), 1), 1
            )::NUMERIC(5,1) AS vir_pct
        FROM videos v
        CROSS JOIN UNNEST(v.tags) AS tg
        JOIN mv_latest_video_snapshot vs ON v.id = vs.video_id
        LEFT JOIN channels c ON v.channel_id = c.id
        LEFT JOIN mv_latest_channel_snapshot cs ON v.channel_id = cs.channel_id
        WHERE v.tags IS NOT NULL AND ARRAY_LENGTH(v.tags, 1) > 0
          AND (p_min_date IS NULL OR v.published_at >= p_min_date)
          AND (p_video_type = 'all'
            OR (p_video_type = 'short' AND v.duration_seconds <= 60)
            OR (p_video_type = 'normal' AND v.duration_seconds > 60))
          AND (p_country IS NULL OR c.country = p_country)
          AND (p_topic_id IS NULL OR p_topic_id = ANY(v.topic_ids))
        GROUP BY LOWER(TRIM(tg))
        HAVING COUNT(*) >= 3 AND LENGTH(LOWER(TRIM(tg))) >= 2
    )
    SELECT tb.vtag, tb.vcnt, tb.ch_cnt, tb.avgv, tb.avg_bz,
        tb.vir_score, tb.maxv, tb.vir_pct,
        ROW_NUMBER() OVER (ORDER BY tb.vir_score DESC)::BIGINT AS rk
    FROM tag_buzz tb ORDER BY tb.vir_score DESC LIMIT 100;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;
