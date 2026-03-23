import { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';
import type { TopicOverlap } from '../types/database';
import type { TimePeriod } from '../hooks/useFilteredQuery';

interface Props {
  period: TimePeriod;
  onOverlapLoaded?: (data: TopicOverlap[]) => void;
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

export function TopicOverlapChart({ period, onOverlapLoaded, onTopicClick }: Props) {
  const [data, setData] = useState<TopicOverlap[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    setLoading(true);
    const fetchData = async () => {
      let result;
      if (period === 'all') {
        result = await supabase
          .from('topic_overlap')
          .select('*')
          .order('shared_channels', { ascending: false })
          .limit(30);
      } else {
        const minDate = getMinDate(period);
        result = await supabase.rpc('fn_topic_overlap', { p_min_date: minDate });
      }
      const d = ((result.data as TopicOverlap[]) ?? [])
        .sort((a, b) => b.shared_channels - a.shared_channels)
        .slice(0, 30);
      setData(d);
      onOverlapLoaded?.(d);
      setLoading(false);
    };
    fetchData();
  }, [period]);

  if (loading) return null;
  if (data.length === 0) return null;

  const maxShared = data[0]?.shared_channels ?? 1;

  return (
    <div className="chart-card">
      <h3>ジャンル相関マップ</h3>
      <p className="chart-desc">
        チャンネルが重複しているジャンルの組み合わせ。隣接ニッチを見つけてクロス展開戦略に活用
      </p>
      <div className="overlap-list">
        {data.map((row, i) => (
          <div key={i} className="overlap-item">
            <div className="overlap-pair">
              <button
                className="overlap-topic"
                onClick={() => onTopicClick?.(row.topic_a)}
              >
                {row.name_a}
              </button>
              <span className="overlap-connector">x</span>
              <button
                className="overlap-topic"
                onClick={() => onTopicClick?.(row.topic_b)}
              >
                {row.name_b}
              </button>
            </div>
            <div className="overlap-bar-wrap">
              <div
                className="overlap-bar"
                style={{ width: `${(row.shared_channels / maxShared) * 100}%` }}
              />
            </div>
            <span className="overlap-count">{row.shared_channels}ch</span>
          </div>
        ))}
      </div>
    </div>
  );
}
