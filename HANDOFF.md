# セッション引継ぎメモ

## ⚠️ Claude へのルール（毎回必読）
- **ツール実行・コード変更・SQL提示のたびに、このファイルを更新すること**
- 更新内容：実施した内容・結果・未解決事項・次にやること
- ファイル末尾の「次のセッションでやること」を常に最新に保つこと

---

## 現在のブランチ
`claude/fix-video-ranking-timeout-bK9OL`（PR #36 → main マージ済み）

---

## 今セッションの作業ログ（2026-05-08）

| # | 実施内容 | 結果 |
|---|---|---|
| 1 | HANDOFF.md 読み込み・状況確認 | ✅ |
| 2 | 全エラーの根本原因調査（7種のタイムアウト） | ✅ 原因特定 |
| 3 | `sql/migrate_fix_video_ranking_timeout.sql` 作成・PR #36 作成・マージ | ✅ |
| 4 | CLAUDE.md 新規作成（HANDOFF更新ルール明文化） | ✅ |
| 5 | SQL ①〜④ をユーザーに提示（インデックス+MV+タグMV） | ✅ 提示済み・**未実行** |

---

## ダッシュボードの現状（2026-05-08 時点）

### 発生中の500エラー（全て statement timeout）
| エラー | 原因 | 修正状況 |
|---|---|---|
| `video_ranking` timeout（BUZZ動画ランキング） | `videos.published_at` インデックスなし | ❌ 未適用 |
| `ai_penetration` timeout | `videos.topic_ids` GINインデックスなし | ❌ 未適用 |
| `topic_duration_stats` timeout | 同上 | ❌ 未適用 |
| `topic_overlap` timeout | `channels.topic_ids` GINインデックスなし | ❌ 未適用 |
| `channels` saturation timeout | `channels.published_at` インデックスなし | ❌ 未適用 |
| `fn_keyword_virality` timeout | インデックスなし + CROSS JOIN UNNEST 86k行 | ❌ 未適用 |
| `fn_keyword_opportunity` timeout | 同上 | ❌ 未適用 |

### 根本原因
データが **86k動画 / 46kチャンネル** に増加。以下のインデックスがないため全行スキャンで 8秒 timeout に達する：
- `idx_videos_published_at`
- `idx_channels_published_at`
- `idx_videos_topic_ids`（GIN）
- `idx_channels_topic_ids`（GIN）

---

## Supabase 適用状況

### 実行済み ✅
- `mv_latest_video_snapshot` 作成
- `mv_latest_channel_snapshot` 作成
- 全ビュー・RPC関数のMV参照化（migrate_performance_indexes.sql）
- `fn_keyword_virality` 再作成
- `fn_keyword_opportunity` 再作成
- `channel_growth_efficiency` → 前セッションで MV 化を試みたが未確認

### 未実行 ❌（← 次のセッションで最初にやること）
以下のSQLを Supabase SQL Editor に **全部まとめて** コピペして Run する：

```sql
-- ============================================================
-- ① インデックス4本（最重要・これだけで大半のタイムアウト解消）
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_videos_published_at
    ON videos(published_at DESC);

CREATE INDEX IF NOT EXISTS idx_channels_published_at
    ON channels(published_at DESC);

CREATE INDEX IF NOT EXISTS idx_videos_topic_ids
    ON videos USING GIN(topic_ids);

CREATE INDEX IF NOT EXISTS idx_channels_topic_ids
    ON channels USING GIN(topic_ids);

-- ============================================================
-- ② channel_growth_efficiency をMV化（channel_growth_efficiency 500 修正）
-- ============================================================
DROP VIEW IF EXISTS channel_growth_efficiency CASCADE;

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_channel_growth_efficiency AS
SELECT
    c.id AS channel_id, c.title, c.published_at, c.country, c.topic_ids,
    cs.subscriber_count, cs.view_count, cs.video_count,
    GREATEST(EXTRACT(EPOCH FROM (NOW() - c.published_at)) / 86400, 1)::INTEGER AS age_days,
    CASE WHEN EXTRACT(EPOCH FROM (NOW() - c.published_at)) > 0
        THEN ROUND(cs.subscriber_count::NUMERIC /
             GREATEST(EXTRACT(EPOCH FROM (NOW() - c.published_at)) / 86400, 1), 2)
        ELSE 0
    END AS subs_per_day,
    CASE WHEN cs.video_count > 0
        THEN ROUND(cs.view_count::NUMERIC / cs.video_count)
        ELSE 0
    END AS views_per_video
FROM channels c
JOIN mv_latest_channel_snapshot cs ON c.id = cs.channel_id
WHERE c.published_at IS NOT NULL AND cs.subscriber_count > 0;

CREATE INDEX IF NOT EXISTS idx_mv_channel_growth_subs_per_day
    ON mv_channel_growth_efficiency(subs_per_day DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_channel_growth_channel_id
    ON mv_channel_growth_efficiency(channel_id);

CREATE VIEW channel_growth_efficiency AS
SELECT channel_id, title, published_at, country, topic_ids,
    subscriber_count, view_count, video_count,
    age_days, subs_per_day, views_per_video
FROM mv_channel_growth_efficiency;

-- ============================================================
-- ③ refresh関数を更新
-- ============================================================
CREATE OR REPLACE FUNCTION refresh_latest_snapshots()
RETURNS void AS $fn$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_latest_video_snapshot;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_latest_channel_snapshot;
    REFRESH MATERIALIZED VIEW mv_channel_growth_efficiency;
END;
$fn$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- ④ タグ事前展開MV（fn_keyword_* のCROSS JOIN UNNEST を高速化）
-- ============================================================
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_video_tags AS
SELECT
    v.id AS video_id,
    v.channel_id,
    v.published_at,
    v.duration_seconds,
    v.topic_ids,
    LOWER(TRIM(tag)) AS tag
FROM videos v
CROSS JOIN UNNEST(v.tags) AS tag
WHERE v.tags IS NOT NULL AND ARRAY_LENGTH(v.tags, 1) > 0
  AND LENGTH(LOWER(TRIM(tag))) >= 2;

CREATE INDEX IF NOT EXISTS idx_mv_video_tags_tag
    ON mv_video_tags(tag);
CREATE INDEX IF NOT EXISTS idx_mv_video_tags_channel
    ON mv_video_tags(channel_id);
CREATE INDEX IF NOT EXISTS idx_mv_video_tags_published_at
    ON mv_video_tags(published_at DESC);
```

Run 後にダッシュボードをリロードして確認。まだ fn_keyword_* が timeout する場合は以下の **⑤** も実行：

```sql
-- ============================================================
-- ⑤ fn_keyword_opportunity を mv_video_tags 参照に書き換え
-- ============================================================
DROP FUNCTION IF EXISTS fn_keyword_opportunity(TIMESTAMPTZ, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION fn_keyword_opportunity(
    p_min_date TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT DEFAULT 'all',
    p_country TEXT DEFAULT NULL,
    p_topic_id TEXT DEFAULT NULL
)
RETURNS TABLE(
    tag TEXT, usage_count BIGINT, channel_count BIGINT,
    avg_views BIGINT, total_views BIGINT,
    avg_like_rate NUMERIC, avg_buzz_score NUMERIC,
    keyword_score BIGINT, rank BIGINT
) AS $$
BEGIN
    RETURN QUERY
    WITH tag_stats AS (
        SELECT
            vt.tag AS vtag,
            COUNT(*)::BIGINT AS cnt,
            COUNT(DISTINCT vt.channel_id)::BIGINT AS ch_cnt,
            COALESCE(AVG(vs.view_count), 0)::BIGINT AS avgv,
            COALESCE(SUM(vs.view_count), 0)::BIGINT AS totv,
            COALESCE(AVG(
                CASE WHEN vs.view_count > 0
                THEN (vs.like_count::NUMERIC / vs.view_count * 100) ELSE 0 END
            ), 0)::NUMERIC(5,2) AS avg_lr,
            COALESCE(AVG(
                CASE WHEN cs.subscriber_count > 0
                THEN vs.view_count::NUMERIC / cs.subscriber_count ELSE 0 END
            ), 0)::NUMERIC(10,1) AS avg_bz
        FROM mv_video_tags vt
        JOIN mv_latest_video_snapshot vs ON vt.video_id = vs.video_id
        LEFT JOIN channels c ON vt.channel_id = c.id
        LEFT JOIN mv_latest_channel_snapshot cs ON vt.channel_id = cs.channel_id
        WHERE (p_min_date IS NULL OR vt.published_at >= p_min_date)
          AND (p_video_type = 'all'
            OR (p_video_type = 'short' AND vt.duration_seconds <= 60)
            OR (p_video_type = 'normal' AND vt.duration_seconds > 60))
          AND (p_country IS NULL OR c.country = p_country)
          AND (p_topic_id IS NULL OR p_topic_id = ANY(vt.topic_ids))
        GROUP BY vt.tag
        HAVING COUNT(*) >= 2
    ),
    scored AS (
        SELECT ts.*,
            ROUND((ts.avgv::NUMERIC / GREATEST(ts.ch_cnt, 1))
                * (1 + ts.avg_lr / 10)
                * LEAST(ts.avg_bz / 10 + 1, 5))::BIGINT AS kscore
        FROM tag_stats ts
    )
    SELECT s.vtag, s.cnt, s.ch_cnt, s.avgv, s.totv, s.avg_lr, s.avg_bz, s.kscore,
        ROW_NUMBER() OVER (ORDER BY s.kscore DESC)::BIGINT AS rk
    FROM scored s ORDER BY s.kscore DESC LIMIT 200;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ============================================================
-- ⑤ fn_keyword_virality を mv_video_tags 参照に書き換え
-- ============================================================
DROP FUNCTION IF EXISTS fn_keyword_virality(TIMESTAMPTZ, TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION fn_keyword_virality(
    p_min_date TIMESTAMPTZ DEFAULT NULL,
    p_video_type TEXT DEFAULT 'all',
    p_country TEXT DEFAULT NULL,
    p_topic_id TEXT DEFAULT NULL
)
RETURNS TABLE(
    tag TEXT, video_count BIGINT, channel_count BIGINT,
    avg_views BIGINT, avg_buzz_score NUMERIC,
    virality_score NUMERIC, max_views BIGINT,
    viral_rate_pct NUMERIC, rank BIGINT
) AS $$
BEGIN
    RETURN QUERY
    WITH tag_buzz AS (
        SELECT
            vt.tag AS vtag,
            COUNT(*)::BIGINT AS vcnt,
            COUNT(DISTINCT vt.channel_id)::BIGINT AS ch_cnt,
            COALESCE(AVG(vs.view_count), 0)::BIGINT AS avgv,
            COALESCE(AVG(
                CASE WHEN cs.subscriber_count > 0
                THEN vs.view_count::NUMERIC / cs.subscriber_count ELSE 0 END
            ), 0)::NUMERIC(10,1) AS avg_bz,
            COALESCE(AVG(
                CASE WHEN cs.subscriber_count > 0 AND vs.view_count > 0
                THEN (vs.view_count::NUMERIC / cs.subscriber_count)
                     * (1 + vs.like_count::NUMERIC / vs.view_count * 5)
                     * (1 + vs.comment_count::NUMERIC / vs.view_count * 10)
                ELSE 0 END
            ), 0)::NUMERIC(10,1) AS vir_score,
            MAX(vs.view_count)::BIGINT AS maxv,
            ROUND(COUNT(*) FILTER (WHERE cs.subscriber_count > 0
                AND vs.view_count::NUMERIC / cs.subscriber_count > 2)
                * 100.0 / GREATEST(COUNT(*), 1), 1)::NUMERIC(5,1) AS vir_pct
        FROM mv_video_tags vt
        JOIN mv_latest_video_snapshot vs ON vt.video_id = vs.video_id
        LEFT JOIN channels c ON vt.channel_id = c.id
        LEFT JOIN mv_latest_channel_snapshot cs ON vt.channel_id = cs.channel_id
        WHERE (p_min_date IS NULL OR vt.published_at >= p_min_date)
          AND (p_video_type = 'all'
            OR (p_video_type = 'short' AND vt.duration_seconds <= 60)
            OR (p_video_type = 'normal' AND vt.duration_seconds > 60))
          AND (p_country IS NULL OR c.country = p_country)
          AND (p_topic_id IS NULL OR p_topic_id = ANY(vt.topic_ids))
        GROUP BY vt.tag
        HAVING COUNT(*) >= 3
    )
    SELECT tb.vtag, tb.vcnt, tb.ch_cnt, tb.avgv, tb.avg_bz,
        tb.vir_score, tb.maxv, tb.vir_pct,
        ROW_NUMBER() OVER (ORDER BY tb.vir_score DESC)::BIGINT AS rk
    FROM tag_buzz tb ORDER BY tb.vir_score DESC LIMIT 100;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;
```

---

## アーキテクチャメモ

### マテリアライズドビュー構成（目標状態）
```
video_snapshots       → mv_latest_video_snapshot（各動画の最新スナップショット）
channel_snapshots     → mv_latest_channel_snapshot（各チャンネルの最新スナップショット）
channels + mv_latest  → mv_channel_growth_efficiency（チャンネル成長効率）
videos × tags         → mv_video_tags（タグ事前展開、keyword RPC 高速化用）

全ビュー・RPC はこれら4つのMVを参照
データ収集後に refresh_latest_snapshots() でMVを一括更新
```

### 各コンポーネントとクエリ対応
| コンポーネント | クエリ | 修正方法 |
|---|---|---|
| BuzzPickup | `video_ranking` + `published_at` filter | `idx_videos_published_at` |
| SaturationChart | `channels` + `published_at` filter | `idx_channels_published_at` |
| TopicDurationStats | `topic_duration_stats` view (`ANY(v.topic_ids)`) | `idx_videos_topic_ids` GIN |
| AiPenetration | `ai_penetration` view (`ANY(v.topic_ids)`) | `idx_videos_topic_ids` GIN |
| TopicOverlap | `topic_overlap` view (`ANY(c.topic_ids)`) | `idx_channels_topic_ids` GIN |
| KeywordOpportunity | `fn_keyword_opportunity` (CROSS JOIN UNNEST) | `mv_video_tags` |
| KeywordVirality | `fn_keyword_virality` (CROSS JOIN UNNEST) | `mv_video_tags` |

### refresh関数に追加すべきMV（全部）
```sql
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_latest_video_snapshot;
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_latest_channel_snapshot;
REFRESH MATERIALIZED VIEW mv_channel_growth_efficiency;
REFRESH MATERIALIZED VIEW mv_video_tags;  -- 追加予定
```

### フロントエンド
- `useFilteredQuery` フック: `period='all' && videoType='all' && country=null` → 静的ビュー直接参照、それ以外 → RPC関数
- BuzzPickup は常に `video_ranking` ビュー直参照（RPC なし）
- ビルド通過確認済み（npx vite build 成功）

### コレクター
- Python 3.12, `collector/main.py`
- GitHub Actions で毎日 08:00 UTC (17:00 JST) に自動実行
- `cleanup_old_snapshots()` → `refresh_materialized_views()` の順で実行

---

## 主要ファイル一覧
| ファイル | 変更内容 | 状態 |
|---------|---------|------|
| `sql/migrate_performance_indexes.sql` | MVビュー・RPC最適化 | ✅ 実行済み |
| `sql/migrate_fix_video_ranking_timeout.sql` | インデックス4本・MV化 | ❌ **未実行** |
| `collector/main.py` | MV リフレッシュ呼び出し追加 | ✅ 実行済み |
| `collector/supabase_client.py` | `refresh_materialized_views()` 追加 | ✅ 実行済み |

---

## 次のセッションでやること（優先順）
1. **上記①〜④のSQL を Supabase SQL Editor で実行**（インデックス + MV作成）
2. ダッシュボードリロードして全チャート確認
3. fn_keyword_* がまだ timeout なら **⑤のSQL も実行**
4. `refresh_latest_snapshots()` に `mv_video_tags` の REFRESH を追加（`collector/supabase_client.py` 更新）
5. 全チャートOKになったら HANDOFF.md を更新してセッション完了
