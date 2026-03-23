import {
  BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid,
} from 'recharts';
import { useIsMobile } from '../hooks/useIsMobile';
import type { TopicSummary } from '../types/database';

interface Props {
  data: TopicSummary[];
  onTopicClick?: (topicId: string) => void;
}

interface ChartEntry {
  name: string;
  depth_ratio: number;
  comment_rate: number;
  like_rate: number;
  topic_id: string;
}

function truncate(s: string, max: number): string {
  return s.length > max ? s.slice(0, max) + '…' : s;
}

export function EngagementDepthChart({ data, onTopicClick }: Props) {
  const isMobile = useIsMobile();
  const itemCount = isMobile ? 10 : 20;
  const subTopics = data.filter((d) => d.parent_id !== null && d.like_rate_pct > 0);

  const chartData: ChartEntry[] = subTopics
    .map((d) => ({
      name: d.name_ja ?? d.topic_name,
      depth_ratio: d.like_rate_pct > 0
        ? Math.round((d.comment_rate_pct / d.like_rate_pct) * 1000) / 10
        : 0,
      comment_rate: d.comment_rate_pct,
      like_rate: d.like_rate_pct,
      topic_id: d.topic_id,
    }))
    .sort((a, b) => b.depth_ratio - a.depth_ratio)
    .slice(0, itemCount);

  const chartHeight = isMobile ? itemCount * 36 + 40 : 500;

  return (
    <div className="chart-card">
      <h3>エンゲージメント深度</h3>
      <p className="chart-desc">
        コメント率 / いいね率 = 「見て終わり」vs「語りたくなる」。高い = コミュニティ形成しやすい（クリックで詳細）
      </p>
      <ResponsiveContainer width="100%" height={chartHeight}>
        <BarChart data={chartData} layout="vertical" margin={{ left: isMobile ? 10 : 100 }}>
          <CartesianGrid strokeDasharray="3 3" />
          <XAxis type="number" tick={{ fontSize: isMobile ? 10 : 11 }} />
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
                  <div>深度スコア: <strong>{d.depth_ratio}</strong></div>
                  <div>コメント率: {d.comment_rate}%</div>
                  <div>いいね率: {d.like_rate}%</div>
                  <div className="tooltip-hint">クリックで詳細</div>
                </div>
              );
            }}
          />
          <Bar
            dataKey="depth_ratio"
            fill="#f472b6"
            name="深度スコア"
            radius={[0, 4, 4, 0]}
            cursor="pointer"
            onClick={(entry: unknown) => onTopicClick?.((entry as ChartEntry).topic_id)}
          />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
