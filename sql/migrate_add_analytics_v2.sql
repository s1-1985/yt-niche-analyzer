-- ============================================================
-- 追加分析ビュー v2: 投稿曜日・成長効率・タグ・国別・相関
-- ============================================================

-- ジャンル別の投稿曜日分析
CREATE OR REPLACE VIEW topic_publish_day AS
WITH topic_videos AS (
    SELECT
        t.id AS topic_id,
        t.name AS topic_name,
        t.name_ja,
        t.parent_id,
        EXTRACT(DOW FROM v.published_at AT TIME ZONE 'Asia/Tokyo') AS dow,
        EXTRACT(HOUR FROM v.published_at AT TIME ZONE 'Asia/Tokyo') AS hour_jst,
        vs.view_count
    FROM topics t
    JOIN videos v ON t.id = ANY(v.topic_ids)
    JOIN (
        SELECT DISTINCT ON (video_id) video_id, view_count
        FROM video_snapshots
        ORDER BY video_id, snapshot_date DESC
    ) vs ON v.id = vs.video_id
)
SELECT
    topic_id,
    topic_name,
    name_ja,
    parent_id,
    dow::INTEGER,
    COUNT(*) AS video_count,
    COALESCE(AVG(view_count), 0)::BIGINT AS avg_views,
    COALESCE(SUM(view_count), 0)::BIGINT AS total_views
FROM topic_videos
GROUP BY topic_id, topic_name, name_ja, parent_id, dow;

-- チャンネル成長効率（年齢 vs 登録者数）
CREATE OR REPLACE VIEW channel_growth_efficiency AS
WITH latest_snap AS (
    SELECT DISTINCT ON (channel_id)
        channel_id,
        subscriber_count,
        view_count,
        video_count
    FROM channel_snapshots
    ORDER BY channel_id, snapshot_date DESC
)
SELECT
    c.id AS channel_id,
    c.title,
    c.published_at,
    c.country,
    c.topic_ids,
    ls.subscriber_count,
    ls.view_count,
    ls.video_count,
    GREATEST(EXTRACT(EPOCH FROM (NOW() - c.published_at)) / 86400, 1)::INTEGER AS age_days,
    CASE
        WHEN EXTRACT(EPOCH FROM (NOW() - c.published_at)) > 0
        THEN ROUND(ls.subscriber_count::NUMERIC / GREATEST(EXTRACT(EPOCH FROM (NOW() - c.published_at)) / 86400, 1), 2)
        ELSE 0
    END AS subs_per_day,
    CASE
        WHEN ls.video_count > 0
        THEN ROUND(ls.view_count::NUMERIC / ls.video_count)
        ELSE 0
    END AS views_per_video
FROM channels c
JOIN latest_snap ls ON c.id = ls.channel_id
WHERE c.published_at IS NOT NULL
  AND ls.subscriber_count > 0;

-- ジャンル別の人気タグ TOP10
CREATE OR REPLACE VIEW topic_popular_tags AS
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
    JOIN (
        SELECT DISTINCT ON (video_id) video_id, view_count
        FROM video_snapshots
        ORDER BY video_id, snapshot_date DESC
    ) vs ON v.id = vs.video_id
    WHERE v.tags IS NOT NULL
      AND ARRAY_LENGTH(v.tags, 1) > 0
),
ranked AS (
    SELECT
        topic_id,
        topic_name,
        name_ja,
        tag,
        COUNT(*) AS usage_count,
        COALESCE(AVG(view_count), 0)::BIGINT AS avg_views,
        ROW_NUMBER() OVER (PARTITION BY topic_id ORDER BY COUNT(*) DESC) AS rank
    FROM tag_data
    WHERE LENGTH(tag) >= 2
    GROUP BY topic_id, topic_name, name_ja, tag
)
SELECT topic_id, topic_name, name_ja, tag, usage_count, avg_views, rank
FROM ranked
WHERE rank <= 10;

-- 国別チャンネル分布
CREATE OR REPLACE VIEW topic_country_distribution AS
WITH latest_snap AS (
    SELECT DISTINCT ON (channel_id)
        channel_id,
        subscriber_count
    FROM channel_snapshots
    ORDER BY channel_id, snapshot_date DESC
)
SELECT
    t.id AS topic_id,
    t.name AS topic_name,
    t.name_ja,
    t.parent_id,
    COALESCE(c.country, 'Unknown') AS country,
    COUNT(DISTINCT c.id) AS channel_count,
    COALESCE(SUM(ls.subscriber_count), 0)::BIGINT AS total_subscribers
FROM topics t
JOIN channels c ON t.id = ANY(c.topic_ids)
JOIN latest_snap ls ON c.id = ls.channel_id
GROUP BY t.id, t.name, t.name_ja, t.parent_id, COALESCE(c.country, 'Unknown');

-- ジャンル間チャンネル重複（相関マップ用）
CREATE OR REPLACE VIEW topic_overlap AS
SELECT
    t1.id AS topic_a,
    t1.name_ja AS name_a,
    t2.id AS topic_b,
    t2.name_ja AS name_b,
    COUNT(DISTINCT c.id) AS shared_channels
FROM channels c
JOIN topics t1 ON t1.id = ANY(c.topic_ids) AND t1.parent_id IS NOT NULL
JOIN topics t2 ON t2.id = ANY(c.topic_ids) AND t2.parent_id IS NOT NULL
WHERE t1.id < t2.id
GROUP BY t1.id, t1.name_ja, t2.id, t2.name_ja
HAVING COUNT(DISTINCT c.id) >= 2;
