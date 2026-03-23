import {
  BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid,
} from 'recharts';
import type { TopicSummary } from '../types/database';

interface Props {
  data: TopicSummary[];
}

export function GapScoreChart({ data }: Props) {
  const sorted = [...data]
    .filter((d) => d.parent_id !== null)
    .sort((a, b) => b.gap_score - a.gap_score)
    .slice(0, 20);

  const chartData = sorted.map((d) => ({
    name: d.name_ja ?? d.topic_name,
    gap_score: d.gap_score,
    avg_views: d.avg_views,
  }));

  return (
    <div className="chart-card">
      <h3>需給ギャップスコア TOP 20</h3>
      <p className="chart-desc">平均再生数 / チャンネル数 = 需要に対する供給の少なさ</p>
      <ResponsiveContainer width="100%" height={400}>
        <BarChart data={chartData} layout="vertical" margin={{ left: 100 }}>
          <CartesianGrid strokeDasharray="3 3" />
          <XAxis type="number" />
          <YAxis type="category" dataKey="name" width={90} tick={{ fontSize: 12 }} />
          <Tooltip
            formatter={(value) => Number(value).toLocaleString()}
            labelStyle={{ fontWeight: 'bold' }}
          />
          <Bar dataKey="gap_score" fill="#6366f1" name="ギャップスコア" radius={[0, 4, 4, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
