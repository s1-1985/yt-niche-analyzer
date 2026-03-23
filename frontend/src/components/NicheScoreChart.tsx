import {
  BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid, Cell,
} from 'recharts';
import type { TopicSummary, CompetitionConcentration, NewChannelSuccessRate, AiPenetration } from '../types/database';

interface Props {
  topics: TopicSummary[];
  competition: CompetitionConcentration[];
  successRate: NewChannelSuccessRate[];
  aiPenetration: AiPenetration[];
  onTopicClick?: (topicId: string) => void;
}

interface ChartEntry {
  name: string;
  niche_score: number;
  gap: number;
  competition: number;
  success: number;
  ai: number;
  topic_id: string;
}

function normalize(value: number, min: number, max: number): number {
  if (max === min) return 50;
  return Math.max(0, Math.min(100, ((value - min) / (max - min)) * 100));
}

export function NicheScoreChart({ topics, competition, successRate, aiPenetration, onTopicClick }: Props) {
  const subTopics = topics.filter((t) => t.parent_id !== null);

  const compMap = new Map(competition.map((c) => [c.topic_id, c.top5_share_pct]));
  const successMap = new Map(successRate.map((s) => [s.topic_id, s.success_rate_pct]));
  const aiMap = new Map(aiPenetration.map((a) => [a.topic_id, a.ai_penetration_pct]));

  const gapScores = subTopics.map((t) => t.gap_score);
  const gapMin = Math.min(...gapScores);
  const gapMax = Math.max(...gapScores);

  const compValues = subTopics.map((t) => compMap.get(t.topic_id) ?? 50);
  const compMin = Math.min(...compValues);
  const compMax = Math.max(...compValues);

  const successValues = subTopics.map((t) => successMap.get(t.topic_id) ?? 0);
  const successMin = Math.min(...successValues);
  const successMax = Math.max(...successValues);

  const aiValues = subTopics.map((t) => aiMap.get(t.topic_id) ?? 0);
  const aiMin = Math.min(...aiValues);
  const aiMax = Math.max(...aiValues);

  const scored: ChartEntry[] = subTopics.map((t) => {
    const gapNorm = normalize(t.gap_score, gapMin, gapMax);
    const compNorm = 100 - normalize(compMap.get(t.topic_id) ?? 50, compMin, compMax);
    const successNorm = normalize(successMap.get(t.topic_id) ?? 0, successMin, successMax);
    const aiNorm = 100 - normalize(aiMap.get(t.topic_id) ?? 0, aiMin, aiMax);

    const score = Math.round(gapNorm * 0.35 + compNorm * 0.25 + successNorm * 0.25 + aiNorm * 0.15);

    return {
      name: t.name_ja ?? t.topic_name,
      niche_score: score,
      gap: Math.round(gapNorm),
      competition: Math.round(compNorm),
      success: Math.round(successNorm),
      ai: Math.round(aiNorm),
      topic_id: t.topic_id,
    };
  });

  const chartData = [...scored].sort((a, b) => b.niche_score - a.niche_score).slice(0, 20);

  const getBarColor = (score: number) => {
    if (score >= 70) return '#10b981';
    if (score >= 50) return '#f59e0b';
    return '#ef4444';
  };

  return (
    <div className="chart-card niche-score-card">
      <h3>ニッチ推奨スコア TOP 20</h3>
      <p className="chart-desc">
        需給ギャップ(35%) + 競合の少なさ(25%) + 新規成功率(25%) + AI未開拓度(15%) の総合スコア
      </p>
      <ResponsiveContainer width="100%" height={500}>
        <BarChart data={chartData} layout="vertical" margin={{ left: 100 }}>
          <CartesianGrid strokeDasharray="3 3" />
          <XAxis type="number" domain={[0, 100]} />
          <YAxis type="category" dataKey="name" width={90} tick={{ fontSize: 12 }} />
          <Tooltip
            content={({ payload }) => {
              if (!payload?.length) return null;
              const d = payload[0].payload as ChartEntry;
              return (
                <div className="custom-tooltip">
                  <strong>{d.name}</strong>
                  <div>総合スコア: <strong>{d.niche_score}</strong>/100</div>
                  <div style={{ marginTop: 4, fontSize: '0.75rem' }}>
                    <div>需給ギャップ: {d.gap}/100</div>
                    <div>競合の少なさ: {d.competition}/100</div>
                    <div>新規成功率: {d.success}/100</div>
                    <div>AI未開拓度: {d.ai}/100</div>
                  </div>
                  <div className="tooltip-hint">クリックで詳細</div>
                </div>
              );
            }}
          />
          <Bar
            dataKey="niche_score"
            name="ニッチスコア"
            radius={[0, 4, 4, 0]}
            cursor="pointer"
            onClick={(entry: unknown) => onTopicClick?.((entry as ChartEntry).topic_id)}
          >
            {chartData.map((entry, index) => (
              <Cell key={index} fill={getBarColor(entry.niche_score)} />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
