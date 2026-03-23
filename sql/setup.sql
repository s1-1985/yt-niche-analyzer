-- ============================================================
-- YouTube Niche Analyzer — Supabase 初期化SQL
-- ============================================================

-- ジャンルマスタ（topicIdベース）
CREATE TABLE topics (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    name_ja TEXT,
    parent_id TEXT REFERENCES topics(id),
    category TEXT
);

-- チャンネル情報
CREATE TABLE channels (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    published_at TIMESTAMPTZ,
    country TEXT,
    topic_ids TEXT[],
    topic_categories TEXT[],
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- チャンネル日次スナップショット
CREATE TABLE channel_snapshots (
    id BIGSERIAL PRIMARY KEY,
    channel_id TEXT REFERENCES channels(id),
    snapshot_date DATE NOT NULL DEFAULT CURRENT_DATE,
    subscriber_count BIGINT,
    view_count BIGINT,
    video_count INTEGER,
    UNIQUE(channel_id, snapshot_date)
);

-- 動画情報
CREATE TABLE videos (
    id TEXT PRIMARY KEY,
    channel_id TEXT REFERENCES channels(id),
    title TEXT NOT NULL,
    published_at TIMESTAMPTZ,
    duration_seconds INTEGER,
    category_id INTEGER,
    topic_ids TEXT[],
    tags TEXT[],
    default_language TEXT,
    has_ai_keywords BOOLEAN DEFAULT FALSE,
    thumbnail_url TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 動画日次スナップショット
CREATE TABLE video_snapshots (
    id BIGSERIAL PRIMARY KEY,
    video_id TEXT REFERENCES videos(id),
    snapshot_date DATE NOT NULL DEFAULT CURRENT_DATE,
    view_count BIGINT,
    like_count BIGINT,
    comment_count BIGINT,
    UNIQUE(video_id, snapshot_date)
);

-- データ収集ログ（ローテーション管理用）
CREATE TABLE collection_log (
    id BIGSERIAL PRIMARY KEY,
    topic_id TEXT REFERENCES topics(id),
    collected_at TIMESTAMPTZ DEFAULT NOW(),
    videos_collected INTEGER,
    channels_collected INTEGER,
    quota_used INTEGER
);

-- ============================================================
-- インデックス
-- ============================================================
CREATE INDEX idx_videos_channel ON videos(channel_id);
CREATE INDEX idx_videos_published ON videos(published_at DESC);
CREATE INDEX idx_videos_topic ON videos USING GIN(topic_ids);
CREATE INDEX idx_videos_ai ON videos(has_ai_keywords) WHERE has_ai_keywords = TRUE;
CREATE INDEX idx_video_snapshots_date ON video_snapshots(snapshot_date DESC);
CREATE INDEX idx_video_snapshots_video ON video_snapshots(video_id);
CREATE INDEX idx_channel_snapshots_date ON channel_snapshots(snapshot_date DESC);
CREATE INDEX idx_channel_snapshots_channel ON channel_snapshots(channel_id);
CREATE INDEX idx_channels_published ON channels(published_at);
CREATE INDEX idx_channels_topic ON channels USING GIN(topic_ids);

-- ============================================================
-- Row Level Security
-- ============================================================
ALTER TABLE topics ENABLE ROW LEVEL SECURITY;
ALTER TABLE channels ENABLE ROW LEVEL SECURITY;
ALTER TABLE channel_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE videos ENABLE ROW LEVEL SECURITY;
ALTER TABLE video_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE collection_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "public_read" ON topics FOR SELECT USING (true);
CREATE POLICY "public_read" ON channels FOR SELECT USING (true);
CREATE POLICY "public_read" ON channel_snapshots FOR SELECT USING (true);
CREATE POLICY "public_read" ON videos FOR SELECT USING (true);
CREATE POLICY "public_read" ON video_snapshots FOR SELECT USING (true);
CREATE POLICY "public_read" ON collection_log FOR SELECT USING (true);

-- ============================================================
-- 初期データ: topicId マスタ
-- ============================================================
INSERT INTO topics (id, name, name_ja, parent_id, category) VALUES
-- Music
('/m/04rlf', 'Music', '音楽', NULL, 'Music'),
('/m/02mscn', 'Christian music', 'クリスチャン音楽', '/m/04rlf', 'Music'),
('/m/0ggq0m', 'Classical music', 'クラシック音楽', '/m/04rlf', 'Music'),
('/m/01lyv', 'Country', 'カントリー', '/m/04rlf', 'Music'),
('/m/02lkt', 'Electronic music', '電子音楽', '/m/04rlf', 'Music'),
('/m/0glt670', 'Hip hop music', 'ヒップホップ', '/m/04rlf', 'Music'),
('/m/05rwpb', 'Independent music', 'インディー音楽', '/m/04rlf', 'Music'),
('/m/03_d0', 'Jazz', 'ジャズ', '/m/04rlf', 'Music'),
('/m/028sqc', 'Music of Asia', 'アジア音楽', '/m/04rlf', 'Music'),
('/m/0g293', 'Music of Latin America', 'ラテン音楽', '/m/04rlf', 'Music'),
('/m/064t9', 'Pop music', 'ポップ', '/m/04rlf', 'Music'),
('/m/06cqb', 'Reggae', 'レゲエ', '/m/04rlf', 'Music'),
('/m/06j6l', 'Rhythm and blues', 'R&B', '/m/04rlf', 'Music'),
('/m/06by7', 'Rock music', 'ロック', '/m/04rlf', 'Music'),
('/m/0gywn', 'Soul music', 'ソウル', '/m/04rlf', 'Music'),
-- Gaming
('/m/0bzvm2', 'Gaming', 'ゲーム', NULL, 'Gaming'),
('/m/025zzc', 'Action game', 'アクション', '/m/0bzvm2', 'Gaming'),
('/m/02ntfj', 'Action-adventure game', 'アクションアドベンチャー', '/m/0bzvm2', 'Gaming'),
('/m/0b1vjn', 'Casual game', 'カジュアルゲーム', '/m/0bzvm2', 'Gaming'),
('/m/02hygl', 'Music video game', '音楽ゲーム', '/m/0bzvm2', 'Gaming'),
('/m/04q1x3q', 'Puzzle video game', 'パズルゲーム', '/m/0bzvm2', 'Gaming'),
('/m/01sjng', 'Racing video game', 'レースゲーム', '/m/0bzvm2', 'Gaming'),
('/m/0403l3g', 'Role-playing video game', 'RPG', '/m/0bzvm2', 'Gaming'),
('/m/021bp2', 'Simulation video game', 'シミュレーション', '/m/0bzvm2', 'Gaming'),
('/m/022dc6', 'Sports game', 'スポーツゲーム', '/m/0bzvm2', 'Gaming'),
('/m/03hf_rm', 'Strategy video game', 'ストラテジー', '/m/0bzvm2', 'Gaming'),
-- Sports
('/m/06ntj', 'Sports', 'スポーツ', NULL, 'Sports'),
('/m/0jm_', 'American football', 'アメフト', '/m/06ntj', 'Sports'),
('/m/018jz', 'Baseball', '野球', '/m/06ntj', 'Sports'),
('/m/018w8', 'Basketball', 'バスケ', '/m/06ntj', 'Sports'),
('/m/01cgz', 'Boxing', 'ボクシング', '/m/06ntj', 'Sports'),
('/m/09xp_', 'Cricket', 'クリケット', '/m/06ntj', 'Sports'),
('/m/02vx4', 'Football', 'サッカー', '/m/06ntj', 'Sports'),
('/m/037hz', 'Golf', 'ゴルフ', '/m/06ntj', 'Sports'),
('/m/03tmr', 'Ice hockey', 'アイスホッケー', '/m/06ntj', 'Sports'),
('/m/01h7lh', 'Mixed martial arts', '格闘技', '/m/06ntj', 'Sports'),
('/m/0410tth', 'Motorsport', 'モータースポーツ', '/m/06ntj', 'Sports'),
('/m/07bs0', 'Tennis', 'テニス', '/m/06ntj', 'Sports'),
('/m/02_7t', 'Volleyball', 'バレーボール', '/m/06ntj', 'Sports'),
-- Entertainment
('/m/02jjt', 'Entertainment', 'エンタメ', NULL, 'Entertainment'),
('/m/09kqc', 'Humor', 'ユーモア', '/m/02jjt', 'Entertainment'),
('/m/02vxn', 'Movies', '映画', '/m/02jjt', 'Entertainment'),
('/m/05qjc', 'Performing arts', '舞台芸術', '/m/02jjt', 'Entertainment'),
('/m/066wd', 'Professional wrestling', 'プロレス', '/m/02jjt', 'Entertainment'),
('/m/0f2f9', 'TV shows', 'テレビ番組', '/m/02jjt', 'Entertainment'),
-- Lifestyle
('/m/019_rr', 'Lifestyle', 'ライフスタイル', NULL, 'Lifestyle'),
('/m/032tl', 'Fashion', 'ファッション', '/m/019_rr', 'Lifestyle'),
('/m/027x7n', 'Fitness', 'フィットネス', '/m/019_rr', 'Lifestyle'),
('/m/02wbm', 'Food', '料理', '/m/019_rr', 'Lifestyle'),
('/m/03glg', 'Hobby', '趣味', '/m/019_rr', 'Lifestyle'),
('/m/068hy', 'Pets', 'ペット', '/m/019_rr', 'Lifestyle'),
('/m/041xxh', 'Physical attractiveness (Beauty)', '美容', '/m/019_rr', 'Lifestyle'),
('/m/07c1v', 'Technology', 'テクノロジー', '/m/019_rr', 'Lifestyle'),
('/m/07bxq', 'Tourism', '旅行', '/m/019_rr', 'Lifestyle'),
('/m/07yv9', 'Vehicles', '乗り物', '/m/019_rr', 'Lifestyle'),
-- Society
('/m/098wr', 'Society', '社会', NULL, 'Society'),
('/m/09s1f', 'Business', 'ビジネス', '/m/098wr', 'Society'),
('/m/0kt51', 'Health', '健康', '/m/098wr', 'Society'),
('/m/01h6rj', 'Military', '軍事', '/m/098wr', 'Society'),
('/m/05qt0', 'Politics', '政治', '/m/098wr', 'Society'),
('/m/06bvp', 'Religion', '宗教', '/m/098wr', 'Society'),
-- Knowledge
('/m/01k8wb', 'Knowledge', '知識', NULL, 'Knowledge');

-- ============================================================
-- ビュー: ジャンル別サマリー（需要/供給ギャップスコア含む）
-- ============================================================
CREATE OR REPLACE VIEW topic_summary AS
WITH topic_videos AS (
    SELECT
        t.id AS topic_id,
        t.name AS topic_name,
        t.name_ja,
        t.parent_id,
        t.category,
        v.id AS video_id,
        v.channel_id,
        vs.view_count,
        vs.like_count,
        vs.comment_count,
        vs.snapshot_date
    FROM topics t
    JOIN videos v ON t.id = ANY(v.topic_ids)
    JOIN video_snapshots vs ON v.id = vs.video_id
),
latest AS (
    SELECT DISTINCT ON (topic_id, video_id)
        *
    FROM topic_videos
    ORDER BY topic_id, video_id, snapshot_date DESC
)
SELECT
    topic_id,
    topic_name,
    name_ja,
    parent_id,
    category,
    COUNT(DISTINCT video_id) AS total_videos,
    COUNT(DISTINCT channel_id) AS total_channels,
    COALESCE(SUM(view_count), 0) AS total_views,
    COALESCE(AVG(view_count), 0)::BIGINT AS avg_views,
    CASE
        WHEN COUNT(DISTINCT channel_id) > 0
        THEN (COALESCE(AVG(view_count), 0) / COUNT(DISTINCT channel_id))::BIGINT
        ELSE 0
    END AS gap_score,
    CASE
        WHEN COALESCE(SUM(view_count), 0) > 0
        THEN ROUND(COALESCE(SUM(like_count), 0)::NUMERIC / SUM(view_count) * 100, 2)
        ELSE 0
    END AS like_rate_pct,
    CASE
        WHEN COALESCE(SUM(view_count), 0) > 0
        THEN ROUND(COALESCE(SUM(comment_count), 0)::NUMERIC / SUM(view_count) * 100, 4)
        ELSE 0
    END AS comment_rate_pct
FROM latest
GROUP BY topic_id, topic_name, name_ja, parent_id, category;

-- ============================================================
-- ビュー: アウトライアーチャンネル
-- ============================================================
CREATE OR REPLACE VIEW outlier_channels AS
WITH latest_channel AS (
    SELECT DISTINCT ON (channel_id)
        channel_id,
        subscriber_count,
        view_count,
        snapshot_date
    FROM channel_snapshots
    ORDER BY channel_id, snapshot_date DESC
),
channel_with_ratio AS (
    SELECT
        c.id,
        c.title,
        c.published_at,
        c.topic_ids,
        lc.subscriber_count,
        lc.view_count,
        CASE
            WHEN lc.subscriber_count > 0
            THEN (lc.view_count::NUMERIC / lc.subscriber_count)
            ELSE 0
        END AS views_to_sub_ratio
    FROM channels c
    JOIN latest_channel lc ON c.id = lc.channel_id
    WHERE lc.subscriber_count > 0
)
SELECT *,
    PERCENT_RANK() OVER (ORDER BY views_to_sub_ratio) AS percentile
FROM channel_with_ratio;

-- ============================================================
-- ビュー: 新規チャンネル成功率
-- ============================================================
CREATE OR REPLACE VIEW new_channel_success_rate AS
WITH new_channels AS (
    SELECT
        c.id,
        c.topic_ids,
        cs.subscriber_count,
        c.published_at
    FROM channels c
    JOIN (
        SELECT DISTINCT ON (channel_id)
            channel_id, subscriber_count
        FROM channel_snapshots
        ORDER BY channel_id, snapshot_date DESC
    ) cs ON c.id = cs.channel_id
    WHERE c.published_at > NOW() - INTERVAL '1 year'
),
per_topic AS (
    SELECT
        t.id AS topic_id,
        t.name AS topic_name,
        t.name_ja,
        COUNT(*) AS new_channel_count,
        COUNT(*) FILTER (WHERE nc.subscriber_count >= 1000) AS successful_count,
        ROUND(
            COUNT(*) FILTER (WHERE nc.subscriber_count >= 1000)::NUMERIC / NULLIF(COUNT(*), 0) * 100,
            1
        ) AS success_rate_pct
    FROM topics t
    JOIN new_channels nc ON t.id = ANY(nc.topic_ids)
    GROUP BY t.id, t.name, t.name_ja
)
SELECT * FROM per_topic;

-- ============================================================
-- ビュー: 競合集中度
-- ============================================================
CREATE OR REPLACE VIEW competition_concentration AS
WITH channel_views AS (
    SELECT
        t.id AS topic_id,
        t.name AS topic_name,
        t.name_ja,
        v.channel_id,
        SUM(vs.view_count) AS total_views
    FROM topics t
    JOIN videos v ON t.id = ANY(v.topic_ids)
    JOIN video_snapshots vs ON v.id = vs.video_id
        AND vs.snapshot_date = (SELECT MAX(snapshot_date) FROM video_snapshots)
    GROUP BY t.id, t.name, t.name_ja, v.channel_id
),
ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY topic_id ORDER BY total_views DESC) AS rank,
        SUM(total_views) OVER (PARTITION BY topic_id) AS topic_total_views
    FROM channel_views
)
SELECT
    topic_id,
    topic_name,
    name_ja,
    topic_total_views,
    SUM(total_views) FILTER (WHERE rank <= 5) AS top5_views,
    ROUND(
        SUM(total_views) FILTER (WHERE rank <= 5)::NUMERIC / NULLIF(topic_total_views, 0) * 100,
        1
    ) AS top5_share_pct
FROM ranked
GROUP BY topic_id, topic_name, name_ja, topic_total_views;

-- ============================================================
-- ビュー: AI動画浸透度
-- ============================================================
CREATE OR REPLACE VIEW ai_penetration AS
SELECT
    t.id AS topic_id,
    t.name AS topic_name,
    t.name_ja,
    COUNT(*) AS total_videos,
    COUNT(*) FILTER (WHERE v.has_ai_keywords = TRUE) AS ai_video_count,
    ROUND(
        COUNT(*) FILTER (WHERE v.has_ai_keywords = TRUE)::NUMERIC / NULLIF(COUNT(*), 0) * 100,
        2
    ) AS ai_penetration_pct
FROM topics t
JOIN videos v ON t.id = ANY(v.topic_ids)
GROUP BY t.id, t.name, t.name_ja;

-- ============================================================
-- ビュー: 動画ランキング（ドリルダウン用）
-- ============================================================
CREATE OR REPLACE VIEW video_ranking AS
SELECT DISTINCT ON (v.id)
    v.id,
    v.title,
    v.channel_id,
    c.title AS channel_title,
    v.published_at,
    v.duration_seconds,
    v.topic_ids,
    v.has_ai_keywords,
    v.thumbnail_url,
    vs.view_count,
    vs.like_count,
    vs.comment_count,
    cs.subscriber_count AS channel_subscribers,
    CASE
        WHEN cs.subscriber_count > 0
        THEN ROUND(vs.view_count::NUMERIC / cs.subscriber_count, 1)
        ELSE 0
    END AS buzz_score
FROM videos v
JOIN video_snapshots vs ON v.id = vs.video_id
LEFT JOIN channels c ON v.channel_id = c.id
LEFT JOIN (
    SELECT DISTINCT ON (channel_id) channel_id, subscriber_count
    FROM channel_snapshots
    ORDER BY channel_id, snapshot_date DESC
) cs ON v.channel_id = cs.channel_id
ORDER BY v.id, vs.snapshot_date DESC;

-- ============================================================
-- ビュー: チャンネルランキング（ドリルダウン用）
-- ============================================================
CREATE OR REPLACE VIEW channel_ranking AS
SELECT DISTINCT ON (c.id)
    c.id,
    c.title,
    c.published_at,
    c.country,
    c.topic_ids,
    cs.subscriber_count,
    cs.view_count,
    cs.video_count
FROM channels c
JOIN channel_snapshots cs ON c.id = cs.channel_id
ORDER BY c.id, cs.snapshot_date DESC;

-- ============================================================
-- RPC関数: 古いスナップショット削除（容量管理）
-- ============================================================
CREATE OR REPLACE FUNCTION cleanup_old_snapshots()
RETURNS void AS $$
BEGIN
    DELETE FROM video_snapshots
    WHERE snapshot_date < CURRENT_DATE - INTERVAL '30 days'
    AND id NOT IN (
        SELECT DISTINCT ON (video_id) id
        FROM video_snapshots
        WHERE snapshot_date < CURRENT_DATE - INTERVAL '30 days'
        ORDER BY video_id, snapshot_date DESC
    );

    DELETE FROM channel_snapshots
    WHERE snapshot_date < CURRENT_DATE - INTERVAL '30 days'
    AND id NOT IN (
        SELECT DISTINCT ON (channel_id) id
        FROM channel_snapshots
        WHERE snapshot_date < CURRENT_DATE - INTERVAL '30 days'
        ORDER BY channel_id, snapshot_date DESC
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
