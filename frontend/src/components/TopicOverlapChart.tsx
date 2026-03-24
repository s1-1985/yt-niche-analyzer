import { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';
import { HelpButton, HELP_TEXTS } from './HelpButton';
import type { TopicOverlap } from '../types/database';
import type { TimePeriod, VideoType } from '../hooks/useFilteredQuery';

interface Props {
  period: TimePeriod;
  videoType?: VideoType;
  country?: string | null;
  onOverlapLoaded?: (data: TopicOverlap[]) => void;
  onTopicClick?: (topicId: string) => void;
  onOverlapClick?: (topicA: string, topicB: string) => void;
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

export function TopicOverlapChart({ period, videoType = 'all', country = null, onOverlapLoaded, onTopicClick, onOverlapClick }: Props) {
  const [data, setData] = useState<TopicOverlap[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    const fetchData = async () => {
      let result;
      if (period === 'all' && videoType === 'all' && country === null) {
        result = await supabase.from('topic_overlap').select('*')
          .order('shared_channels', { ascending: false }).limit(30);
      } else {
        const minDate = getMinDate(period);
        result = await supabase.rpc('fn_topic_overlap', {
          p_min_date: minDate, p_video_type: videoType, p_country: country,
        });
      }
      if (cancelled) return;
      const d = ((result.data as TopicOverlap[]) ?? [])
        .sort((a, b) => b.shared_channels - a.shared_channels).slice(0, 30);
      setData(d);
      onOverlapLoaded?.(d);
      setLoading(false);
    };
    fetchData();
    return () => { cancelled = true; };
  }, [period, videoType, country]);

  if (loading) return null;
  if (data.length === 0) return null;

  return (
    <div className="chart-card">
      <div className="chart-title-row">
        <h3>ジャンル相関マップ</h3>
        <HelpButton {...HELP_TEXTS.topicOverlap} />
      </div>
      <p className="chart-desc">
        チャンネルが重複しているジャンルの組み合わせ。組み合わせをタップで両ジャンルの動画を表示。個別ジャンル名をタップでそのジャンルの詳細へ
      </p>
      <div className="overlap-list-simple">
        {data.map((row, i) => (
          <div key={i} className="overlap-row">
            <span className="overlap-rank">#{i + 1}</span>
            <div className="overlap-names">
              <button className="overlap-topic" onClick={(e) => { e.stopPropagation(); onTopicClick?.(row.topic_a); }}>
                {row.name_a}
              </button>
              <span className="overlap-x">×</span>
              <button className="overlap-topic" onClick={(e) => { e.stopPropagation(); onTopicClick?.(row.topic_b); }}>
                {row.name_b}
              </button>
            </div>
            <button
              className="overlap-combo-btn"
              onClick={() => onOverlapClick?.(row.topic_a, row.topic_b)}
              title={`${row.name_a} × ${row.name_b} の動画を表示`}
            >
              両方
            </button>
            <span className="overlap-ch">{row.shared_channels}ch</span>
          </div>
        ))}
      </div>
    </div>
  );
}
