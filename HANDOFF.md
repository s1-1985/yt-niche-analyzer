# セッション引継ぎメモ

## ⚠️ Claude へのルール（毎回必読）
- **ツール実行・コード変更・SQL提示のたびに、このファイルを更新すること**
- 更新内容：実施した内容・結果・未解決事項・次にやること
- ファイル末尾の「次のセッションでやること」を常に最新に保つこと

---

## 現在のブランチ
`claude/hopeful-babbage-g5QTg`

---

## 🔴 最優先（2026-06-02 調査）— 総動画数が約1ヶ月増えない問題

### 症状
- 更新履歴（collection_log）には前日分まで GitHub Actions の収集が記録されている
- なのに「総動画数」(topic_summary) が約1ヶ月前から増えていない

### 根本原因（確定）
**MVリフレッシュが Supabase Free の statement timeout (8秒) を超えて失敗し続けている。**
- GitHub Actions ログ（2026-06-01 のラン）で確認:
  `refresh failed [Group1: snapshot base]: 'canceling statement due to statement timeout', code '57014'`
  （Group2/3/6 も同様にタイムアウト。Group4/5 は古いデータを読むだけなので 204 成功）
- `topic_summary` は `videos JOIN mv_latest_video_snapshot`（INNER JOIN）。
  MVが凍結 → 先月以降に収集した動画がJOINで除外 → 件数が増えない。
- `videos` / `video_snapshots` テーブル自体には毎日正常に書き込まれている
  （だから collection_log の更新履歴は出るのに件数だけ止まる）。
- データ増加（約86k動画）で `REFRESH MATERIALIZED VIEW CONCURRENTLY` が8秒超になったのが引き金。

### 対策（作成済み・**未実行**）
- `sql/migrate_fix_refresh_timeout.sql` を作成。
  - (A) 全リフレッシュ関数に `statement_timeout = '120s'` を付与し、関数実行中だけ8秒制限を上書き。
  - (B) `refresh_snapshot_base()` を非CONCURRENTLY化（高速・安定化＋SQL Editor一括Run可能化）。
        代償は更新中の一瞬の読み取りロックのみ（日次・夜間・低トラフィックで許容）。
  - STEP2で即時手動リフレッシュ、STEP3で件数確認。
- **次にやること**: このSQLを Supabase SQL Editor に貼って Run → 件数が復旧するか STEP3 で確認。

---

## 今セッションの作業ログ（2026-05-08）

| # | 実施内容 | 結果 |
|---|---|---|
| 1 | HANDOFF.md 読み込み・状況確認 | ✅ |
| 2 | 全500エラー修正（GRANT不足・GIN非使用JOINなど） | ✅ |
| 3 | `sql/migrate_fix_500_errors.sql` 実行 | ✅ Success |
| 4 | `sql/migrate_fix_topic_views.sql` 実行（mv_video_topics + ai_penetration + topic_duration MV） | ✅ Success |
| 5 | `sql/migrate_split_refresh_functions.sql` 実行（PR #46マージ） | ✅ Success |
| 6 | `collector/supabase_client.py` を3グループRPC呼び出しに更新 | ✅ コミット済み |
| 7 | video_type=short/normal 切り替えで全RPCがタイムアウトすることを確認 | ⚠️ 問題確認 |
| 8 | `sql/migrate_fix_filtered_rpcs.sql` 実行（mv_video_topics ベースに全RPC書き換え） | ✅ 実行済み（効果不十分） |
| 9 | `sql/migrate_precompute_video_types.sql` 作成（10個の新規MV + 全RPC更新） | ✅ 作成完了・**未実行** |
| 10 | `collector/supabase_client.py` を6グループRPC呼び出しに更新 | ✅ 変更済み |

---

## ダッシュボード現状（2026-05-08 時点）

### デフォルト状態（video_type=all, 期間=all, 国=null）→ 全チャート正常 ✅

### video_type=short または normal に切り替えると → **全チャートでタイムアウト** ❌

---

## Supabase 適用状況

### 実行済み MV（migrate_fix_500_errors + migrate_fix_topic_views + migrate_split_refresh_functions）
| MV名 | 状態 |
|---|---|
| mv_latest_video_snapshot | ✅ |
| mv_latest_channel_snapshot | ✅ |
| mv_channel_growth_efficiency | ✅ |
| mv_video_tags | ✅ |
| mv_video_topics | ✅ |
| mv_video_ranking | ✅ |
| mv_keyword_opportunity | ✅ |
| mv_keyword_virality | ✅ |
| mv_ai_penetration | ✅ |
| mv_topic_duration_stats | ✅ |
| mv_topic_overlap | ✅ |

### 未実行 ❌（次のセッションでやること）
1. **`sql/migrate_fix_refresh_timeout.sql`**（🔴最優先 / 2026-06-02）
   — 総動画数が増えない問題の修正。MVリフレッシュの8秒タイムアウト対策。
2. **`sql/migrate_precompute_video_types.sql`** を Supabase SQL Editor で実行する

このファイルで行うこと:
1. 10個の新規MV作成（short/normal 事前計算）
   - mv_topic_video_short / mv_topic_video_normal
   - mv_active_ch_short / mv_active_ch_normal
   - mv_topic_overlap_short / mv_topic_overlap_normal
   - mv_keyword_opp_short / mv_keyword_opp_normal
   - mv_keyword_vir_short / mv_keyword_vir_normal
2. 全13RPC関数の更新（short/normal フィルタ時はMV直読み）
3. 3つの新規リフレッシュ関数の作成（Group4〜6）

---

## アーキテクチャメモ

### MV依存関係
```
[Group1] mv_latest_video_snapshot, mv_latest_channel_snapshot
   ↓
[Group2] mv_channel_growth_efficiency, mv_video_tags, mv_video_topics, mv_video_ranking
   ↓
[Group3] mv_ai_penetration, mv_topic_duration_stats, mv_keyword_opportunity,
         mv_keyword_virality, mv_topic_overlap
   ↓
[Group4] mv_topic_video_short, mv_topic_video_normal, mv_active_ch_short, mv_active_ch_normal
   ↓
[Group5] mv_topic_overlap_short, mv_topic_overlap_normal (depends on Group4)
[Group6] mv_keyword_opp_short/normal, mv_keyword_vir_short/normal (depends on Group2+4)
```

### useFilteredQuery フック
- フィルタがデフォルト（all/all/null）→ 静的ビュー直参照
- それ以外 → `supabase.rpc('fn_${view}', {p_min_date, p_video_type, p_country})` を3パラメータで呼び出す
- **注意**: fn_keyword_virality/opportunity は以前4パラメータ(+p_topic_id)だったが、今回3パラメータに統一

### RPC リフレッシュ（supabase_client.py - 6グループ）
```python
groups = [
    ("refresh_snapshot_base",    "Group1: snapshot base"),
    ("refresh_derived_mvs",      "Group2: derived MVs"),
    ("refresh_analytics_mvs",    "Group3: analytics MVs"),
    ("refresh_type_base_mvs",    "Group4: type base MVs"),     # NEW
    ("refresh_type_overlap_mvs", "Group5: type overlap MVs"),  # NEW
    ("refresh_type_keyword_mvs", "Group6: type keyword MVs"),  # NEW
]
```

---

## 主要ファイル一覧

| ファイル | 内容 | 状態 |
|---|---|---|
| `sql/migrate_precompute_video_types.sql` | 10個の新規MV + 全RPC更新 + 新リフレッシュ関数 | ❌ **未実行** |
| `sql/migrate_fix_filtered_rpcs.sql` | RPC書き換え（mv_video_topicsベース） | ✅ 実行済み |
| `sql/migrate_fix_topic_views.sql` | mv_video_topics + ai/duration MV | ✅ 実行済み |
| `sql/migrate_fix_500_errors.sql` | GRANT + keyword/overlap MV | ✅ 実行済み |
| `sql/migrate_split_refresh_functions.sql` | 3グループリフレッシュ | ✅ 実行済み |
| `collector/supabase_client.py` | 6グループRPC呼び出し | ✅ 変更済み（push待ち） |

---

## 次のセッションでやること

### 0. 🔴 `sql/migrate_fix_refresh_timeout.sql` を Supabase SQL Editor で実行（最優先）
   - 「総動画数が約1ヶ月増えない」問題の修正
   - STEP1（ALTER FUNCTION）→ STEP2（手動リフレッシュ）→ STEP3（件数確認）の順で1ファイルを Run
   - STEP3 で `mv_snapshot_count` が `videos_table_count` に追いついていれば復旧
   - 以降は日次 cron（08:00 UTC）でMVが更新され続けるか、翌日 collection_log とあわせて確認

### 1. `sql/migrate_precompute_video_types.sql` を Supabase SQL Editor で実行
   - ファイル内容を全コピペして Run
   - 「Success. No rows returned」が出ればOK
   - エラーが出た場合はエラー内容をClaude Codeに共有

### 2. ダッシュボードで video_type=short に切り替えて全チャート確認
   - 全チャートがタイムアウトなしで表示されれば完了

### 3. 未完成の対応（SQLが正常実行された後）
   - video_type=short/normal での動作確認
   - 必要なら BuzzPickup の video_type フィルタ確認（現在はクライアント側フィルタ）
