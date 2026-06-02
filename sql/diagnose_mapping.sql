-- ============================================================
-- 「新規動画がジャンルに紐づいていない」仮説の検証
-- ============================================================

-- Q1: 直近7日に純増した動画の topic_ids を10件サンプル表示
--     → ここに '/m/xxx'（サブトピックID）が入っているかが核心
SELECT v.id, v.published_at::date AS pub, v.topic_ids
FROM videos v
WHERE v.id IN (
  SELECT video_id FROM video_snapshots
  GROUP BY video_id HAVING MIN(snapshot_date) > CURRENT_DATE - 7
)
LIMIT 10;

-- Q2: 集計（こちらも実行して数字を教えてほしい）
--   map_subtopic_total : サブトピックに紐づく動画の総数（86,153の正体）
--   new30d_map_subtopic: 直近30日純増(49,076)のうちサブトピックに紐づく数
--   empty_topics       : topic_ids が空の動画数
SELECT
  (SELECT COUNT(*) FROM videos v
     WHERE EXISTS (SELECT 1 FROM topics t
                   WHERE t.parent_id IS NOT NULL AND t.id = ANY(v.topic_ids))
  ) AS map_subtopic_total,
  (SELECT COUNT(*) FROM videos v
     WHERE v.id IN (SELECT video_id FROM video_snapshots
                    GROUP BY video_id HAVING MIN(snapshot_date) > CURRENT_DATE - 30)
       AND EXISTS (SELECT 1 FROM topics t
                   WHERE t.parent_id IS NOT NULL AND t.id = ANY(v.topic_ids))
  ) AS new30d_map_subtopic,
  (SELECT COUNT(*) FROM videos v
     WHERE v.topic_ids IS NULL OR cardinality(v.topic_ids) = 0
  ) AS empty_topics;
