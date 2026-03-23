"""Supabase 書き込みロジック"""

import logging
from datetime import date

from supabase import create_client, Client

logger = logging.getLogger(__name__)


def init_client(url: str, service_role_key: str) -> Client:
    """Supabase クライアントを初期化（service_role キーで書き込み権限あり）"""
    return create_client(url, service_role_key)


def upsert_channels(client: Client, channels: list[dict]) -> int:
    """チャンネル情報を upsert し、日次スナップショットを挿入"""
    if not channels:
        return 0

    # チャンネルマスタ upsert
    channel_rows = [
        {
            "id": ch["id"],
            "title": ch["title"],
            "published_at": ch["published_at"],
            "country": ch["country"],
            "topic_ids": ch["topic_ids"],
            "topic_categories": ch["topic_categories"],
        }
        for ch in channels
    ]
    client.table("channels").upsert(channel_rows, on_conflict="id").execute()

    # チャンネルスナップショット upsert
    today = date.today().isoformat()
    snapshot_rows = [
        {
            "channel_id": ch["id"],
            "snapshot_date": today,
            "subscriber_count": ch["subscriber_count"],
            "view_count": ch["view_count"],
            "video_count": ch["video_count"],
        }
        for ch in channels
    ]
    client.table("channel_snapshots").upsert(
        snapshot_rows, on_conflict="channel_id,snapshot_date"
    ).execute()

    logger.info(f"Upserted {len(channels)} channels + snapshots")
    return len(channels)


def upsert_videos(client: Client, videos: list[dict]) -> int:
    """動画情報を upsert し、日次スナップショットを挿入"""
    if not videos:
        return 0

    # 動画マスタ upsert
    video_rows = [
        {
            "id": v["id"],
            "channel_id": v["channel_id"],
            "title": v["title"],
            "published_at": v["published_at"],
            "duration_seconds": v["duration_seconds"],
            "category_id": v["category_id"],
            "topic_ids": v["topic_ids"],
            "tags": v["tags"],
            "default_language": v["default_language"],
            "has_ai_keywords": v["has_ai_keywords"],
            "thumbnail_url": v.get("thumbnail_url"),
        }
        for v in videos
    ]
    client.table("videos").upsert(video_rows, on_conflict="id").execute()

    # 動画スナップショット upsert
    today = date.today().isoformat()
    snapshot_rows = [
        {
            "video_id": v["id"],
            "snapshot_date": today,
            "view_count": v["view_count"],
            "like_count": v["like_count"],
            "comment_count": v["comment_count"],
        }
        for v in videos
    ]
    client.table("video_snapshots").upsert(
        snapshot_rows, on_conflict="video_id,snapshot_date"
    ).execute()

    logger.info(f"Upserted {len(videos)} videos + snapshots")
    return len(videos)


def cleanup_old_snapshots(client: Client):
    """30日以上前のスナップショットを最新のみ残して削除（容量管理）"""
    cleanup_sql = """
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
    """
    try:
        client.rpc("cleanup_old_snapshots", {}).execute()
        logger.info("Old snapshots cleanup completed")
    except Exception:
        # RPC が未定義の場合は直接SQLで実行を試みる
        # Supabase の REST API では直接 SQL を実行できないため、
        # setup.sql に RPC 関数を定義しておく必要がある
        logger.warning(
            "cleanup_old_snapshots RPC not found. "
            "Please add the cleanup function to setup.sql"
        )
