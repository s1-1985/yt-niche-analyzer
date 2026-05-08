-- ============================================================
-- パフォーマンス最適化 v2
-- 問題: 集計ビュー自体（topic_popular_tags, competition_concentration等）が
--       mv_latest_*経由でも statement timeout になる
-- 対策: 全集計ビューをマテリアライズドビュー化（"全期間"クエリを即時返却）
--       RPC関数用に videos テーブルへのインデックスも追加
-- ============================================================

-- 1. videosテーブルのインデックス追加（RPC関数のフィルタ高速化）
CREATE INDEX IF NOT EXISTS idx_videos_published_at
    ON videos(published_at DESC);

CREATE INDEX IF NOT EXISTS idx_videos_channel_id
    ON videos(channel_id);

CREATE INDEX IF NOT EXISTS idx_videos_duration
    ON videos(duration_seconds);

-- ============================================================
-- 2. 集計マテリアライズドビュー（"全期間・全タイプ・全国" 用）
-- ============================================================

-- mv_topic_summary
DROP MATERIALIZED VIEW IF EXISTS mv_topic_summary CASCADE;
CREATE MATERIALIZED VIEW mv_topic_summary AS
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

CREATE UNIQUE INDEX idx_mv_topic_summary_tid ON mv_topic_summary(topic_id);

-- mv_competition_concentration
DROP MATERIALIZED VIEW IF EXISTS mv_competition_concentration CASCADE;
CREATE MATERIALIZED VIEW mv_competition_concentration AS
WITH channel_views AS (
    SELECT
        t.id AS topic_id, t.name AS topic_name, t.name_ja,
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
    topic_id, topic_name, name_ja, topic_total_views::BIGINT,
    SUM(total_views) FILTER (WHERE rank <= 5)::BIGINT AS top5_views,
    ROUND(SUM(total_views) FILTER (WHERE rank <= 5)::NUMERIC / NULLIF(topic_total_views, 0) * 100, 1) AS top5_share_pct
FROM ranked
GROUP BY topic_id, topic_name, name_ja, topic_total_views;

CREATE UNIQUE INDEX idx_mv_competition_concentration_tid ON mv_competition_concentration(topic_id);

-- mv_new_channel_success_rate
DROP MATERIALIZED VIEW IF EXISTS mv_new_channel_success_rate CASCADE;
CREATE MATERIALIZED VIEW mv_new_channel_success_rate AS
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

CREATE UNIQUE INDEX idx_mv_new_channel_success_rate_tid ON mv_new_channel_success_rate(topic_id);

-- mv_topic_popular_tags（最重量級: UNNEST × JOIN を事前集計）
DROP MATERIALIZED VIEW IF EXISTS mv_topic_popular_tags CASCADE;
CREATE MATERIALIZED VIEW mv_topic_popular_tags AS
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

CREATE INDEX idx_mv_topic_popular_tags_tid ON mv_topic_popular_tags(topic_id);

-- mv_topic_publish_day
DROP MATERIALIZED VIEW IF EXISTS mv_topic_publish_day CASCADE;
CREATE MATERIALIZED VIEW mv_topic_publish_day AS
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

CREATE INDEX idx_mv_topic_publish_day_tid ON mv_topic_publish_day(topic_id);

-- mv_topic_country_distribution
DROP MATERIALIZED VIEW IF EXISTS mv_topic_country_distribution CASCADE;
CREATE MATERIALIZED VIEW mv_topic_country_distribution AS
SELECT
    t.id AS topic_id, t.name AS topic_name, t.name_ja, t.parent_id,
    COALESCE(c.country, 'Unknown') AS country,
    COUNT(DISTINCT c.id) AS channel_count,
    COALESCE(SUM(cs.subscriber_count), 0)::BIGINT AS total_subscribers
FROM topics t
JOIN channels c ON t.id = ANY(c.topic_ids)
JOIN mv_latest_channel_snapshot cs ON c.id = cs.channel_id
GROUP BY t.id, t.name, t.name_ja, t.parent_id, COALESCE(c.country, 'Unknown');

CREATE INDEX idx_mv_topic_country_distribution_tid ON mv_topic_country_distribution(topic_id);

-- mv_topic_channel_size
DROP MATERIALIZED VIEW IF EXISTS mv_topic_channel_size CASCADE;
CREATE MATERIALIZED VIEW mv_topic_channel_size AS
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

CREATE UNIQUE INDEX idx_mv_topic_channel_size_tid ON mv_topic_channel_size(topic_id);

-- mv_topic_duration_stats
DROP MATERIALIZED VIEW IF EXISTS mv_topic_duration_stats CASCADE;
CREATE MATERIALIZED VIEW mv_topic_duration_stats AS
WITH topic_videos AS (
    SELECT t.id AS topic_id, t.name AS topic_name, t.name_ja, t.parent_id,
        v.duration_seconds AS dur
    FROM topics t
    JOIN videos v ON t.id = ANY(v.topic_ids)
    WHERE v.duration_seconds > 0
)
SELECT
    topic_id, topic_name, name_ja, parent_id,
    COUNT(*)::BIGINT AS video_count,
    ROUND(AVG(dur))::INTEGER AS avg_duration,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY dur)::INTEGER AS median_duration,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY dur)::INTEGER AS p25_duration,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY dur)::INTEGER AS p75_duration,
    COUNT(*) FILTER (WHERE dur <= 60)::BIGINT AS short_count,
    COUNT(*) FILTER (WHERE dur > 60 AND dur <= 600)::BIGINT AS medium_count,
    COUNT(*) FILTER (WHERE dur > 600)::BIGINT AS long_count
FROM topic_videos
GROUP BY topic_id, topic_name, name_ja, parent_id;

CREATE UNIQUE INDEX idx_mv_topic_duration_stats_tid ON mv_topic_duration_stats(topic_id);

-- mv_video_ranking（Buzz動画ピックアップ用: buzz_score事前計算 + published_atインデックス）
DROP MATERIALIZED VIEW IF EXISTS mv_video_ranking CASCADE;
CREATE MATERIALIZED VIEW mv_video_ranking AS
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

CREATE UNIQUE INDEX idx_mv_video_ranking_id ON mv_video_ranking(id);
CREATE INDEX idx_mv_video_ranking_pub_buzz ON mv_video_ranking(published_at DESC, buzz_score DESC);

-- mv_channel_growth_efficiency（チャンネル成長効率: subs_per_day事前計算）
DROP MATERIALIZED VIEW IF EXISTS mv_channel_growth_efficiency CASCADE;
CREATE MATERIALIZED VIEW mv_channel_growth_efficiency AS
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

CREATE UNIQUE INDEX idx_mv_channel_growth_cid ON mv_channel_growth_efficiency(channel_id);
CREATE INDEX idx_mv_channel_growth_spd ON mv_channel_growth_efficiency(subs_per_day DESC);

-- mv_outlier_channels（外れ値チャンネル: PERCENT_RANK事前計算）
DROP MATERIALIZED VIEW IF EXISTS mv_outlier_channels CASCADE;
CREATE MATERIALIZED VIEW mv_outlier_channels AS
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

CREATE UNIQUE INDEX idx_mv_outlier_channels_id ON mv_outlier_channels(id);

-- mv_keyword_opportunity（お宝キーワード: mv_latest_*使用で高速化）
DROP MATERIALIZED VIEW IF EXISTS mv_keyword_opportunity CASCADE;
CREATE MATERIALIZED VIEW mv_keyword_opportunity AS
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

CREATE UNIQUE INDEX idx_mv_keyword_opportunity_tag ON mv_keyword_opportunity(tag);

-- mv_keyword_virality（キーワード拡散: mv_latest_*使用で高速化）
DROP MATERIALIZED VIEW IF EXISTS mv_keyword_virality CASCADE;
CREATE MATERIALIZED VIEW mv_keyword_virality AS
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
            * 100.0 / GREATEST(COUNT(*), 1),
            1
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

CREATE UNIQUE INDEX idx_mv_keyword_virality_tag ON mv_keyword_virality(tag);

-- ============================================================
-- 3. 静的ビューをMV参照に書き換え（SELECT * FROM mv_xxx のみ）
-- ============================================================

DROP VIEW IF EXISTS topic_summary CASCADE;
CREATE VIEW topic_summary AS SELECT * FROM mv_topic_summary;

DROP VIEW IF EXISTS competition_concentration CASCADE;
CREATE VIEW competition_concentration AS SELECT * FROM mv_competition_concentration;

DROP VIEW IF EXISTS new_channel_success_rate CASCADE;
CREATE VIEW new_channel_success_rate AS SELECT * FROM mv_new_channel_success_rate;

DROP VIEW IF EXISTS topic_popular_tags CASCADE;
CREATE VIEW topic_popular_tags AS SELECT * FROM mv_topic_popular_tags;

DROP VIEW IF EXISTS topic_publish_day CASCADE;
CREATE VIEW topic_publish_day AS SELECT * FROM mv_topic_publish_day;

DROP VIEW IF EXISTS topic_country_distribution CASCADE;
CREATE VIEW topic_country_distribution AS SELECT * FROM mv_topic_country_distribution;

DROP VIEW IF EXISTS topic_channel_size CASCADE;
CREATE VIEW topic_channel_size AS SELECT * FROM mv_topic_channel_size;

DROP VIEW IF EXISTS video_ranking CASCADE;
CREATE VIEW video_ranking AS SELECT * FROM mv_video_ranking;

DROP VIEW IF EXISTS channel_growth_efficiency CASCADE;
CREATE VIEW channel_growth_efficiency AS SELECT * FROM mv_channel_growth_efficiency;

DROP VIEW IF EXISTS outlier_channels CASCADE;
CREATE VIEW outlier_channels AS SELECT * FROM mv_outlier_channels;

DROP VIEW IF EXISTS keyword_opportunity CASCADE;
CREATE VIEW keyword_opportunity AS SELECT * FROM mv_keyword_opportunity;

DROP VIEW IF EXISTS keyword_virality CASCADE;
CREATE VIEW keyword_virality AS SELECT * FROM mv_keyword_virality;

-- ============================================================
-- 4. refresh関数を全MV対応に更新
-- ============================================================

CREATE OR REPLACE FUNCTION refresh_latest_snapshots()
RETURNS void AS $fn$
BEGIN
    -- スナップショットMV（他のMVが依存するため先にリフレッシュ）
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_latest_video_snapshot;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_latest_channel_snapshot;
    -- 集計MV
    REFRESH MATERIALIZED VIEW mv_topic_summary;
    REFRESH MATERIALIZED VIEW mv_competition_concentration;
    REFRESH MATERIALIZED VIEW mv_new_channel_success_rate;
    REFRESH MATERIALIZED VIEW mv_topic_popular_tags;
    REFRESH MATERIALIZED VIEW mv_topic_publish_day;
    REFRESH MATERIALIZED VIEW mv_topic_country_distribution;
    REFRESH MATERIALIZED VIEW mv_topic_channel_size;
    REFRESH MATERIALIZED VIEW mv_topic_duration_stats;
    -- ランキング・分析MV
    REFRESH MATERIALIZED VIEW mv_video_ranking;
    REFRESH MATERIALIZED VIEW mv_channel_growth_efficiency;
    REFRESH MATERIALIZED VIEW mv_outlier_channels;
    REFRESH MATERIALIZED VIEW mv_keyword_opportunity;
    REFRESH MATERIALIZED VIEW mv_keyword_virality;
END;
$fn$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 5. 初回リフレッシュ実行
-- ※ mv_latest_*が既に存在する前提。なければ先に v1 マイグレーションを実行
-- ============================================================
SELECT refresh_latest_snapshots();
