-- ============================================================
-- Tier1: doctor（自動健康診断）
--
-- 目的: 「データが静かに古くなる / DBとコードがズレる」を自動検知する。
--   今回の「総動画数が1ヶ月凍結」は、collectorは成功扱いなのにMVが更新されて
--   いなかったのが原因。誰も気づけなかった。これを毎日 pg_cron で点検し、
--   結果を system_health テーブルに記録する（フロントから読めるよう anon 公開）。
--
-- 検知する異常:
--   1. 22個のMVのいずれかが存在しない（drift）
--   2. 主要な関数が存在しない（drift）
--   3. 収集が止まっている（video_snapshots の最新日が3日より古い）
--   4. MVが凍結している（videos 件数と mv_latest_video_snapshot 件数が5%以上乖離）
--
-- 列名に依存しない指標のみ使用（MV定義がリポジトリに無い箇所があるため）。
-- 前提: pg_cron 有効（migrate_pgcron_refresh.sql 適用済み）。
-- ============================================================

-- 1) 健康診断の結果を貯めるテーブル
CREATE TABLE IF NOT EXISTS system_health (
  id          bigserial PRIMARY KEY,
  checked_at  timestamptz NOT NULL DEFAULT now(),
  ok          boolean     NOT NULL,
  issues      text[]      NOT NULL DEFAULT '{}',
  videos_count   bigint,
  mv_count       bigint,
  latest_snapshot date
);

-- フロント(anon)から最新の健康状態を読めるように
ALTER TABLE system_health ENABLE ROW LEVEL SECURITY;
DO $pol$ BEGIN
  CREATE POLICY "system_health public read" ON system_health FOR SELECT USING (true);
EXCEPTION WHEN duplicate_object THEN NULL;
END $pol$;
GRANT SELECT ON system_health TO anon, authenticated;

-- 2) 健康診断本体
CREATE OR REPLACE FUNCTION run_health_check()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET statement_timeout = '60s'
AS $fn$
DECLARE
  issues       text[] := '{}';
  v            text;
  v_videos     bigint;
  v_mv         bigint;
  v_latest     date;
  expected_mvs text[] := ARRAY[
    'mv_latest_video_snapshot','mv_latest_channel_snapshot',
    'mv_channel_growth_efficiency','mv_video_tags','mv_video_topics','mv_video_ranking',
    'mv_topic_summary','mv_ai_penetration','mv_topic_duration_stats',
    'mv_keyword_opportunity','mv_keyword_virality','mv_topic_overlap',
    'mv_topic_video_short','mv_topic_video_normal','mv_active_ch_short','mv_active_ch_normal',
    'mv_keyword_opp_short','mv_keyword_opp_normal','mv_keyword_vir_short','mv_keyword_vir_normal',
    'mv_topic_overlap_short','mv_topic_overlap_normal'
  ];
  expected_fns text[] := ARRAY[
    'refresh_all_mvs','cleanup_old_snapshots','refresh_topic_summary',
    'refresh_snapshot_base','refresh_derived_mvs','refresh_analytics_mvs',
    'refresh_type_base_mvs','refresh_type_overlap_mvs','refresh_type_keyword_mvs'
  ];
BEGIN
  -- (1) MV存在チェック
  FOREACH v IN ARRAY expected_mvs LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_matviews WHERE matviewname = v) THEN
      issues := issues || ('MV欠落: ' || v);
    END IF;
  END LOOP;

  -- (2) 関数存在チェック
  FOREACH v IN ARRAY expected_fns LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = v) THEN
      issues := issues || ('関数欠落: ' || v);
    END IF;
  END LOOP;

  -- (3) 収集の鮮度（最新スナップショットが3日以内か）
  BEGIN
    SELECT max(snapshot_date) INTO v_latest FROM video_snapshots;
    IF v_latest IS NULL OR v_latest < current_date - 3 THEN
      issues := issues || ('収集が停止の可能性: 最新snapshot='
                           || COALESCE(v_latest::text, 'なし'));
    END IF;
  EXCEPTION WHEN OTHERS THEN
    issues := issues || ('収集鮮度チェック失敗: ' || SQLERRM);
  END;

  -- (4) MVの鮮度（videos 件数と MV 件数の乖離＝凍結検知）
  BEGIN
    SELECT count(*) INTO v_videos FROM videos;
    SELECT count(*) INTO v_mv     FROM mv_latest_video_snapshot;
    IF v_videos > 0 AND v_mv < v_videos * 0.95 THEN
      issues := issues || ('MV凍結の可能性: videos=' || v_videos
                           || ' / mv_latest_video_snapshot=' || v_mv);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    issues := issues || ('MV鮮度チェック失敗: ' || SQLERRM);
  END;

  -- 記録
  INSERT INTO system_health (ok, issues, videos_count, mv_count, latest_snapshot)
  VALUES (array_length(issues, 1) IS NULL, issues, v_videos, v_mv, v_latest);
END;
$fn$;
GRANT EXECUTE ON FUNCTION run_health_check() TO service_role;

-- 3) 毎日 14:30 UTC に点検（refresh_all_mvs の 14:00 の後）
DO $do$ BEGIN
  PERFORM cron.unschedule('run-health-check');
EXCEPTION WHEN OTHERS THEN NULL;
END $do$;
SELECT cron.schedule('run-health-check', '30 14 * * *', $cmd$SELECT run_health_check()$cmd$);

-- ------------------------------------------------------------
-- 適用後すぐに動作確認（軽いので直接実行OK）:
--   SELECT run_health_check();
--   SELECT checked_at, ok, issues, videos_count, mv_count, latest_snapshot
--     FROM system_health ORDER BY checked_at DESC LIMIT 1;
--   → ok=true, issues={} なら健全。
-- ------------------------------------------------------------
