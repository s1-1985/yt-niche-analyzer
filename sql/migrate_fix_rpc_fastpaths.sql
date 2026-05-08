-- ============================================================
-- 完全修正 SQL（一括実行版）
--
-- これまでの途中失敗で壊れた状態を全て修正する。
-- 以下を実行:
--   1. mv_keyword_opp/vir_short/normal を (再)作成 (NUMERIC(8,2)修正済み)
--   2. 全13RPC関数を更新 (short/normal fast path + 全オーバーロード削除)
--   3. リフレッシュ関数 Group4-6 を作成
-- ============================================================

-- ============================================================
-- 1. mv_keyword_opp_short / mv_keyword_opp_normal
-- ============================================================
DROP MATERIALIZED VIEW IF EXISTS mv_keyword_opp_short CASCADE;
CREATE MATERIALIZED VIEW mv_keyword_opp_short AS
WITH ts AS (
    SELECT vt.tag,
           COUNT(*)::BIGINT AS usage_count,
           COUNT(DISTINCT vt.channel_id)::BIGINT AS channel_count,
           COALESCE(AVG(vs.view_count), 0)::BIGINT AS avg_views,
           COALESCE(SUM(vs.view_count), 0)::BIGINT AS total_views,
           COALESCE(AVG(CASE WHEN vs.view_count > 0
               THEN vs.like_count::NUMERIC / vs.view_count * 100
               ELSE 0 END), 0)::NUMERIC(8,2) AS avg_like_rate,
           COALESCE(AVG(CASE WHEN cs.subscriber_count > 0
               THEN vs.view_count::NUMERIC / cs.subscriber_count
               ELSE 0 END), 0)::NUMERIC(10,1) AS avg_buzz_score
    FROM mv_video_tags vt
    JOIN mv_latest_video_snapshot vs ON vt.video_id = vs.video_id
    LEFT JOIN mv_latest_channel_snapshot cs ON vt.channel_id = cs.channel_id
    WHERE vt.duration_seconds <= 60
    GROUP BY vt.tag HAVING COUNT(*) >= 2
),
sc AS (
    SELECT *,
           ROUND((avg_views::NUMERIC / GREATEST(channel_count, 1))
                 * (1 + avg_like_rate / 10)
                 * LEAST(avg_buzz_score / 10 + 1, 5))::BIGINT AS keyword_score
    FROM ts
)
SELECT tag, usage_count, channel_count, avg_views, total_views,
       avg_like_rate, avg_buzz_score, keyword_score,
       ROW_NUMBER() OVER (ORDER BY keyword_score DESC)::BIGINT AS rank
FROM sc ORDER BY keyword_score DESC LIMIT 200;
GRANT SELECT ON mv_keyword_opp_short TO anon, authenticated;

DROP MATERIALIZED VIEW IF EXISTS mv_keyword_opp_normal CASCADE;
CREATE MATERIALIZED VIEW mv_keyword_opp_normal AS
WITH ts AS (
    SELECT vt.tag,
           COUNT(*)::BIGINT AS usage_count,
           COUNT(DISTINCT vt.channel_id)::BIGINT AS channel_count,
           COALESCE(AVG(vs.view_count), 0)::BIGINT AS avg_views,
           COALESCE(SUM(vs.view_count), 0)::BIGINT AS total_views,
           COALESCE(AVG(CASE WHEN vs.view_count > 0
               THEN vs.like_count::NUMERIC / vs.view_count * 100
               ELSE 0 END), 0)::NUMERIC(8,2) AS avg_like_rate,
           COALESCE(AVG(CASE WHEN cs.subscriber_count > 0
               THEN vs.view_count::NUMERIC / cs.subscriber_count
               ELSE 0 END), 0)::NUMERIC(10,1) AS avg_buzz_score
    FROM mv_video_tags vt
    JOIN mv_latest_video_snapshot vs ON vt.video_id = vs.video_id
    LEFT JOIN mv_latest_channel_snapshot cs ON vt.channel_id = cs.channel_id
    WHERE vt.duration_seconds > 60
    GROUP BY vt.tag HAVING COUNT(*) >= 2
),
sc AS (
    SELECT *,
           ROUND((avg_views::NUMERIC / GREATEST(channel_count, 1))
                 * (1 + avg_like_rate / 10)
                 * LEAST(avg_buzz_score / 10 + 1, 5))::BIGINT AS keyword_score
    FROM ts
)
SELECT tag, usage_count, channel_count, avg_views, total_views,
       avg_like_rate, avg_buzz_score, keyword_score,
       ROW_NUMBER() OVER (ORDER BY keyword_score DESC)::BIGINT AS rank
FROM sc ORDER BY keyword_score DESC LIMIT 200;
GRANT SELECT ON mv_keyword_opp_normal TO anon, authenticated;

-- ============================================================
-- 2. mv_keyword_vir_short / mv_keyword_vir_normal
-- ============================================================
DROP MATERIALIZED VIEW IF EXISTS mv_keyword_vir_short CASCADE;
CREATE MATERIALIZED VIEW mv_keyword_vir_short AS
WITH tb AS (
    SELECT vt.tag,
           COUNT(*)::BIGINT AS video_count,
           COUNT(DISTINCT vt.channel_id)::BIGINT AS channel_count,
           COALESCE(AVG(vs.view_count), 0)::BIGINT AS avg_views,
           COALESCE(AVG(CASE WHEN cs.subscriber_count > 0
               THEN vs.view_count::NUMERIC / cs.subscriber_count
               ELSE 0 END), 0)::NUMERIC(10,1) AS avg_buzz_score,
           COALESCE(AVG(CASE WHEN cs.subscriber_count > 0 AND vs.view_count > 0
               THEN (vs.view_count::NUMERIC / cs.subscriber_count)
                    * (1 + vs.like_count::NUMERIC / vs.view_count * 5)
                    * (1 + vs.comment_count::NUMERIC / vs.view_count * 10)
               ELSE 0 END), 0)::NUMERIC(10,1) AS virality_score,
           MAX(vs.view_count)::BIGINT AS max_views,
           ROUND(COUNT(*) FILTER (
               WHERE cs.subscriber_count > 0
                 AND vs.view_count::NUMERIC / cs.subscriber_count > 2
           ) * 100.0 / GREATEST(COUNT(*), 1), 1)::NUMERIC(5,1) AS viral_rate_pct
    FROM mv_video_tags vt
    JOIN mv_latest_video_snapshot vs ON vt.video_id = vs.video_id
    LEFT JOIN mv_latest_channel_snapshot cs ON vt.channel_id = cs.channel_id
    WHERE vt.duration_seconds <= 60
    GROUP BY vt.tag HAVING COUNT(*) >= 3
)
SELECT tag, video_count, channel_count, avg_views, avg_buzz_score,
       virality_score, max_views, viral_rate_pct,
       ROW_NUMBER() OVER (ORDER BY virality_score DESC)::BIGINT AS rank
FROM tb ORDER BY virality_score DESC LIMIT 100;
GRANT SELECT ON mv_keyword_vir_short TO anon, authenticated;

DROP MATERIALIZED VIEW IF EXISTS mv_keyword_vir_normal CASCADE;
CREATE MATERIALIZED VIEW mv_keyword_vir_normal AS
WITH tb AS (
    SELECT vt.tag,
           COUNT(*)::BIGINT AS video_count,
           COUNT(DISTINCT vt.channel_id)::BIGINT AS channel_count,
           COALESCE(AVG(vs.view_count), 0)::BIGINT AS avg_views,
           COALESCE(AVG(CASE WHEN cs.subscriber_count > 0
               THEN vs.view_count::NUMERIC / cs.subscriber_count
               ELSE 0 END), 0)::NUMERIC(10,1) AS avg_buzz_score,
           COALESCE(AVG(CASE WHEN cs.subscriber_count > 0 AND vs.view_count > 0
               THEN (vs.view_count::NUMERIC / cs.subscriber_count)
                    * (1 + vs.like_count::NUMERIC / vs.view_count * 5)
                    * (1 + vs.comment_count::NUMERIC / vs.view_count * 10)
               ELSE 0 END), 0)::NUMERIC(10,1) AS virality_score,
           MAX(vs.view_count)::BIGINT AS max_views,
           ROUND(COUNT(*) FILTER (
               WHERE cs.subscriber_count > 0
                 AND vs.view_count::NUMERIC / cs.subscriber_count > 2
           ) * 100.0 / GREATEST(COUNT(*), 1), 1)::NUMERIC(5,1) AS viral_rate_pct
    FROM mv_video_tags vt
    JOIN mv_latest_video_snapshot vs ON vt.video_id = vs.video_id
    LEFT JOIN mv_latest_channel_snapshot cs ON vt.channel_id = cs.channel_id
    WHERE vt.duration_seconds > 60
    GROUP BY vt.tag HAVING COUNT(*) >= 3
)
SELECT tag, video_count, channel_count, avg_views, avg_buzz_score,
       virality_score, max_views, viral_rate_pct,
       ROW_NUMBER() OVER (ORDER BY virality_score DESC)::BIGINT AS rank
FROM tb ORDER BY virality_score DESC LIMIT 100;
GRANT SELECT ON mv_keyword_vir_normal TO anon, authenticated;

-- ============================================================
-- 3. 全RPC関数 (全オーバーロード削除 + 再作成)
-- ============================================================

-- fn_topic_summary
DROP FUNCTION IF EXISTS fn_topic_summary(TIMESTAMPTZ, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS fn_topic_summary(TIMESTAMPTZ, TEXT, TEXT);
DROP FUNCTION IF EXISTS fn_topic_summary(TIMESTAMPTZ, TEXT);
DROP FUNCTION IF EXISTS fn_topic_summary(TIMESTAMPTZ);
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
DECLARE src TEXT;
BEGIN
    IF p_min_date IS NULL AND p_country IS NULL THEN
        IF    p_video_type = 'short'  THEN src := 'mv_topic_video_short';
        ELSIF p_video_type = 'normal' THEN src := 'mv_topic_video_normal';
        END IF;
        IF src IS NOT NULL THEN
            RETURN QUERY EXECUTE format($q$
                SELECT t.id, t.name, t.name_ja, t.parent_id, t.category,
                       COUNT(*)::BIGINT, COUNT(DISTINCT tv.channel_id)::BIGINT,
                       COALESCE(SUM(tv.view_count),0),
                       COALESCE(AVG(tv.view_count),0)::BIGINT,
                       CASE WHEN COUNT(DISTINCT tv.channel_id)>0
                            THEN (COALESCE(AVG(tv.view_count),0)/COUNT(DISTINCT tv.channel_id))::BIGINT
                            ELSE 0 END,
                       CASE WHEN COALESCE(SUM(tv.view_count),0)>0
                            THEN ROUND(COALESCE(SUM(tv.like_count),0)::NUMERIC/SUM(tv.view_count)*100,2)
                            ELSE 0 END,
                       CASE WHEN COALESCE(SUM(tv.view_count),0)>0
                            THEN ROUND(COALESCE(SUM(tv.comment_count),0)::NUMERIC/SUM(tv.view_count)*100,4)
                            ELSE 0 END
                FROM topics t JOIN %I tv ON tv.topic_id = t.id
                GROUP BY t.id, t.name, t.name_ja, t.parent_id, t.category
            $q$, src);
            RETURN;
        END IF;
    END IF;
    RETURN QUERY
    WITH tv AS (
        SELECT t.id AS tid, t.name AS tname, t.name_ja AS tname_ja,
               t.parent_id AS tparent, t.category AS tcategory,
               vt.video_id, vt.channel_id, vs.view_count, vs.like_count, vs.comment_count
        FROM topics t
        JOIN mv_video_topics vt ON vt.topic_id = t.id
        JOIN mv_latest_video_snapshot vs ON vt.video_id = vs.video_id
        LEFT JOIN channels c ON vt.channel_id = c.id
        WHERE (p_min_date IS NULL OR vt.published_at >= p_min_date)
          AND (p_video_type='all' OR (p_video_type='short' AND vt.duration_seconds<=60)
               OR (p_video_type='normal' AND vt.duration_seconds>60))
          AND (p_country IS NULL OR c.country = p_country)
    )
    SELECT tid, tname, tname_ja, tparent, tcategory,
           COUNT(DISTINCT video_id)::BIGINT, COUNT(DISTINCT channel_id)::BIGINT,
           COALESCE(SUM(view_count),0),
           COALESCE(AVG(view_count),0)::BIGINT,
           CASE WHEN COUNT(DISTINCT channel_id)>0
                THEN (COALESCE(AVG(view_count),0)/COUNT(DISTINCT channel_id))::BIGINT ELSE 0 END,
           CASE WHEN COALESCE(SUM(view_count),0)>0
                THEN ROUND(COALESCE(SUM(like_count),0)::NUMERIC/SUM(view_count)*100,2) ELSE 0 END,
           CASE WHEN COALESCE(SUM(view_count),0)>0
                THEN ROUND(COALESCE(SUM(comment_count),0)::NUMERIC/SUM(view_count)*100,4) ELSE 0 END
    FROM tv GROUP BY tid, tname, tname_ja, tparent, tcategory;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- fn_competition_concentration
DROP FUNCTION IF EXISTS fn_competition_concentration(TIMESTAMPTZ, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS fn_competition_concentration(TIMESTAMPTZ, TEXT, TEXT);
DROP FUNCTION IF EXISTS fn_competition_concentration(TIMESTAMPTZ, TEXT);
CREATE OR REPLACE FUNCTION fn_competition_concentration(
    p_min_date   TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT        DEFAULT 'all',
    p_country    TEXT        DEFAULT NULL
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT,
    topic_total_views BIGINT, top5_views BIGINT, top5_share_pct NUMERIC
) AS $$
DECLARE src TEXT;
BEGIN
    IF p_min_date IS NULL AND p_country IS NULL THEN
        IF    p_video_type = 'short'  THEN src := 'mv_topic_video_short';
        ELSIF p_video_type = 'normal' THEN src := 'mv_topic_video_normal';
        END IF;
        IF src IS NOT NULL THEN
            RETURN QUERY EXECUTE format($q$
                WITH cv AS (
                    SELECT t.id AS tid, t.name AS tname, t.name_ja AS tname_ja,
                           tv.channel_id, SUM(tv.view_count) AS total_v
                    FROM topics t JOIN %I tv ON tv.topic_id = t.id
                    GROUP BY t.id, t.name, t.name_ja, tv.channel_id
                ), r AS (
                    SELECT *, ROW_NUMBER() OVER (PARTITION BY tid ORDER BY total_v DESC) AS rnk,
                           SUM(total_v) OVER (PARTITION BY tid) AS topic_total
                    FROM cv
                )
                SELECT tid, tname, tname_ja, topic_total::BIGINT,
                       SUM(total_v) FILTER (WHERE rnk<=5)::BIGINT,
                       ROUND(SUM(total_v) FILTER (WHERE rnk<=5)::NUMERIC/NULLIF(topic_total,0)*100,1)
                FROM r GROUP BY tid, tname, tname_ja, topic_total
            $q$, src);
            RETURN;
        END IF;
    END IF;
    RETURN QUERY
    WITH cv AS (
        SELECT t.id AS tid, t.name AS tname, t.name_ja AS tname_ja,
               vt.channel_id, SUM(vs.view_count) AS total_v
        FROM topics t
        JOIN mv_video_topics vt ON vt.topic_id = t.id
        JOIN mv_latest_video_snapshot vs ON vt.video_id = vs.video_id
        LEFT JOIN channels c ON vt.channel_id = c.id
        WHERE (p_min_date IS NULL OR vt.published_at >= p_min_date)
          AND (p_video_type='all' OR (p_video_type='short' AND vt.duration_seconds<=60)
               OR (p_video_type='normal' AND vt.duration_seconds>60))
          AND (p_country IS NULL OR c.country = p_country)
        GROUP BY t.id, t.name, t.name_ja, vt.channel_id
    ), r AS (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY tid ORDER BY total_v DESC) AS rnk,
               SUM(total_v) OVER (PARTITION BY tid) AS topic_total FROM cv
    )
    SELECT tid, tname, tname_ja, topic_total::BIGINT,
           SUM(total_v) FILTER (WHERE rnk<=5)::BIGINT,
           ROUND(SUM(total_v) FILTER (WHERE rnk<=5)::NUMERIC/NULLIF(topic_total,0)*100,1)
    FROM r GROUP BY tid, tname, tname_ja, topic_total;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- fn_new_channel_success_rate
DROP FUNCTION IF EXISTS fn_new_channel_success_rate(TIMESTAMPTZ, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS fn_new_channel_success_rate(TIMESTAMPTZ, TEXT, TEXT);
DROP FUNCTION IF EXISTS fn_new_channel_success_rate(TIMESTAMPTZ, TEXT);
CREATE OR REPLACE FUNCTION fn_new_channel_success_rate(
    p_min_date   TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT        DEFAULT 'all',
    p_country    TEXT        DEFAULT NULL
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT,
    new_channel_count BIGINT, successful_count BIGINT, success_rate_pct NUMERIC
) AS $$
DECLARE src TEXT;
BEGIN
    IF p_min_date IS NULL AND p_country IS NULL THEN
        IF    p_video_type = 'short'  THEN src := 'mv_active_ch_short';
        ELSIF p_video_type = 'normal' THEN src := 'mv_active_ch_normal';
        END IF;
        IF src IS NOT NULL THEN
            RETURN QUERY EXECUTE format($q$
                WITH nc AS (
                    SELECT c.id, c.topic_ids, cs.subscriber_count
                    FROM channels c
                    JOIN mv_latest_channel_snapshot cs ON c.id = cs.channel_id
                    JOIN %I ac ON c.id = ac.channel_id
                    WHERE c.published_at > NOW() - INTERVAL '1 year'
                )
                SELECT t.id, t.name, t.name_ja, COUNT(*)::BIGINT,
                       COUNT(*) FILTER (WHERE nc.subscriber_count>=1000)::BIGINT,
                       ROUND(COUNT(*) FILTER (WHERE nc.subscriber_count>=1000)::NUMERIC
                             /NULLIF(COUNT(*),0)*100,1)
                FROM topics t JOIN nc ON t.id = ANY(nc.topic_ids)
                GROUP BY t.id, t.name, t.name_ja
            $q$, src);
            RETURN;
        END IF;
    END IF;
    RETURN QUERY
    WITH ac AS (
        SELECT DISTINCT channel_id FROM mv_video_topics
        WHERE (p_video_type='all' OR (p_video_type='short' AND duration_seconds<=60)
               OR (p_video_type='normal' AND duration_seconds>60))
    ), nc AS (
        SELECT c.id, c.topic_ids, cs.subscriber_count
        FROM channels c
        JOIN mv_latest_channel_snapshot cs ON c.id = cs.channel_id
        JOIN ac ON c.id = ac.channel_id
        WHERE c.published_at > COALESCE(p_min_date, NOW()-INTERVAL '1 year')
          AND (p_country IS NULL OR c.country = p_country)
    )
    SELECT t.id, t.name, t.name_ja, COUNT(*)::BIGINT,
           COUNT(*) FILTER (WHERE nc.subscriber_count>=1000)::BIGINT,
           ROUND(COUNT(*) FILTER (WHERE nc.subscriber_count>=1000)::NUMERIC/NULLIF(COUNT(*),0)*100,1)
    FROM topics t JOIN nc ON t.id = ANY(nc.topic_ids)
    GROUP BY t.id, t.name, t.name_ja;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- fn_topic_channel_size
DROP FUNCTION IF EXISTS fn_topic_channel_size(TIMESTAMPTZ, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS fn_topic_channel_size(TIMESTAMPTZ, TEXT, TEXT);
DROP FUNCTION IF EXISTS fn_topic_channel_size(TIMESTAMPTZ, TEXT);
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
DECLARE src TEXT;
BEGIN
    IF p_min_date IS NULL AND p_country IS NULL THEN
        IF    p_video_type = 'short'  THEN src := 'mv_active_ch_short';
        ELSIF p_video_type = 'normal' THEN src := 'mv_active_ch_normal';
        END IF;
        IF src IS NOT NULL THEN
            RETURN QUERY EXECUTE format($q$
                WITH tc AS (
                    SELECT t.id AS tid, t.name AS tname, t.name_ja AS tname_ja,
                           t.parent_id AS tparent, c.id AS cid, cs.subscriber_count AS subs
                    FROM topics t
                    JOIN channels c ON t.id = ANY(c.topic_ids)
                    JOIN mv_latest_channel_snapshot cs ON c.id = cs.channel_id
                    JOIN %I ac ON c.id = ac.channel_id
                )
                SELECT tid, tname, tname_ja, tparent,
                       COUNT(DISTINCT cid)::BIGINT,
                       COUNT(DISTINCT cid) FILTER (WHERE subs<1000)::BIGINT,
                       COUNT(DISTINCT cid) FILTER (WHERE subs>=1000 AND subs<10000)::BIGINT,
                       COUNT(DISTINCT cid) FILTER (WHERE subs>=10000 AND subs<100000)::BIGINT,
                       COUNT(DISTINCT cid) FILTER (WHERE subs>=100000)::BIGINT,
                       ROUND(COUNT(DISTINCT cid) FILTER (WHERE subs<1000)::NUMERIC/NULLIF(COUNT(DISTINCT cid),0)*100,1),
                       ROUND(COUNT(DISTINCT cid) FILTER (WHERE subs>=1000 AND subs<10000)::NUMERIC/NULLIF(COUNT(DISTINCT cid),0)*100,1),
                       ROUND(COUNT(DISTINCT cid) FILTER (WHERE subs>=10000 AND subs<100000)::NUMERIC/NULLIF(COUNT(DISTINCT cid),0)*100,1),
                       ROUND(COUNT(DISTINCT cid) FILTER (WHERE subs>=100000)::NUMERIC/NULLIF(COUNT(DISTINCT cid),0)*100,1)
                FROM tc GROUP BY tid, tname, tname_ja, tparent
            $q$, src);
            RETURN;
        END IF;
    END IF;
    RETURN QUERY
    WITH ac AS (
        SELECT DISTINCT channel_id FROM mv_video_topics
        WHERE (p_min_date IS NULL OR published_at >= p_min_date)
          AND (p_video_type='all' OR (p_video_type='short' AND duration_seconds<=60)
               OR (p_video_type='normal' AND duration_seconds>60))
    ), tc AS (
        SELECT t.id AS tid, t.name AS tname, t.name_ja AS tname_ja,
               t.parent_id AS tparent, c.id AS cid, cs.subscriber_count AS subs
        FROM topics t
        JOIN channels c ON t.id = ANY(c.topic_ids)
        JOIN mv_latest_channel_snapshot cs ON c.id = cs.channel_id
        JOIN ac ON c.id = ac.channel_id
        WHERE (p_country IS NULL OR c.country = p_country)
    )
    SELECT tid, tname, tname_ja, tparent,
           COUNT(DISTINCT cid)::BIGINT,
           COUNT(DISTINCT cid) FILTER (WHERE subs<1000)::BIGINT,
           COUNT(DISTINCT cid) FILTER (WHERE subs>=1000 AND subs<10000)::BIGINT,
           COUNT(DISTINCT cid) FILTER (WHERE subs>=10000 AND subs<100000)::BIGINT,
           COUNT(DISTINCT cid) FILTER (WHERE subs>=100000)::BIGINT,
           ROUND(COUNT(DISTINCT cid) FILTER (WHERE subs<1000)::NUMERIC/NULLIF(COUNT(DISTINCT cid),0)*100,1),
           ROUND(COUNT(DISTINCT cid) FILTER (WHERE subs>=1000 AND subs<10000)::NUMERIC/NULLIF(COUNT(DISTINCT cid),0)*100,1),
           ROUND(COUNT(DISTINCT cid) FILTER (WHERE subs>=10000 AND subs<100000)::NUMERIC/NULLIF(COUNT(DISTINCT cid),0)*100,1),
           ROUND(COUNT(DISTINCT cid) FILTER (WHERE subs>=100000)::NUMERIC/NULLIF(COUNT(DISTINCT cid),0)*100,1)
    FROM tc GROUP BY tid, tname, tname_ja, tparent;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- fn_topic_publish_day
DROP FUNCTION IF EXISTS fn_topic_publish_day(TIMESTAMPTZ, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS fn_topic_publish_day(TIMESTAMPTZ, TEXT, TEXT);
DROP FUNCTION IF EXISTS fn_topic_publish_day(TIMESTAMPTZ, TEXT);
CREATE OR REPLACE FUNCTION fn_topic_publish_day(
    p_min_date   TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT        DEFAULT 'all',
    p_country    TEXT        DEFAULT NULL
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT, parent_id TEXT,
    dow INTEGER, video_count BIGINT, avg_views BIGINT, total_views BIGINT
) AS $$
DECLARE src TEXT;
BEGIN
    IF p_min_date IS NULL AND p_country IS NULL THEN
        IF    p_video_type = 'short'  THEN src := 'mv_topic_video_short';
        ELSIF p_video_type = 'normal' THEN src := 'mv_topic_video_normal';
        END IF;
        IF src IS NOT NULL THEN
            RETURN QUERY EXECUTE format($q$
                SELECT t.id, t.name, t.name_ja, t.parent_id,
                       EXTRACT(DOW FROM tv.published_at AT TIME ZONE 'Asia/Tokyo')::INTEGER,
                       COUNT(*)::BIGINT,
                       COALESCE(AVG(tv.view_count),0)::BIGINT,
                       COALESCE(SUM(tv.view_count),0)::BIGINT
                FROM topics t JOIN %I tv ON tv.topic_id = t.id
                GROUP BY t.id, t.name, t.name_ja, t.parent_id,
                         EXTRACT(DOW FROM tv.published_at AT TIME ZONE 'Asia/Tokyo')
            $q$, src);
            RETURN;
        END IF;
    END IF;
    RETURN QUERY
    WITH tv AS (
        SELECT t.id AS tid, t.name AS tname, t.name_ja AS tname_ja, t.parent_id AS tparent,
               EXTRACT(DOW FROM vt.published_at AT TIME ZONE 'Asia/Tokyo')::INTEGER AS vdow,
               vs.view_count
        FROM topics t
        JOIN mv_video_topics vt ON vt.topic_id = t.id
        JOIN mv_latest_video_snapshot vs ON vt.video_id = vs.video_id
        LEFT JOIN channels c ON vt.channel_id = c.id
        WHERE (p_min_date IS NULL OR vt.published_at >= p_min_date)
          AND (p_video_type='all' OR (p_video_type='short' AND vt.duration_seconds<=60)
               OR (p_video_type='normal' AND vt.duration_seconds>60))
          AND (p_country IS NULL OR c.country = p_country)
    )
    SELECT tid, tname, tname_ja, tparent, vdow,
           COUNT(*)::BIGINT, COALESCE(AVG(view_count),0)::BIGINT, COALESCE(SUM(view_count),0)::BIGINT
    FROM tv GROUP BY tid, tname, tname_ja, tparent, vdow;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- fn_topic_country_distribution
DROP FUNCTION IF EXISTS fn_topic_country_distribution(TIMESTAMPTZ, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS fn_topic_country_distribution(TIMESTAMPTZ, TEXT, TEXT);
DROP FUNCTION IF EXISTS fn_topic_country_distribution(TIMESTAMPTZ, TEXT);
CREATE OR REPLACE FUNCTION fn_topic_country_distribution(
    p_min_date   TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT        DEFAULT 'all',
    p_country    TEXT        DEFAULT NULL
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT, parent_id TEXT,
    country TEXT, channel_count BIGINT, total_subscribers BIGINT
) AS $$
DECLARE src TEXT;
BEGIN
    IF p_min_date IS NULL AND p_country IS NULL THEN
        IF    p_video_type = 'short'  THEN src := 'mv_active_ch_short';
        ELSIF p_video_type = 'normal' THEN src := 'mv_active_ch_normal';
        END IF;
        IF src IS NOT NULL THEN
            RETURN QUERY EXECUTE format($q$
                SELECT t.id, t.name, t.name_ja, t.parent_id,
                       COALESCE(c.country,'Unknown'), COUNT(DISTINCT c.id)::BIGINT,
                       COALESCE(SUM(cs.subscriber_count),0)::BIGINT
                FROM topics t
                JOIN channels c ON t.id = ANY(c.topic_ids)
                JOIN mv_latest_channel_snapshot cs ON c.id = cs.channel_id
                JOIN %I ac ON c.id = ac.channel_id
                GROUP BY t.id, t.name, t.name_ja, t.parent_id, COALESCE(c.country,'Unknown')
            $q$, src);
            RETURN;
        END IF;
    END IF;
    RETURN QUERY
    WITH ac AS (
        SELECT DISTINCT channel_id FROM mv_video_topics
        WHERE (p_min_date IS NULL OR published_at >= p_min_date)
          AND (p_video_type='all' OR (p_video_type='short' AND duration_seconds<=60)
               OR (p_video_type='normal' AND duration_seconds>60))
    )
    SELECT t.id, t.name, t.name_ja, t.parent_id,
           COALESCE(c.country,'Unknown'), COUNT(DISTINCT c.id)::BIGINT,
           COALESCE(SUM(cs.subscriber_count),0)::BIGINT
    FROM topics t
    JOIN channels c ON t.id = ANY(c.topic_ids)
    JOIN mv_latest_channel_snapshot cs ON c.id = cs.channel_id
    JOIN ac ON c.id = ac.channel_id
    WHERE (p_country IS NULL OR c.country = p_country)
    GROUP BY t.id, t.name, t.name_ja, t.parent_id, COALESCE(c.country,'Unknown');
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- fn_topic_popular_tags
DROP FUNCTION IF EXISTS fn_topic_popular_tags(TIMESTAMPTZ, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS fn_topic_popular_tags(TIMESTAMPTZ, TEXT, TEXT);
DROP FUNCTION IF EXISTS fn_topic_popular_tags(TIMESTAMPTZ, TEXT);
CREATE OR REPLACE FUNCTION fn_topic_popular_tags(
    p_min_date   TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT        DEFAULT 'all',
    p_country    TEXT        DEFAULT NULL
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT,
    tag TEXT, usage_count BIGINT, avg_views BIGINT, rank BIGINT
) AS $$
DECLARE src TEXT;
BEGIN
    IF p_min_date IS NULL AND p_country IS NULL THEN
        IF    p_video_type = 'short'  THEN src := 'mv_topic_video_short';
        ELSIF p_video_type = 'normal' THEN src := 'mv_topic_video_normal';
        END IF;
        IF src IS NOT NULL THEN
            RETURN QUERY EXECUTE format($q$
                WITH td AS (
                    SELECT tv.topic_id AS tid, vtags.tag, tv.view_count
                    FROM %I tv JOIN mv_video_tags vtags ON tv.video_id = vtags.video_id
                    WHERE LENGTH(vtags.tag) >= 2
                ), r AS (
                    SELECT t.id, t.name, t.name_ja, td.tag,
                           COUNT(*)::BIGINT AS cnt,
                           COALESCE(AVG(td.view_count),0)::BIGINT AS avgv,
                           ROW_NUMBER() OVER (PARTITION BY t.id ORDER BY COUNT(*) DESC) AS rk
                    FROM topics t JOIN td ON td.tid = t.id
                    GROUP BY t.id, t.name, t.name_ja, td.tag
                )
                SELECT id, name, name_ja, tag, cnt, avgv, rk FROM r WHERE rk <= 10
            $q$, src);
            RETURN;
        END IF;
    END IF;
    RETURN QUERY
    WITH fv AS (
        SELECT DISTINCT vt.topic_id, vt.video_id
        FROM mv_video_topics vt
        LEFT JOIN channels c ON vt.channel_id = c.id
        WHERE (p_min_date IS NULL OR vt.published_at >= p_min_date)
          AND (p_video_type='all' OR (p_video_type='short' AND vt.duration_seconds<=60)
               OR (p_video_type='normal' AND vt.duration_seconds>60))
          AND (p_country IS NULL OR c.country = p_country)
    ), td AS (
        SELECT fv.topic_id AS tid, vtags.tag, vs.view_count
        FROM fv
        JOIN mv_video_tags vtags ON fv.video_id = vtags.video_id
        JOIN mv_latest_video_snapshot vs ON fv.video_id = vs.video_id
        WHERE LENGTH(vtags.tag) >= 2
    ), r AS (
        SELECT t.id, t.name, t.name_ja, td.tag,
               COUNT(*)::BIGINT AS cnt, COALESCE(AVG(td.view_count),0)::BIGINT AS avgv,
               ROW_NUMBER() OVER (PARTITION BY t.id ORDER BY COUNT(*) DESC) AS rk
        FROM topics t JOIN td ON td.tid = t.id
        GROUP BY t.id, t.name, t.name_ja, td.tag
    )
    SELECT id, name, name_ja, tag, cnt, avgv, rk FROM r WHERE rk <= 10;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- fn_channel_growth_efficiency (全バリアント削除)
DROP FUNCTION IF EXISTS fn_channel_growth_efficiency(TIMESTAMPTZ, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS fn_channel_growth_efficiency(TIMESTAMPTZ, TEXT, TEXT);
DROP FUNCTION IF EXISTS fn_channel_growth_efficiency(TIMESTAMPTZ, TEXT);
DROP FUNCTION IF EXISTS fn_channel_growth_efficiency(TIMESTAMPTZ);
DROP FUNCTION IF EXISTS fn_channel_growth_efficiency();
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
DECLARE src TEXT;
BEGIN
    IF p_min_date IS NULL AND p_country IS NULL THEN
        IF    p_video_type = 'all'    THEN RETURN QUERY SELECT * FROM mv_channel_growth_efficiency; RETURN;
        ELSIF p_video_type = 'short'  THEN src := 'mv_active_ch_short';
        ELSIF p_video_type = 'normal' THEN src := 'mv_active_ch_normal';
        END IF;
        IF src IS NOT NULL THEN
            RETURN QUERY EXECUTE format($q$
                SELECT c.id, c.title, c.published_at, c.country, c.topic_ids,
                       cs.subscriber_count, cs.view_count, cs.video_count,
                       GREATEST(EXTRACT(EPOCH FROM (NOW()-c.published_at))/86400,1)::INTEGER,
                       CASE WHEN EXTRACT(EPOCH FROM (NOW()-c.published_at))>0
                            THEN ROUND(cs.subscriber_count::NUMERIC/GREATEST(EXTRACT(EPOCH FROM (NOW()-c.published_at))/86400,1),2)
                            ELSE 0 END,
                       CASE WHEN cs.video_count>0 THEN ROUND(cs.view_count::NUMERIC/cs.video_count) ELSE 0 END
                FROM channels c
                JOIN mv_latest_channel_snapshot cs ON c.id = cs.channel_id
                JOIN %I ac ON c.id = ac.channel_id
                WHERE c.published_at IS NOT NULL AND cs.subscriber_count > 0
            $q$, src);
            RETURN;
        END IF;
    END IF;
    RETURN QUERY
    WITH ac AS (
        SELECT DISTINCT channel_id FROM mv_video_topics
        WHERE (p_min_date IS NULL OR published_at >= p_min_date)
          AND (p_video_type='all' OR (p_video_type='short' AND duration_seconds<=60)
               OR (p_video_type='normal' AND duration_seconds>60))
    )
    SELECT c.id, c.title, c.published_at, c.country, c.topic_ids,
           cs.subscriber_count, cs.view_count, cs.video_count,
           GREATEST(EXTRACT(EPOCH FROM (NOW()-c.published_at))/86400,1)::INTEGER,
           CASE WHEN EXTRACT(EPOCH FROM (NOW()-c.published_at))>0
                THEN ROUND(cs.subscriber_count::NUMERIC/GREATEST(EXTRACT(EPOCH FROM (NOW()-c.published_at))/86400,1),2)
                ELSE 0 END,
           CASE WHEN cs.video_count>0 THEN ROUND(cs.view_count::NUMERIC/cs.video_count) ELSE 0 END
    FROM channels c
    JOIN mv_latest_channel_snapshot cs ON c.id = cs.channel_id
    JOIN ac ON c.id = ac.channel_id
    WHERE c.published_at IS NOT NULL AND cs.subscriber_count > 0
      AND (p_country IS NULL OR c.country = p_country);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- fn_topic_overlap
DROP FUNCTION IF EXISTS fn_topic_overlap(TIMESTAMPTZ, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS fn_topic_overlap(TIMESTAMPTZ, TEXT, TEXT);
DROP FUNCTION IF EXISTS fn_topic_overlap(TIMESTAMPTZ, TEXT);
CREATE OR REPLACE FUNCTION fn_topic_overlap(
    p_min_date   TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT        DEFAULT 'all',
    p_country    TEXT        DEFAULT NULL
)
RETURNS TABLE(topic_a TEXT, name_a TEXT, topic_b TEXT, name_b TEXT, shared_channels BIGINT) AS $$
BEGIN
    IF p_min_date IS NULL AND p_country IS NULL THEN
        IF p_video_type = 'all'    THEN RETURN QUERY SELECT * FROM mv_topic_overlap;        RETURN;
        ELSIF p_video_type = 'short'  THEN RETURN QUERY SELECT * FROM mv_topic_overlap_short;  RETURN;
        ELSIF p_video_type = 'normal' THEN RETURN QUERY SELECT * FROM mv_topic_overlap_normal; RETURN;
        END IF;
    END IF;
    RETURN QUERY
    WITH ac AS (
        SELECT DISTINCT channel_id FROM mv_video_topics
        WHERE (p_min_date IS NULL OR published_at >= p_min_date)
          AND (p_video_type='all' OR (p_video_type='short' AND duration_seconds<=60)
               OR (p_video_type='normal' AND duration_seconds>60))
    )
    SELECT t1.id, t1.name_ja, t2.id, t2.name_ja, COUNT(DISTINCT c.id)::BIGINT
    FROM channels c JOIN ac ON c.id = ac.channel_id
    JOIN topics t1 ON t1.id = ANY(c.topic_ids) AND t1.parent_id IS NOT NULL
    JOIN topics t2 ON t2.id = ANY(c.topic_ids) AND t2.parent_id IS NOT NULL
    WHERE t1.id < t2.id AND (p_country IS NULL OR c.country = p_country)
    GROUP BY t1.id, t1.name_ja, t2.id, t2.name_ja
    HAVING COUNT(DISTINCT c.id) >= 2;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- fn_ai_penetration
DROP FUNCTION IF EXISTS fn_ai_penetration(TIMESTAMPTZ, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS fn_ai_penetration(TIMESTAMPTZ, TEXT, TEXT);
DROP FUNCTION IF EXISTS fn_ai_penetration(TIMESTAMPTZ, TEXT);
CREATE OR REPLACE FUNCTION fn_ai_penetration(
    p_min_date   TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT        DEFAULT 'all',
    p_country    TEXT        DEFAULT NULL
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT, parent_id TEXT, category TEXT,
    total_videos BIGINT, ai_video_count BIGINT, ai_penetration_pct NUMERIC
) AS $$
DECLARE src TEXT;
BEGIN
    IF p_min_date IS NULL AND p_country IS NULL THEN
        IF    p_video_type = 'all'    THEN RETURN QUERY SELECT * FROM mv_ai_penetration; RETURN;
        ELSIF p_video_type = 'short'  THEN src := 'mv_topic_video_short';
        ELSIF p_video_type = 'normal' THEN src := 'mv_topic_video_normal';
        END IF;
        IF src IS NOT NULL THEN
            RETURN QUERY EXECUTE format($q$
                SELECT t.id, t.name, t.name_ja, t.parent_id, t.category,
                       COUNT(*)::BIGINT,
                       COUNT(*) FILTER (WHERE tv.has_ai_keywords)::BIGINT,
                       ROUND(COUNT(*) FILTER (WHERE tv.has_ai_keywords)::NUMERIC/NULLIF(COUNT(*),0)*100,1)
                FROM topics t JOIN %I tv ON tv.topic_id = t.id
                GROUP BY t.id, t.name, t.name_ja, t.parent_id, t.category
            $q$, src);
            RETURN;
        END IF;
    END IF;
    RETURN QUERY
    SELECT t.id, t.name, t.name_ja, t.parent_id, t.category,
           COUNT(*)::BIGINT,
           COUNT(*) FILTER (WHERE vt.has_ai_keywords)::BIGINT,
           ROUND(COUNT(*) FILTER (WHERE vt.has_ai_keywords)::NUMERIC/NULLIF(COUNT(*),0)*100,1)
    FROM topics t JOIN mv_video_topics vt ON vt.topic_id = t.id
    LEFT JOIN channels c ON vt.channel_id = c.id
    WHERE (p_min_date IS NULL OR vt.published_at >= p_min_date)
      AND (p_video_type='all' OR (p_video_type='short' AND vt.duration_seconds<=60)
           OR (p_video_type='normal' AND vt.duration_seconds>60))
      AND (p_country IS NULL OR c.country = p_country)
    GROUP BY t.id, t.name, t.name_ja, t.parent_id, t.category;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- fn_topic_duration_stats
DROP FUNCTION IF EXISTS fn_topic_duration_stats(TIMESTAMPTZ, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS fn_topic_duration_stats(TIMESTAMPTZ, TEXT, TEXT);
DROP FUNCTION IF EXISTS fn_topic_duration_stats(TIMESTAMPTZ, TEXT);
CREATE OR REPLACE FUNCTION fn_topic_duration_stats(
    p_min_date   TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT        DEFAULT 'all',
    p_country    TEXT        DEFAULT NULL
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT, parent_id TEXT,
    avg_duration_sec NUMERIC, median_duration_sec NUMERIC,
    short_pct NUMERIC, normal_pct NUMERIC
) AS $$
BEGIN
    IF p_min_date IS NULL AND p_country IS NULL THEN
        IF p_video_type = 'all' THEN
            RETURN QUERY SELECT * FROM mv_topic_duration_stats; RETURN;
        ELSIF p_video_type = 'short' THEN
            RETURN QUERY
            SELECT t.id, t.name, t.name_ja, t.parent_id,
                   COALESCE(AVG(vt.duration_seconds),0),
                   COALESCE(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY vt.duration_seconds),0),
                   100.0::NUMERIC, 0.0::NUMERIC
            FROM topics t JOIN mv_video_topics vt ON vt.topic_id = t.id
            WHERE vt.duration_seconds <= 60
            GROUP BY t.id, t.name, t.name_ja, t.parent_id;
            RETURN;
        ELSIF p_video_type = 'normal' THEN
            RETURN QUERY
            SELECT t.id, t.name, t.name_ja, t.parent_id,
                   COALESCE(AVG(vt.duration_seconds),0),
                   COALESCE(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY vt.duration_seconds),0),
                   0.0::NUMERIC, 100.0::NUMERIC
            FROM topics t JOIN mv_video_topics vt ON vt.topic_id = t.id
            WHERE vt.duration_seconds > 60
            GROUP BY t.id, t.name, t.name_ja, t.parent_id;
            RETURN;
        END IF;
    END IF;
    RETURN QUERY
    SELECT t.id, t.name, t.name_ja, t.parent_id,
           COALESCE(AVG(vt.duration_seconds),0),
           COALESCE(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY vt.duration_seconds),0),
           ROUND(COUNT(*) FILTER (WHERE vt.duration_seconds<=60)::NUMERIC/NULLIF(COUNT(*),0)*100,1),
           ROUND(COUNT(*) FILTER (WHERE vt.duration_seconds>60)::NUMERIC/NULLIF(COUNT(*),0)*100,1)
    FROM topics t JOIN mv_video_topics vt ON vt.topic_id = t.id
    LEFT JOIN channels c ON vt.channel_id = c.id
    WHERE (p_min_date IS NULL OR vt.published_at >= p_min_date)
      AND (p_video_type='all' OR (p_video_type='short' AND vt.duration_seconds<=60)
           OR (p_video_type='normal' AND vt.duration_seconds>60))
      AND (p_country IS NULL OR c.country = p_country)
    GROUP BY t.id, t.name, t.name_ja, t.parent_id;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- fn_keyword_opportunity (3パラメータ, 全オーバーロード削除)
DROP FUNCTION IF EXISTS fn_keyword_opportunity(TIMESTAMPTZ, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS fn_keyword_opportunity(TIMESTAMPTZ, TEXT, TEXT);
DROP FUNCTION IF EXISTS fn_keyword_opportunity(TIMESTAMPTZ, TEXT);
DROP FUNCTION IF EXISTS fn_keyword_opportunity(TIMESTAMPTZ);
CREATE OR REPLACE FUNCTION fn_keyword_opportunity(
    p_min_date   TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT        DEFAULT 'all',
    p_country    TEXT        DEFAULT NULL
)
RETURNS TABLE(
    tag TEXT, usage_count BIGINT, channel_count BIGINT,
    avg_views BIGINT, total_views BIGINT, avg_like_rate NUMERIC,
    avg_buzz_score NUMERIC, keyword_score BIGINT, rank BIGINT
) AS $$
BEGIN
    IF p_min_date IS NULL AND p_country IS NULL THEN
        IF    p_video_type = 'all'    THEN RETURN QUERY SELECT * FROM mv_keyword_opportunity; RETURN;
        ELSIF p_video_type = 'short'  THEN RETURN QUERY SELECT * FROM mv_keyword_opp_short;   RETURN;
        ELSIF p_video_type = 'normal' THEN RETURN QUERY SELECT * FROM mv_keyword_opp_normal;  RETURN;
        END IF;
    END IF;
    RETURN QUERY
    WITH ts AS (
        SELECT vt.tag, COUNT(*)::BIGINT AS usage_count,
               COUNT(DISTINCT vt.channel_id)::BIGINT AS channel_count,
               COALESCE(AVG(vs.view_count),0)::BIGINT AS avg_views,
               COALESCE(SUM(vs.view_count),0)::BIGINT AS total_views,
               COALESCE(AVG(CASE WHEN vs.view_count>0 THEN vs.like_count::NUMERIC/vs.view_count*100 ELSE 0 END),0)::NUMERIC(8,2) AS avg_like_rate,
               COALESCE(AVG(CASE WHEN cs.subscriber_count>0 THEN vs.view_count::NUMERIC/cs.subscriber_count ELSE 0 END),0)::NUMERIC(10,1) AS avg_buzz_score
        FROM mv_video_tags vt
        JOIN mv_latest_video_snapshot vs ON vt.video_id = vs.video_id
        LEFT JOIN mv_latest_channel_snapshot cs ON vt.channel_id = cs.channel_id
        LEFT JOIN channels c ON vt.channel_id = c.id
        WHERE (p_min_date IS NULL OR vt.published_at >= p_min_date)
          AND (p_video_type='all' OR (p_video_type='short' AND vt.duration_seconds<=60)
               OR (p_video_type='normal' AND vt.duration_seconds>60))
          AND (p_country IS NULL OR c.country = p_country)
        GROUP BY vt.tag HAVING COUNT(*) >= 2
    ), sc AS (
        SELECT *, ROUND((avg_views::NUMERIC/GREATEST(channel_count,1))*(1+avg_like_rate/10)*LEAST(avg_buzz_score/10+1,5))::BIGINT AS keyword_score FROM ts
    )
    SELECT tag, usage_count, channel_count, avg_views, total_views,
           avg_like_rate, avg_buzz_score, keyword_score,
           ROW_NUMBER() OVER (ORDER BY keyword_score DESC)::BIGINT
    FROM sc ORDER BY keyword_score DESC LIMIT 200;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- fn_keyword_virality (3パラメータ, 全オーバーロード削除)
DROP FUNCTION IF EXISTS fn_keyword_virality(TIMESTAMPTZ, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS fn_keyword_virality(TIMESTAMPTZ, TEXT, TEXT);
DROP FUNCTION IF EXISTS fn_keyword_virality(TIMESTAMPTZ, TEXT);
DROP FUNCTION IF EXISTS fn_keyword_virality(TIMESTAMPTZ);
CREATE OR REPLACE FUNCTION fn_keyword_virality(
    p_min_date   TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT        DEFAULT 'all',
    p_country    TEXT        DEFAULT NULL
)
RETURNS TABLE(
    tag TEXT, video_count BIGINT, channel_count BIGINT,
    avg_views BIGINT, avg_buzz_score NUMERIC, virality_score NUMERIC,
    max_views BIGINT, viral_rate_pct NUMERIC, rank BIGINT
) AS $$
BEGIN
    IF p_min_date IS NULL AND p_country IS NULL THEN
        IF    p_video_type = 'all'    THEN RETURN QUERY SELECT * FROM mv_keyword_virality;   RETURN;
        ELSIF p_video_type = 'short'  THEN RETURN QUERY SELECT * FROM mv_keyword_vir_short;  RETURN;
        ELSIF p_video_type = 'normal' THEN RETURN QUERY SELECT * FROM mv_keyword_vir_normal; RETURN;
        END IF;
    END IF;
    RETURN QUERY
    WITH tb AS (
        SELECT vt.tag, COUNT(*)::BIGINT AS video_count,
               COUNT(DISTINCT vt.channel_id)::BIGINT AS channel_count,
               COALESCE(AVG(vs.view_count),0)::BIGINT AS avg_views,
               COALESCE(AVG(CASE WHEN cs.subscriber_count>0 THEN vs.view_count::NUMERIC/cs.subscriber_count ELSE 0 END),0)::NUMERIC(10,1) AS avg_buzz_score,
               COALESCE(AVG(CASE WHEN cs.subscriber_count>0 AND vs.view_count>0
                   THEN (vs.view_count::NUMERIC/cs.subscriber_count)*(1+vs.like_count::NUMERIC/vs.view_count*5)*(1+vs.comment_count::NUMERIC/vs.view_count*10) ELSE 0 END),0)::NUMERIC(10,1) AS virality_score,
               MAX(vs.view_count)::BIGINT AS max_views,
               ROUND(COUNT(*) FILTER (WHERE cs.subscriber_count>0 AND vs.view_count::NUMERIC/cs.subscriber_count>2)*100.0/GREATEST(COUNT(*),1),1)::NUMERIC(5,1) AS viral_rate_pct
        FROM mv_video_tags vt
        JOIN mv_latest_video_snapshot vs ON vt.video_id = vs.video_id
        LEFT JOIN mv_latest_channel_snapshot cs ON vt.channel_id = cs.channel_id
        LEFT JOIN channels c ON vt.channel_id = c.id
        WHERE (p_min_date IS NULL OR vt.published_at >= p_min_date)
          AND (p_video_type='all' OR (p_video_type='short' AND vt.duration_seconds<=60)
               OR (p_video_type='normal' AND vt.duration_seconds>60))
          AND (p_country IS NULL OR c.country = p_country)
        GROUP BY vt.tag HAVING COUNT(*) >= 3
    )
    SELECT tag, video_count, channel_count, avg_views, avg_buzz_score,
           virality_score, max_views, viral_rate_pct,
           ROW_NUMBER() OVER (ORDER BY virality_score DESC)::BIGINT
    FROM tb ORDER BY virality_score DESC LIMIT 100;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ============================================================
-- 4. リフレッシュ関数 Group4-6
-- ============================================================
CREATE OR REPLACE FUNCTION refresh_type_base_mvs()
RETURNS VOID AS $$
BEGIN
    REFRESH MATERIALIZED VIEW mv_topic_video_short;
    REFRESH MATERIALIZED VIEW mv_topic_video_normal;
    REFRESH MATERIALIZED VIEW mv_active_ch_short;
    REFRESH MATERIALIZED VIEW mv_active_ch_normal;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION refresh_type_overlap_mvs()
RETURNS VOID AS $$
BEGIN
    REFRESH MATERIALIZED VIEW mv_topic_overlap_short;
    REFRESH MATERIALIZED VIEW mv_topic_overlap_normal;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION refresh_type_keyword_mvs()
RETURNS VOID AS $$
BEGIN
    REFRESH MATERIALIZED VIEW mv_keyword_opp_short;
    REFRESH MATERIALIZED VIEW mv_keyword_opp_normal;
    REFRESH MATERIALIZED VIEW mv_keyword_vir_short;
    REFRESH MATERIALIZED VIEW mv_keyword_vir_normal;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
