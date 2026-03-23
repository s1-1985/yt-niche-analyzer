import { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';
import { HelpButton, HELP_TEXTS } from './HelpButton';
import type { TopicPopularTag } from '../types/database';
import type { TimePeriod, VideoType } from '../hooks/useFilteredQuery';

interface Props {
  period: TimePeriod;
  videoType?: VideoType;
  onTagsLoaded?: (tags: TopicPopularTag[]) => void;
  onTopicClick?: (topicId: string) => void;
}

function getMinDate(period: TimePeriod): string | null {
  if (period === 'all') return null;
  const now = new Date();
  switch (period) {
    case '24h': now.setHours(now.getHours() - 24); break;
    case '1w': now.setDate(now.getDate() - 7); break;
    case '1m': now.setMonth(now.getMonth() - 1); break;
    case '3m': now.setMonth(now.getMonth() - 3); break;
  }
  return now.toISOString();
}

export function TopTagsChart({ period, videoType = 'all', onTagsLoaded, onTopicClick }: Props) {
  const [data, setData] = useState<TopicPopularTag[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedTopic, setSelectedTopic] = useState<string | null>(null);

  useEffect(() => {
    setLoading(true);
    const fetchData = async () => {
      let result;
      if (period === 'all' && videoType === 'all') {
        result = await supabase.from('topic_popular_tags').select('*')
          .order('topic_id').order('rank');
      } else {
        const minDate = getMinDate(period);
        result = await supabase.rpc('fn_topic_popular_tags', {
          p_min_date: minDate, p_video_type: videoType,
        });
      }
      const d = (result.data as TopicPopularTag[]) ?? [];
      setData(d);
      onTagsLoaded?.(d);
      setLoading(false);
    };
    fetchData();
  }, [period, videoType]);

  if (loading) return null;
  if (data.length === 0) return null;

  const topicMap = new Map<string, string>();
  for (const row of data) {
    if (!topicMap.has(row.topic_id)) {
      topicMap.set(row.topic_id, row.name_ja ?? row.topic_name);
    }
  }
  const topics = Array.from(topicMap.entries());
  const activeTopic = selectedTopic ?? topics[0]?.[0] ?? null;
  const tags = data.filter((d) => d.topic_id === activeTopic);

  return (
    <div className="chart-card">
      <div className="chart-title-row">
        <h3>人気タグ TOP10</h3>
        <HelpButton {...HELP_TEXTS.topTags} />
      </div>
      <p className="chart-desc">
        ジャンル別の頻出タグ。動画投稿時にどんなタグをつけるべきかの参考に
      </p>
      <div className="tag-topic-selector">
        {topics.map(([id, name]) => (
          <button key={id}
            className={`tag-topic-btn ${id === activeTopic ? 'active' : ''}`}
            onClick={() => setSelectedTopic(id)}>
            {name}
          </button>
        ))}
      </div>
      <div className="tag-list">
        {tags.map((t) => (
          <div key={t.tag} className="tag-item">
            <span className="tag-rank">#{t.rank}</span>
            <span className="tag-name">{t.tag}</span>
            <div className="tag-bar-wrap">
              <div className="tag-bar"
                style={{ width: `${Math.min(100, (t.usage_count / (tags[0]?.usage_count || 1)) * 100)}%` }} />
            </div>
            <span className="tag-count">{t.usage_count}回</span>
            <span className="tag-views">{t.avg_views.toLocaleString()}再生</span>
          </div>
        ))}
        {tags.length === 0 && <p className="empty-msg">このジャンルのタグデータがありません</p>}
      </div>
      {activeTopic && (
        <button className="tag-detail-btn" onClick={() => onTopicClick?.(activeTopic)}>
          このジャンルの動画を見る →
        </button>
      )}
    </div>
  );
}
