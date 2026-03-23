"""YouTube Niche Analyzer — データ収集メインエントリポイント

GitHub Actions (日次 cron) から実行される。
1. ローテーションで今日のtopicIdグループを決定
2. 各topicIdで search.list → videos.list → channels.list
3. Supabase に upsert
4. 古いスナップショットを削除（容量管理）
"""

import logging
import os
import sys

from youtube_client import YouTubeClient, QuotaExceededError
from supabase_client import init_client, upsert_channels, upsert_videos, cleanup_old_snapshots
from rotation import get_today_topics, log_collection
from metrics import compute_collection_stats
from topic_ids import TOPIC_IDS

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)


def main():
    # 環境変数から認証情報取得
    youtube_api_key = os.environ.get("YOUTUBE_API_KEY")
    supabase_url = os.environ.get("SUPABASE_URL")
    supabase_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")

    if not all([youtube_api_key, supabase_url, supabase_key]):
        logger.error("Missing required environment variables")
        sys.exit(1)

    # クライアント初期化
    yt = YouTubeClient(youtube_api_key)
    sb = init_client(supabase_url, supabase_key)

    # 今日処理するtopicIdグループを取得
    today_topics = get_today_topics(sb)
    logger.info(f"Today's topics: {len(today_topics)} topic(s)")

    total_videos = 0
    total_channels = 0

    for topic_id in today_topics:
        logger.info(f"--- Processing topic: {topic_id} ---")

        try:
            # 1. search.list で動画IDを取得（再生数順 + 新着順）
            topic_info = TOPIC_IDS.get(topic_id, {})
            query = topic_info.get("name")
            video_ids_popular = yt.search_videos_by_topic(topic_id, order="viewCount", query=query)
            video_ids_recent = yt.search_videos_by_topic(topic_id, order="date", query=query)
        except QuotaExceededError:
            logger.warning("Quota exceeded — stopping collection early")
            break

        # 重複を除いて結合
        all_video_ids = list(dict.fromkeys(video_ids_popular + video_ids_recent))
        if not all_video_ids:
            logger.warning(f"No videos found for {topic_id}")
            log_collection(sb, topic_id, 0, 0, yt.quota_used)
            continue

        # 2. videos.list で詳細取得
        videos = yt.get_video_details(all_video_ids)

        # 3. ユニークなchannel_idを抽出してchannels.list
        channel_ids = list({v["channel_id"] for v in videos if v.get("channel_id")})
        channels = yt.get_channel_details(channel_ids)

        # 4. Supabase に書き込み（チャンネルを先に入れて外部キー制約を満たす）
        n_channels = upsert_channels(sb, channels)
        n_videos = upsert_videos(sb, videos)

        total_videos += n_videos
        total_channels += n_channels

        # 5. 収集ログ記録
        log_collection(sb, topic_id, n_videos, n_channels, yt.quota_used)

        # 統計表示
        stats = compute_collection_stats(videos, channels)
        logger.info(f"Topic {topic_id} stats: {stats}")

    # 6. 古いスナップショット削除（容量管理）
    cleanup_old_snapshots(sb)

    logger.info(
        f"Collection complete. "
        f"Total: {total_videos} videos, {total_channels} channels. "
        f"Quota used: {yt.quota_used}"
    )


if __name__ == "__main__":
    main()
