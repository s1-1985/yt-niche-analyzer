-- ============================================================
-- キーワード分析: スコア・トレンド・拡散度
-- ============================================================

-- 1. キーワードスコア: 高需要 × 低競合のお宝キーワード発見
-- score = avg_views(需要) / usage_count(供給=競合の多さ) × engagement_boost
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
    JOIN (
        SELECT DISTINCT ON (video_id) video_id, view_count, like_count, comment_count
        FROM video_snapshots ORDER BY video_id, snapshot_date DESC
    ) vs ON v.id = vs.video_id
    LEFT JOIN (
        SELECT DISTINCT ON (channel_id) channel_id, subscriber_count
        FROM channel_snapshots ORDER BY channel_id, snapshot_date DESC
    ) cs ON v.channel_id = cs.channel_id
    WHERE v.tags IS NOT NULL AND ARRAY_LENGTH(v.tags, 1) > 0
    GROUP BY LOWER(TRIM(tag))
    HAVING COUNT(*) >= 2 AND LENGTH(LOWER(TRIM(tag))) >= 2
),
scored AS (
    SELECT *,
        -- キーワードスコア: 需要(avg_views)が高く、競合(channel_count)が少ないほど高い
        -- エンゲージメント(avg_like_rate)と拡散度(avg_buzz_score)でブースト
        ROUND(
            (avg_views::NUMERIC / GREATEST(channel_count, 1))
            * (1 + avg_like_rate / 10)
            * LEAST(avg_buzz_score / 10 + 1, 5)
        )::BIGINT AS keyword_score
    FROM tag_stats
)
SELECT
    tag,
    usage_count,
    channel_count,
    avg_views,
    total_views,
    avg_like_rate,
    avg_buzz_score,
    keyword_score,
    ROW_NUMBER() OVER (ORDER BY keyword_score DESC) AS rank
FROM scored
ORDER BY keyword_score DESC
LIMIT 200;

-- 2. キーワードスコア RPC関数（フィルタ付き）
CREATE OR REPLACE FUNCTION fn_keyword_opportunity(
    p_min_date TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT DEFAULT 'all',
    p_country TEXT DEFAULT NULL,
    p_topic_id TEXT DEFAULT NULL
)
RETURNS TABLE(
    tag TEXT,
    usage_count BIGINT,
    channel_count BIGINT,
    avg_views BIGINT,
    total_views BIGINT,
    avg_like_rate NUMERIC,
    avg_buzz_score NUMERIC,
    keyword_score BIGINT,
    rank BIGINT
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
        JOIN (
            SELECT DISTINCT ON (video_id) video_id, view_count, like_count, comment_count
            FROM video_snapshots ORDER BY video_id, snapshot_date DESC
        ) vs ON v.id = vs.video_id
        LEFT JOIN channels c ON v.channel_id = c.id
        LEFT JOIN (
            SELECT DISTINCT ON (channel_id) channel_id, subscriber_count
            FROM channel_snapshots ORDER BY channel_id, snapshot_date DESC
        ) cs ON v.channel_id = cs.channel_id
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
    SELECT
        s.vtag, s.cnt, s.ch_cnt, s.avgv, s.totv, s.avg_lr, s.avg_bz, s.kscore,
        ROW_NUMBER() OVER (ORDER BY s.kscore DESC)::BIGINT AS rk
    FROM scored s
    ORDER BY s.kscore DESC
    LIMIT 200;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- 3. キーワード拡散ランキング: タグごとの拡散力（buzz_score平均）
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
        -- 拡散スコア = buzz_score × エンゲージメント補正
        COALESCE(AVG(
            CASE WHEN cs.subscriber_count > 0 AND vs.view_count > 0
            THEN (vs.view_count::NUMERIC / cs.subscriber_count)
                 * (1 + vs.like_count::NUMERIC / vs.view_count * 5)
                 * (1 + vs.comment_count::NUMERIC / vs.view_count * 10)
            ELSE 0 END
        ), 0)::NUMERIC(10,1) AS virality_score,
        MAX(vs.view_count) AS max_views,
        -- buzz_score > 2 (再生数が登録者の2倍以上) の動画の割合
        ROUND(
            COUNT(*) FILTER (WHERE cs.subscriber_count > 0
                AND vs.view_count::NUMERIC / cs.subscriber_count > 2)
            * 100.0 / GREATEST(COUNT(*), 1),
            1
        )::NUMERIC(5,1) AS viral_rate_pct
    FROM videos v
    CROSS JOIN UNNEST(v.tags) AS tag
    JOIN (
        SELECT DISTINCT ON (video_id) video_id, view_count, like_count, comment_count
        FROM video_snapshots ORDER BY video_id, snapshot_date DESC
    ) vs ON v.id = vs.video_id
    LEFT JOIN (
        SELECT DISTINCT ON (channel_id) channel_id, subscriber_count
        FROM channel_snapshots ORDER BY channel_id, snapshot_date DESC
    ) cs ON v.channel_id = cs.channel_id
    WHERE v.tags IS NOT NULL AND ARRAY_LENGTH(v.tags, 1) > 0
    GROUP BY LOWER(TRIM(tag))
    HAVING COUNT(*) >= 3 AND LENGTH(LOWER(TRIM(tag))) >= 2
)
SELECT
    tag,
    video_count,
    channel_count,
    avg_views,
    avg_buzz_score,
    virality_score,
    max_views,
    viral_rate_pct,
    ROW_NUMBER() OVER (ORDER BY virality_score DESC) AS rank
FROM tag_buzz
ORDER BY virality_score DESC
LIMIT 100;

-- 4. キーワード拡散ランキング RPC関数（フィルタ付き）
CREATE OR REPLACE FUNCTION fn_keyword_virality(
    p_min_date TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT DEFAULT 'all',
    p_country TEXT DEFAULT NULL,
    p_topic_id TEXT DEFAULT NULL
)
RETURNS TABLE(
    tag TEXT,
    video_count BIGINT,
    channel_count BIGINT,
    avg_views BIGINT,
    avg_buzz_score NUMERIC,
    virality_score NUMERIC,
    max_views BIGINT,
    viral_rate_pct NUMERIC,
    rank BIGINT
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
                * 100.0 / GREATEST(COUNT(*), 1),
                1
            )::NUMERIC(5,1) AS vir_pct
        FROM videos v
        CROSS JOIN UNNEST(v.tags) AS tg
        JOIN (
            SELECT DISTINCT ON (video_id) video_id, view_count, like_count, comment_count
            FROM video_snapshots ORDER BY video_id, snapshot_date DESC
        ) vs ON v.id = vs.video_id
        LEFT JOIN channels c ON v.channel_id = c.id
        LEFT JOIN (
            SELECT DISTINCT ON (channel_id) channel_id, subscriber_count
            FROM channel_snapshots ORDER BY channel_id, snapshot_date DESC
        ) cs ON v.channel_id = cs.channel_id
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
    SELECT
        tb.vtag, tb.vcnt, tb.ch_cnt, tb.avgv, tb.avg_bz,
        tb.vir_score, tb.maxv, tb.vir_pct,
        ROW_NUMBER() OVER (ORDER BY tb.vir_score DESC)::BIGINT AS rk
    FROM tag_buzz tb
    ORDER BY tb.vir_score DESC
    LIMIT 100;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;
