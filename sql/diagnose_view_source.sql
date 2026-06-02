-- topic_summary が実際に「何を」読んでいるか（FROM の対象）を特定する
--   source_relation: FROM の後ろのテーブル/ビュー名（これが核心）
--   full_def       : 226文字の定義全文
SELECT
  substring(pg_get_viewdef('topic_summary'::regclass, true) from 'FROM\s+([a-zA-Z0-9_."]+)') AS source_relation,
  pg_get_viewdef('topic_summary'::regclass, true) AS full_def;
