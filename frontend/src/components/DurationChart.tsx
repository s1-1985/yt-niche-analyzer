import {
  BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid, Legend,
} from 'recharts';
import { useIsMobile } from '../hooks/useIsMobile';
import { HelpButton, HELP_TEXTS } from './HelpButton';
import type { TopicDurationStats } from '../types/database';

interface Props {
  data: TopicDurationStats[];
  onTopicClick?: (topicId: string) => void;
}

interface ChartEntry {
  name: string;
  median_min: number;
  p25_min: number;
  p75_min: number;
  short_pct: number;
  medium_pct: number;
  long_pct: number;
  topic_id: string;
}

function toMin(sec: number): number {
  return Math.round(sec / 60 * 10) / 10;
}

function truncate(s: string, max: number): string {
  return s.length > max ? s.slice(0, max) + '…' : s;
}

export function DurationChart({ data, onTopicClick }: Props) {
  const isMobile = useIsMobile();
  const subTopics = data.filter((d) => d.parent_id !== null);
  const itemCount = isMobile ? 10 : 25;

  const sorted = [...subTopics]
    .sort((a, b) => a.median_duration - b.median_duration)
    .slice(0, itemCount);

  const chartData: ChartEntry[] = sorted.map((d) => ({
    name: d.name_ja ?? d.topic_name,
    median_min: toMin(d.median_duration),
    p25_min: toMin(d.p25_duration),
    p75_min: toMin(d.p75_duration),
    short_pct: Math.round(d.short_count / d.video_count * 100),
    medium_pct: Math.round(d.medium_count / d.video_count * 100),
    long_pct: Math.round(d.long_count / d.video_count * 100),
    topic_id: d.topic_id,
  }));

  const chartHeight = isMobile ? itemCount * 36 + 40 : 500;

  return (
    <div className="chart-card">
      <div className="chart-title-row">
        <h3>動画尺の最適ゾーン</h3>
        <HelpButton {...HELP_TEXTS.duration} />
      </div>
      <p className="chart-desc">
        ジャンル別の中央値動画長（分）。何分の動画を作ればそのジャンルの「普通」に合うかがわかる（クリックで詳細）
      </p>
      <ResponsiveContainer width="100%" height={chartHeight}>
        <BarChart data={chartData} layout="vertical" margin={{ left: isMobile ? 10 : 100 }}>
          <CartesianGrid strokeDasharray="3 3" />
          <XAxis type="number" unit="分" tick={{ fontSize: isMobile ? 10 : 11 }} />
          <YAxis
            type="category"
            dataKey="name"
            width={isMobile ? 60 : 90}
            tick={{ fontSize: isMobile ? 10 : 12 }}
            tickFormatter={(v) => truncate(v, isMobile ? 6 : 20)}
          />
          <Tooltip
            content={({ payload }) => {
              if (!payload?.length) return null;
              const d = payload[0].payload as ChartEntry;
              return (
                <div className="custom-tooltip">
                  <strong>{d.name}</strong>
                  <div>中央値: <strong>{d.median_min}分</strong></div>
                  <div>25-75%: {d.p25_min}分 ~ {d.p75_min}分</div>
                  <div style={{ marginTop: 4, fontSize: '0.75rem' }}>
                    <div>ショート(~1分): {d.short_pct}%</div>
                    <div>ミドル(1~10分): {d.medium_pct}%</div>
                    <div>ロング(10分~): {d.long_pct}%</div>
                  </div>
                  <div className="tooltip-hint">クリックで詳細</div>
                </div>
              );
            }}
          />
          {!isMobile && <Legend />}
          <Bar
            dataKey="median_min"
            fill="#06b6d4"
            name="中央値（分）"
            radius={[0, 4, 4, 0]}
            cursor="pointer"
            onClick={(entry: unknown) => onTopicClick?.((entry as ChartEntry).topic_id)}
          />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
