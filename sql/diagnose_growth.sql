-- ============================================================
-- 「総動画数が増えない」真因の切り分け診断
--   そのまま1回 Run（単一SELECT。少し時間がかかる場合あり）
--
-- 最重要列: new_videos_30d / new_videos_7d
--   = その期間に「初めて登場した動画」＝純増の数
--   - ほぼ 0 なら → コレクターが新規動画を追加できていない（収集側の問題）
--   - 大きい数なら → DBは増えている＝集計/表示側の問題
-- ============================================================
SELECT
  (SELECT COUNT(*) FROM videos)                         AS videos_total,
  (SELECT MAX(snapshot_date) FROM video_snapshots)      AS last_collection,
  (SELECT MAX(published_at) FROM videos)                AS newest_video_published,
  -- 直近30日に「何らかのスナップショットが付いた」動画数（＝処理対象になった動画）
  (SELECT COUNT(DISTINCT video_id) FROM video_snapshots
     WHERE snapshot_date > CURRENT_DATE - 30)           AS videos_touched_30d,
  -- 直近30日に「初めて登場した」動画数（＝純増）
  (SELECT COUNT(*) FROM (
     SELECT video_id FROM video_snapshots
     GROUP BY video_id HAVING MIN(snapshot_date) > CURRENT_DATE - 30
   ) a)                                                 AS new_videos_30d,
  -- 直近7日の純増
  (SELECT COUNT(*) FROM (
     SELECT video_id FROM video_snapshots
     GROUP BY video_id HAVING MIN(snapshot_date) > CURRENT_DATE - 7
   ) b)                                                 AS new_videos_7d;
