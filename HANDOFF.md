# セッション引継ぎメモ

## ⚠️ Claude へのルール（毎回必読）
- **ツール実行・コード変更・SQL提示のたびに、このファイルを更新すること**
- 更新内容：実施した内容・結果・未解決事項・次にやること
- ファイル末尾の「次のセッションでやること」を常に最新に保つこと

---

## 現在のブランチ
`claude/verify-materialized-views-eRnyj`（main にほぼ全部マージ済み）

---

## 今セッションの作業ログ（2026-05-21）

| # | 実施内容 | 結果 |
|---|---|---|
| 1 | migrate_fix_rpc_fastpaths.sql コミット・プッシュ | ✅ |
| 2 | migrate_create_base_type_mvs.sql 作成・プッシュ | ✅ |
| 3 | フロントエンドエラーメッセージ修正（PR #52 マージ済み） | ✅ |
| 4 | requirements.txt バージョン上限ピン留め | ✅ |
| 5 | collect.yml の外部キー制約違反修正（PR #53 マージ済み） | ✅ |
| 6 | ベースMV SQL → ユーザーが実行済みと申告（未検証） | ❓ |

---

## Supabase 現状（未検証）

ユーザーがベースMV作成SQLを実行済みと言っているが、ダッシュボードで
video_type=short/normal が正常動作するかまだ確認していない。

### 次のセッション開始時に最初にやること

**1. 診断クエリで MV の存在を確認**

Supabase SQL Editor で実行：
```sql
SELECT matviewname FROM pg_matviews
WHERE matviewname LIKE 'mv_%short%' OR matviewname LIKE 'mv_%normal%'
ORDER BY matviewname;
```

期待される結果（6行）:
```
mv_active_ch_normal
mv_active_ch_short
mv_keyword_opp_normal
mv_keyword_opp_short
mv_keyword_vir_normal
mv_keyword_vir_short
mv_topic_overlap_normal
mv_topic_overlap_short
mv_topic_video_normal
mv_topic_video_short
```

**2. ダッシュボードで video_type=ショート に切り替えて全チャートを確認**
- エラーなし → 完了 ✅
- エラーあり → エラー内容を Claude Code に共有

---

## 既知の修正済み問題

| 問題 | 修正 | PR |
|---|---|---|
| short/normal フィルタで全RPC 500タイムアウト | 事前計算MV + fast path | #48〜#51 |
| NUMERIC(5,2) オーバーフロー | NUMERIC(8,2) に変更 | #49 |
| フロントエンドの誤解を招くエラーメッセージ | 実際のエラー内容を表示 | #52 |
| collect.yml が毎日クラッシュ（外部キー違反） | 削除済みチャンネルの動画を除外 | #53 |
| requirements.txt バージョン上限なし | メジャーバージョン上限を追加 | #53 |

---

## 主要ファイル一覧

| ファイル | 状態 |
|---|---|
| `sql/migrate_create_base_type_mvs.sql` | ✅ コミット済み・Supabase実行済み（未検証） |
| `sql/migrate_fix_rpc_fastpaths.sql` | ✅ 実行済み（RPC関数更新完了） |
| `collector/main.py` | ✅ 外部キー修正マージ済み（PR #53） |
| `collector/requirements.txt` | ✅ バージョン上限追加済み |
| `frontend/src/hooks/useFilteredQuery.ts` | ✅ エラーメッセージ修正済み |

---

## アーキテクチャメモ（RPC fast path）

- フィルタなし（all/all/null）→ 静的ビュー直読み（最速）
- short/normal のみ → MV直読み（fast path、事前計算）
- 期間 or 国フィルタ → MV結合の動的クエリ（十分速い）
- Supabase Free プランの statement timeout: 8秒

### MV依存関係（リフレッシュ順序）
```
Group1: mv_latest_video_snapshot, mv_latest_channel_snapshot
  ↓
Group2: mv_channel_growth_efficiency, mv_video_tags, mv_video_topics, mv_video_ranking
  ↓
Group3: mv_ai_penetration, mv_topic_duration_stats, mv_keyword_opportunity,
        mv_keyword_virality, mv_topic_overlap
  ↓
Group4: mv_topic_video_short/normal, mv_active_ch_short/normal
  ↓
Group5: mv_topic_overlap_short/normal
Group6: mv_keyword_opp_short/normal, mv_keyword_vir_short/normal
```
