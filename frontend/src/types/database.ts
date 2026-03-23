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

export interface VideoRanking {
  id: string;
  title: string;
  channel_id: string;
  channel_title: string | null;
  published_at: string;
  duration_seconds: number;
  topic_ids: string[];
  has_ai_keywords: boolean;
  thumbnail_url: string | null;
  view_count: number;
  like_count: number;
  comment_count: number;
  channel_subscribers: number;
  buzz_score: number;
}

export interface ChannelRanking {
  id: string;
  title: string;
  published_at: string;
  country: string | null;
  topic_ids: string[];
  subscriber_count: number;
  view_count: number;
  video_count: number;
}

export interface CollectionLog {
  id: number;
  topic_id: string;
  collected_at: string;
  videos_collected: number;
  channels_collected: number;
  quota_used: number;
}

export interface TopicDurationStats {
  topic_id: string;
  topic_name: string;
  name_ja: string | null;
  parent_id: string | null;
  video_count: number;
  avg_duration: number;
  median_duration: number;
  p25_duration: number;
  p75_duration: number;
  short_count: number;
  medium_count: number;
  long_count: number;
}

export interface TopicChannelSize {
  topic_id: string;
  topic_name: string;
  name_ja: string | null;
  parent_id: string | null;
  total_channels: number;
  small_count: number;
  medium_count: number;
  large_count: number;
  mega_count: number;
  small_pct: number;
  medium_pct: number;
  large_pct: number;
  mega_pct: number;
}

export interface TopicPublishDay {
  topic_id: string;
  topic_name: string;
  name_ja: string | null;
  parent_id: string | null;
  dow: number;
  video_count: number;
  avg_views: number;
  total_views: number;
}

export interface ChannelGrowthEfficiency {
  channel_id: string;
  title: string;
  published_at: string;
  country: string | null;
  topic_ids: string[];
  subscriber_count: number;
  view_count: number;
  video_count: number;
  age_days: number;
  subs_per_day: number;
  views_per_video: number;
}

export interface TopicPopularTag {
  topic_id: string;
  topic_name: string;
  name_ja: string | null;
  tag: string;
  usage_count: number;
  avg_views: number;
  rank: number;
}

export interface TopicCountryDistribution {
  topic_id: string;
  topic_name: string;
  name_ja: string | null;
  parent_id: string | null;
  country: string;
  channel_count: number;
  total_subscribers: number;
}

export interface TopicOverlap {
  topic_a: string;
  name_a: string | null;
  topic_b: string;
  name_b: string | null;
  shared_channels: number;
}
