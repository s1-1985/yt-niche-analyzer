-- マイグレーション: videos テーブルに thumbnail_url カラム追加
ALTER TABLE videos ADD COLUMN IF NOT EXISTS thumbnail_url TEXT;

-- video_ranking ビューを再作成（thumbnail_url を含む）
CREATE OR REPLACE VIEW video_ranking AS
SELECT DISTINCT ON (v.id)
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
    CASE
        WHEN cs.subscriber_count > 0
        THEN ROUND(vs.view_count::NUMERIC / cs.subscriber_count, 1)
        ELSE 0
    END AS buzz_score
FROM videos v
JOIN video_snapshots vs ON v.id = vs.video_id
LEFT JOIN channels c ON v.channel_id = c.id
LEFT JOIN (
    SELECT DISTINCT ON (channel_id) channel_id, subscriber_count
    FROM channel_snapshots
    ORDER BY channel_id, snapshot_date DESC
) cs ON v.channel_id = cs.channel_id
ORDER BY v.id, vs.snapshot_date DESC;
