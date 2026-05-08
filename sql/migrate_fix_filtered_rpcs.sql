-- ============================================================
-- フィルタ時（video_type=short/normal）の全RPC 500エラー修正
--
-- 根本原因3パターン:
--   ① JOIN videos v ON t.id = ANY(v.topic_ids) → GINインデックス不使用
--   ② JOIN video_snapshots DISTINCT ON → 全スナップショットスキャン
--   ③ SELECT DISTINCT channel_id FROM videos → 86k行フルスキャン
--
-- 修正方針:
--   ① → mv_video_topics (topic_id インデックス) に差し替え
--   ② → mv_latest_video_snapshot / mv_latest_channel_snapshot に差し替え
--   ③ → mv_video_topics の部分インデックス経由に差し替え
-- ============================================================

-- ============================================================
-- 1. 不足インデックス追加
-- ============================================================
-- mv_video_topics: (topic_id, duration_seconds) 複合 / 部分インデックス
CREATE INDEX IF NOT EXISTS idx_mv_video_topics_topic_dur
    ON mv_video_topics(topic_id, duration_seconds);
CREATE INDEX IF NOT EXISTS idx_mv_video_topics_ch_short
    ON mv_video_topics(channel_id) WHERE duration_seconds <= 60;
CREATE INDEX IF NOT EXISTS idx_mv_video_topics_ch_normal
    ON mv_video_topics(channel_id) WHERE duration_seconds > 60;

-- mv_video_tags: video_id でのJOIN高速化（fn_topic_popular_tags用）
CREATE INDEX IF NOT EXISTS idx_mv_video_tags_video_id
    ON mv_video_tags(video_id);

-- mv_video_ranking: duration フィルタ用
CREATE INDEX IF NOT EXISTS idx_mv_video_ranking_duration
    ON mv_video_ranking(duration_seconds);

-- ============================================================
-- 2. fn_topic_summary
--    video_snapshots JOIN（全スナップ）→ mv_latest_video_snapshot
-- ============================================================
DROP FUNCTION IF EXISTS fn_topic_summary(TIMESTAMPTZ, TEXT, TEXT);
CREATE OR REPLACE FUNCTION fn_topic_summary(
    p_min_date   TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT        DEFAULT 'all',
    p_country    TEXT        DEFAULT NULL
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT, parent_id TEXT, category TEXT,
    total_videos BIGINT, total_channels BIGINT, total_views NUMERIC,
    avg_views BIGINT, gap_score BIGINT, like_rate_pct NUMERIC, comment_rate_pct NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    WITH tv AS (
        SELECT t.id AS tid, t.name AS tname, t.name_ja AS tname_ja,
               t.parent_id AS tparent, t.category AS tcategory,
               vt.video_id AS vid, vt.channel_id AS vchannel,
               vs.view_count AS vview, vs.like_count AS vlike, vs.comment_count AS vcomment
        FROM topics t
        JOIN mv_video_topics vt ON vt.topic_id = t.id
        JOIN mv_latest_video_snapshot vs ON vt.video_id = vs.video_id
        LEFT JOIN channels c ON vt.channel_id = c.id
        WHERE (p_min_date   IS NULL OR vt.published_at >= p_min_date)
          AND (p_video_type = 'all'
            OR (p_video_type = 'short'  AND vt.duration_seconds <= 60)
            OR (p_video_type = 'normal' AND vt.duration_seconds >  60))
          AND (p_country IS NULL OR c.country = p_country)
    )
    SELECT
        tv.tid, tv.tname, tv.tname_ja, tv.tparent, tv.tcategory,
        COUNT(DISTINCT tv.vid)::BIGINT,
        COUNT(DISTINCT tv.vchannel)::BIGINT,
        COALESCE(SUM(tv.vview), 0),
        COALESCE(AVG(tv.vview), 0)::BIGINT,
        CASE WHEN COUNT(DISTINCT tv.vchannel) > 0
             THEN (COALESCE(AVG(tv.vview), 0) / COUNT(DISTINCT tv.vchannel))::BIGINT
             ELSE 0 END,
        CASE WHEN COALESCE(SUM(tv.vview), 0) > 0
             THEN ROUND(COALESCE(SUM(tv.vlike), 0)::NUMERIC / SUM(tv.vview) * 100, 2)
             ELSE 0 END,
        CASE WHEN COALESCE(SUM(tv.vview), 0) > 0
             THEN ROUND(COALESCE(SUM(tv.vcomment), 0)::NUMERIC / SUM(tv.vview) * 100, 4)
             ELSE 0 END
    FROM tv
    GROUP BY tv.tid, tv.tname, tv.tname_ja, tv.tparent, tv.tcategory;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ============================================================
-- 3. fn_competition_concentration
--    video_snapshots + MAX subquery → mv_latest_video_snapshot
-- ============================================================
DROP FUNCTION IF EXISTS fn_competition_concentration(TIMESTAMPTZ, TEXT, TEXT);
CREATE OR REPLACE FUNCTION fn_competition_concentration(
    p_min_date   TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT        DEFAULT 'all',
    p_country    TEXT        DEFAULT NULL
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT,
    topic_total_views BIGINT, top5_views BIGINT, top5_share_pct NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    WITH channel_views AS (
        SELECT t.id AS tid, t.name AS tname, t.name_ja AS tname_ja,
               vt.channel_id, SUM(vs.view_count) AS total_v
        FROM topics t
        JOIN mv_video_topics vt ON vt.topic_id = t.id
        JOIN mv_latest_video_snapshot vs ON vt.video_id = vs.video_id
        LEFT JOIN channels c ON vt.channel_id = c.id
        WHERE (p_min_date   IS NULL OR vt.published_at >= p_min_date)
          AND (p_video_type = 'all'
            OR (p_video_type = 'short'  AND vt.duration_seconds <= 60)
            OR (p_video_type = 'normal' AND vt.duration_seconds >  60))
          AND (p_country IS NULL OR c.country = p_country)
        GROUP BY t.id, t.name, t.name_ja, vt.channel_id
    ),
    ranked AS (
        SELECT *,
               ROW_NUMBER() OVER (PARTITION BY tid ORDER BY total_v DESC) AS rnk,
               SUM(total_v) OVER (PARTITION BY tid) AS topic_total
        FROM channel_views
    )
    SELECT r.tid, r.tname, r.tname_ja, r.topic_total::BIGINT,
           SUM(r.total_v) FILTER (WHERE r.rnk <= 5)::BIGINT,
           ROUND(SUM(r.total_v) FILTER (WHERE r.rnk <= 5)::NUMERIC
                 / NULLIF(r.topic_total, 0) * 100, 1)
    FROM ranked r
    GROUP BY r.tid, r.tname, r.tname_ja, r.topic_total;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ============================================================
-- 4. fn_new_channel_success_rate
--    DISTINCT channel_id FROM videos → mv_video_topics
--    channel_snapshots DISTINCT ON → mv_latest_channel_snapshot
-- ============================================================
DROP FUNCTION IF EXISTS fn_new_channel_success_rate(TIMESTAMPTZ, TEXT, TEXT);
CREATE OR REPLACE FUNCTION fn_new_channel_success_rate(
    p_min_date   TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT        DEFAULT 'all',
    p_country    TEXT        DEFAULT NULL
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT,
    new_channel_count BIGINT, successful_count BIGINT, success_rate_pct NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    WITH active_channels AS (
        SELECT DISTINCT channel_id FROM mv_video_topics
        WHERE (p_video_type = 'all'
            OR (p_video_type = 'short'  AND duration_seconds <= 60)
            OR (p_video_type = 'normal' AND duration_seconds >  60))
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
           COUNT(*)::BIGINT,
           COUNT(*) FILTER (WHERE nc.csub >= 1000)::BIGINT,
           ROUND(COUNT(*) FILTER (WHERE nc.csub >= 1000)::NUMERIC
                 / NULLIF(COUNT(*), 0) * 100, 1)
    FROM topics t
    JOIN new_channels nc ON t.id = ANY(nc.ctopic_ids)
    GROUP BY t.id, t.name, t.name_ja;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ============================================================
-- 5. fn_topic_channel_size
--    DISTINCT channel_id FROM videos → mv_video_topics
--    channel_snapshots DISTINCT ON → mv_latest_channel_snapshot
-- ============================================================
DROP FUNCTION IF EXISTS fn_topic_channel_size(TIMESTAMPTZ, TEXT, TEXT);
CREATE OR REPLACE FUNCTION fn_topic_channel_size(
    p_min_date   TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT        DEFAULT 'all',
    p_country    TEXT        DEFAULT NULL
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
        SELECT DISTINCT channel_id FROM mv_video_topics
        WHERE (p_min_date   IS NULL OR published_at >= p_min_date)
          AND (p_video_type = 'all'
            OR (p_video_type = 'short'  AND duration_seconds <= 60)
            OR (p_video_type = 'normal' AND duration_seconds >  60))
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
           COUNT(DISTINCT tc.cid) FILTER (WHERE tc.subs <  1000)::BIGINT,
           COUNT(DISTINCT tc.cid) FILTER (WHERE tc.subs >= 1000  AND tc.subs < 10000)::BIGINT,
           COUNT(DISTINCT tc.cid) FILTER (WHERE tc.subs >= 10000 AND tc.subs < 100000)::BIGINT,
           COUNT(DISTINCT tc.cid) FILTER (WHERE tc.subs >= 100000)::BIGINT,
           ROUND(COUNT(DISTINCT tc.cid) FILTER (WHERE tc.subs <  1000)::NUMERIC
                 / NULLIF(COUNT(DISTINCT tc.cid), 0) * 100, 1),
           ROUND(COUNT(DISTINCT tc.cid) FILTER (WHERE tc.subs >= 1000  AND tc.subs < 10000)::NUMERIC
                 / NULLIF(COUNT(DISTINCT tc.cid), 0) * 100, 1),
           ROUND(COUNT(DISTINCT tc.cid) FILTER (WHERE tc.subs >= 10000 AND tc.subs < 100000)::NUMERIC
                 / NULLIF(COUNT(DISTINCT tc.cid), 0) * 100, 1),
           ROUND(COUNT(DISTINCT tc.cid) FILTER (WHERE tc.subs >= 100000)::NUMERIC
                 / NULLIF(COUNT(DISTINCT tc.cid), 0) * 100, 1)
    FROM topic_channels tc
    GROUP BY tc.tid, tc.tname, tc.tname_ja, tc.tparent;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ============================================================
-- 6. fn_topic_publish_day
--    video_snapshots DISTINCT ON → mv_latest_video_snapshot
-- ============================================================
DROP FUNCTION IF EXISTS fn_topic_publish_day(TIMESTAMPTZ, TEXT, TEXT);
CREATE OR REPLACE FUNCTION fn_topic_publish_day(
    p_min_date   TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT        DEFAULT 'all',
    p_country    TEXT        DEFAULT NULL
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT, parent_id TEXT,
    dow INTEGER, video_count BIGINT, avg_views BIGINT, total_views BIGINT
) AS $$
BEGIN
    RETURN QUERY
    WITH tv AS (
        SELECT t.id AS tid, t.name AS tname, t.name_ja AS tname_ja, t.parent_id AS tparent,
               EXTRACT(DOW FROM vt.published_at AT TIME ZONE 'Asia/Tokyo')::INTEGER AS vdow,
               vs.view_count AS vview
        FROM topics t
        JOIN mv_video_topics vt ON vt.topic_id = t.id
        JOIN mv_latest_video_snapshot vs ON vt.video_id = vs.video_id
        LEFT JOIN channels c ON vt.channel_id = c.id
        WHERE (p_min_date   IS NULL OR vt.published_at >= p_min_date)
          AND (p_video_type = 'all'
            OR (p_video_type = 'short'  AND vt.duration_seconds <= 60)
            OR (p_video_type = 'normal' AND vt.duration_seconds >  60))
          AND (p_country IS NULL OR c.country = p_country)
    )
    SELECT tv.tid, tv.tname, tv.tname_ja, tv.tparent, tv.vdow,
           COUNT(*)::BIGINT,
           COALESCE(AVG(tv.vview), 0)::BIGINT,
           COALESCE(SUM(tv.vview), 0)::BIGINT
    FROM tv
    GROUP BY tv.tid, tv.tname, tv.tname_ja, tv.tparent, tv.vdow;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ============================================================
-- 7. fn_topic_country_distribution
--    DISTINCT channel_id FROM videos → mv_video_topics
--    channel_snapshots DISTINCT ON → mv_latest_channel_snapshot
-- ============================================================
DROP FUNCTION IF EXISTS fn_topic_country_distribution(TIMESTAMPTZ, TEXT, TEXT);
CREATE OR REPLACE FUNCTION fn_topic_country_distribution(
    p_min_date   TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT        DEFAULT 'all',
    p_country    TEXT        DEFAULT NULL
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT, parent_id TEXT,
    country TEXT, channel_count BIGINT, total_subscribers BIGINT
) AS $$
BEGIN
    RETURN QUERY
    WITH active_channels AS (
        SELECT DISTINCT channel_id FROM mv_video_topics
        WHERE (p_min_date   IS NULL OR published_at >= p_min_date)
          AND (p_video_type = 'all'
            OR (p_video_type = 'short'  AND duration_seconds <= 60)
            OR (p_video_type = 'normal' AND duration_seconds >  60))
    )
    SELECT t.id, t.name, t.name_ja, t.parent_id,
           COALESCE(c.country, 'Unknown'),
           COUNT(DISTINCT c.id)::BIGINT,
           COALESCE(SUM(cs.subscriber_count), 0)::BIGINT
    FROM topics t
    JOIN channels c ON t.id = ANY(c.topic_ids)
    JOIN mv_latest_channel_snapshot cs ON c.id = cs.channel_id
    JOIN active_channels ac ON c.id = ac.channel_id
    WHERE (p_country IS NULL OR c.country = p_country)
    GROUP BY t.id, t.name, t.name_ja, t.parent_id, COALESCE(c.country, 'Unknown');
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ============================================================
-- 8. fn_topic_popular_tags
--    CROSS JOIN UNNEST + video_snapshots DISTINCT ON
--    → mv_video_topics JOIN mv_video_tags + mv_latest_video_snapshot
-- ============================================================
DROP FUNCTION IF EXISTS fn_topic_popular_tags(TIMESTAMPTZ, TEXT, TEXT);
CREATE OR REPLACE FUNCTION fn_topic_popular_tags(
    p_min_date   TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT        DEFAULT 'all',
    p_country    TEXT        DEFAULT NULL
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT,
    tag TEXT, usage_count BIGINT, avg_views BIGINT, rank BIGINT
) AS $$
BEGIN
    RETURN QUERY
    WITH filtered_videos AS (
        -- まずフィルタ条件でvideo_idを絞る（mv_video_topicsのインデックスを活用）
        SELECT DISTINCT vt.topic_id, vt.video_id
        FROM mv_video_topics vt
        LEFT JOIN channels c ON vt.channel_id = c.id
        WHERE (p_min_date   IS NULL OR vt.published_at >= p_min_date)
          AND (p_video_type = 'all'
            OR (p_video_type = 'short'  AND vt.duration_seconds <= 60)
            OR (p_video_type = 'normal' AND vt.duration_seconds >  60))
          AND (p_country IS NULL OR c.country = p_country)
    ),
    tag_data AS (
        SELECT fv.topic_id AS tid, vtags.tag AS vtag, vs.view_count AS vview
        FROM filtered_videos fv
        JOIN mv_video_tags vtags ON fv.video_id = vtags.video_id
        JOIN mv_latest_video_snapshot vs ON fv.video_id = vs.video_id
        WHERE LENGTH(vtags.tag) >= 2
    ),
    ranked AS (
        SELECT t.id AS rtid, t.name AS rtname, t.name_ja AS rtname_ja,
               td.vtag,
               COUNT(*)::BIGINT                    AS cnt,
               COALESCE(AVG(td.vview), 0)::BIGINT  AS avgv,
               ROW_NUMBER() OVER (PARTITION BY t.id ORDER BY COUNT(*) DESC) AS rk
        FROM topics t
        JOIN tag_data td ON td.tid = t.id
        GROUP BY t.id, t.name, t.name_ja, td.vtag
    )
    SELECT r.rtid, r.rtname, r.rtname_ja, r.vtag, r.cnt, r.avgv, r.rk
    FROM ranked r WHERE r.rk <= 10;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ============================================================
-- 9. fn_channel_growth_efficiency
--    DISTINCT channel_id FROM videos → mv_video_topics
--    channel_snapshots DISTINCT ON → mv_latest_channel_snapshot
-- ============================================================
DROP FUNCTION IF EXISTS fn_channel_growth_efficiency(TIMESTAMPTZ, TEXT, TEXT);
CREATE OR REPLACE FUNCTION fn_channel_growth_efficiency(
    p_min_date   TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT        DEFAULT 'all',
    p_country    TEXT        DEFAULT NULL
)
RETURNS TABLE(
    channel_id TEXT, title TEXT, published_at TIMESTAMPTZ, country TEXT,
    topic_ids TEXT[], subscriber_count BIGINT, view_count BIGINT,
    video_count INTEGER, age_days INTEGER, subs_per_day NUMERIC, views_per_video NUMERIC
) AS $$
BEGIN
    IF p_min_date IS NULL AND p_video_type = 'all' AND p_country IS NULL THEN
        RETURN QUERY SELECT * FROM mv_channel_growth_efficiency;
        RETURN;
    END IF;

    RETURN QUERY
    WITH active_channels AS (
        SELECT DISTINCT channel_id FROM mv_video_topics
        WHERE (p_min_date   IS NULL OR published_at >= p_min_date)
          AND (p_video_type = 'all'
            OR (p_video_type = 'short'  AND duration_seconds <= 60)
            OR (p_video_type = 'normal' AND duration_seconds >  60))
    )
    SELECT c.id, c.title, c.published_at, c.country, c.topic_ids,
           cs.subscriber_count, cs.view_count, cs.video_count,
           GREATEST(EXTRACT(EPOCH FROM (NOW() - c.published_at)) / 86400, 1)::INTEGER,
           CASE WHEN EXTRACT(EPOCH FROM (NOW() - c.published_at)) > 0
                THEN ROUND(cs.subscriber_count::NUMERIC
                     / GREATEST(EXTRACT(EPOCH FROM (NOW() - c.published_at)) / 86400, 1), 2)
                ELSE 0 END,
           CASE WHEN cs.video_count > 0
                THEN ROUND(cs.view_count::NUMERIC / cs.video_count) ELSE 0 END
    FROM channels c
    JOIN mv_latest_channel_snapshot cs ON c.id = cs.channel_id
    JOIN active_channels ac ON c.id = ac.channel_id
    WHERE c.published_at IS NOT NULL AND cs.subscriber_count > 0
      AND (p_country IS NULL OR c.country = p_country);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ============================================================
-- 10. fn_topic_overlap
--     active_channels FROM videos → mv_video_topics
-- ============================================================
DROP FUNCTION IF EXISTS fn_topic_overlap(TIMESTAMPTZ, TEXT, TEXT);
CREATE OR REPLACE FUNCTION fn_topic_overlap(
    p_min_date   TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT        DEFAULT 'all',
    p_country    TEXT        DEFAULT NULL
)
RETURNS TABLE(
    topic_a TEXT, name_a TEXT, topic_b TEXT, name_b TEXT, shared_channels BIGINT
) AS $$
BEGIN
    IF p_min_date IS NULL AND p_video_type = 'all' AND p_country IS NULL THEN
        RETURN QUERY SELECT * FROM mv_topic_overlap;
        RETURN;
    END IF;

    RETURN QUERY
    WITH active_channels AS (
        SELECT DISTINCT channel_id FROM mv_video_topics
        WHERE (p_min_date   IS NULL OR published_at >= p_min_date)
          AND (p_video_type = 'all'
            OR (p_video_type = 'short'  AND duration_seconds <= 60)
            OR (p_video_type = 'normal' AND duration_seconds >  60))
    )
    SELECT t1.id, t1.name_ja, t2.id, t2.name_ja, COUNT(DISTINCT c.id)::BIGINT
    FROM channels c
    JOIN active_channels ac ON c.id = ac.channel_id
    JOIN topics t1 ON t1.id = ANY(c.topic_ids) AND t1.parent_id IS NOT NULL
    JOIN topics t2 ON t2.id = ANY(c.topic_ids) AND t2.parent_id IS NOT NULL
    WHERE t1.id < t2.id
      AND (p_country IS NULL OR c.country = p_country)
    GROUP BY t1.id, t1.name_ja, t2.id, t2.name_ja
    HAVING COUNT(DISTINCT c.id) >= 2;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;
