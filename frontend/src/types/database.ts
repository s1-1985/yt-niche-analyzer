export interface TopicSummary {
  topic_id: string;
  topic_name: string;
  name_ja: string | null;
  parent_id: string | null;
  category: string;
  total_videos: number;
  total_channels: number;
  total_views: number;
  avg_views: number;
  gap_score: number;
  like_rate_pct: number;
  comment_rate_pct: number;
}

export interface OutlierChannel {
  id: string;
  title: string;
  published_at: string;
  topic_ids: string[];
  subscriber_count: number;
  view_count: number;
  views_to_sub_ratio: number;
  percentile: number;
}

export interface NewChannelSuccessRate {
  topic_id: string;
  topic_name: string;
  name_ja: string | null;
  new_channel_count: number;
  successful_count: number;
  success_rate_pct: number;
}

export interface CompetitionConcentration {
  topic_id: string;
  topic_name: string;
  name_ja: string | null;
  topic_total_views: number;
  top5_views: number;
  top5_share_pct: number;
}

export interface AiPenetration {
  topic_id: string;
  topic_name: string;
  name_ja: string | null;
  total_videos: number;
  ai_video_count: number;
  ai_penetration_pct: number;
}

export interface CollectionLog {
  id: number;
  topic_id: string;
  collected_at: string;
  videos_collected: number;
  channels_collected: number;
  quota_used: number;
}
