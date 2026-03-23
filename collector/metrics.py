"""スコア計算（需給ギャップ等）

主要な分析指標はDBビュー側で計算するが、
収集時に必要な前処理はここで行う。
"""

import logging
from topic_ids import AI_KEYWORDS

logger = logging.getLogger(__name__)


def detect_ai_keywords(title: str, description: str, tags: list[str]) -> bool:
    """動画のタイトル・説明・タグからAI関連キーワードを検出"""
    searchable = f"{title} {description} {' '.join(tags or [])}".lower()
    return any(kw.lower() in searchable for kw in AI_KEYWORDS)


def compute_collection_stats(videos: list[dict], channels: list[dict]) -> dict:
    """収集結果のサマリー統計を計算"""
    ai_count = sum(1 for v in videos if v.get("has_ai_keywords"))
    total_views = sum(v.get("view_count", 0) for v in videos)

    return {
        "total_videos": len(videos),
        "total_channels": len(channels),
        "ai_video_count": ai_count,
        "ai_ratio": ai_count / len(videos) if videos else 0,
        "total_views": total_views,
        "avg_views": total_views // len(videos) if videos else 0,
    }
