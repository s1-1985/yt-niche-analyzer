-- ============================================================
-- 500エラー完全修正
-- 対象:
--   video_ranking          500 → mv_video_ranking への GRANT 不足
--   fn_keyword_opportunity 500 → CROSS JOIN UNNEST on videos タイムアウト
--   fn_keyword_virality    500 → CROSS JOIN UNNEST on videos タイムアウト
--   topic_overlap          500 → channels 2重JOIN タイムアウト
--   channels(SaturationChart) 500 → 権限確認 + MV化
-- ============================================================

-- ============================================================
-- 1. GRANT: 新規MVへの anon/authenticated 権限付与
--    （Supabaseは新規MV/テーブルを自動GRANTしない）
-- ============================================================
GRANT SELECT ON mv_video_ranking        TO anon, authenticated;
GRANT SELECT ON mv_video_tags           TO anon, authenticated;
GRANT SELECT ON mv_channel_growth_efficiency TO anon, authenticated;
GRANT SELECT ON mv_latest_video_snapshot    TO anon, authenticated;
GRANT SELECT ON mv_latest_channel_snapshot  TO anon, authenticated;

-- ============================================================
-- 2. mv_keyword_opportunity: キーワード機会スコアを事前計算
--    keyword_opportunity ビューをこのMVから読むように変更
-- ============================================================
DROP MATERIALIZED VIEW IF EXISTS mv_keyword_opportunity CASCADE;
CREATE MATERIALIZED VIEW mv_keyword_opportunity AS
WITH tag_stats AS (
    SELECT
        vt.tag,
        COUNT(*)::BIGINT                                         AS usage_count,
        COUNT(DISTINCT vt.channel_id)::BIGINT                   AS channel_count,
        COALESCE(AVG(vs.view_count), 0)::BIGINT                 AS avg_views,
        COALESCE(SUM(vs.view_count), 0)::BIGINT                 AS total_views,
        COALESCE(AVG(
            CASE WHEN vs.view_count > 0
            THEN vs.like_count::NUMERIC / vs.view_count * 100
            ELSE 0 END
        ), 0)::NUMERIC(5,2)                                     AS avg_like_rate,
        COALESCE(AVG(
            CASE WHEN cs.subscriber_count > 0
            THEN vs.view_count::NUMERIC / cs.subscriber_count
            ELSE 0 END
        ), 0)::NUMERIC(10,1)                                    AS avg_buzz_score
    FROM mv_video_tags vt
    JOIN mv_latest_video_snapshot  vs ON vt.video_id   = vs.video_id
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
    ROW_NUMBER() OVER (ORDER BY keyword_score DESC)::BIGINT AS rank
FROM scored
ORDER BY keyword_score DESC
LIMIT 200;

CREATE UNIQUE INDEX idx_mv_keyword_opportunity_rank ON mv_keyword_opportunity(rank);
GRANT SELECT ON mv_keyword_opportunity TO anon, authenticated;

-- ============================================================
-- 3. mv_keyword_virality: バイラルスコアを事前計算
-- ============================================================
DROP MATERIALIZED VIEW IF EXISTS mv_keyword_virality CASCADE;
CREATE MATERIALIZED VIEW mv_keyword_virality AS
WITH tag_buzz AS (
    SELECT
        vt.tag,
        COUNT(*)::BIGINT                                         AS video_count,
        COUNT(DISTINCT vt.channel_id)::BIGINT                   AS channel_count,
        COALESCE(AVG(vs.view_count), 0)::BIGINT                 AS avg_views,
        COALESCE(AVG(
            CASE WHEN cs.subscriber_count > 0
            THEN vs.view_count::NUMERIC / cs.subscriber_count
            ELSE 0 END
        ), 0)::NUMERIC(10,1)                                    AS avg_buzz_score,
        COALESCE(AVG(
            CASE WHEN cs.subscriber_count > 0 AND vs.view_count > 0
            THEN (vs.view_count::NUMERIC / cs.subscriber_count)
                 * (1 + vs.like_count::NUMERIC  / vs.view_count * 5)
                 * (1 + vs.comment_count::NUMERIC / vs.view_count * 10)
            ELSE 0 END
        ), 0)::NUMERIC(10,1)                                    AS virality_score,
        MAX(vs.view_count)::BIGINT                              AS max_views,
        ROUND(
            COUNT(*) FILTER (
                WHERE cs.subscriber_count > 0
                  AND vs.view_count::NUMERIC / cs.subscriber_count > 2
            ) * 100.0 / GREATEST(COUNT(*), 1),
            1
        )::NUMERIC(5,1)                                         AS viral_rate_pct
    FROM mv_video_tags vt
    JOIN mv_latest_video_snapshot  vs ON vt.video_id   = vs.video_id
    LEFT JOIN mv_latest_channel_snapshot cs ON vt.channel_id = cs.channel_id
    GROUP BY vt.tag
    HAVING COUNT(*) >= 3
)
SELECT
    tag, video_count, channel_count, avg_views, avg_buzz_score,
    virality_score, max_views, viral_rate_pct,
    ROW_NUMBER() OVER (ORDER BY virality_score DESC)::BIGINT AS rank
FROM tag_buzz
ORDER BY virality_score DESC
LIMIT 100;

CREATE UNIQUE INDEX idx_mv_keyword_virality_rank ON mv_keyword_virality(rank);
GRANT SELECT ON mv_keyword_virality TO anon, authenticated;

-- ============================================================
-- 4. keyword_opportunity / keyword_virality ビューを
--    事前計算MVから読むように差し替え（デフォルト時に高速化）
-- ============================================================
CREATE OR REPLACE VIEW keyword_opportunity AS
SELECT * FROM mv_keyword_opportunity;

CREATE OR REPLACE VIEW keyword_virality AS
SELECT * FROM mv_keyword_virality;

-- ============================================================
-- 5. fn_keyword_opportunity: mv_video_tags ベースに修正
--    （フィルタあり時もCROSS JOIN UNNESTを廃止）
-- ============================================================
DROP FUNCTION IF EXISTS fn_keyword_opportunity(TIMESTAMPTZ, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION fn_keyword_opportunity(
    p_min_date   TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT        DEFAULT 'all',
    p_country    TEXT        DEFAULT NULL,
    p_topic_id   TEXT        DEFAULT NULL
)
RETURNS TABLE(
    tag TEXT, usage_count BIGINT, channel_count BIGINT,
    avg_views BIGINT, total_views BIGINT,
    avg_like_rate NUMERIC, avg_buzz_score NUMERIC,
    keyword_score BIGINT, rank BIGINT
) AS $$
BEGIN
    -- フィルタなし（デフォルト）は事前計算MVから返す
    IF p_min_date IS NULL AND p_video_type = 'all'
       AND p_country IS NULL AND p_topic_id IS NULL THEN
        RETURN QUERY SELECT * FROM mv_keyword_opportunity;
        RETURN;
    END IF;

    RETURN QUERY
    WITH ts AS (
        SELECT
            vt.tag AS vtag,
            COUNT(*)::BIGINT                    AS cnt,
            COUNT(DISTINCT vt.channel_id)::BIGINT AS ch_cnt,
            COALESCE(AVG(vs.view_count), 0)::BIGINT AS avgv,
            COALESCE(SUM(vs.view_count), 0)::BIGINT AS totv,
            COALESCE(AVG(
                CASE WHEN vs.view_count > 0
                THEN vs.like_count::NUMERIC / vs.view_count * 100 ELSE 0 END
            ), 0)::NUMERIC(5,2)  AS avg_lr,
            COALESCE(AVG(
                CASE WHEN cs.subscriber_count > 0
                THEN vs.view_count::NUMERIC / cs.subscriber_count ELSE 0 END
            ), 0)::NUMERIC(10,1) AS avg_bz
        FROM mv_video_tags vt
        JOIN mv_latest_video_snapshot  vs ON vt.video_id   = vs.video_id
        LEFT JOIN channels             c  ON vt.channel_id = c.id
        LEFT JOIN mv_latest_channel_snapshot cs ON vt.channel_id = cs.channel_id
        WHERE (p_min_date   IS NULL OR vt.published_at >= p_min_date)
          AND (p_video_type = 'all'
            OR (p_video_type = 'short'  AND vt.duration_seconds <= 60)
            OR (p_video_type = 'normal' AND vt.duration_seconds >  60))
          AND (p_country  IS NULL OR c.country = p_country)
          AND (p_topic_id IS NULL OR p_topic_id = ANY(vt.topic_ids))
        GROUP BY vt.tag
        HAVING COUNT(*) >= 2
    ),
    sc AS (
        SELECT ts.*,
            ROUND(
                (ts.avgv::NUMERIC / GREATEST(ts.ch_cnt, 1))
                * (1 + ts.avg_lr / 10)
                * LEAST(ts.avg_bz / 10 + 1, 5)
            )::BIGINT AS kscore
        FROM ts
    )
    SELECT s.vtag, s.cnt, s.ch_cnt, s.avgv, s.totv, s.avg_lr, s.avg_bz,
           s.kscore, ROW_NUMBER() OVER (ORDER BY s.kscore DESC)::BIGINT
    FROM sc s
    ORDER BY s.kscore DESC LIMIT 200;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ============================================================
-- 6. fn_keyword_virality: mv_video_tags ベースに修正
-- ============================================================
DROP FUNCTION IF EXISTS fn_keyword_virality(TIMESTAMPTZ, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION fn_keyword_virality(
    p_min_date   TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT        DEFAULT 'all',
    p_country    TEXT        DEFAULT NULL,
    p_topic_id   TEXT        DEFAULT NULL
)
RETURNS TABLE(
    tag TEXT, video_count BIGINT, channel_count BIGINT,
    avg_views BIGINT, avg_buzz_score NUMERIC,
    virality_score NUMERIC, max_views BIGINT,
    viral_rate_pct NUMERIC, rank BIGINT
) AS $$
BEGIN
    IF p_min_date IS NULL AND p_video_type = 'all'
       AND p_country IS NULL AND p_topic_id IS NULL THEN
        RETURN QUERY SELECT * FROM mv_keyword_virality;
        RETURN;
    END IF;

    RETURN QUERY
    WITH tb AS (
        SELECT
            vt.tag AS vtag,
            COUNT(*)::BIGINT                    AS vcnt,
            COUNT(DISTINCT vt.channel_id)::BIGINT AS ch_cnt,
            COALESCE(AVG(vs.view_count), 0)::BIGINT AS avgv,
            COALESCE(AVG(
                CASE WHEN cs.subscriber_count > 0
                THEN vs.view_count::NUMERIC / cs.subscriber_count ELSE 0 END
            ), 0)::NUMERIC(10,1) AS avg_bz,
            COALESCE(AVG(
                CASE WHEN cs.subscriber_count > 0 AND vs.view_count > 0
                THEN (vs.view_count::NUMERIC / cs.subscriber_count)
                     * (1 + vs.like_count::NUMERIC  / vs.view_count * 5)
                     * (1 + vs.comment_count::NUMERIC / vs.view_count * 10)
                ELSE 0 END
            ), 0)::NUMERIC(10,1) AS vir_score,
            MAX(vs.view_count)::BIGINT AS maxv,
            ROUND(
                COUNT(*) FILTER (
                    WHERE cs.subscriber_count > 0
                      AND vs.view_count::NUMERIC / cs.subscriber_count > 2
                ) * 100.0 / GREATEST(COUNT(*), 1), 1
            )::NUMERIC(5,1) AS vir_pct
        FROM mv_video_tags vt
        JOIN mv_latest_video_snapshot  vs ON vt.video_id   = vs.video_id
        LEFT JOIN channels             c  ON vt.channel_id = c.id
        LEFT JOIN mv_latest_channel_snapshot cs ON vt.channel_id = cs.channel_id
        WHERE (p_min_date   IS NULL OR vt.published_at >= p_min_date)
          AND (p_video_type = 'all'
            OR (p_video_type = 'short'  AND vt.duration_seconds <= 60)
            OR (p_video_type = 'normal' AND vt.duration_seconds >  60))
          AND (p_country  IS NULL OR c.country = p_country)
          AND (p_topic_id IS NULL OR p_topic_id = ANY(vt.topic_ids))
        GROUP BY vt.tag
        HAVING COUNT(*) >= 3
    )
    SELECT tb.vtag, tb.vcnt, tb.ch_cnt, tb.avgv, tb.avg_bz,
           tb.vir_score, tb.maxv, tb.vir_pct,
           ROW_NUMBER() OVER (ORDER BY tb.vir_score DESC)::BIGINT
    FROM tb
    ORDER BY tb.vir_score DESC LIMIT 100;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ============================================================
-- 7. mv_topic_overlap: topic_overlap の重いJOINを事前計算
-- ============================================================
DROP VIEW IF EXISTS topic_overlap CASCADE;
CREATE MATERIALIZED VIEW mv_topic_overlap AS
SELECT
    t1.id        AS topic_a,
    t1.name_ja   AS name_a,
    t2.id        AS topic_b,
    t2.name_ja   AS name_b,
    COUNT(DISTINCT c.id)::BIGINT AS shared_channels
FROM channels c
JOIN topics t1 ON t1.id = ANY(c.topic_ids) AND t1.parent_id IS NOT NULL
JOIN topics t2 ON t2.id = ANY(c.topic_ids) AND t2.parent_id IS NOT NULL
WHERE t1.id < t2.id
GROUP BY t1.id, t1.name_ja, t2.id, t2.name_ja
HAVING COUNT(DISTINCT c.id) >= 2;

CREATE INDEX idx_mv_topic_overlap_shared ON mv_topic_overlap(shared_channels DESC);
GRANT SELECT ON mv_topic_overlap TO anon, authenticated;

CREATE VIEW topic_overlap AS SELECT * FROM mv_topic_overlap;

-- ============================================================
-- 8. refresh_latest_snapshots() に全MVを追加
-- ============================================================
CREATE OR REPLACE FUNCTION refresh_latest_snapshots()
RETURNS void AS $fn$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_latest_video_snapshot;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_latest_channel_snapshot;
    REFRESH MATERIALIZED VIEW mv_channel_growth_efficiency;
    REFRESH MATERIALIZED VIEW mv_video_tags;
    REFRESH MATERIALIZED VIEW mv_video_ranking;
    REFRESH MATERIALIZED VIEW mv_keyword_opportunity;
    REFRESH MATERIALIZED VIEW mv_keyword_virality;
    REFRESH MATERIALIZED VIEW mv_topic_overlap;
END;
$fn$ LANGUAGE plpgsql SECURITY DEFINER;
