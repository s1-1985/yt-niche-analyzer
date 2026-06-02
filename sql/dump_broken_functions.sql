-- バグ5関数の「実際にDBで動いている定義」を取得する。
-- 結果の def 列を見せてほしい（Export → Copy が楽。または各セルをクリックして全文）。
SELECT p.proname AS fn, pg_get_functiondef(p.oid) AS def
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    'fn_topic_popular_tags',
    'fn_channel_growth_efficiency',
    'fn_keyword_virality',
    'fn_keyword_opportunity',
    'fn_topic_duration_stats'
  )
ORDER BY p.proname;
