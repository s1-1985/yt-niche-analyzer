import {
  BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid,
} from 'recharts';
import type { AiPenetration } from '../types/database';

interface Props {
  data: AiPenetration[];
}

export function AiPenetrationChart({ data }: Props) {
  const sorted = [...data]
    .filter((d) => d.ai_video_count > 0)
    .sort((a, b) => b.ai_penetration_pct - a.ai_penetration_pct)
    .slice(0, 20);

  const chartData = sorted.map((d) => ({
    name: d.name_ja ?? d.topic_name,
    ai_pct: d.ai_penetration_pct,
    ai_count: d.ai_video_count,
    total: d.total_videos,
  }));

  return (
    <div className="chart-card">
      <h3>AI動画浸透度</h3>
      <p className="chart-desc">タイトル・説明にAIキーワードを含む動画の割合</p>
      <ResponsiveContainer width="100%" height={400}>
        <BarChart data={chartData} layout="vertical" margin={{ left: 100 }}>
          <CartesianGrid strokeDasharray="3 3" />
          <XAxis type="number" domain={[0, 'auto']} unit="%" />
          <YAxis type="category" dataKey="name" width={90} tick={{ fontSize: 12 }} />
          <Tooltip
            formatter={(value) => `${value}%`}
            labelStyle={{ fontWeight: 'bold' }}
          />
          <Bar dataKey="ai_pct" fill="#ec4899" name="AI浸透率" radius={[0, 4, 4, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
