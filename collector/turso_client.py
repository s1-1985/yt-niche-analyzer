"""Turso 書き込みロジック（supabase_client.py の Turso 版）

collector の dual-write で使用。Supabase 書き込みと並行して Turso にも書く。
Turso 書き込みは non-critical — 失敗してもコレクター全体は継続する。
"""

import logging
from datetime import date, datetime, timezone

logger = logging.getLogger(__name__)

_BATCH_SIZE = 200  # 1 回の HTTP リクエストに含める SQL 文数


def init_turso_client(url: str, auth_token: str):
    """Turso (LibSQL) 同期クライアントを初期化する。

    スキーマは FK 制約なし（turso/schema.sql 参照）。PRAGMA foreign_keys は
    接続単位の設定でステートレスな HTTP API では信頼できないため使わない。
    """
    import libsql_client  # type: ignore
    # libsql:// は WebSocket(WSS)を使い 400 になるため https:// に変換して HTTP API を使う
    http_url = url.replace("libsql://", "https://")
    return libsql_client.create_client_sync(url=http_url, auth_token=auth_token)


def _batch(client, stmts: list) -> None:
    """stmts を _BATCH_SIZE ずつに分割して client.batch() で送信する。"""
    import libsql_client  # type: ignore
    for i in range(0, len(stmts), _BATCH_SIZE):
        chunk = [
            libsql_client.Statement(s[0], s[1]) if isinstance(s, tuple) else s
            for s in stmts[i : i + _BATCH_SIZE]
        ]
        client.batch(chunk)


def upsert_channels_turso(client, channels: list[dict]) -> int:
    """チャンネルマスタ・channel_topics・channel_snapshots を upsert する。"""
    if not channels:
        return 0

    today = date.today().isoformat()
    stmts: list = []

    for ch in channels:
        stmts.append((
            "INSERT OR REPLACE INTO channels (id, title, published_at, country)"
            " VALUES (?, ?, ?, ?)",
            [ch["id"], ch.get("title"), ch.get("published_at"), ch.get("country")],
        ))
        for tid in (ch.get("topic_ids") or []):
            stmts.append((
                "INSERT OR IGNORE INTO channel_topics (channel_id, topic_id) VALUES (?, ?)",
                [ch["id"], tid],
            ))
        stmts.append((
            "INSERT OR REPLACE INTO channel_snapshots"
            " (channel_id, snapshot_date, subscriber_count, view_count, video_count)"
            " VALUES (?, ?, ?, ?, ?)",
            [ch["id"], today,
             ch.get("subscriber_count"), ch.get("view_count"), ch.get("video_count")],
        ))

    _batch(client, stmts)
    logger.info(f"Turso: upserted {len(channels)} channels")
    return len(channels)


def upsert_videos_turso(client, videos: list[dict]) -> int:
    """動画マスタ・video_topics・video_tags・video_snapshots を upsert する。"""
    if not videos:
        return 0

    today = date.today().isoformat()
    stmts: list = []

    for v in videos:
        stmts.append((
            "INSERT OR REPLACE INTO videos"
            " (id, channel_id, title, published_at, duration_seconds,"
            "  category_id, default_language, has_ai_keywords, thumbnail_url)"
            " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [
                v["id"], v["channel_id"], v.get("title"), v.get("published_at"),
                v.get("duration_seconds"), v.get("category_id"),
                v.get("default_language"),
                1 if v.get("has_ai_keywords") else 0,
                v.get("thumbnail_url"),
            ],
        ))
        for tid in (v.get("topic_ids") or []):
            stmts.append((
                "INSERT OR IGNORE INTO video_topics (video_id, topic_id) VALUES (?, ?)",
                [v["id"], tid],
            ))
        for tag in (v.get("tags") or []):
            stmts.append((
                "INSERT OR IGNORE INTO video_tags (video_id, tag) VALUES (?, ?)",
                [v["id"], tag],
            ))
        stmts.append((
            "INSERT OR REPLACE INTO video_snapshots"
            " (video_id, snapshot_date, view_count, like_count, comment_count)"
            " VALUES (?, ?, ?, ?, ?)",
            [v["id"], today,
             v.get("view_count"), v.get("like_count"), v.get("comment_count")],
        ))

    _batch(client, stmts)
    logger.info(f"Turso: upserted {len(videos)} videos")
    return len(videos)


def log_collection_turso(client, topic_id: str,
                          videos_collected: int, channels_collected: int,
                          quota_used: int) -> None:
    """収集結果を collection_log に記録する。"""
    import libsql_client  # type: ignore
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
    try:
        client.execute(libsql_client.Statement(
            "INSERT INTO collection_log"
            " (topic_id, collected_at, videos_collected, channels_collected, quota_used)"
            " VALUES (?, ?, ?, ?, ?)",
            [topic_id, now, videos_collected, channels_collected, quota_used],
        ))
    except Exception as e:
        logger.warning(f"Turso: log_collection failed: {e}")
