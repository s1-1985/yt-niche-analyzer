# セッション引継ぎメモ

## ⚠️ Claude へのルール（毎回必読）
- **ツール実行・コード変更・SQL提示のたびに、このファイルを更新すること**
- 更新内容：実施した内容・結果・未解決事項・次にやること
- ファイル末尾の「次のセッションでやること」を常に最新に保つこと

---

## 現在のブランチ
`claude/hopeful-babbage-g5QTg`

---

## 🔴 進行中（2026-06-02 後半）— ダッシュボード他機能のエラー（実測デバッグ）

公開バンドルから anon キー(公開JWT)を取得し、`mnqcjnaxnklrfgyvhsgu.supabase.co` の各RPCを
実際に叩いて挙動を実測（コードベースは多版乱立＆DB乖離で追えないため）。結果、原因は2種類:

### A. コードのバグ（毎回400・即死。データ量と無関係）
| 関数 | エラー |
|---|---|
| fn_topic_popular_tags | 42702 column "name_ja" is ambiguous |
| fn_channel_growth_efficiency | 42702 column "channel_id" is ambiguous |
| fn_keyword_virality | 42702 column "tag" is ambiguous |
| fn_keyword_opportunity | 42702 column "avg_views" is ambiguous |
| fn_topic_duration_stats | 42804 returned double precision ≠ numeric (col 6) |
→ 修正には**実DBの関数定義**が必要（`sql/dump_broken_functions.sql` で取得依頼中）。

### B. 遅い（1〜5秒・境界で時々500）
fn_topic_summary / fn_topic_channel_size / video_ranking(topic絞り+view順) 等。
実測で **anon ロールの statement_timeout が約3秒**しかないのが原因。
→ 対策: `sql/migrate_raise_frontend_timeout.sql`（anon/authenticated を15sに引き上げ）。**適用依頼中**。

### 検証方法（重要・再現可能）
```
KEY=$(grep -oE 'eyJ...JWT...' /tmp/bundle.js | head -1)  # 公開バンドルから anon キー
curl -k -X POST https://mnqcjnaxnklrfgyvhsgu.supabase.co/rest/v1/rpc/<fn> \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"p_min_date":"2026-05-01T00:00:00Z","p_video_type":"all","p_country":null}'
```
B適用後・A修正後に同じ方法で再テストして200を確認する。

### 対応状況（2026-06-02）
- **B（遅い）: 適用済み・実測検証OK** — `migrate_raise_frontend_timeout.sql`（anon/authenticated=15s）。
  fn_topic_summary/channel_size 等が全て200に。video_ranking(topic絞り)も200/5s。
- **A（コードバグ）: 修正作成（要適用）** — `sql/migrate_fix_broken_rpcs.sql`
  - 曖昧カラム4関数 → `ALTER FUNCTION ... SET plpgsql.variable_conflict='use_column'`（本体非改変）。
  - fn_topic_duration_stats → PERCENTILE_CONT/AVG を ::NUMERIC キャスト。
  - keyword系404 → フロントを3引数化（KeywordVirality/OpportunityChart.tsx の p_topic_id 削除）。
  - 適用後に anon実RPCで再検証予定。
- **A適用後の実測（2026-06-02）**: 曖昧4関数は200に回復✅。ただし `fn_topic_duration_stats` で
  別問題が判明：(1)関数は8列の別形を返す古い設計で、フロント/MV/静的ビューの**12列形と乖離**、
  (2)フィルタ時のライブ集計が16.5秒で重い。
  → `sql/migrate_fix_duration_stats_shape.sql` 追加：12列形にDROP+再作成、分位点を
  PERCENTILE_CONT(ARRAY[…])で1ソート化、重い関数に statement_timeout=30s 付与。**適用待ち**。
- **教訓**: 関数の戻り値「形」もフロント/MVと乖離しうる。200でも中身が出ない場合は
  実DBのMV/ビューの列名(`?limit=1`)とフロントが使う列を突き合わせること。

### 徹底検証（実RPC総当たり 2026-06-02）
全静的ビュー＋13RPC×{デフォルト/short/normal/国JP} を実測。**ほぼ全て200**。
唯一: `fn_topic_popular_tags`+国JP が 32.9秒で500、`fn_keyword_opportunity`+国JP が29.4秒（境界）。
→ `sql/migrate_bump_tag_timeouts.sql`：タグ/キーワード3関数を 60s に引上げ（**適用待ち**）。
国フィルタ時のタグ集計が重い（~30s）のは既知。恒久対策は国別事前計算MV（将来課題）。
デフォルト/期間/short/normal/ランキングは全て高速(<8s)で正常。

### 🔴 リフレッシュ基盤の問題と pg_cron 移行（2026-06-02）
今日の collect ログ(12:00 UTC)で判明:
- `refresh_topic_summary` が **404**（migrate_refresh_mv_topic_summary.sql 未適用）→ 総動画数が再凍結する状態
- `refresh_analytics_mvs`(Group3)・`refresh_type_keyword_mvs`(Group6) が **120秒でタイムアウト**
  （コレクターの supabase-py クライアント read timeout 120s が原因）→ 分析/キーワードMVが毎日更新されていない
- 一方 Group2(derived)は66秒で成功 → ゲートウェイは66秒以上は許容

**方針（ユーザー合意「無料一択」）**: MVリフレッシュを **pg_cron（DB内部）** に移行。
クライアント/ゲートウェイのタイムアウトと無縁になり重いMVも確実に更新。
- **Phase 1（作成済み・適用待ち）**: `sql/migrate_pgcron_refresh.sql`
  - pg_cron有効化 ＋ refresh_topic_summary作成(404解消) ＋ refresh_all_mvs(全22MV依存順・1800s・堅牢化)
  - 毎日 14:00 UTC にスケジュール。適用は SQL のみ（コレクター変更/マージ不要）。
  - ※ CREATE EXTENSION で権限エラー時は Dashboard→Extensions で pg_cron 有効化してから再実行。
  - 適用後、次の14:00 UTC実行を anon でMV鮮度確認して検証する。
- **Phase 2（Phase1確認後）**: 国×トピック×タグ の事前計算MV追加＋RPCの国fast-path＋pg_cron組込み。

【教訓の更新】重いMVは「収集後にコレクターRPCで更新」だとクライアント120秒で失敗する。
pg_cron（DB内部）が無料枠での正解。

### 🔵 安定稼働 実地監査の結果とロードマップ（2026-06-03）
「永続稼働」目的でコード全体を監査。最大の弱点は性能でなく**運用**（静かな障害／手作業SQLのdrift／安全装置の未検証）。

監査で判明した事実：
- MVリフレッシュ失敗時、collectorは警告のみで**exit 1しない**（supabase_client.py:154-158）→ Actions「成功」扱い→1ヶ月気づかず。
- GitHub Actions collect.yml に失敗通知なし。cron は 08:00 UTC。
- UIの「最終更新」(App.tsx:76-84)は collection_log の時刻で、MV更新成否は見ていない（古くても新しく見える）。
- スナップショット削除は**実装あり**(supabase_client.py:99-130, 365日保持)だが、RPC `cleanup_old_snapshots` がDBに無ければ静かに無削除→**要生存確認**。
- SQL: 全34ファイル、マイグレーション順序管理なし。22MV中12個が `IF NOT EXISTS` 無しで再実行不可。health check無し。
- collector は今も7つの refresh_* をRPC呼び出し中（pg_cron適用後は重複→重い物は削除して一本化すべき）。
- APIキー失効は未検知（quota超過のみ検知）。
- CLAUDE.md が乖離：「86k動画/MV4個」→ 実際 140k/**MV22個**。

**安定化ロードマップ（着手順）**：
- A. ✅ `cleanup_old_snapshots` はDBに**実在確認済み**（2026-06-03）→ 削除処理は生きている。
- 🔴🔴 **【緊急】DB容量が無料枠超過（2026-06-03 確認）**: `pg_database_size` = **605MB > 500MB上限**。
     - **主因はMV**（再生成可能なキャッシュ）: mv_video_tags 160MB / mv_video_ranking 64MB /
       mv_video_topics 43MB … 上位だけで350MB超。本物のデータ(videos96+snapshots48+44+channels33≒220MB)は軽い。
     - ※mv_outlier_channels(12MB) は doctor の22MVリストに無い＝MVがさらに存在(drift)。
     - **将来の別問題**: video/channel_snapshots は今92MBだが365日保持で1年後~600MBまで増える→保持短縮(90日)が必要。
     - **対策順**: (1)全MVサイズ一覧で不要MV特定→削除 (2)14:00 UTCの非CONCURRENT全更新でbloat回収し再計測
       (3)snapshot保持365→90日 (4)なお超過ならPro/範囲縮小。MVは消しても実データ無傷。
     - 教訓: 「無料×全部MVで爆速×データ増加」の三立は構造的に困難。容量は継続監視必須。
- Tier1（静かな障害をなくす）:
     ③ ✅ **doctor適用済み・初回オールグリーン**（2026-06-03 02:09）`sql/migrate_health_check.sql`
        cronジョブID2で毎日14:30 UTC点検。初回 ok=true / issues={} /
        **videos_count=142,844 == mv_count=142,844（MV完全同期＝凍結完治を確認）** / latest_snapshot=06-02。
        （system_healthテーブル＝anon公開。22MV/9関数の存在・収集鮮度(3日)・MV凍結(件数乖離5%)を点検）
     ① collector: リフレッシュ/収集失敗で exit 1 + GitHub Actions通知（未）
     ② frontend: 「最終更新」を収集ログ時刻でなく system_health/実データ鮮度に（未）
- Tier2: ④削除のpg_cron化+容量監視(無料500MB) ⑤全SQL冪等化+順序運用 ⑥リフレッシュ経路をpg_cronに一本化(collectorの重い物削除)。
- Tier3: ⑦APIキー失効検知 ⑧CLAUDE.md実態反映 ⑨外部依存メモ(キー/quota/GH Actions 60日無活動停止/Supabase一時停止)。
- ※Phase 2(国別事前計算MV)はこの安定化と並行 or 後。ユーザー指示待ち。

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

### 対策（適用済み・⚠️ただし総動画数は変化せず＝真因は別 2026-06-02）
- `sql/migrate_fix_refresh_timeout.sql` を作成（一括Run用に `sql/apply_fix_now.sql` も追加）。
  - (A) 全リフレッシュ関数に `statement_timeout = '120s'` を付与し、関数実行中だけ8秒制限を上書き。
  - (B) `refresh_snapshot_base()` を非CONCURRENTLY化（高速・安定化＋SQL Editor一括Run可能化）。
- **結果**: SQL Editor で STEP1（関数修正）＋ `SELECT refresh_snapshot_base();` を実行。
  - `refresh_snapshot_base()` は **2.1秒で完了**（以前は CONCURRENTLY で8秒超→失敗）。
  - 確認クエリ（④）の結果:
    - `videos_table_count = 140,791`
    - `mv_snapshot_count  = 140,791`  ← **生テーブルと一致＝凍結解消の決定的証拠**
    - `dashboard_total_videos = 86,153`

### ⚠️ 重要な訂正（ユーザー指摘 2026-06-02）
- **ダッシュボード「総動画数」は修正前から 86,153 のままで、MVリフレッシュ後も変化なし。**
- つまり MV凍結はログ上は実在したが、**ユーザーの本当の問題（総動画数が約1ヶ月増えない）の真因ではなかった。**
  （MV凍結の修正自体は再生数・ランキング等の鮮度には有効なので無駄ではない）
- コード調査: `videos` テーブルを削除する処理は存在しない＝本来は単調増加するはず。

### ✅ 真因の特定（2026-06-02）
診断クエリで切り分けた結果:
- `videos` = 140,791件、直近30日の純増 `new_videos_30d` = 49,076 → **DBは猛烈に増えている**（収集は正常）
- 紐づけも正常（サブトピック紐づけ 121,925件、新規49kのうち 43,321件が紐づく）
- なのに `topic_summary` 合計 = 86,153 で矛盾（紐づく121,925 > 合計86,153 はありえない）
- **`topic_summary` ビューの実体 = `SELECT ... FROM mv_topic_summary;`（226文字）**
- **`mv_topic_summary` はマテビューで、どのリフレッシュ関数にも含まれず、リポジトリSQLにも存在しない**
  → 作成時点（約1ヶ月前=86,153件）で凍結。誰も更新しないため総動画数が固定されていた。
- **DBがリポジトリから乖離している**（mv_topic_summary はSupabase上で直接作られた）。

### ✅ 解決（2026-06-02）
1. **即時復旧 完了**: `REFRESH MATERIALIZED VIEW mv_topic_summary;` 実行 →
   `dashboard_total` が **86,153 → 121,925** に回復。ダッシュボードの総動画数が復活。
2. **恒久対策 実装済み（要適用）**: `sql/migrate_refresh_mv_topic_summary.sql` を追加。
   - 専用関数 `refresh_topic_summary()`（statement_timeout=120s, mv_topic_summary をREFRESH）を新設（既存関数は非変更）。
   - mv_topic_summary 定義をリポジトリに記録（IF NOT EXISTS）＋ topic_summary 薄ラッパビューも記録。
   - `collector/supabase_client.py` のグループ列に `refresh_topic_summary`(Group1b) を追加。
   - mv_topic_summary の定義 = topics × videos × mv_latest_video_snapshot の集計（migrate_performance_indexes の topic_summary と同一内容）。

### 残作業（ユーザー）
- `sql/migrate_refresh_mv_topic_summary.sql` を Supabase SQL Editor で実行（refresh_topic_summary 関数を作成）。
- ブランチをマージ → 以降の日次cronが mv_topic_summary を毎日リフレッシュ（再凍結しない）。
- 教訓: **DBがリポジトリから乖離している**箇所が他にもある可能性。ダッシュボードが参照する
  ビューが「マテビューの薄いラッパ」かどうか、refresh対象に入っているかを今後要確認。

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
