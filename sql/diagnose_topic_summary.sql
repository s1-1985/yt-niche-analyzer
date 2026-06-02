-- ============================================================
-- 矛盾の解明: 紐づく動画 121,925 件あるのに topic_summary 合計が 86,153 で止まる
-- ============================================================

-- Q_A: topic_summary ビューの実際の定義を確認
SELECT pg_get_viewdef('topic_summary', true);

-- Q_B: 整合性チェック
--   dashboard_now     : 今の「総動画数」(topic_summary サブトピック合計)
--   mv_now            : mv_latest_video_snapshot の現在の件数
--   mapped_not_in_mv  : サブトピックに紐づくのに MV に存在しない動画数
--                       （大きい＝MVがまだ不完全 → topic_summary が取りこぼす）
SELECT
  (SELECT SUM(total_videos) FROM topic_summary WHERE parent_id IS NOT NULL) AS dashboard_now,
  (SELECT COUNT(*) FROM mv_latest_video_snapshot)                           AS mv_now,
  (SELECT COUNT(*) FROM videos v
     WHERE EXISTS (SELECT 1 FROM topics t
                   WHERE t.parent_id IS NOT NULL AND t.id = ANY(v.topic_ids))
       AND NOT EXISTS (SELECT 1 FROM mv_latest_video_snapshot m
                       WHERE m.video_id = v.id)
  ) AS mapped_not_in_mv;
