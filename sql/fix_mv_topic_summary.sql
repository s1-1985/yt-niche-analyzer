-- ============================================================
-- 真因: topic_summary ビューは mv_topic_summary（マテリアライズドビュー）を
--       SELECT しているだけ。この mv_topic_summary はどのリフレッシュ関数にも
--       含まれておらず（リポジトリにも無い）、作成時点で凍結していた。
--       → ダッシュボード「総動画数」が約1ヶ月 86,153 のまま固定されていた。
--
-- まず即時リフレッシュして復旧する（恒久対策は定義確認後に別途）。
-- ============================================================
SET statement_timeout = '120s';

REFRESH MATERIALIZED VIEW mv_topic_summary;

-- 復旧確認: 86,153 から大きく増えれば成功（12万件前後の見込み）
SELECT SUM(total_videos) AS dashboard_total
FROM topic_summary
WHERE parent_id IS NOT NULL;
