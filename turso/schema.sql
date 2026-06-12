-- ============================================================
-- Turso (LibSQL/SQLite) スキーマ
--
-- Supabase からの移行設計:
--   PostgreSQL の配列型 (topic_ids[], tags[]) を junction テーブルに正規化。
--   マテリアライズドビュー 22個は全廃。集計はその場計算（SQLite ならタイムアウトなし）。
--   スナップショット保持: 90日（Supabase の 365日から短縮）。
--
-- ⚠️ FK 制約は意図的に張らない:
--   1. topic_ids には topics テーブル（キュレーション62件）外の ID が混入する
--   2. Turso は FK を強制し、FK 有効時の INSERT OR REPLACE は親行の
--      DELETE→CASCADE で子行（動画・スナップショット）を全消しする
--   3. PRAGMA foreign_keys は接続単位の設定で、ステートレスな HTTP API では
--      リクエストごとに別接続に当たるため信頼できない
--   孤立行は JOIN で自然に除外される（Supabase と同じ挙動）。
-- ============================================================

-- トピック（ジャンル）マスタ
CREATE TABLE IF NOT EXISTS topics (
  id        TEXT PRIMARY KEY,
  name      TEXT NOT NULL,
  name_ja   TEXT,
  category  TEXT,
  parent_id TEXT
);

-- チャンネルマスタ
CREATE TABLE IF NOT EXISTS channels (
  id           TEXT PRIMARY KEY,
  title        TEXT,
  published_at TEXT,  -- ISO8601
  country      TEXT
);

-- チャンネル×トピック（channels.topic_ids[] を正規化）
CREATE TABLE IF NOT EXISTS channel_topics (
  channel_id TEXT NOT NULL,
  topic_id   TEXT NOT NULL,
  PRIMARY KEY (channel_id, topic_id)
);

-- 動画マスタ
CREATE TABLE IF NOT EXISTS videos (
  id               TEXT PRIMARY KEY,
  channel_id       TEXT NOT NULL,
  title            TEXT,
  published_at     TEXT,  -- ISO8601
  duration_seconds INTEGER,
  category_id      TEXT,
  default_language TEXT,
  has_ai_keywords  INTEGER NOT NULL DEFAULT 0,  -- 0/1 boolean
  thumbnail_url    TEXT
);

-- 動画×トピック（videos.topic_ids[] を正規化）
CREATE TABLE IF NOT EXISTS video_topics (
  video_id TEXT NOT NULL,
  topic_id TEXT NOT NULL,
  PRIMARY KEY (video_id, topic_id)
);

-- 動画タグ（videos.tags[] を正規化）
CREATE TABLE IF NOT EXISTS video_tags (
  video_id TEXT NOT NULL,
  tag      TEXT NOT NULL,
  PRIMARY KEY (video_id, tag)
);

-- 動画スナップショット（日次指標。90日保持）
CREATE TABLE IF NOT EXISTS video_snapshots (
  video_id      TEXT NOT NULL,
  snapshot_date TEXT NOT NULL,  -- YYYY-MM-DD
  view_count    INTEGER,
  like_count    INTEGER,
  comment_count INTEGER,
  PRIMARY KEY (video_id, snapshot_date)
);

-- チャンネルスナップショット（日次指標。90日保持）
CREATE TABLE IF NOT EXISTS channel_snapshots (
  channel_id       TEXT NOT NULL,
  snapshot_date    TEXT NOT NULL,  -- YYYY-MM-DD
  subscriber_count INTEGER,
  view_count       INTEGER,
  video_count      INTEGER,
  PRIMARY KEY (channel_id, snapshot_date)
);

-- 収集ログ
CREATE TABLE IF NOT EXISTS collection_log (
  id                 INTEGER PRIMARY KEY AUTOINCREMENT,
  topic_id           TEXT,
  collected_at       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  videos_collected   INTEGER,
  channels_collected INTEGER,
  quota_used         INTEGER
);

-- ============================================================
-- インデックス（クエリ速度の要。スパイクで実測済み）
-- ============================================================

-- 動画
CREATE INDEX IF NOT EXISTS idx_videos_channel   ON videos(channel_id);
CREATE INDEX IF NOT EXISTS idx_videos_published ON videos(published_at);
CREATE INDEX IF NOT EXISTS idx_videos_duration  ON videos(duration_seconds);
CREATE INDEX IF NOT EXISTS idx_videos_has_ai    ON videos(has_ai_keywords);

-- 動画×トピック（topic_summary / topic_popular_tags 等で多用）
CREATE INDEX IF NOT EXISTS idx_video_topics_topic ON video_topics(topic_id);
CREATE INDEX IF NOT EXISTS idx_video_topics_video ON video_topics(video_id);

-- 動画タグ（keyword_virality / keyword_opportunity で多用）
CREATE INDEX IF NOT EXISTS idx_video_tags_tag   ON video_tags(tag);
CREATE INDEX IF NOT EXISTS idx_video_tags_video ON video_tags(video_id);

-- チャンネル×トピック
CREATE INDEX IF NOT EXISTS idx_channel_topics_topic   ON channel_topics(topic_id);
CREATE INDEX IF NOT EXISTS idx_channel_topics_channel ON channel_topics(channel_id);

-- スナップショット（期間フィルタで必須）
CREATE INDEX IF NOT EXISTS idx_video_snap_date   ON video_snapshots(snapshot_date);
CREATE INDEX IF NOT EXISTS idx_channel_snap_date ON channel_snapshots(snapshot_date);

-- 収集ログ（ローテーション順序決定用）
CREATE INDEX IF NOT EXISTS idx_collection_log_topic ON collection_log(topic_id, collected_at);
