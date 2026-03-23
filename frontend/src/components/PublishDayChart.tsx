import {
  BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid, Cell,
} from 'recharts';
import { useIsMobile } from '../hooks/useIsMobile';
import { HelpButton, HELP_TEXTS } from './HelpButton';
import type { TopicPublishDay } from '../types/database';

interface Props {
  data: TopicPublishDay[];
}

const DAY_NAMES = ['日', '月', '火', '水', '木', '金', '土'];

interface DayEntry {
  day: string;
  dow: number;
  video_count: number;
  avg_views: number;
  total_views: number;
}

export function PublishDayChart({ data }: Props) {
  const isMobile = useIsMobile();

  // Aggregate across all topics by day of week
  const byDay = new Map<number, { count: number; totalViews: number; viewsWeighted: number }>();
  for (const row of data) {
    const cur = byDay.get(row.dow) ?? { count: 0, totalViews: 0, viewsWeighted: 0 };
    cur.count += row.video_count;
    cur.totalViews += row.total_views;
    cur.viewsWeighted += row.avg_views * row.video_count;
    byDay.set(row.dow, cur);
  }

  const chartData: DayEntry[] = Array.from({ length: 7 }, (_, i) => {
    const cur = byDay.get(i) ?? { count: 0, totalViews: 0, viewsWeighted: 0 };
    return {
      day: DAY_NAMES[i],
      dow: i,
      video_count: cur.count,
      avg_views: cur.count > 0 ? Math.round(cur.viewsWeighted / cur.count) : 0,
      total_views: cur.totalViews,
    };
  });

  // Reorder: Mon-Sun
  const reordered = [...chartData.slice(1), chartData[0]];

  const maxAvg = Math.max(...reordered.map((d) => d.avg_views));

  return (
    <div className="chart-card">
      <div className="chart-title-row">
        <h3>投稿曜日と平均再生数</h3>
        <HelpButton {...HELP_TEXTS.publishDay} />
      </div>
      <p className="chart-desc">
        曜日別の平均再生数（全ジャンル集計）。バズりやすい曜日がわかる
      </p>
      <ResponsiveContainer width="100%" height={isMobile ? 220 : 300}>
        <BarChart data={reordered} margin={{ left: isMobile ? 5 : 20 }}>
          <CartesianGrid strokeDasharray="3 3" />
          <XAxis dataKey="day" tick={{ fontSize: isMobile ? 12 : 14 }} />
          <YAxis
            tick={{ fontSize: isMobile ? 9 : 11 }}
            width={isMobile ? 40 : 60}
            tickFormatter={isMobile ? ((v: number) => v >= 1000 ? `${(v / 1000).toFixed(0)}K` : String(v)) : undefined}
          />
          <Tooltip
            content={({ payload }) => {
              if (!payload?.length) return null;
              const d = payload[0].payload as DayEntry;
              return (
                <div className="custom-tooltip">
                  <strong>{d.day}曜日</strong>
                  <div>平均再生: {d.avg_views.toLocaleString()}</div>
                  <div>動画数: {d.video_count.toLocaleString()}</div>
                  <div>総再生: {d.total_views.toLocaleString()}</div>
                </div>
              );
            }}
          />
          <Bar
            dataKey="avg_views"
            name="平均再生数"
            radius={[4, 4, 0, 0]}
          >
            {reordered.map((entry, index) => (
              <Cell
                key={index}
                fill={entry.avg_views === maxAvg ? '#10b981' : '#6366f1'}
              />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
