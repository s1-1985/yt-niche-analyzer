"""ジャンルローテーション管理

全topicIdを「最終収集日が古い順」にソートし、
クォータ上限まで可能な限り多くのトピックを処理する。
collection_log テーブルで最後に収集した日時を管理する。
"""

import logging
from topic_ids import TOPIC_IDS

logger = logging.getLogger(__name__)

# 1トピックあたりの概算クォータ消費: search×2(200) + videos(2) + channels(2) ≈ 204
QUOTA_PER_TOPIC = 210  # 余裕を持たせた見積もり
DAILY_QUOTA_LIMIT = 9500  # 10,000の95%を安全上限とする


def get_today_topics(supabase_client) -> list[str]:
    """collection_logから最終収集日が古い順にトピックを返す（全トピック対象）。
    呼び出し側がクォータ超過で停止するまで順に処理する。"""
    all_topic_ids = list(TOPIC_IDS.keys())

    try:
        # 各topicIdの最終収集日を取得
        result = supabase_client.table("collection_log") \
            .select("topic_id, collected_at") \
            .order("collected_at", desc=True) \
            .execute()

        last_collected = {}
        for row in result.data:
            tid = row["topic_id"]
            if tid not in last_collected:
                last_collected[tid] = row["collected_at"]

        # 未収集トピックを最優先、次に最終収集日が古い順
        def sort_key(tid):
            ts = last_collected.get(tid)
            if ts is None:
                return ""  # 未収集 = 最優先
            return ts

        all_topic_ids.sort(key=sort_key)

        uncollected = sum(1 for tid in all_topic_ids if tid not in last_collected)
        max_processable = DAILY_QUOTA_LIMIT // QUOTA_PER_TOPIC

        logger.info(
            f"Total topics: {len(all_topic_ids)}, "
            f"uncollected: {uncollected}, "
            f"max processable today: {max_processable}"
        )

        return all_topic_ids

    except Exception as e:
        logger.warning(f"Failed to determine rotation order: {e}")
        return all_topic_ids


def log_collection(supabase_client, topic_id: str, videos_collected: int,
                   channels_collected: int, quota_used: int):
    """収集結果をcollection_logに記録"""
    supabase_client.table("collection_log").insert({
        "topic_id": topic_id,
        "videos_collected": videos_collected,
        "channels_collected": channels_collected,
        "quota_used": quota_used,
    }).execute()
