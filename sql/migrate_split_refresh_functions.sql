-- ============================================================
-- MV更新を3グループに分割（各グループ8秒以内に収まるよう設計）
--
-- Group 1: refresh_snapshot_base()
--   スナップショット系（軽い・CONCURRENTLY対応）
--   mv_latest_video_snapshot, mv_latest_channel_snapshot
--
-- Group 2: refresh_derived_mvs()
--   展開系（中程度・依存先はGroup1のみ）
--   mv_channel_growth_efficiency, mv_video_tags, mv_video_topics,
--   mv_video_ranking
--
-- Group 3: refresh_analytics_mvs()
--   集計系（重い・依存先はGroup1,2のMV）
--   mv_ai_penetration, mv_topic_duration_stats,
--   mv_keyword_opportunity, mv_keyword_virality, mv_topic_overlap
-- ============================================================

CREATE OR REPLACE FUNCTION refresh_snapshot_base()
RETURNS void AS $fn$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_latest_video_snapshot;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_latest_channel_snapshot;
END;
$fn$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION refresh_derived_mvs()
RETURNS void AS $fn$
BEGIN
    REFRESH MATERIALIZED VIEW mv_channel_growth_efficiency;
    REFRESH MATERIALIZED VIEW mv_video_tags;
    REFRESH MATERIALIZED VIEW mv_video_topics;
    REFRESH MATERIALIZED VIEW mv_video_ranking;
END;
$fn$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION refresh_analytics_mvs()
RETURNS void AS $fn$
BEGIN
    REFRESH MATERIALIZED VIEW mv_ai_penetration;
    REFRESH MATERIALIZED VIEW mv_topic_duration_stats;
    REFRESH MATERIALIZED VIEW mv_keyword_opportunity;
    REFRESH MATERIALIZED VIEW mv_keyword_virality;
    REFRESH MATERIALIZED VIEW mv_topic_overlap;
END;
$fn$ LANGUAGE plpgsql SECURITY DEFINER;

-- 後方互換: 既存の関数は3グループを順番に呼ぶように変更
-- ※ RPC経由で呼ぶと1関数=1トランザクション扱いのためタイムアウトするが、
--    Pythonから3関数を個別に呼ぶことで各8秒制限内に収まる
CREATE OR REPLACE FUNCTION refresh_latest_snapshots()
RETURNS void AS $fn$
BEGIN
    PERFORM refresh_snapshot_base();
    PERFORM refresh_derived_mvs();
    PERFORM refresh_analytics_mvs();
END;
$fn$ LANGUAGE plpgsql SECURITY DEFINER;
