-- ============================================================
-- 日本語タグ優先: タグランキングで日本語タグを優先表示
-- 日本語文字（ひらがな・カタカナ・漢字）を含むタグに2倍の重み付け
-- ============================================================

-- ビュー: ジャンル別人気タグ TOP10（日本語優先）
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
        ROW_NUMBER() OVER (
            PARTITION BY topic_id
            ORDER BY
                COUNT(*) * CASE WHEN tag ~ '[ぁ-んァ-ヶー一-龥々〆〤]' THEN 2 ELSE 1 END DESC
        ) AS rank
    FROM tag_data
    WHERE LENGTH(tag) >= 2
    GROUP BY topic_id, topic_name, name_ja, tag
)
SELECT topic_id, topic_name, name_ja, tag, usage_count, avg_views, rank
FROM ranked
WHERE rank <= 10;

-- RPC関数: 日本語優先タグ TOP10
DROP FUNCTION IF EXISTS fn_topic_popular_tags(TIMESTAMPTZ, TEXT, TEXT);
CREATE OR REPLACE FUNCTION fn_topic_popular_tags(
    p_min_date TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT DEFAULT 'all',
    p_country TEXT DEFAULT NULL
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
        JOIN channels c ON v.channel_id = c.id
        WHERE v.tags IS NOT NULL AND ARRAY_LENGTH(v.tags, 1) > 0
          AND (p_min_date IS NULL OR v.published_at >= p_min_date)
          AND (p_video_type = 'all'
            OR (p_video_type = 'short' AND v.duration_seconds <= 60)
            OR (p_video_type = 'normal' AND v.duration_seconds > 60))
          AND (p_country IS NULL OR c.country = p_country)
    ),
    ranked AS (
        SELECT td.tid, td.tname, td.tname_ja, td.vtag,
            COUNT(*)::BIGINT AS cnt, COALESCE(AVG(td.vview), 0)::BIGINT AS avgv,
            ROW_NUMBER() OVER (
                PARTITION BY td.tid
                ORDER BY
                    COUNT(*) * CASE WHEN td.vtag ~ '[ぁ-んァ-ヶー一-龥々〆〤]' THEN 2 ELSE 1 END DESC
            ) AS rk
        FROM tag_data td WHERE LENGTH(td.vtag) >= 2
        GROUP BY td.tid, td.tname, td.tname_ja, td.vtag
    )
    SELECT r.tid, r.tname, r.tname_ja, r.vtag, r.cnt, r.avgv, r.rk
    FROM ranked r WHERE r.rk <= 10;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;
