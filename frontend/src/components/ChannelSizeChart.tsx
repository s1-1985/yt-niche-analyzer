import { useState } from 'react';
import {
  BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid, Legend,
} from 'recharts';
import { useIsMobile } from '../hooks/useIsMobile';
import { HelpButton, HELP_TEXTS } from './HelpButton';
import type { TopicChannelSize } from '../types/database';

interface Props {
  data: TopicChannelSize[];
  onTopicClick?: (topicId: string) => void;
}

interface ChartEntry {
  name: string;
  small_pct: number;
  medium_pct: number;
  large_pct: number;
  mega_pct: number;
  total: number;
  topic_id: string;
}

type SizeZone = 'all' | 'small' | 'medium' | 'large' | 'mega';

const ZONE_LABELS: Record<SizeZone, string> = {
  all: '全体',
  small: '~1K登録',
  medium: '1K~10K',
  large: '10K~100K',
  mega: '100K~',
};

function truncate(s: string, max: number): string {
  return s.length > max ? s.slice(0, max) + '…' : s;
}

export function ChannelSizeChart({ data, onTopicClick }: Props) {
  const isMobile = useIsMobile();
  const [selectedZone, setSelectedZone] = useState<SizeZone>('all');
  const subTopics = data.filter((d) => d.parent_id !== null);
  const itemCount = isMobile ? 10 : 25;

  const sorted = [...subTopics]
    .sort((a, b) => b.small_pct - a.small_pct)
    .slice(0, itemCount);

  const chartData: ChartEntry[] = sorted.map((d) => ({
    name: d.name_ja ?? d.topic_name,
    small_pct: d.small_pct,
    medium_pct: d.medium_pct,
    large_pct: d.large_pct,
    mega_pct: d.mega_pct,
    total: d.total_channels,
    topic_id: d.topic_id,
  }));

  // Zone-specific ranking
  const getZoneRanking = () => {
    if (selectedZone === 'all') return null;
    const getPct = (d: TopicChannelSize): number => {
      switch (selectedZone) {
        case 'small': return d.small_pct;
        case 'medium': return d.medium_pct;
        case 'large': return d.large_pct;
        case 'mega': return d.mega_pct;
        default: return 0;
      }
    };
    const getCount = (d: TopicChannelSize): number => {
      switch (selectedZone) {
        case 'small': return d.small_count;
        case 'medium': return d.medium_count;
        case 'large': return d.large_count;
        case 'mega': return d.mega_count;
        default: return 0;
      }
    };
    return [...subTopics]
      .sort((a, b) => getPct(b) - getPct(a))
      .slice(0, 20)
      .map((d, i) => {
        const pct = getPct(d);
        const count = getCount(d);
        return (
          <div key={d.topic_id} className="ranking-row ranking-clickable"
            onClick={() => onTopicClick?.(d.topic_id)}>
            <span className="ranking-rank">{i + 1}</span>
            <span className="ranking-name">{isMobile && (d.name_ja ?? d.topic_name).length > 8
              ? (d.name_ja ?? d.topic_name).slice(0, 8) + '…'
              : (d.name_ja ?? d.topic_name)}</span>
            <div className="ranking-bar-wrap">
              <div className="ranking-bar" style={{ width: `${pct}%` }} />
            </div>
            <span className="ranking-value">{pct}%</span>
            <span className="ranking-sub">{count}ch</span>
          </div>
        );
      });
  };

  const chartHeight = isMobile ? itemCount * 36 + 40 : 500;
  const zoneRanking = getZoneRanking();

  return (
    <div className="chart-card">
      <div className="chart-title-row">
        <h3>チャンネル規模分布</h3>
        <HelpButton {...HELP_TEXTS.channelSize} />
      </div>
      <p className="chart-desc">
        小規模が多い = 新規参入しやすい。ゾーンをタップすると詳細ランキング
      </p>

      <div className="zone-selector">
        {(Object.entries(ZONE_LABELS) as [SizeZone, string][]).map(([zone, label]) => (
          <button key={zone}
            className={`zone-btn ${selectedZone === zone ? 'active' : ''}`}
            onClick={() => setSelectedZone(zone)}>
            {label}
          </button>
        ))}
      </div>

      {zoneRanking ? (
        <div className="ranking-list">
          <div className="ranking-header-row">
            <span className="ranking-h-rank">#</span>
            <span className="ranking-h-name">ジャンル</span>
            <span className="ranking-h-bar"></span>
            <span className="ranking-h-value">割合</span>
          </div>
          {zoneRanking}
        </div>
      ) : (
        <ResponsiveContainer width="100%" height={chartHeight}>
          <BarChart data={chartData} layout="vertical" margin={{ left: isMobile ? 10 : 100 }}>
            <CartesianGrid strokeDasharray="3 3" />
            <XAxis type="number" domain={[0, 100]} unit="%" tick={{ fontSize: isMobile ? 10 : 11 }} />
            <YAxis type="category" dataKey="name" width={isMobile ? 60 : 90}
              tick={{ fontSize: isMobile ? 10 : 12 }}
              tickFormatter={(v) => truncate(v, isMobile ? 6 : 20)} />
            <Tooltip
              content={({ payload }) => {
                if (!payload?.length) return null;
                const d = payload[0].payload as ChartEntry;
                return (
                  <div className="custom-tooltip">
                    <strong>{d.name}</strong>
                    <div>全{d.total}チャンネル</div>
                    <div style={{ marginTop: 4, fontSize: '0.75rem' }}>
                      <div>~1K: {d.small_pct}%</div>
                      <div>1K~10K: {d.medium_pct}%</div>
                      <div>10K~100K: {d.large_pct}%</div>
                      <div>100K~: {d.mega_pct}%</div>
                    </div>
                    <div className="tooltip-hint">クリックで詳細</div>
                  </div>
                );
              }}
            />
            <Legend wrapperStyle={isMobile ? { fontSize: '0.65rem' } : undefined} />
            <Bar dataKey="small_pct" stackId="a" fill="#10b981" name="~1K" />
            <Bar dataKey="medium_pct" stackId="a" fill="#6366f1" name="1K~10K" />
            <Bar dataKey="large_pct" stackId="a" fill="#f59e0b" name="10K~100K" />
            <Bar dataKey="mega_pct" stackId="a" fill="#ef4444" name="100K~"
              radius={[0, 4, 4, 0]} cursor="pointer"
              onClick={(entry: unknown) => onTopicClick?.((entry as ChartEntry).topic_id)} />
          </BarChart>
        </ResponsiveContainer>
      )}
    </div>
  );
}
