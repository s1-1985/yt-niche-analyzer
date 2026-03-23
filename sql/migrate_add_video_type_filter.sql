-- ============================================================
-- 動画タイプフィルタ対応: 全RPC関数に p_video_type パラメータ追加
-- p_video_type = 'all' (デフォルト), 'short' (<=60s), 'normal' (>60s)
-- 既存関数をDROP→再作成
-- ============================================================

-- ジャンル別サマリー
DROP FUNCTION IF EXISTS fn_topic_summary(TIMESTAMPTZ);
CREATE OR REPLACE FUNCTION fn_topic_summary(
    p_min_date TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT DEFAULT 'all'
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT, parent_id TEXT, category TEXT,
    total_videos BIGINT, total_channels BIGINT, total_views NUMERIC,
    avg_views BIGINT, gap_score BIGINT, like_rate_pct NUMERIC, comment_rate_pct NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    WITH topic_videos AS (
        SELECT t.id AS tid, t.name AS tname, t.name_ja AS tname_ja,
            t.parent_id AS tparent, t.category AS tcategory,
            v.id AS vid, v.channel_id AS vchannel,
            vs.view_count AS vview, vs.like_count AS vlike,
            vs.comment_count AS vcomment, vs.snapshot_date AS sdate
        FROM topics t
        JOIN videos v ON t.id = ANY(v.topic_ids)
        JOIN video_snapshots vs ON v.id = vs.video_id
        WHERE (p_min_date IS NULL OR v.published_at >= p_min_date)
          AND (p_video_type = 'all'
            OR (p_video_type = 'short' AND v.duration_seconds <= 60)
            OR (p_video_type = 'normal' AND v.duration_seconds > 60))
    ),
    latest AS (
        SELECT DISTINCT ON (tid, vid) * FROM topic_videos ORDER BY tid, vid, sdate DESC
    )
    SELECT l.tid, l.tname, l.tname_ja, l.tparent, l.tcategory,
        COUNT(DISTINCT l.vid), COUNT(DISTINCT l.vchannel),
        COALESCE(SUM(l.vview), 0),
        COALESCE(AVG(l.vview), 0)::BIGINT,
        CASE WHEN COUNT(DISTINCT l.vchannel) > 0
            THEN (COALESCE(AVG(l.vview), 0) / COUNT(DISTINCT l.vchannel))::BIGINT ELSE 0 END,
        CASE WHEN COALESCE(SUM(l.vview), 0) > 0
            THEN ROUND(COALESCE(SUM(l.vlike), 0)::NUMERIC / SUM(l.vview) * 100, 2) ELSE 0 END,
        CASE WHEN COALESCE(SUM(l.vview), 0) > 0
            THEN ROUND(COALESCE(SUM(l.vcomment), 0)::NUMERIC / SUM(l.vview) * 100, 4) ELSE 0 END
    FROM latest l
    GROUP BY l.tid, l.tname, l.tname_ja, l.tparent, l.tcategory;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- 競合集中度
DROP FUNCTION IF EXISTS fn_competition_concentration(TIMESTAMPTZ);
CREATE OR REPLACE FUNCTION fn_competition_concentration(
    p_min_date TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT DEFAULT 'all'
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT,
    topic_total_views BIGINT, top5_views BIGINT, top5_share_pct NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    WITH channel_views AS (
        SELECT t.id AS tid, t.name AS tname, t.name_ja AS tname_ja,
            v.channel_id, SUM(vs.view_count) AS total_v
        FROM topics t
        JOIN videos v ON t.id = ANY(v.topic_ids)
        JOIN video_snapshots vs ON v.id = vs.video_id
            AND vs.snapshot_date = (SELECT MAX(snapshot_date) FROM video_snapshots)
        WHERE (p_min_date IS NULL OR v.published_at >= p_min_date)
          AND (p_video_type = 'all'
            OR (p_video_type = 'short' AND v.duration_seconds <= 60)
            OR (p_video_type = 'normal' AND v.duration_seconds > 60))
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
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- 新規チャンネル成功率
DROP FUNCTION IF EXISTS fn_new_channel_success_rate(TIMESTAMPTZ);
CREATE OR REPLACE FUNCTION fn_new_channel_success_rate(
    p_min_date TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT DEFAULT 'all'
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT,
    new_channel_count BIGINT, successful_count BIGINT, success_rate_pct NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    WITH active_channels AS (
        SELECT DISTINCT v.channel_id
        FROM videos v
        WHERE (p_video_type = 'all'
            OR (p_video_type = 'short' AND v.duration_seconds <= 60)
            OR (p_video_type = 'normal' AND v.duration_seconds > 60))
    ),
    new_channels AS (
        SELECT c.id, c.topic_ids AS ctopic_ids, cs.subscriber_count AS csub
        FROM channels c
        JOIN (SELECT DISTINCT ON (channel_id) channel_id, subscriber_count
              FROM channel_snapshots ORDER BY channel_id, snapshot_date DESC) cs ON c.id = cs.channel_id
        JOIN active_channels ac ON c.id = ac.channel_id
        WHERE c.published_at > COALESCE(p_min_date, NOW() - INTERVAL '1 year')
    )
    SELECT t.id, t.name, t.name_ja,
        COUNT(*)::BIGINT, COUNT(*) FILTER (WHERE nc.csub >= 1000)::BIGINT,
        ROUND(COUNT(*) FILTER (WHERE nc.csub >= 1000)::NUMERIC / NULLIF(COUNT(*), 0) * 100, 1)
    FROM topics t
    JOIN new_channels nc ON t.id = ANY(nc.ctopic_ids)
    GROUP BY t.id, t.name, t.name_ja;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- AI浸透度
DROP FUNCTION IF EXISTS fn_ai_penetration(TIMESTAMPTZ);
CREATE OR REPLACE FUNCTION fn_ai_penetration(
    p_min_date TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT DEFAULT 'all'
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT,
    total_videos BIGINT, ai_video_count BIGINT, ai_penetration_pct NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT t.id, t.name, t.name_ja,
        COUNT(*)::BIGINT,
        COUNT(*) FILTER (WHERE v.has_ai_keywords = TRUE)::BIGINT,
        ROUND(COUNT(*) FILTER (WHERE v.has_ai_keywords = TRUE)::NUMERIC / NULLIF(COUNT(*), 0) * 100, 2)
    FROM topics t
    JOIN videos v ON t.id = ANY(v.topic_ids)
    WHERE (p_min_date IS NULL OR v.published_at >= p_min_date)
      AND (p_video_type = 'all'
        OR (p_video_type = 'short' AND v.duration_seconds <= 60)
        OR (p_video_type = 'normal' AND v.duration_seconds > 60))
    GROUP BY t.id, t.name, t.name_ja;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- 動画尺統計
DROP FUNCTION IF EXISTS fn_topic_duration_stats(TIMESTAMPTZ);
CREATE OR REPLACE FUNCTION fn_topic_duration_stats(
    p_min_date TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT DEFAULT 'all'
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT, parent_id TEXT,
    video_count BIGINT, avg_duration INTEGER, median_duration INTEGER,
    p25_duration INTEGER, p75_duration INTEGER,
    short_count BIGINT, medium_count BIGINT, long_count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    WITH topic_videos AS (
        SELECT t.id AS tid, t.name AS tname, t.name_ja AS tname_ja, t.parent_id AS tparent,
            v.duration_seconds AS dur
        FROM topics t
        JOIN videos v ON t.id = ANY(v.topic_ids)
        WHERE v.duration_seconds > 0
          AND (p_min_date IS NULL OR v.published_at >= p_min_date)
          AND (p_video_type = 'all'
            OR (p_video_type = 'short' AND v.duration_seconds <= 60)
            OR (p_video_type = 'normal' AND v.duration_seconds > 60))
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
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- チャンネル規模分布
DROP FUNCTION IF EXISTS fn_topic_channel_size(TIMESTAMPTZ);
CREATE OR REPLACE FUNCTION fn_topic_channel_size(
    p_min_date TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT DEFAULT 'all'
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT, parent_id TEXT,
    total_channels BIGINT, small_count BIGINT, medium_count BIGINT,
    large_count BIGINT, mega_count BIGINT,
    small_pct NUMERIC, medium_pct NUMERIC, large_pct NUMERIC, mega_pct NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    WITH active_channels AS (
        SELECT DISTINCT channel_id FROM videos
        WHERE (p_min_date IS NULL OR published_at >= p_min_date)
          AND (p_video_type = 'all'
            OR (p_video_type = 'short' AND duration_seconds <= 60)
            OR (p_video_type = 'normal' AND duration_seconds > 60))
    ),
    latest_subs AS (
        SELECT DISTINCT ON (cs.channel_id) cs.channel_id, cs.subscriber_count
        FROM channel_snapshots cs JOIN active_channels ac ON cs.channel_id = ac.channel_id
        ORDER BY cs.channel_id, cs.snapshot_date DESC
    ),
    topic_channels AS (
        SELECT t.id AS tid, t.name AS tname, t.name_ja AS tname_ja, t.parent_id AS tparent,
            c.id AS cid, ls.subscriber_count AS subs
        FROM topics t JOIN channels c ON t.id = ANY(c.topic_ids)
        JOIN latest_subs ls ON c.id = ls.channel_id
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
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- 投稿曜日分析
DROP FUNCTION IF EXISTS fn_topic_publish_day(TIMESTAMPTZ);
CREATE OR REPLACE FUNCTION fn_topic_publish_day(
    p_min_date TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT DEFAULT 'all'
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT, parent_id TEXT,
    dow INTEGER, video_count BIGINT, avg_views BIGINT, total_views BIGINT
) AS $$
BEGIN
    RETURN QUERY
    WITH topic_videos AS (
        SELECT t.id AS tid, t.name AS tname, t.name_ja AS tname_ja, t.parent_id AS tparent,
            EXTRACT(DOW FROM v.published_at AT TIME ZONE 'Asia/Tokyo')::INTEGER AS vdow,
            vs.view_count AS vview
        FROM topics t
        JOIN videos v ON t.id = ANY(v.topic_ids)
        JOIN (SELECT DISTINCT ON (video_id) video_id, view_count
              FROM video_snapshots ORDER BY video_id, snapshot_date DESC) vs ON v.id = vs.video_id
        WHERE (p_min_date IS NULL OR v.published_at >= p_min_date)
          AND (p_video_type = 'all'
            OR (p_video_type = 'short' AND v.duration_seconds <= 60)
            OR (p_video_type = 'normal' AND v.duration_seconds > 60))
    )
    SELECT tv.tid, tv.tname, tv.tname_ja, tv.tparent, tv.vdow,
        COUNT(*)::BIGINT, COALESCE(AVG(tv.vview), 0)::BIGINT, COALESCE(SUM(tv.vview), 0)::BIGINT
    FROM topic_videos tv
    GROUP BY tv.tid, tv.tname, tv.tname_ja, tv.tparent, tv.vdow;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- 国別チャンネル分布
DROP FUNCTION IF EXISTS fn_topic_country_distribution(TIMESTAMPTZ);
CREATE OR REPLACE FUNCTION fn_topic_country_distribution(
    p_min_date TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT DEFAULT 'all'
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT, parent_id TEXT,
    country TEXT, channel_count BIGINT, total_subscribers BIGINT
) AS $$
BEGIN
    RETURN QUERY
    WITH active_channels AS (
        SELECT DISTINCT channel_id FROM videos
        WHERE (p_min_date IS NULL OR published_at >= p_min_date)
          AND (p_video_type = 'all'
            OR (p_video_type = 'short' AND duration_seconds <= 60)
            OR (p_video_type = 'normal' AND duration_seconds > 60))
    ),
    latest_snap AS (
        SELECT DISTINCT ON (cs.channel_id) cs.channel_id, cs.subscriber_count
        FROM channel_snapshots cs JOIN active_channels ac ON cs.channel_id = ac.channel_id
        ORDER BY cs.channel_id, cs.snapshot_date DESC
    )
    SELECT t.id, t.name, t.name_ja, t.parent_id,
        COALESCE(c.country, 'Unknown'), COUNT(DISTINCT c.id)::BIGINT,
        COALESCE(SUM(ls.subscriber_count), 0)::BIGINT
    FROM topics t JOIN channels c ON t.id = ANY(c.topic_ids)
    JOIN latest_snap ls ON c.id = ls.channel_id
    GROUP BY t.id, t.name, t.name_ja, t.parent_id, COALESCE(c.country, 'Unknown');
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- 人気タグ TOP10
DROP FUNCTION IF EXISTS fn_topic_popular_tags(TIMESTAMPTZ);
CREATE OR REPLACE FUNCTION fn_topic_popular_tags(
    p_min_date TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT DEFAULT 'all'
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT,
    tag TEXT, usage_count BIGINT, avg_views BIGINT, rank BIGINT
) AS $$
BEGIN
    RETURN QUERY
    WITH tag_data AS (
        SELECT t.id AS tid, t.name AS tname, t.name_ja AS tname_ja,
            LOWER(TRIM(tg)) AS vtag, vs.view_count AS vview
        FROM topics t
        JOIN videos v ON t.id = ANY(v.topic_ids)
        CROSS JOIN UNNEST(v.tags) AS tg
        JOIN (SELECT DISTINCT ON (video_id) video_id, view_count
              FROM video_snapshots ORDER BY video_id, snapshot_date DESC) vs ON v.id = vs.video_id
        WHERE v.tags IS NOT NULL AND ARRAY_LENGTH(v.tags, 1) > 0
          AND (p_min_date IS NULL OR v.published_at >= p_min_date)
          AND (p_video_type = 'all'
            OR (p_video_type = 'short' AND v.duration_seconds <= 60)
            OR (p_video_type = 'normal' AND v.duration_seconds > 60))
    ),
    ranked AS (
        SELECT td.tid, td.tname, td.tname_ja, td.vtag,
            COUNT(*)::BIGINT AS cnt, COALESCE(AVG(td.vview), 0)::BIGINT AS avgv,
            ROW_NUMBER() OVER (PARTITION BY td.tid ORDER BY COUNT(*) DESC) AS rk
        FROM tag_data td WHERE LENGTH(td.vtag) >= 2
        GROUP BY td.tid, td.tname, td.tname_ja, td.vtag
    )
    SELECT r.tid, r.tname, r.tname_ja, r.vtag, r.cnt, r.avgv, r.rk
    FROM ranked r WHERE r.rk <= 10;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- チャンネル成長効率
DROP FUNCTION IF EXISTS fn_channel_growth_efficiency(TIMESTAMPTZ);
CREATE OR REPLACE FUNCTION fn_channel_growth_efficiency(
    p_min_date TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT DEFAULT 'all'
)
RETURNS TABLE(
    channel_id TEXT, title TEXT, published_at TIMESTAMPTZ, country TEXT,
    topic_ids TEXT[], subscriber_count BIGINT, view_count BIGINT,
    video_count INTEGER, age_days INTEGER, subs_per_day NUMERIC, views_per_video NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    WITH active_channels AS (
        SELECT DISTINCT v.channel_id FROM videos v
        WHERE (p_min_date IS NULL OR v.published_at >= p_min_date)
          AND (p_video_type = 'all'
            OR (p_video_type = 'short' AND v.duration_seconds <= 60)
            OR (p_video_type = 'normal' AND v.duration_seconds > 60))
    ),
    latest_snap AS (
        SELECT DISTINCT ON (cs.channel_id)
            cs.channel_id, cs.subscriber_count, cs.view_count, cs.video_count
        FROM channel_snapshots cs JOIN active_channels ac ON cs.channel_id = ac.channel_id
        ORDER BY cs.channel_id, cs.snapshot_date DESC
    )
    SELECT c.id, c.title, c.published_at, c.country, c.topic_ids,
        ls.subscriber_count, ls.view_count, ls.video_count,
        GREATEST(EXTRACT(EPOCH FROM (NOW() - c.published_at)) / 86400, 1)::INTEGER,
        CASE WHEN EXTRACT(EPOCH FROM (NOW() - c.published_at)) > 0
            THEN ROUND(ls.subscriber_count::NUMERIC / GREATEST(EXTRACT(EPOCH FROM (NOW() - c.published_at)) / 86400, 1), 2)
            ELSE 0 END,
        CASE WHEN ls.video_count > 0
            THEN ROUND(ls.view_count::NUMERIC / ls.video_count) ELSE 0 END
    FROM channels c JOIN latest_snap ls ON c.id = ls.channel_id
    WHERE c.published_at IS NOT NULL AND ls.subscriber_count > 0;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ジャンル相関
DROP FUNCTION IF EXISTS fn_topic_overlap(TIMESTAMPTZ);
CREATE OR REPLACE FUNCTION fn_topic_overlap(
    p_min_date TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT DEFAULT 'all'
)
RETURNS TABLE(
    topic_a TEXT, name_a TEXT, topic_b TEXT, name_b TEXT, shared_channels BIGINT
) AS $$
BEGIN
    RETURN QUERY
    WITH active_channels AS (
        SELECT DISTINCT channel_id FROM videos
        WHERE (p_min_date IS NULL OR published_at >= p_min_date)
          AND (p_video_type = 'all'
            OR (p_video_type = 'short' AND duration_seconds <= 60)
            OR (p_video_type = 'normal' AND duration_seconds > 60))
    )
    SELECT t1.id, t1.name_ja, t2.id, t2.name_ja, COUNT(DISTINCT c.id)::BIGINT
    FROM channels c
    JOIN active_channels ac ON c.id = ac.channel_id
    JOIN topics t1 ON t1.id = ANY(c.topic_ids) AND t1.parent_id IS NOT NULL
    JOIN topics t2 ON t2.id = ANY(c.topic_ids) AND t2.parent_id IS NOT NULL
    WHERE t1.id < t2.id
    GROUP BY t1.id, t1.name_ja, t2.id, t2.name_ja
    HAVING COUNT(DISTINCT c.id) >= 2;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;
