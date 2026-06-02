-- ============================================================
-- フロントが叩く RPC のコードバグ修正（実測デバッグで特定）
--
-- ※ 当初 ALTER FUNCTION ... SET plpgsql.variable_conflict='use_column' を使ったが、
--    Supabase の postgres ロールは非スーパーユーザーで権限不足(42501)になるため、
--    関数本体内の #variable_conflict use_column ディレクティブ方式に変更。
--    （ディレクティブはコンパイル指示で権限不要。本体は実DB定義のまま＋1行追加）
--
-- A) 曖昧カラム参照(42702) 4関数:
--    name_ja/channel_id/avg_views/tag が RETURNS TABLE のOUT名と衝突。
--    #variable_conflict use_column で「曖昧時はカラム優先」させて解消。
-- B) 戻り値型不一致(42804) fn_topic_duration_stats:
--    PERCENTILE_CONT(double precision) を numeric 列に返していた → ::NUMERIC。
-- ============================================================

-- ------------------------------------------------------------
-- A-1. fn_topic_popular_tags
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_topic_popular_tags(
    p_min_date   TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT        DEFAULT 'all',
    p_country    TEXT        DEFAULT NULL
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT,
    tag TEXT, usage_count BIGINT, avg_views BIGINT, rank BIGINT
) AS $$
#variable_conflict use_column
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

-- ------------------------------------------------------------
-- A-2. fn_channel_growth_efficiency
-- ------------------------------------------------------------
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
#variable_conflict use_column
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

-- ------------------------------------------------------------
-- A-3. fn_keyword_opportunity
-- ------------------------------------------------------------
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
#variable_conflict use_column
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

-- ------------------------------------------------------------
-- A-4. fn_keyword_virality
-- ------------------------------------------------------------
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
#variable_conflict use_column
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

-- ------------------------------------------------------------
-- B. fn_topic_duration_stats の型不一致を修正（PERCENTILE_CONT/AVG を ::NUMERIC）
-- ------------------------------------------------------------
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
            RETURN QUERY
            SELECT m.topic_id, m.topic_name, m.name_ja, m.parent_id,
                   m.avg_duration_sec::NUMERIC, m.median_duration_sec::NUMERIC,
                   m.short_pct::NUMERIC, m.normal_pct::NUMERIC
            FROM mv_topic_duration_stats m;
            RETURN;
        ELSIF p_video_type = 'short' THEN
            RETURN QUERY
            SELECT t.id, t.name, t.name_ja, t.parent_id,
                   COALESCE(AVG(vt.duration_seconds),0)::NUMERIC,
                   COALESCE(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY vt.duration_seconds),0)::NUMERIC,
                   100.0::NUMERIC, 0.0::NUMERIC
            FROM topics t JOIN mv_video_topics vt ON vt.topic_id = t.id
            WHERE vt.duration_seconds <= 60
            GROUP BY t.id, t.name, t.name_ja, t.parent_id;
            RETURN;
        ELSIF p_video_type = 'normal' THEN
            RETURN QUERY
            SELECT t.id, t.name, t.name_ja, t.parent_id,
                   COALESCE(AVG(vt.duration_seconds),0)::NUMERIC,
                   COALESCE(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY vt.duration_seconds),0)::NUMERIC,
                   0.0::NUMERIC, 100.0::NUMERIC
            FROM topics t JOIN mv_video_topics vt ON vt.topic_id = t.id
            WHERE vt.duration_seconds > 60
            GROUP BY t.id, t.name, t.name_ja, t.parent_id;
            RETURN;
        END IF;
    END IF;
    RETURN QUERY
    SELECT t.id, t.name, t.name_ja, t.parent_id,
           COALESCE(AVG(vt.duration_seconds),0)::NUMERIC,
           COALESCE(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY vt.duration_seconds),0)::NUMERIC,
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

-- PostgREST に再読み込み通知
NOTIFY pgrst, 'reload config';
