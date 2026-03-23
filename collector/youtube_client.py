"""YouTube Data API v3 ラッパー"""

import logging
from datetime import datetime, timedelta, timezone

import isodate
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

from topic_ids import AI_KEYWORDS

logger = logging.getLogger(__name__)


class QuotaExceededError(Exception):
    """YouTube API クオータ超過"""
    pass


class YouTubeClient:
    def __init__(self, api_key: str):
        self.youtube = build("youtube", "v3", developerKey=api_key)
        self.quota_used = 0

    def search_videos_by_topic(self, topic_id: str, max_results: int = 50,
                                order: str = "viewCount",
                                query: str | None = None) -> list[str]:
        """キーワード検索で動画IDリストを取得（search.list: 100 quota units）

        topicId は YouTube API で結果が返らなくなっているため、
        query（トピック名）によるキーワード検索を使用する。
        """
        published_after = (datetime.now(timezone.utc) - timedelta(days=30)).isoformat()

        try:
            params = dict(
                part="snippet",
                type="video",
                order=order,
                regionCode="JP",
                maxResults=max_results,
                publishedAfter=published_after,
            )

            # topicId は機能しないため、直接キーワード検索を使用
            if query:
                params["q"] = query
            else:
                params["topicId"] = topic_id

            response = self.youtube.search().list(**params).execute()
            self.quota_used += 100

            video_ids = [item["id"]["videoId"] for item in response.get("items", [])]
            logger.info(f"search.list topic={topic_id} order={order}: {len(video_ids)} videos")
            return video_ids

        except HttpError as e:
            if e.resp.status == 403 and "quotaExceeded" in str(e):
                logger.error(f"YouTube API quota exceeded at {self.quota_used} units")
                raise QuotaExceededError(f"Quota exceeded after {self.quota_used} units")
            logger.error(f"search.list failed for {topic_id}: {e}")
            return []
        except Exception as e:
            logger.error(f"search.list failed for {topic_id}: {e}")
            return []

    def get_video_details(self, video_ids: list[str]) -> list[dict]:
        """動画の詳細情報を取得（videos.list: 1 quota unit per call）"""
        results = []
        # 50件ずつバッチ処理
        for i in range(0, len(video_ids), 50):
            batch = video_ids[i:i + 50]
            try:
                response = self.youtube.videos().list(
                    part="snippet,statistics,contentDetails,topicDetails",
                    id=",".join(batch),
                ).execute()
                self.quota_used += 1

                for item in response.get("items", []):
                    results.append(self._parse_video(item))

            except Exception as e:
                logger.error(f"videos.list failed for batch starting at {i}: {e}")

        logger.info(f"Fetched details for {len(results)} videos")
        return results

    def get_channel_details(self, channel_ids: list[str]) -> list[dict]:
        """チャンネルの詳細情報を取得（channels.list: 1 quota unit per call）"""
        results = []
        for i in range(0, len(channel_ids), 50):
            batch = channel_ids[i:i + 50]
            try:
                response = self.youtube.channels().list(
                    part="snippet,statistics,topicDetails",
                    id=",".join(batch),
                ).execute()
                self.quota_used += 1

                for item in response.get("items", []):
                    results.append(self._parse_channel(item))

            except Exception as e:
                logger.error(f"channels.list failed for batch starting at {i}: {e}")

        logger.info(f"Fetched details for {len(results)} channels")
        return results

    def _parse_video(self, item: dict) -> dict:
        """YouTube API レスポンスから動画データを整形"""
        snippet = item.get("snippet", {})
        stats = item.get("statistics", {})
        content = item.get("contentDetails", {})
        topic_details = item.get("topicDetails", {})

        # ISO 8601 duration → 秒
        duration_seconds = 0
        if content.get("duration"):
            try:
                duration_seconds = int(isodate.parse_duration(content["duration"]).total_seconds())
            except Exception:
                pass

        # topic_ids 抽出
        topic_ids = []
        for url in topic_details.get("topicIds", []):
            topic_ids.append(url)
        # topicCategories からは Wikipedia URL が返る
        topic_categories = topic_details.get("topicCategories", [])

        # AI キーワード検出
        title = snippet.get("title", "")
        description = snippet.get("description", "")
        tags = snippet.get("tags", [])
        searchable = f"{title} {description} {' '.join(tags)}".lower()
        has_ai = any(kw.lower() in searchable for kw in AI_KEYWORDS)

        return {
            "id": item["id"],
            "channel_id": snippet.get("channelId"),
            "title": title,
            "published_at": snippet.get("publishedAt"),
            "duration_seconds": duration_seconds,
            "category_id": int(snippet.get("categoryId", 0)) or None,
            "topic_ids": topic_ids if topic_ids else [],
            "tags": tags if tags else None,
            "default_language": snippet.get("defaultLanguage"),
            "has_ai_keywords": has_ai,
            "view_count": int(stats.get("viewCount", 0)),
            "like_count": int(stats.get("likeCount", 0)),
            "comment_count": int(stats.get("commentCount", 0)),
        }

    def _parse_channel(self, item: dict) -> dict:
        """YouTube API レスポンスからチャンネルデータを整形"""
        snippet = item.get("snippet", {})
        stats = item.get("statistics", {})
        topic_details = item.get("topicDetails", {})

        topic_ids = topic_details.get("topicIds", [])
        topic_categories = topic_details.get("topicCategories", [])

        return {
            "id": item["id"],
            "title": snippet.get("title"),
            "published_at": snippet.get("publishedAt"),
            "country": snippet.get("country"),
            "topic_ids": topic_ids if topic_ids else [],
            "topic_categories": topic_categories if topic_categories else None,
            "subscriber_count": int(stats.get("subscriberCount", 0)),
            "view_count": int(stats.get("viewCount", 0)),
            "video_count": int(stats.get("videoCount", 0)),
        }
