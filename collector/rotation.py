"""ジャンルローテーション管理

全topicIdを3グループに分割し、毎日1グループを処理（3日で全ジャンル1巡）。
collection_log テーブルで最後に収集した日時を管理し、最も古いグループから優先的に処理する。
"""

import logging
from topic_ids import TOPIC_IDS

logger = logging.getLogger(__name__)

# 全topicIdを3グループに分割
def _build_groups():
    all_ids = list(TOPIC_IDS.keys())
    group_size = len(all_ids) // 3
    return [
        all_ids[:group_size],
        all_ids[group_size:group_size * 2],
        all_ids[group_size * 2:],
    ]

TOPIC_GROUPS = _build_groups()


def get_today_topics(supabase_client) -> list[str]:
    """collection_logから最も古いグループを特定し、今日処理すべきtopicIdリストを返す"""
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

        # 各グループの「最古の収集日」を計算
        group_scores = []
        for i, group in enumerate(TOPIC_GROUPS):
            dates = [last_collected.get(tid) for tid in group]
            # 未収集のtopicが含まれるグループを最優先
            if any(d is None for d in dates):
                group_scores.append((i, ""))
            else:
                oldest = min(d for d in dates if d is not None)
                group_scores.append((i, oldest))

        # 最も古い（または未収集）グループを選択
        group_scores.sort(key=lambda x: x[1])
        selected_group_idx = group_scores[0][0]
        selected_topics = TOPIC_GROUPS[selected_group_idx]

        logger.info(
            f"Selected group {selected_group_idx + 1}/{len(TOPIC_GROUPS)} "
            f"with {len(selected_topics)} topics"
        )
        return selected_topics

    except Exception as e:
        logger.warning(f"Failed to determine rotation, falling back to group 0: {e}")
        return TOPIC_GROUPS[0]


def log_collection(supabase_client, topic_id: str, videos_collected: int,
                   channels_collected: int, quota_used: int):
    """収集結果をcollection_logに記録"""
    supabase_client.table("collection_log").insert({
        "topic_id": topic_id,
        "videos_collected": videos_collected,
        "channels_collected": channels_collected,
        "quota_used": quota_used,
    }).execute()
