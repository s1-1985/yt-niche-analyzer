"""Supabase → Turso 一回限り移行スクリプト

使い方:
  cd yt-niche-analyzer
  pip install supabase libsql-client
  SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \
  TURSO_DATABASE_URL=... TURSO_AUTH_TOKEN=... \
  python turso/sync.py

処理順（依存順）:
  topics → channels → channel_topics
  → videos → video_topics → video_tags
  → video_snapshots(90日) → channel_snapshots(90日)

所要時間目安: 140k動画・85万タグ で 15〜30分程度（ネットワーク次第）。
再実行は安全（INSERT OR REPLACE / INSERT OR IGNORE）。
"""

import logging
import os
import sys
from datetime import date, timedelta
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)

PAGE = 1000   # Supabase ページサイズ
BATCH = 500   # Turso 1リクエストの SQL 文数

# DROP 順（子→親の順。FK は無いが念のため依存の逆順）
ALL_TABLES = [
    "collection_log",
    "video_snapshots", "channel_snapshots",
    "video_tags", "video_topics", "channel_topics",
    "videos", "channels", "topics",
]


# ── helpers ──────────────────────────────────────────────────

def _paginate(sb, table: str, select: str = "*", order=("id",), extra=None):
    """Supabase テーブルをページ単位で全行読む（ジェネレータ）。

    ORDER BY を必ず付ける: 順序なし OFFSET ページングは Postgres では
    行の取りこぼし・重複が起きうる。
    """
    offset = 0
    while True:
        q = sb.table(table).select(select)
        for col in order:
            q = q.order(col)
        q = q.range(offset, offset + PAGE - 1)
        if extra:
            q = extra(q)
        rows = q.execute().data
        if not rows:
            break
        logger.info(f"  {table}: fetched rows {offset}–{offset + len(rows) - 1}")
        yield from rows
        if len(rows) < PAGE:
            break
        offset += PAGE


def _run(client, stmts: list, label: str = "") -> None:
    import libsql_client  # type: ignore
    total = len(stmts)
    for i in range(0, total, BATCH):
        chunk = [
            libsql_client.Statement(s[0], s[1]) if isinstance(s, tuple) else s
            for s in stmts[i : i + BATCH]
        ]
        client.batch(chunk)
        done = min(i + BATCH, total)
        # 大きいテーブル（タグ85万件等）で沈黙しないよう 5万件ごとに進捗を出す
        if done % 50_000 < BATCH or done == total:
            logger.info(f"  {label or 'stmts'}: pushed {done}/{total}")


# ── schema ────────────────────────────────────────────────────

def apply_schema(client) -> None:
    # 旧テーブルは FK 制約付きで作成済みの可能性がある。SQLite は FK を後から
    # 外せず CREATE TABLE IF NOT EXISTS も既存を置き換えないため、必ず DROP する。
    # （データは直後に Supabase から全量再投入されるので安全）
    for t in ALL_TABLES:
        client.execute(f"DROP TABLE IF EXISTS {t}")
    logger.info("Old tables dropped.")

    schema = (Path(__file__).parent / "schema.sql").read_text()
    stmts = [s.strip() for s in schema.split(";") if s.strip()]
    for stmt in stmts:
        client.execute(stmt)
    logger.info("Schema applied.")


# ── sync functions ────────────────────────────────────────────

def sync_topics(sb, client) -> None:
    logger.info("Syncing topics…")
    stmts = []
    for row in _paginate(sb, "topics"):
        stmts.append((
            "INSERT OR REPLACE INTO topics (id, name, name_ja, category, parent_id)"
            " VALUES (?, ?, ?, ?, ?)",
            [row["id"], row["name"], row.get("name_ja"),
             row.get("category"), row.get("parent_id")],
        ))
    _run(client, stmts, "topics")
    logger.info(f"topics: {len(stmts)} rows synced.")


def sync_channels(sb, client) -> None:
    logger.info("Syncing channels + channel_topics…")
    ch_stmts: list = []
    ct_stmts: list = []

    for row in _paginate(sb, "channels"):
        ch_stmts.append((
            "INSERT OR REPLACE INTO channels (id, title, published_at, country)"
            " VALUES (?, ?, ?, ?)",
            [row["id"], row.get("title"), row.get("published_at"), row.get("country")],
        ))
        for tid in (row.get("topic_ids") or []):
            ct_stmts.append((
                "INSERT OR IGNORE INTO channel_topics (channel_id, topic_id) VALUES (?, ?)",
                [row["id"], tid],
            ))

    _run(client, ch_stmts, "channels")
    _run(client, ct_stmts, "channel_topics")
    logger.info(f"channels: {len(ch_stmts)} rows, channel_topics: {len(ct_stmts)} rows synced.")


def sync_videos(sb, client) -> None:
    logger.info("Syncing videos + video_topics + video_tags…")
    v_stmts: list = []
    vt_stmts: list = []
    vtag_stmts: list = []

    for row in _paginate(sb, "videos"):
        v_stmts.append((
            "INSERT OR REPLACE INTO videos"
            " (id, channel_id, title, published_at, duration_seconds,"
            "  category_id, default_language, has_ai_keywords, thumbnail_url)"
            " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [
                row["id"], row["channel_id"], row.get("title"), row.get("published_at"),
                row.get("duration_seconds"), row.get("category_id"),
                row.get("default_language"),
                1 if row.get("has_ai_keywords") else 0,
                row.get("thumbnail_url"),
            ],
        ))
        for tid in (row.get("topic_ids") or []):
            vt_stmts.append((
                "INSERT OR IGNORE INTO video_topics (video_id, topic_id) VALUES (?, ?)",
                [row["id"], tid],
            ))
        for tag in (row.get("tags") or []):
            vtag_stmts.append((
                "INSERT OR IGNORE INTO video_tags (video_id, tag) VALUES (?, ?)",
                [row["id"], tag],
            ))

    _run(client, v_stmts, "videos")
    logger.info(f"videos: {len(v_stmts)} rows synced.")
    _run(client, vt_stmts, "video_topics")
    logger.info(f"video_topics: {len(vt_stmts)} rows synced.")
    _run(client, vtag_stmts, "video_tags")
    logger.info(f"video_tags: {len(vtag_stmts)} rows synced.")


def sync_video_snapshots(sb, client, days: int = 90) -> None:
    cutoff = (date.today() - timedelta(days=days)).isoformat()
    logger.info(f"Syncing video_snapshots (since {cutoff})…")
    stmts: list = []

    def _filter(q):
        return q.gte("snapshot_date", cutoff)

    for row in _paginate(sb, "video_snapshots",
                         order=("video_id", "snapshot_date"), extra=_filter):
        stmts.append((
            "INSERT OR REPLACE INTO video_snapshots"
            " (video_id, snapshot_date, view_count, like_count, comment_count)"
            " VALUES (?, ?, ?, ?, ?)",
            [row["video_id"], row["snapshot_date"],
             row.get("view_count"), row.get("like_count"), row.get("comment_count")],
        ))
    _run(client, stmts, "video_snapshots")
    logger.info(f"video_snapshots: {len(stmts)} rows synced.")


def sync_channel_snapshots(sb, client, days: int = 90) -> None:
    cutoff = (date.today() - timedelta(days=days)).isoformat()
    logger.info(f"Syncing channel_snapshots (since {cutoff})…")
    stmts: list = []

    def _filter(q):
        return q.gte("snapshot_date", cutoff)

    for row in _paginate(sb, "channel_snapshots",
                         order=("channel_id", "snapshot_date"), extra=_filter):
        stmts.append((
            "INSERT OR REPLACE INTO channel_snapshots"
            " (channel_id, snapshot_date, subscriber_count, view_count, video_count)"
            " VALUES (?, ?, ?, ?, ?)",
            [row["channel_id"], row["snapshot_date"],
             row.get("subscriber_count"), row.get("view_count"), row.get("video_count")],
        ))
    _run(client, stmts, "channel_snapshots")
    logger.info(f"channel_snapshots: {len(stmts)} rows synced.")


# ── verify ────────────────────────────────────────────────────

def verify(client) -> None:
    """移行結果の件数を Turso 側で実測してログに残す。"""
    logger.info("--- Turso row counts ---")
    for t in ["topics", "channels", "channel_topics",
              "videos", "video_topics", "video_tags",
              "video_snapshots", "channel_snapshots"]:
        rs = client.execute(f"SELECT COUNT(*) FROM {t}")
        logger.info(f"  {t}: {rs.rows[0][0]} rows")


# ── main ──────────────────────────────────────────────────────

def main() -> None:
    supabase_url = os.environ.get("SUPABASE_URL")
    supabase_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    turso_url    = os.environ.get("TURSO_DATABASE_URL")
    turso_token  = os.environ.get("TURSO_AUTH_TOKEN")

    if not all([supabase_url, supabase_key, turso_url, turso_token]):
        logger.error(
            "Required env vars: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY,"
            " TURSO_DATABASE_URL, TURSO_AUTH_TOKEN"
        )
        sys.exit(1)

    from supabase import create_client
    import libsql_client  # type: ignore

    sb = create_client(supabase_url, supabase_key)
    # libsql:// は WebSocket(WSS)を使い 400 エラーになるため https:// に変換して HTTP API を使う
    http_url = turso_url.replace("libsql://", "https://")
    tc = libsql_client.create_client_sync(url=http_url, auth_token=turso_token)

    try:
        logger.info("=== Turso migration start ===")
        apply_schema(tc)
        sync_topics(sb, tc)
        sync_channels(sb, tc)
        sync_videos(sb, tc)
        sync_video_snapshots(sb, tc)
        sync_channel_snapshots(sb, tc)
        verify(tc)
        logger.info("=== Migration complete ===")
    finally:
        tc.close()


if __name__ == "__main__":
    main()
