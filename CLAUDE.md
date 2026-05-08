# Claude Code 作業ルール

## 必須ルール（毎回厳守）

### HANDOFF.md を常に最新に保つ
**以下のタイミングで必ず HANDOFF.md を更新すること：**
- ツールを実行したとき
- コードを変更したとき
- SQLをユーザーに提示したとき
- ユーザーから実行結果を受け取ったとき
- セッション終了前

**更新する内容：**
- 実施した作業と結果（成功 / 失敗 / 未確認）
- 新たに発見した問題
- 未解決の問題と次にやること

### セッション開始時
1. `HANDOFF.md` を必ず読む
2. 「次のセッションでやること」から着手する

---

## プロジェクト概要

YouTube ニッチ分析ダッシュボード。YouTube チャンネル・動画データを収集し、
ジャンル別のトレンド・競合・キーワード分析を可視化する。

- **フロントエンド**: React + TypeScript + Vite → GitHub Pages
- **バックエンド**: Supabase (PostgreSQL)
- **コレクター**: Python 3.12 + GitHub Actions (毎日 08:00 UTC)

## ディレクトリ構成

```
frontend/        # React ダッシュボード
collector/       # YouTube データ収集スクリプト
sql/             # Supabase マイグレーション SQL
HANDOFF.md       # セッション引継ぎ（毎回更新）
```

## Supabase SQL の適用方法

SQL ファイルの内容を **Supabase SQL Editor** に貼り付けて Run する。
ユーザーが手動で実行する。自動適用の仕組みはない。

## 重要な制約

- Supabase Free プランの statement timeout: **8秒**
- データ量: 約 86k動画 / 46k チャンネル（2026-05 時点）
- 重いクエリは必ずマテリアライズドビュー (MV) に変換すること
- MV は `refresh_latest_snapshots()` でデータ収集後に一括更新される

## マテリアライズドビュー一覧

| MV名 | 元テーブル | 用途 |
|---|---|---|
| `mv_latest_video_snapshot` | video_snapshots | 各動画の最新スナップショット |
| `mv_latest_channel_snapshot` | channel_snapshots | 各チャンネルの最新スナップショット |
| `mv_channel_growth_efficiency` | channels + mv_latest_channel_snapshot | チャンネル成長効率 |
| `mv_video_tags` | videos (tags展開) | キーワード分析の高速化 |
