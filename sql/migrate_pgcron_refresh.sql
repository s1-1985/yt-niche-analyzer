-- ============================================================
-- Phase 1: MVリフレッシュを pg_cron（DB内部スケジュール）に移行
--
-- 背景（実測で判明）:
--   コレクターのRPCリフレッシュは「クライアント120秒」制限があり、重いMV群
--   （refresh_analytics_mvs / refresh_type_keyword_mvs）が毎日タイムアウトで
--   更新できていなかった。さらに refresh_topic_summary が未作成で404（→総動画数が
--   再び凍結する状態）だった。
--
--   pg_cron は DB内部で実行するため、クライアント/ゲートウェイのタイムアウトと無縁。
--   重いMVも statement_timeout の範囲で確実に毎日更新できる。
--
-- 前提: pg_cron 拡張。下の CREATE EXTENSION で有効化を試みる。
--   もし権限エラー(42501)が出たら、先に Supabase Dashboard →
--   Database → Extensions → "pg_cron" を有効化してから、このSQLを再実行。
-- ============================================================

-- 1) pg_cron 有効化
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- 2) topic_summary 専用リフレッシュ関数（コレクターのGroup1bが404だったのを解消）
--    → これで翌日以降の収集後に総動画数が自動更新され、再凍結しない
CREATE OR REPLACE FUNCTION refresh_topic_summary()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET statement_timeout = '120s'
AS $fn$
BEGIN
  REFRESH MATERIALIZED VIEW mv_topic_summary;
END;
$fn$;
GRANT EXECUTE ON FUNCTION refresh_topic_summary() TO anon, authenticated, service_role;

-- 3) 全MVを依存順にまとめて更新する関数（pg_cron が呼ぶ）
--    サーバー内部実行なので上限を 30分に（クライアント120秒制限とは無関係）
--    1つのMVが失敗しても残りを続行（堅牢化）
CREATE OR REPLACE FUNCTION refresh_all_mvs()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET statement_timeout = '1800s'
AS $fn$
DECLARE
  v   text;
  mvs text[] := ARRAY[
    -- 依存順（上から）
    'mv_latest_video_snapshot','mv_latest_channel_snapshot',
    'mv_channel_growth_efficiency','mv_video_tags','mv_video_topics','mv_video_ranking',
    'mv_topic_summary',
    'mv_ai_penetration','mv_topic_duration_stats',
    'mv_keyword_opportunity','mv_keyword_virality','mv_topic_overlap',
    'mv_topic_video_short','mv_topic_video_normal','mv_active_ch_short','mv_active_ch_normal',
    'mv_topic_overlap_short','mv_topic_overlap_normal',
    'mv_keyword_opp_short','mv_keyword_opp_normal','mv_keyword_vir_short','mv_keyword_vir_normal'
  ];
BEGIN
  FOREACH v IN ARRAY mvs LOOP
    BEGIN
      EXECUTE format('REFRESH MATERIALIZED VIEW %I', v);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'refresh skipped for %: %', v, SQLERRM;
    END;
  END LOOP;
END;
$fn$;

-- 4) 毎日 14:00 UTC に実行をスケジュール（収集後。GitHub Actions の遅延にも余裕）
--    既存ジョブがあれば作り直し（再実行しても安全）
DO $do$ BEGIN
  PERFORM cron.unschedule('refresh-all-mvs');
EXCEPTION WHEN OTHERS THEN NULL;
END $do$;
SELECT cron.schedule('refresh-all-mvs', '0 14 * * *', $cmd$SELECT refresh_all_mvs()$cmd$);

-- ------------------------------------------------------------
-- 確認用（任意・別タブで実行）:
--   登録確認 : SELECT jobname, schedule, active FROM cron.job;
--   実行履歴 : SELECT jobname, status, start_time, end_time
--             FROM cron.job_run_details ORDER BY start_time DESC LIMIT 5;
-- ------------------------------------------------------------
