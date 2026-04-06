-- ============================================================
-- パフォーマンス最適化マイグレーション
-- 問題: データ増加に伴い全ビューが statement timeout
-- 対策: 複合インデックス追加 + ビュー最適化
-- ============================================================

-- 1. 複合インデックス追加（DISTINCT ON パターン高速化）
CREATE INDEX IF NOT EXISTS idx_video_snapshots_video_date
    ON video_snapshots(video_id, snapshot_date DESC);

CREATE INDEX IF NOT EXISTS idx_channel_snapshots_channel_date
    ON channel_snapshots(channel_id, snapshot_date DESC);

-- 2. channels.country インデックス
CREATE INDEX IF NOT EXISTS idx_channels_country
    ON channels(country) WHERE country IS NOT NULL;

-- 3. 最新スナップショットのマテリアライズドビュー
-- video_snapshots の最新行だけを保持
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_latest_video_snapshot AS
SELECT DISTINCT ON (video_id)
    video_id, view_count, like_count, comment_count, snapshot_date
FROM video_snapshots
ORDER BY video_id, snapshot_date DESC;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_latest_video_snapshot_vid
    ON mv_latest_video_snapshot(video_id);

-- channel_snapshots の最新行だけを保持
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_latest_channel_snapshot AS
SELECT DISTINCT ON (channel_id)
    channel_id, subscriber_count, view_count, video_count, snapshot_date
FROM channel_snapshots
ORDER BY channel_id, snapshot_date DESC;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_latest_channel_snapshot_cid
    ON mv_latest_channel_snapshot(channel_id);

-- 4. マテリアライズドビューのリフレッシュ関数
CREATE OR REPLACE FUNCTION refresh_latest_snapshots()
RETURNS void AS $fn$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_latest_video_snapshot;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_latest_channel_snapshot;
END;
$fn$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. ビュー再定義（マテリアライズドビュー使用で高速化）
-- 既存ビューをDROPしてから再作成（カラム変更に対応）

DROP VIEW IF EXISTS topic_summary CASCADE;
CREATE VIEW topic_summary AS
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

DROP VIEW IF EXISTS competition_concentration CASCADE;
CREATE VIEW competition_concentration AS
WITH channel_views AS (
    SELECT
        t.id AS topic_id,
        t.name AS topic_name,
        t.name_ja,
        v.channel_id,
        SUM(vs.view_count) AS total_views
    FROM topics t
    JOIN videos v ON t.id = ANY(v.topic_ids)
    JOIN mv_latest_video_snapshot vs ON v.id = vs.video_id
    GROUP BY t.id, t.name, t.name_ja, v.channel_id
),
ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY topic_id ORDER BY total_views DESC) AS rank,
        SUM(total_views) OVER (PARTITION BY topic_id) AS topic_total_views
    FROM channel_views
)
SELECT
    topic_id, topic_name, name_ja, topic_total_views,
    SUM(total_views) FILTER (WHERE rank <= 5) AS top5_views,
    ROUND(SUM(total_views) FILTER (WHERE rank <= 5)::NUMERIC / NULLIF(topic_total_views, 0) * 100, 1) AS top5_share_pct
FROM ranked
GROUP BY topic_id, topic_name, name_ja, topic_total_views;

-- ai_penetration: 変更なし（元々軽い）

DROP VIEW IF EXISTS new_channel_success_rate CASCADE;
CREATE VIEW new_channel_success_rate AS
WITH new_channels AS (
    SELECT c.id, c.topic_ids, cs.subscriber_count, c.published_at
    FROM channels c
    JOIN mv_latest_channel_snapshot cs ON c.id = cs.channel_id
    WHERE c.published_at > NOW() - INTERVAL '1 year'
)
SELECT
    t.id AS topic_id,
    t.name AS topic_name,
    t.name_ja,
    COUNT(*) AS new_channel_count,
    COUNT(*) FILTER (WHERE nc.subscriber_count >= 1000) AS successful_count,
    ROUND(COUNT(*) FILTER (WHERE nc.subscriber_count >= 1000)::NUMERIC / NULLIF(COUNT(*), 0) * 100, 1) AS success_rate_pct
FROM topics t
JOIN new_channels nc ON t.id = ANY(nc.topic_ids)
GROUP BY t.id, t.name, t.name_ja;

DROP VIEW IF EXISTS video_ranking CASCADE;
CREATE VIEW video_ranking AS
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

DROP VIEW IF EXISTS channel_ranking CASCADE;
CREATE VIEW channel_ranking AS
SELECT
    c.id,
    c.title,
    c.published_at,
    c.country,
    c.topic_ids,
    cs.subscriber_count,
    cs.view_count,
    cs.video_count
FROM channels c
JOIN mv_latest_channel_snapshot cs ON c.id = cs.channel_id;

DROP VIEW IF EXISTS outlier_channels CASCADE;
CREATE VIEW outlier_channels AS
WITH channel_with_ratio AS (
    SELECT
        c.id, c.title, c.published_at, c.topic_ids,
        cs.subscriber_count, cs.view_count,
        CASE WHEN cs.subscriber_count > 0
            THEN (cs.view_count::NUMERIC / cs.subscriber_count)
            ELSE 0
        END AS views_to_sub_ratio
    FROM channels c
    JOIN mv_latest_channel_snapshot cs ON c.id = cs.channel_id
    WHERE cs.subscriber_count > 0
)
SELECT *, PERCENT_RANK() OVER (ORDER BY views_to_sub_ratio) AS percentile
FROM channel_with_ratio;

-- topic_popular_tags: DISTINCT ON → mv_latest_video_snapshot
DROP VIEW IF EXISTS topic_popular_tags CASCADE;
CREATE VIEW topic_popular_tags AS
WITH tag_data AS (
    SELECT
        t.id AS topic_id,
        t.name AS topic_name,
        t.name_ja,
        LOWER(TRIM(tag)) AS tag,
        vs.view_count
    FROM topics t
    JOIN videos v ON t.id = ANY(v.topic_ids)
    CROSS JOIN UNNEST(v.tags) AS tag
    JOIN mv_latest_video_snapshot vs ON v.id = vs.video_id
    WHERE v.tags IS NOT NULL
      AND ARRAY_LENGTH(v.tags, 1) > 0
),
ranked AS (
    SELECT
        topic_id, topic_name, name_ja, tag,
        COUNT(*) AS usage_count,
        COALESCE(AVG(view_count), 0)::BIGINT AS avg_views,
        ROW_NUMBER() OVER (
            PARTITION BY topic_id
            ORDER BY COUNT(*) * CASE WHEN tag ~ '[ぁ-んァ-ヶー一-龥々〆〤]' THEN 2 ELSE 1 END DESC
        ) AS rank
    FROM tag_data
    WHERE LENGTH(tag) >= 2
    GROUP BY topic_id, topic_name, name_ja, tag
)
SELECT topic_id, topic_name, name_ja, tag, usage_count, avg_views, rank
FROM ranked WHERE rank <= 10;

-- topic_publish_day: DISTINCT ON → mv_latest_video_snapshot
DROP VIEW IF EXISTS topic_publish_day CASCADE;
CREATE VIEW topic_publish_day AS
SELECT
    t.id AS topic_id, t.name AS topic_name, t.name_ja, t.parent_id,
    EXTRACT(DOW FROM v.published_at AT TIME ZONE 'Asia/Tokyo')::INTEGER AS dow,
    COUNT(*) AS video_count,
    COALESCE(AVG(vs.view_count), 0)::BIGINT AS avg_views,
    COALESCE(SUM(vs.view_count), 0)::BIGINT AS total_views
FROM topics t
JOIN videos v ON t.id = ANY(v.topic_ids)
JOIN mv_latest_video_snapshot vs ON v.id = vs.video_id
GROUP BY t.id, t.name, t.name_ja, t.parent_id,
    EXTRACT(DOW FROM v.published_at AT TIME ZONE 'Asia/Tokyo');

-- topic_country_distribution: DISTINCT ON → mv_latest_channel_snapshot
DROP VIEW IF EXISTS topic_country_distribution CASCADE;
CREATE VIEW topic_country_distribution AS
SELECT
    t.id AS topic_id, t.name AS topic_name, t.name_ja, t.parent_id,
    COALESCE(c.country, 'Unknown') AS country,
    COUNT(DISTINCT c.id) AS channel_count,
    COALESCE(SUM(cs.subscriber_count), 0)::BIGINT AS total_subscribers
FROM topics t
JOIN channels c ON t.id = ANY(c.topic_ids)
JOIN mv_latest_channel_snapshot cs ON c.id = cs.channel_id
GROUP BY t.id, t.name, t.name_ja, t.parent_id, COALESCE(c.country, 'Unknown');

-- topic_channel_size: DISTINCT ON → mv_latest_channel_snapshot
DROP VIEW IF EXISTS topic_channel_size CASCADE;
CREATE VIEW topic_channel_size AS
WITH topic_channels AS (
    SELECT
        t.id AS topic_id, t.name AS topic_name, t.name_ja, t.parent_id,
        c.id AS channel_id, cs.subscriber_count
    FROM topics t
    JOIN channels c ON t.id = ANY(c.topic_ids)
    JOIN mv_latest_channel_snapshot cs ON c.id = cs.channel_id
)
SELECT
    topic_id, topic_name, name_ja, parent_id,
    COUNT(DISTINCT channel_id) AS total_channels,
    COUNT(DISTINCT channel_id) FILTER (WHERE subscriber_count < 1000) AS small_count,
    COUNT(DISTINCT channel_id) FILTER (WHERE subscriber_count >= 1000 AND subscriber_count < 10000) AS medium_count,
    COUNT(DISTINCT channel_id) FILTER (WHERE subscriber_count >= 10000 AND subscriber_count < 100000) AS large_count,
    COUNT(DISTINCT channel_id) FILTER (WHERE subscriber_count >= 100000) AS mega_count,
    ROUND(COUNT(DISTINCT channel_id) FILTER (WHERE subscriber_count < 1000)::NUMERIC / NULLIF(COUNT(DISTINCT channel_id), 0) * 100, 1) AS small_pct,
    ROUND(COUNT(DISTINCT channel_id) FILTER (WHERE subscriber_count >= 1000 AND subscriber_count < 10000)::NUMERIC / NULLIF(COUNT(DISTINCT channel_id), 0) * 100, 1) AS medium_pct,
    ROUND(COUNT(DISTINCT channel_id) FILTER (WHERE subscriber_count >= 10000 AND subscriber_count < 100000)::NUMERIC / NULLIF(COUNT(DISTINCT channel_id), 0) * 100, 1) AS large_pct,
    ROUND(COUNT(DISTINCT channel_id) FILTER (WHERE subscriber_count >= 100000)::NUMERIC / NULLIF(COUNT(DISTINCT channel_id), 0) * 100, 1) AS mega_pct
FROM topic_channels
GROUP BY topic_id, topic_name, name_ja, parent_id;

-- channel_growth_efficiency: DISTINCT ON → mv_latest_channel_snapshot
DROP VIEW IF EXISTS channel_growth_efficiency CASCADE;
CREATE VIEW channel_growth_efficiency AS
SELECT
    c.id AS channel_id, c.title, c.published_at, c.country, c.topic_ids,
    cs.subscriber_count, cs.view_count, cs.video_count,
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

-- 6. RPC関数も最適化（マテリアライズドビュー使用）

-- fn_topic_summary
DROP FUNCTION IF EXISTS fn_topic_summary(TIMESTAMPTZ, TEXT, TEXT);
CREATE OR REPLACE FUNCTION fn_topic_summary(
    p_min_date TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT DEFAULT 'all',
    p_country TEXT DEFAULT NULL
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT, parent_id TEXT, category TEXT,
    total_videos BIGINT, total_channels BIGINT, total_views NUMERIC,
    avg_views BIGINT, gap_score BIGINT, like_rate_pct NUMERIC, comment_rate_pct NUMERIC
) AS $fn$
BEGIN
    RETURN QUERY
    SELECT t.id, t.name, t.name_ja, t.parent_id, t.category,
        COUNT(DISTINCT v.id), COUNT(DISTINCT v.channel_id),
        COALESCE(SUM(vs.view_count), 0),
        COALESCE(AVG(vs.view_count), 0)::BIGINT,
        CASE WHEN COUNT(DISTINCT v.channel_id) > 0
            THEN (COALESCE(AVG(vs.view_count), 0) / COUNT(DISTINCT v.channel_id))::BIGINT ELSE 0 END,
        CASE WHEN COALESCE(SUM(vs.view_count), 0) > 0
            THEN ROUND(COALESCE(SUM(vs.like_count), 0)::NUMERIC / SUM(vs.view_count) * 100, 2) ELSE 0 END,
        CASE WHEN COALESCE(SUM(vs.view_count), 0) > 0
            THEN ROUND(COALESCE(SUM(vs.comment_count), 0)::NUMERIC / SUM(vs.view_count) * 100, 4) ELSE 0 END
    FROM topics t
    JOIN videos v ON t.id = ANY(v.topic_ids)
    JOIN mv_latest_video_snapshot vs ON v.id = vs.video_id
    JOIN channels c ON v.channel_id = c.id
    WHERE (p_min_date IS NULL OR v.published_at >= p_min_date)
      AND (p_video_type = 'all'
        OR (p_video_type = 'short' AND v.duration_seconds <= 60)
        OR (p_video_type = 'normal' AND v.duration_seconds > 60))
      AND (p_country IS NULL OR c.country = p_country)
    GROUP BY t.id, t.name, t.name_ja, t.parent_id, t.category;
END;
$fn$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- fn_competition_concentration
DROP FUNCTION IF EXISTS fn_competition_concentration(TIMESTAMPTZ, TEXT, TEXT);
CREATE OR REPLACE FUNCTION fn_competition_concentration(
    p_min_date TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT DEFAULT 'all',
    p_country TEXT DEFAULT NULL
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT,
    topic_total_views BIGINT, top5_views BIGINT, top5_share_pct NUMERIC
) AS $fn$
BEGIN
    RETURN QUERY
    WITH channel_views AS (
        SELECT t.id AS tid, t.name AS tname, t.name_ja AS tname_ja,
            v.channel_id, SUM(vs.view_count) AS total_v
        FROM topics t
        JOIN videos v ON t.id = ANY(v.topic_ids)
        JOIN mv_latest_video_snapshot vs ON v.id = vs.video_id
        JOIN channels c ON v.channel_id = c.id
        WHERE (p_min_date IS NULL OR v.published_at >= p_min_date)
          AND (p_video_type = 'all'
            OR (p_video_type = 'short' AND v.duration_seconds <= 60)
            OR (p_video_type = 'normal' AND v.duration_seconds > 60))
          AND (p_country IS NULL OR c.country = p_country)
        GROUP BY t.id, t.name, t.name_ja, v.channel_id
    ),
    ranked AS (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY tid ORDER BY total_v DESC) AS rank,
            SUM(total_v) OVER (PARTITION BY tid) AS topic_total
        FROM channel_views
    )
    SELECT r.tid, r.tname, r.tname_ja, r.topic_total::BIGINT,
        SUM(r.total_v) FILTER (WHERE r.rank <= 5)::BIGINT,
        ROUND(SUM(r.total_v) FILTER (WHERE r.rank <= 5)::NUMERIC / NULLIF(r.topic_total, 0) * 100, 1)
    FROM ranked r
    GROUP BY r.tid, r.tname, r.tname_ja, r.topic_total;
END;
$fn$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- fn_ai_penetration
DROP FUNCTION IF EXISTS fn_ai_penetration(TIMESTAMPTZ, TEXT, TEXT);
CREATE OR REPLACE FUNCTION fn_ai_penetration(
    p_min_date TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT DEFAULT 'all',
    p_country TEXT DEFAULT NULL
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT,
    total_videos BIGINT, ai_video_count BIGINT, ai_penetration_pct NUMERIC
) AS $fn$
BEGIN
    RETURN QUERY
    SELECT t.id, t.name, t.name_ja,
        COUNT(*)::BIGINT,
        COUNT(*) FILTER (WHERE v.has_ai_keywords = TRUE)::BIGINT,
        ROUND(COUNT(*) FILTER (WHERE v.has_ai_keywords = TRUE)::NUMERIC / NULLIF(COUNT(*), 0) * 100, 2)
    FROM topics t
    JOIN videos v ON t.id = ANY(v.topic_ids)
    JOIN channels c ON v.channel_id = c.id
    WHERE (p_min_date IS NULL OR v.published_at >= p_min_date)
      AND (p_video_type = 'all'
        OR (p_video_type = 'short' AND v.duration_seconds <= 60)
        OR (p_video_type = 'normal' AND v.duration_seconds > 60))
      AND (p_country IS NULL OR c.country = p_country)
    GROUP BY t.id, t.name, t.name_ja;
END;
$fn$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- fn_new_channel_success_rate
DROP FUNCTION IF EXISTS fn_new_channel_success_rate(TIMESTAMPTZ, TEXT, TEXT);
CREATE OR REPLACE FUNCTION fn_new_channel_success_rate(
    p_min_date TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT DEFAULT 'all',
    p_country TEXT DEFAULT NULL
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT,
    new_channel_count BIGINT, successful_count BIGINT, success_rate_pct NUMERIC
) AS $fn$
BEGIN
    RETURN QUERY
    WITH active_channels AS (
        SELECT DISTINCT v.channel_id
        FROM videos v
        JOIN channels c ON v.channel_id = c.id
        WHERE (p_video_type = 'all'
            OR (p_video_type = 'short' AND v.duration_seconds <= 60)
            OR (p_video_type = 'normal' AND v.duration_seconds > 60))
          AND (p_country IS NULL OR c.country = p_country)
    ),
    new_channels AS (
        SELECT c.id, c.topic_ids AS ctopic_ids, cs.subscriber_count AS csub
        FROM channels c
        JOIN mv_latest_channel_snapshot cs ON c.id = cs.channel_id
        JOIN active_channels ac ON c.id = ac.channel_id
        WHERE c.published_at > COALESCE(p_min_date, NOW() - INTERVAL '1 year')
          AND (p_country IS NULL OR c.country = p_country)
    )
    SELECT t.id, t.name, t.name_ja,
        COUNT(*)::BIGINT, COUNT(*) FILTER (WHERE nc.csub >= 1000)::BIGINT,
        ROUND(COUNT(*) FILTER (WHERE nc.csub >= 1000)::NUMERIC / NULLIF(COUNT(*), 0) * 100, 1)
    FROM topics t
    JOIN new_channels nc ON t.id = ANY(nc.ctopic_ids)
    GROUP BY t.id, t.name, t.name_ja;
END;
$fn$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- fn_topic_duration_stats
DROP FUNCTION IF EXISTS fn_topic_duration_stats(TIMESTAMPTZ, TEXT, TEXT);
CREATE OR REPLACE FUNCTION fn_topic_duration_stats(
    p_min_date TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT DEFAULT 'all',
    p_country TEXT DEFAULT NULL
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT, parent_id TEXT,
    video_count BIGINT, avg_duration INTEGER, median_duration INTEGER,
    p25_duration INTEGER, p75_duration INTEGER,
    short_count BIGINT, medium_count BIGINT, long_count BIGINT
) AS $fn$
BEGIN
    RETURN QUERY
    WITH topic_videos AS (
        SELECT t.id AS tid, t.name AS tname, t.name_ja AS tname_ja, t.parent_id AS tparent,
            v.duration_seconds AS dur
        FROM topics t
        JOIN videos v ON t.id = ANY(v.topic_ids)
        JOIN channels c ON v.channel_id = c.id
        WHERE v.duration_seconds > 0
          AND (p_min_date IS NULL OR v.published_at >= p_min_date)
          AND (p_video_type = 'all'
            OR (p_video_type = 'short' AND v.duration_seconds <= 60)
            OR (p_video_type = 'normal' AND v.duration_seconds > 60))
          AND (p_country IS NULL OR c.country = p_country)
    )
    SELECT tv.tid, tv.tname, tv.tname_ja, tv.tparent,
        COUNT(*)::BIGINT, ROUND(AVG(tv.dur))::INTEGER,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY tv.dur)::INTEGER,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY tv.dur)::INTEGER,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY tv.dur)::INTEGER,
        COUNT(*) FILTER (WHERE tv.dur <= 60)::BIGINT,
        COUNT(*) FILTER (WHERE tv.dur > 60 AND tv.dur <= 600)::BIGINT,
        COUNT(*) FILTER (WHERE tv.dur > 600)::BIGINT
    FROM topic_videos tv
    GROUP BY tv.tid, tv.tname, tv.tname_ja, tv.tparent;
END;
$fn$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- fn_topic_channel_size
DROP FUNCTION IF EXISTS fn_topic_channel_size(TIMESTAMPTZ, TEXT, TEXT);
CREATE OR REPLACE FUNCTION fn_topic_channel_size(
    p_min_date TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT DEFAULT 'all',
    p_country TEXT DEFAULT NULL
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT, parent_id TEXT,
    total_channels BIGINT, small_count BIGINT, medium_count BIGINT,
    large_count BIGINT, mega_count BIGINT,
    small_pct NUMERIC, medium_pct NUMERIC, large_pct NUMERIC, mega_pct NUMERIC
) AS $fn$
BEGIN
    RETURN QUERY
    WITH active_channels AS (
        SELECT DISTINCT channel_id FROM videos
        WHERE (p_min_date IS NULL OR published_at >= p_min_date)
          AND (p_video_type = 'all'
            OR (p_video_type = 'short' AND duration_seconds <= 60)
            OR (p_video_type = 'normal' AND duration_seconds > 60))
    ),
    topic_channels AS (
        SELECT t.id AS tid, t.name AS tname, t.name_ja AS tname_ja, t.parent_id AS tparent,
            c.id AS cid, cs.subscriber_count AS subs
        FROM topics t
        JOIN channels c ON t.id = ANY(c.topic_ids)
        JOIN mv_latest_channel_snapshot cs ON c.id = cs.channel_id
        JOIN active_channels ac ON c.id = ac.channel_id
        WHERE (p_country IS NULL OR c.country = p_country)
    )
    SELECT tc.tid, tc.tname, tc.tname_ja, tc.tparent,
        COUNT(DISTINCT tc.cid)::BIGINT,
        COUNT(DISTINCT tc.cid) FILTER (WHERE tc.subs < 1000)::BIGINT,
        COUNT(DISTINCT tc.cid) FILTER (WHERE tc.subs >= 1000 AND tc.subs < 10000)::BIGINT,
        COUNT(DISTINCT tc.cid) FILTER (WHERE tc.subs >= 10000 AND tc.subs < 100000)::BIGINT,
        COUNT(DISTINCT tc.cid) FILTER (WHERE tc.subs >= 100000)::BIGINT,
        ROUND(COUNT(DISTINCT tc.cid) FILTER (WHERE tc.subs < 1000)::NUMERIC / NULLIF(COUNT(DISTINCT tc.cid), 0) * 100, 1),
        ROUND(COUNT(DISTINCT tc.cid) FILTER (WHERE tc.subs >= 1000 AND tc.subs < 10000)::NUMERIC / NULLIF(COUNT(DISTINCT tc.cid), 0) * 100, 1),
        ROUND(COUNT(DISTINCT tc.cid) FILTER (WHERE tc.subs >= 10000 AND tc.subs < 100000)::NUMERIC / NULLIF(COUNT(DISTINCT tc.cid), 0) * 100, 1),
        ROUND(COUNT(DISTINCT tc.cid) FILTER (WHERE tc.subs >= 100000)::NUMERIC / NULLIF(COUNT(DISTINCT tc.cid), 0) * 100, 1)
    FROM topic_channels tc
    GROUP BY tc.tid, tc.tname, tc.tname_ja, tc.tparent;
END;
$fn$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- fn_topic_publish_day
DROP FUNCTION IF EXISTS fn_topic_publish_day(TIMESTAMPTZ, TEXT, TEXT);
CREATE OR REPLACE FUNCTION fn_topic_publish_day(
    p_min_date TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT DEFAULT 'all',
    p_country TEXT DEFAULT NULL
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT, parent_id TEXT,
    dow INTEGER, video_count BIGINT, avg_views BIGINT, total_views BIGINT
) AS $fn$
BEGIN
    RETURN QUERY
    SELECT t.id, t.name, t.name_ja, t.parent_id,
        EXTRACT(DOW FROM v.published_at AT TIME ZONE 'Asia/Tokyo')::INTEGER AS vdow,
        COUNT(*)::BIGINT, COALESCE(AVG(vs.view_count), 0)::BIGINT, COALESCE(SUM(vs.view_count), 0)::BIGINT
    FROM topics t
    JOIN videos v ON t.id = ANY(v.topic_ids)
    JOIN mv_latest_video_snapshot vs ON v.id = vs.video_id
    JOIN channels c ON v.channel_id = c.id
    WHERE (p_min_date IS NULL OR v.published_at >= p_min_date)
      AND (p_video_type = 'all'
        OR (p_video_type = 'short' AND v.duration_seconds <= 60)
        OR (p_video_type = 'normal' AND v.duration_seconds > 60))
      AND (p_country IS NULL OR c.country = p_country)
    GROUP BY t.id, t.name, t.name_ja, t.parent_id, vdow;
END;
$fn$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- fn_topic_country_distribution
DROP FUNCTION IF EXISTS fn_topic_country_distribution(TIMESTAMPTZ, TEXT, TEXT);
CREATE OR REPLACE FUNCTION fn_topic_country_distribution(
    p_min_date TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT DEFAULT 'all',
    p_country TEXT DEFAULT NULL
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT, parent_id TEXT,
    country TEXT, channel_count BIGINT, total_subscribers BIGINT
) AS $fn$
BEGIN
    RETURN QUERY
    WITH active_channels AS (
        SELECT DISTINCT channel_id FROM videos
        WHERE (p_min_date IS NULL OR published_at >= p_min_date)
          AND (p_video_type = 'all'
            OR (p_video_type = 'short' AND duration_seconds <= 60)
            OR (p_video_type = 'normal' AND duration_seconds > 60))
    )
    SELECT t.id, t.name, t.name_ja, t.parent_id,
        COALESCE(c.country, 'Unknown'), COUNT(DISTINCT c.id)::BIGINT,
        COALESCE(SUM(cs.subscriber_count), 0)::BIGINT
    FROM topics t
    JOIN channels c ON t.id = ANY(c.topic_ids)
    JOIN mv_latest_channel_snapshot cs ON c.id = cs.channel_id
    JOIN active_channels ac ON c.id = ac.channel_id
    WHERE (p_country IS NULL OR c.country = p_country)
    GROUP BY t.id, t.name, t.name_ja, t.parent_id, COALESCE(c.country, 'Unknown');
END;
$fn$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- fn_topic_popular_tags
DROP FUNCTION IF EXISTS fn_topic_popular_tags(TIMESTAMPTZ, TEXT, TEXT);
CREATE OR REPLACE FUNCTION fn_topic_popular_tags(
    p_min_date TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT DEFAULT 'all',
    p_country TEXT DEFAULT NULL
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT,
    tag TEXT, usage_count BIGINT, avg_views BIGINT, rank BIGINT
) AS $fn$
BEGIN
    RETURN QUERY
    WITH tag_data AS (
        SELECT t.id AS tid, t.name AS tname, t.name_ja AS tname_ja,
            LOWER(TRIM(tg)) AS vtag, vs.view_count AS vview
        FROM topics t
        JOIN videos v ON t.id = ANY(v.topic_ids)
        CROSS JOIN UNNEST(v.tags) AS tg
        JOIN mv_latest_video_snapshot vs ON v.id = vs.video_id
        JOIN channels c ON v.channel_id = c.id
        WHERE v.tags IS NOT NULL AND ARRAY_LENGTH(v.tags, 1) > 0
          AND (p_min_date IS NULL OR v.published_at >= p_min_date)
          AND (p_video_type = 'all'
            OR (p_video_type = 'short' AND v.duration_seconds <= 60)
            OR (p_video_type = 'normal' AND v.duration_seconds > 60))
          AND (p_country IS NULL OR c.country = p_country)
    ),
    tag_agg AS (
        SELECT tid, tname, tname_ja, vtag,
            COUNT(*) AS cnt, COALESCE(AVG(vview), 0)::BIGINT AS avgv
        FROM tag_data
        GROUP BY tid, tname, tname_ja, vtag
    ),
    ranked AS (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY tid ORDER BY cnt DESC) AS rn
        FROM tag_agg
    )
    SELECT ranked.tid, ranked.tname, ranked.tname_ja,
        ranked.vtag, ranked.cnt, ranked.avgv, ranked.rn
    FROM ranked WHERE rn <= 20;
END;
$fn$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- 7. 初回リフレッシュ実行
SELECT refresh_latest_snapshots();

-- ============================================================
-- 重要: GitHub Actions の collect 後に毎回リフレッシュが必要
-- collect.yml に以下を追加:
--   await supabase.rpc('refresh_latest_snapshots')
-- ============================================================
