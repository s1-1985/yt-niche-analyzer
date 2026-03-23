import { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';
import type { TopicOverlap } from '../types/database';

interface Props {
  onTopicClick?: (topicId: string) => void;
}

export function TopicOverlapChart({ onTopicClick }: Props) {
  const [data, setData] = useState<TopicOverlap[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    supabase
      .from('topic_overlap')
      .select('*')
      .order('shared_channels', { ascending: false })
      .limit(30)
      .then(({ data: d }) => {
        setData((d as TopicOverlap[]) ?? []);
        setLoading(false);
      });
  }, []);

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
              <span className="overlap-connector">×</span>
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
