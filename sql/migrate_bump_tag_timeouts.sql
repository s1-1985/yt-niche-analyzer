-- ============================================================
-- 国フィルタ時のタグ/キーワード集計タイムアウト対策
--
-- 徹底検証(実RPC総当たり)で判明:
--   fn_topic_popular_tags + 国フィルタ(JP) … 32.9秒で 500 (57014 timeout)
--   fn_keyword_opportunity + 国フィルタ(JP) … 29.4秒（30s制限ギリギリ）
--   ※ 国フィルタは channels JOIN が入りタグ展開が重く、事前計算MVも使えないため。
--
-- 対策: タグ展開が重い3関数の statement_timeout を 60s に引き上げる。
--   （statement_timeout は USERSET なので postgres でも設定可・権限問題なし）
--
-- 注意: これは「動くようにする」対症療法。国フィルタ時は依然 ~30秒かかる。
--   恒久的に速くするには国別タグ統計の事前計算(MV)が必要だが、国数が多く
--   コストが高いため将来課題とする。デフォルト/期間/short/normal は全て高速(<8s)。
-- ============================================================
ALTER FUNCTION fn_topic_popular_tags(TIMESTAMPTZ, TEXT, TEXT)  SET statement_timeout = '60s';
ALTER FUNCTION fn_keyword_opportunity(TIMESTAMPTZ, TEXT, TEXT) SET statement_timeout = '60s';
ALTER FUNCTION fn_keyword_virality(TIMESTAMPTZ, TEXT, TEXT)    SET statement_timeout = '60s';

NOTIFY pgrst, 'reload config';
