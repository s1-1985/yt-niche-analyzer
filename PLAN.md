# 実装プラン: データベース統計 + ジャンルフィルタ + 競合分析

## 概要
3つの機能を追加する:
1. **データベース統計パネル**: ジャンルごとのデータ蓄積量を表示するモーダル
2. **ジャンル（カテゴリ）フィルタ**: ダッシュボード全体を特定ジャンルに絞り込み
3. **ジャンル内競合分析**: 選択ジャンル内の動画・チャンネルランキング、Buzz動画、急成長チャンネル等

## UIレイアウト

### ヘッダー構成（提案）

```
YouTube Niche Analyzer
ジャンル別の需給ギャップ・競合分析ダッシュボード

最終更新: 2026/3/24 03:00  [更新履歴] [データベース]

[ジャンル: 全体 | Music ▼ | Gaming ▼ | Sports ▼ | ... ]  ← カテゴリ選択（親ジャンル）
[サブジャンル: 全サブ | ヒップホップ | ロック | ポップ | ... ] ← 親選択時にサブジャンル表示
[期間: 24h 1w 1m 3m all]  [動画: all normal short]
```

**ジャンル選択の動作:**
- 「全体」選択時 → 現在のダッシュボード（ジャンル横断比較）
- カテゴリ選択時（例: Music）→ Music配下のサブジャンルだけで比較分析
- サブジャンル選択時（例: ヒップホップ）→ そのジャンル内の競合分析モードに切り替え

### 表示モード

**モードA: ジャンル横断比較（現状 + カテゴリ絞り込み）**
- 「全体」or カテゴリ選択時
- 現在のチャート群をそのまま表示（データをフィルタして渡す）
- カテゴリ選択時は、そのカテゴリのサブジャンルだけで各チャートを表示

**モードB: ジャンル内競合分析（新規）**
- サブジャンル選択時に表示
- KPIカード: そのジャンルの動画数、チャンネル数、平均再生数、平均いいね率
- Buzz動画ピックアップ（そのジャンル内）
- 人気動画ランキング TOP20（再生数順）
- 人気チャンネルランキング TOP20（登録者順）
- 急成長チャンネル（登録者/日が高い新しいチャンネル）
- 穴場チャンネル（登録者少ないのに再生数が多い = outlier）
- そのジャンルの動画尺分布
- そのジャンルのタグクラウド/人気タグ
- そのジャンルの投稿曜日パフォーマンス

---

## 実装ステップ

### Step 1: データベース統計モーダル (DataStats コンポーネント)
- 新規: `frontend/src/components/DataStats.tsx`
- Supabaseから `topics` + 動画数・チャンネル数を集計するクエリ
  - `SELECT t.id, t.name, t.name_ja, t.category, t.parent_id, COUNT(DISTINCT v.id) as video_count, COUNT(DISTINCT v.channel_id) as channel_count FROM topics t LEFT JOIN videos v ON t.id = ANY(v.topic_ids) WHERE t.parent_id IS NOT NULL GROUP BY t.id`
  - もしくはRPC関数を作る（より効率的）
- 実装方法: 直接Supabaseから `topic_summary` ビューを使う（既に total_videos, total_channels がある）
- UI: モーダル形式、カテゴリ別にグループ化して表示
- ボタン: 「更新履歴」の隣に「データベース」ボタン

### Step 2: ジャンルフィルタ (TopicFilter コンポーネント)
- 新規: `frontend/src/components/TopicFilter.tsx`
- 状態: `selectedCategory: string | null`, `selectedTopicId: string | null`
- App.tsxに状態追加、全チャートにフィルタ適用
- カテゴリ選択 → subTopicsをそのカテゴリだけにフィルタ
- サブジャンル選択 → 競合分析モードへ切り替え

### Step 3: データフィルタリング（クライアントサイド）
- App.tsxで、選択カテゴリに基づいてデータをフィルタしてからチャートに渡す
- 例: `topics.data.filter(t => !selectedCategory || t.category === selectedCategory)`
- 全ての useFilteredQuery の結果に対して同様のフィルタを適用

### Step 4: 競合分析モード (CompetitiveAnalysis コンポーネント)
- 新規: `frontend/src/components/CompetitiveAnalysis.tsx`
- サブジャンル選択時にダッシュボード本体の代わりに表示
- 内部で video_ranking, channel_ranking を topic_id でフィルタ取得
- サブコンポーネント:
  - GenreKpiCards: ジャンル内KPI
  - GenreBuzzVideos: ジャンル内Buzz動画
  - GenreVideoRanking: 人気動画TOP20
  - GenreChannelRanking: 人気チャンネルTOP20
  - GenreGrowthChannels: 急成長チャンネル
  - GenreOutlierChannels: 穴場チャンネル（登録者少×再生多）
- 既存の TopicDetail モーダルのコンテンツを拡張・再利用

### Step 5: CSS追加
- ジャンルフィルタのスタイリング
- 競合分析セクションのスタイリング
- データベース統計モーダルのスタイリング

---

## ファイル変更一覧

### 新規ファイル
- `frontend/src/components/DataStats.tsx` - データベース統計モーダル
- `frontend/src/components/TopicFilter.tsx` - ジャンル/カテゴリフィルタ
- `frontend/src/components/CompetitiveAnalysis.tsx` - ジャンル内競合分析

### 変更ファイル
- `frontend/src/App.tsx` - 状態追加、フィルタ適用、モード切替
- `frontend/src/App.css` - 新コンポーネントのスタイル追加
