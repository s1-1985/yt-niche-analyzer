import {
  ScatterChart, Scatter, XAxis, YAxis, Tooltip, ResponsiveContainer,
  CartesianGrid, ZAxis, ReferenceArea, ReferenceLine, Label, Cell,
} from 'recharts';
import type { TopicSummary, CompetitionConcentration } from '../types/database';

interface Props {
  topics: TopicSummary[];
  competition: CompetitionConcentration[];
  onTopicClick?: (topicId: string) => void;
}

interface ChartEntry {
  name: string;
  gap_score: number;
  top5_share: number;
  avg_views: number;
  topic_id: string;
  category: string;
}

const CATEGORY_COLORS: Record<string, string> = {
  Music: '#a78bfa',
  Gaming: '#34d399',
  Sports: '#fbbf24',
  Entertainment: '#f472b6',
  Lifestyle: '#818cf8',
  Society: '#22d3ee',
  Knowledge: '#c084fc',
};

export function EntryMatrixChart({ topics, competition, onTopicClick }: Props) {
  const compMap = new Map(competition.map((c) => [c.topic_id, c.top5_share_pct]));

  const subTopics = topics.filter((t) => t.parent_id !== null);

  const chartData: ChartEntry[] = subTopics
    .filter((t) => compMap.has(t.topic_id))
    .map((t) => ({
      name: t.name_ja ?? t.topic_name,
      gap_score: t.gap_score,
      top5_share: compMap.get(t.topic_id) ?? 0,
      avg_views: t.avg_views,
      topic_id: t.topic_id,
      category: t.category,
    }));

  const gapMedian = chartData.length > 0
    ? [...chartData].sort((a, b) => a.gap_score - b.gap_score)[Math.floor(chartData.length / 2)].gap_score
    : 0;
  const compMedian = chartData.length > 0
    ? [...chartData].sort((a, b) => a.top5_share - b.top5_share)[Math.floor(chartData.length / 2)].top5_share
    : 50;

  const maxGap = Math.max(...chartData.map((d) => d.gap_score), 1);
  const maxComp = Math.max(...chartData.map((d) => d.top5_share), 100);

  return (
    <div className="chart-card">
      <h3>参入難易度マトリクス</h3>
      <p className="chart-desc">
        右下が狙い目ゾーン（需要が高く、競合が分散）。左上は避けるべきゾーン（クリックで詳細）
      </p>
      <ResponsiveContainer width="100%" height={450}>
        <ScatterChart margin={{ left: 20, bottom: 30, right: 20, top: 10 }}>
          <CartesianGrid strokeDasharray="3 3" />
          <XAxis
            type="number"
            dataKey="gap_score"
            name="需給ギャップ"
            tick={{ fontSize: 11 }}
          >
            <Label value="需給ギャップ (高い = 需要大)" position="bottom" offset={10} style={{ fill: '#9ca3af', fontSize: 12 }} />
          </XAxis>
          <YAxis
            type="number"
            dataKey="top5_share"
            name="Top5集中度"
            unit="%"
            domain={[0, 100]}
            tick={{ fontSize: 11 }}
          >
            <Label value="競合集中度 (低い = 参入しやすい)" angle={-90} position="insideLeft" offset={-5} style={{ fill: '#9ca3af', fontSize: 12 }} />
          </YAxis>
          <ZAxis type="number" dataKey="avg_views" range={[60, 400]} name="平均再生" />
          {/* Sweet spot zone - bottom right */}
          <ReferenceArea
            x1={gapMedian}
            x2={maxGap * 1.1}
            y1={0}
            y2={compMedian}
            fill="#10b981"
            fillOpacity={0.08}
            stroke="#10b981"
            strokeOpacity={0.2}
            strokeDasharray="4 4"
          />
          {/* Danger zone - top left */}
          <ReferenceArea
            x1={0}
            x2={gapMedian}
            y1={compMedian}
            y2={maxComp * 1.05}
            fill="#ef4444"
            fillOpacity={0.06}
            stroke="#ef4444"
            strokeOpacity={0.15}
            strokeDasharray="4 4"
          />
          <ReferenceLine x={gapMedian} stroke="#4b5563" strokeDasharray="3 3" />
          <ReferenceLine y={compMedian} stroke="#4b5563" strokeDasharray="3 3" />
          <Tooltip
            content={({ payload }) => {
              if (!payload?.length) return null;
              const d = payload[0].payload as ChartEntry;
              return (
                <div className="custom-tooltip">
                  <strong>{d.name}</strong>
                  <div style={{ fontSize: '0.7rem', color: CATEGORY_COLORS[d.category] }}>{d.category}</div>
                  <div>需給ギャップ: {d.gap_score.toLocaleString()}</div>
                  <div>競合集中度: {d.top5_share}%</div>
                  <div>平均再生: {d.avg_views.toLocaleString()}</div>
                  <div className="tooltip-hint">クリックで詳細</div>
                </div>
              );
            }}
          />
          <Scatter
            data={chartData}
            cursor="pointer"
            onClick={(entry: unknown) => onTopicClick?.((entry as ChartEntry).topic_id)}
          >
            {chartData.map((entry, index) => (
              <Cell
                key={index}
                fill={CATEGORY_COLORS[entry.category] ?? '#6366f1'}
                stroke="#ffffff"
                strokeWidth={2}
              />
            ))}
          </Scatter>
        </ScatterChart>
      </ResponsiveContainer>
      <div className="matrix-legend">
        {Object.entries(CATEGORY_COLORS).map(([cat, color]) => (
          <span key={cat} className="matrix-legend-item">
            <span className="matrix-legend-dot" style={{ background: color }} />
            {cat}
          </span>
        ))}
      </div>
    </div>
  );
}
