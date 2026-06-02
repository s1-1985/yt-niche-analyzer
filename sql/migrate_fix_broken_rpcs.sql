-- ============================================================
-- フロントが叩く RPC のコードバグ修正（実測デバッグで特定）
--
-- 実測(anonキーで実RPC呼び出し)で判明した「毎回400で即死」する関数:
--   A) 曖昧カラム参照 (42702):
--      fn_topic_popular_tags        … "name_ja" ambiguous
--      fn_channel_growth_efficiency … "channel_id" ambiguous
--      fn_keyword_opportunity       … "avg_views" ambiguous
--      fn_keyword_virality          … "tag" ambiguous
--      → RETURNS TABLE のOUT名と同名カラムをスローパスで未修飾参照しているため。
--        本体は触らず plpgsql.variable_conflict=use_column を設定して
--        「曖昧時はカラムを優先」させる（ドリフトの巻き込みゼロ）。
--   B) 戻り値型不一致 (42804):
--      fn_topic_duration_stats … 6列目 median が double precision、宣言は numeric。
--        PERCENTILE_CONT が double precision を返すため。NUMERIC にキャストして修正。
--
-- ※ keyword系はフロントが p_topic_id 付き4引数で呼んでいて404にもなっていたが、
--   それはフロント側を3引数に修正済み(KeywordVirality/OpportunityChart.tsx)。
-- ============================================================

-- ------------------------------------------------------------
-- A. 曖昧カラム参照の4関数（本体非改変・設定のみ）
-- ------------------------------------------------------------
ALTER FUNCTION fn_topic_popular_tags(timestamptz, text, text)        SET plpgsql.variable_conflict = 'use_column';
ALTER FUNCTION fn_channel_growth_efficiency(timestamptz, text, text) SET plpgsql.variable_conflict = 'use_column';
ALTER FUNCTION fn_keyword_opportunity(timestamptz, text, text)       SET plpgsql.variable_conflict = 'use_column';
ALTER FUNCTION fn_keyword_virality(timestamptz, text, text)          SET plpgsql.variable_conflict = 'use_column';

-- ------------------------------------------------------------
-- B. fn_topic_duration_stats の型不一致を修正（PERCENTILE_CONT/AVG を ::NUMERIC）
--    シグネチャ・戻り値定義は不変。計算列を numeric に明示キャストするだけ。
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
