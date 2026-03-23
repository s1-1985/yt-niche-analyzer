-- ============================================================
-- 追加分析ビュー: 動画尺分析 + チャンネル規模分布
-- ============================================================

-- ジャンル別の動画尺統計
CREATE OR REPLACE VIEW topic_duration_stats AS
WITH topic_videos AS (
    SELECT
        t.id AS topic_id,
        t.name AS topic_name,
        t.name_ja,
        t.parent_id,
        v.duration_seconds
    FROM topics t
    JOIN videos v ON t.id = ANY(v.topic_ids)
    WHERE v.duration_seconds > 0
)
SELECT
    topic_id,
    topic_name,
    name_ja,
    parent_id,
    COUNT(*) AS video_count,
    ROUND(AVG(duration_seconds))::INTEGER AS avg_duration,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY duration_seconds)::INTEGER AS median_duration,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY duration_seconds)::INTEGER AS p25_duration,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY duration_seconds)::INTEGER AS p75_duration,
    COUNT(*) FILTER (WHERE duration_seconds <= 60) AS short_count,
    COUNT(*) FILTER (WHERE duration_seconds > 60 AND duration_seconds <= 600) AS medium_count,
    COUNT(*) FILTER (WHERE duration_seconds > 600) AS long_count
FROM topic_videos
GROUP BY topic_id, topic_name, name_ja, parent_id;

-- ジャンル別のチャンネル規模分布
CREATE OR REPLACE VIEW topic_channel_size AS
WITH latest_subs AS (
    SELECT DISTINCT ON (channel_id)
        channel_id,
        subscriber_count
    FROM channel_snapshots
    ORDER BY channel_id, snapshot_date DESC
),
topic_channels AS (
    SELECT
        t.id AS topic_id,
        t.name AS topic_name,
        t.name_ja,
        t.parent_id,
        c.id AS channel_id,
        ls.subscriber_count
    FROM topics t
    JOIN channels c ON t.id = ANY(c.topic_ids)
    JOIN latest_subs ls ON c.id = ls.channel_id
)
SELECT
    topic_id,
    topic_name,
    name_ja,
    parent_id,
    COUNT(DISTINCT channel_id) AS total_channels,
    COUNT(DISTINCT channel_id) FILTER (WHERE subscriber_count < 1000) AS small_count,
    COUNT(DISTINCT channel_id) FILTER (WHERE subscriber_count >= 1000 AND subscriber_count < 10000) AS medium_count,
    COUNT(DISTINCT channel_id) FILTER (WHERE subscriber_count >= 10000 AND subscriber_count < 100000) AS large_count,
    COUNT(DISTINCT channel_id) FILTER (WHERE subscriber_count >= 100000) AS mega_count,
    ROUND(
        COUNT(DISTINCT channel_id) FILTER (WHERE subscriber_count < 1000)::NUMERIC
        / NULLIF(COUNT(DISTINCT channel_id), 0) * 100, 1
    ) AS small_pct,
    ROUND(
        COUNT(DISTINCT channel_id) FILTER (WHERE subscriber_count >= 1000 AND subscriber_count < 10000)::NUMERIC
        / NULLIF(COUNT(DISTINCT channel_id), 0) * 100, 1
    ) AS medium_pct,
    ROUND(
        COUNT(DISTINCT channel_id) FILTER (WHERE subscriber_count >= 10000 AND subscriber_count < 100000)::NUMERIC
        / NULLIF(COUNT(DISTINCT channel_id), 0) * 100, 1
    ) AS large_pct,
    ROUND(
        COUNT(DISTINCT channel_id) FILTER (WHERE subscriber_count >= 100000)::NUMERIC
        / NULLIF(COUNT(DISTINCT channel_id), 0) * 100, 1
    ) AS mega_pct
FROM topic_channels
GROUP BY topic_id, topic_name, name_ja, parent_id;

-- RLS (public read)
-- Note: Views inherit RLS from underlying tables, no additional policy needed.
