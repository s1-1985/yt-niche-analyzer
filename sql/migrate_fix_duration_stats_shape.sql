-- ============================================================
-- fn_topic_duration_stats を「実DBのMV/静的ビューと同じ12列の形」に作り直す
--
-- 実測で判明:
--   ・mv_topic_duration_stats / 静的ビュー topic_duration_stats は12列
--     (… video_count, avg_duration, median_duration, p25_duration, p75_duration,
--        short_count, medium_count, long_count)
--   ・フロント DurationChart はこの12列を使う
--   ・しかし fn_topic_duration_stats は8列の別形(avg_duration_sec/median_duration_sec/
--     short_pct/normal_pct)を返す古い設計で乖離 → フィルタ時に中身が出ない＋重くて時々500
--
-- 対応:
--   1) 戻り値型が変わるので DROP してから 12列の形で再作成
--   2) 分位点(median/p25/p75)は PERCENTILE_CONT(ARRAY[...]) で1回のソートに集約して高速化
--   3) 重い関数(本関数・popular_tags・keyword系)に statement_timeout=30s を付与
--      （statement_timeout は USERSET なので postgres でも設定可。曖昧設定の権限問題は無い）
-- ============================================================

DROP FUNCTION IF EXISTS fn_topic_duration_stats(TIMESTAMPTZ, TEXT, TEXT);

CREATE FUNCTION fn_topic_duration_stats(
    p_min_date   TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT        DEFAULT 'all',
    p_country    TEXT        DEFAULT NULL
)
RETURNS TABLE(
    topic_id TEXT, topic_name TEXT, name_ja TEXT, parent_id TEXT,
    video_count BIGINT, avg_duration INTEGER, median_duration INTEGER,
    p25_duration INTEGER, p75_duration INTEGER,
    short_count BIGINT, medium_count BIGINT, long_count BIGINT
) AS $$
BEGIN
    -- デフォルト(all/期間all/国null)は事前計算MVをそのまま返す（高速）
    IF p_min_date IS NULL AND p_country IS NULL AND p_video_type = 'all' THEN
        RETURN QUERY SELECT * FROM mv_topic_duration_stats;
        RETURN;
    END IF;

    -- フィルタ時はライブ集計（分位点は1回のソートにまとめる）
    RETURN QUERY
    SELECT s.topic_id, s.topic_name, s.name_ja, s.parent_id, s.video_count, s.avg_duration,
           s.pa[1]::INTEGER, s.pa[2]::INTEGER, s.pa[3]::INTEGER,
           s.short_count, s.medium_count, s.long_count
    FROM (
        SELECT t.id AS topic_id, t.name AS topic_name, t.name_ja AS name_ja, t.parent_id AS parent_id,
               COUNT(*)::BIGINT AS video_count,
               ROUND(AVG(vt.duration_seconds))::INTEGER AS avg_duration,
               PERCENTILE_CONT(ARRAY[0.5,0.25,0.75]) WITHIN GROUP (ORDER BY vt.duration_seconds) AS pa,
               COUNT(*) FILTER (WHERE vt.duration_seconds <= 60)::BIGINT AS short_count,
               COUNT(*) FILTER (WHERE vt.duration_seconds > 60 AND vt.duration_seconds <= 600)::BIGINT AS medium_count,
               COUNT(*) FILTER (WHERE vt.duration_seconds > 600)::BIGINT AS long_count
        FROM topics t
        JOIN mv_video_topics vt ON vt.topic_id = t.id
        LEFT JOIN channels c ON vt.channel_id = c.id
        WHERE vt.duration_seconds > 0
          AND (p_min_date IS NULL OR vt.published_at >= p_min_date)
          AND (p_video_type='all' OR (p_video_type='short' AND vt.duration_seconds<=60)
               OR (p_video_type='normal' AND vt.duration_seconds>60))
          AND (p_country IS NULL OR c.country = p_country)
        GROUP BY t.id, t.name, t.name_ja, t.parent_id
    ) s;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION fn_topic_duration_stats(TIMESTAMPTZ, TEXT, TEXT) TO anon, authenticated, service_role;

-- 重い関数に個別タイムアウト30秒（フィルタ時のライブ集計対策）
ALTER FUNCTION fn_topic_duration_stats(TIMESTAMPTZ, TEXT, TEXT)   SET statement_timeout = '30s';
ALTER FUNCTION fn_topic_popular_tags(TIMESTAMPTZ, TEXT, TEXT)     SET statement_timeout = '30s';
ALTER FUNCTION fn_keyword_opportunity(TIMESTAMPTZ, TEXT, TEXT)    SET statement_timeout = '30s';
ALTER FUNCTION fn_keyword_virality(TIMESTAMPTZ, TEXT, TEXT)       SET statement_timeout = '30s';

NOTIFY pgrst, 'reload config';
