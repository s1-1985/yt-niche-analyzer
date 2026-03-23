import {
  BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid,
} from 'recharts';
import type { CompetitionConcentration } from '../types/database';

interface Props {
  data: CompetitionConcentration[];
  onTopicClick?: (topicId: string) => void;
}

interface ChartEntry {
  name: string;
  top5_share: number;
  topic_id: string;
}

export function CompetitionChart({ data, onTopicClick }: Props) {
  const sorted = [...data].sort((a, b) => b.top5_share_pct - a.top5_share_pct).slice(0, 20);

  const chartData: ChartEntry[] = sorted.map((d) => ({
    name: d.name_ja ?? d.topic_name,
    top5_share: d.top5_share_pct,
    topic_id: d.topic_id,
  }));

  return (
    <div className="chart-card">
      <h3>競合集中度（Top5 シェア %）</h3>
      <p className="chart-desc">上位5チャンネルが占める再生数の割合。高いほど寡占（クリックで詳細）</p>
      <ResponsiveContainer width="100%" height={400}>
        <BarChart data={chartData} layout="vertical" margin={{ left: 100 }}>
          <CartesianGrid strokeDasharray="3 3" />
          <XAxis type="number" domain={[0, 100]} unit="%" />
          <YAxis type="category" dataKey="name" width={90} tick={{ fontSize: 12 }} />
          <Tooltip formatter={(value) => `${value}%`} />
          <Bar
            dataKey="top5_share"
            fill="#f59e0b"
            name="Top5 シェア"
            radius={[0, 4, 4, 0]}
            cursor="pointer"
            onClick={(entry: unknown) => onTopicClick?.((entry as ChartEntry).topic_id)}
          />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
