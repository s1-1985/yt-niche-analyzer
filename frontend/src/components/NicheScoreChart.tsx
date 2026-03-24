import { useState, useMemo } from 'react';
import {
  BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid, Cell,
} from 'recharts';
import { useIsMobile } from '../hooks/useIsMobile';
import { HelpButton, HELP_TEXTS } from './HelpButton';
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

interface Weights {
  gap: number;
  competition: number;
  success: number;
  ai: number;
}

const PRESETS: { label: string; weights: Weights }[] = [
  { label: 'バランス', weights: { gap: 35, competition: 25, success: 25, ai: 15 } },
  { label: 'バズ重視', weights: { gap: 50, competition: 15, success: 20, ai: 15 } },
  { label: '安定重視', weights: { gap: 20, competition: 35, success: 35, ai: 10 } },
  { label: '新規参入', weights: { gap: 25, competition: 20, success: 40, ai: 15 } },
  { label: 'AI穴場', weights: { gap: 25, competition: 20, success: 15, ai: 40 } },
];

function normalize(value: number, min: number, max: number): number {
  if (max === min) return 50;
  return Math.max(0, Math.min(100, ((value - min) / (max - min)) * 100));
}

function truncate(s: string, max: number): string {
  return s.length > max ? s.slice(0, max) + '\u2026' : s;
}

export function NicheScoreChart({ topics, competition, successRate, aiPenetration, onTopicClick }: Props) {
  const isMobile = useIsMobile();
  const [weights, setWeights] = useState<Weights>({ gap: 35, competition: 25, success: 25, ai: 15 });
  const [showSettings, setShowSettings] = useState(false);

  const subTopics = topics.filter((t) => t.parent_id !== null);

  const compMap = new Map(competition.map((c) => [c.topic_id, c.top5_share_pct]));
  const successMap = new Map(successRate.map((s) => [s.topic_id, s.success_rate_pct]));
  const aiMap = new Map(aiPenetration.map((a) => [a.topic_id, a.ai_penetration_pct]));

  const { gapMin, gapMax, compMin, compMax, successMin, successMax, aiMin, aiMax } = useMemo(() => {
    const gapScores = subTopics.map((t) => t.gap_score);
    const compValues = subTopics.map((t) => compMap.get(t.topic_id) ?? 50);
    const successValues = subTopics.map((t) => successMap.get(t.topic_id) ?? 0);
    const aiValues = subTopics.map((t) => aiMap.get(t.topic_id) ?? 0);
    return {
      gapMin: gapScores.length > 0 ? Math.min(...gapScores) : 0,
      gapMax: gapScores.length > 0 ? Math.max(...gapScores) : 0,
      compMin: compValues.length > 0 ? Math.min(...compValues) : 0,
      compMax: compValues.length > 0 ? Math.max(...compValues) : 0,
      successMin: successValues.length > 0 ? Math.min(...successValues) : 0,
      successMax: successValues.length > 0 ? Math.max(...successValues) : 0,
      aiMin: aiValues.length > 0 ? Math.min(...aiValues) : 0,
      aiMax: aiValues.length > 0 ? Math.max(...aiValues) : 0,
    };
  }, [subTopics, compMap, successMap, aiMap]);

  const scored: ChartEntry[] = useMemo(() => {
    const total = weights.gap + weights.competition + weights.success + weights.ai;
    const wGap = weights.gap / total;
    const wComp = weights.competition / total;
    const wSuccess = weights.success / total;
    const wAi = weights.ai / total;

    return subTopics.map((t) => {
      const gapNorm = normalize(t.gap_score, gapMin, gapMax);
      const compNorm = 100 - normalize(compMap.get(t.topic_id) ?? 50, compMin, compMax);
      const successNorm = normalize(successMap.get(t.topic_id) ?? 0, successMin, successMax);
      const aiNorm = 100 - normalize(aiMap.get(t.topic_id) ?? 0, aiMin, aiMax);

      const score = Math.round(gapNorm * wGap + compNorm * wComp + successNorm * wSuccess + aiNorm * wAi);

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
  }, [subTopics, weights, gapMin, gapMax, compMin, compMax, successMin, successMax, aiMin, aiMax, compMap, successMap, aiMap]);

  const itemCount = isMobile ? 10 : 20;
  const chartData = [...scored].sort((a, b) => b.niche_score - a.niche_score).slice(0, itemCount);

  const getBarColor = (score: number) => {
    if (score >= 70) return '#10b981';
    if (score >= 50) return '#f59e0b';
    return '#ef4444';
  };

  const chartHeight = isMobile ? itemCount * 36 + 40 : 500;
  const labelLen = isMobile ? 6 : 20;

  const total = weights.gap + weights.competition + weights.success + weights.ai;

  const handleWeightChange = (key: keyof Weights, value: number) => {
    setWeights((prev) => ({ ...prev, [key]: value }));
  };

  return (
    <div className="chart-card niche-score-card">
      <div className="chart-title-row">
        <h3>ニッチ推奨スコア TOP {itemCount}</h3>
        <HelpButton {...HELP_TEXTS.nicheScore} />
      </div>
      <p className="chart-desc">
        需給ギャップ({Math.round(weights.gap / total * 100)}%) + 競合の少なさ({Math.round(weights.competition / total * 100)}%) + 新規成功率({Math.round(weights.success / total * 100)}%) + AI未開拓度({Math.round(weights.ai / total * 100)}%) の総合スコア
      </p>

      <button
        className="view-toggle-btn"
        onClick={() => setShowSettings(!showSettings)}
      >
        {showSettings ? '設定を閉じる' : '重み付けをカスタマイズ'}
      </button>

      {showSettings && (
        <div className="niche-weight-settings">
          <div className="niche-presets">
            {PRESETS.map((p) => (
              <button
                key={p.label}
                className={`buzz-period-btn ${
                  weights.gap === p.weights.gap &&
                  weights.competition === p.weights.competition &&
                  weights.success === p.weights.success &&
                  weights.ai === p.weights.ai
                    ? 'active'
                    : ''
                }`}
                onClick={() => setWeights(p.weights)}
              >
                {p.label}
              </button>
            ))}
          </div>
          <div className="niche-sliders">
            {([
              { key: 'gap' as const, label: '需給ギャップ', color: '#6366f1' },
              { key: 'competition' as const, label: '競合の少なさ', color: '#10b981' },
              { key: 'success' as const, label: '新規成功率', color: '#f59e0b' },
              { key: 'ai' as const, label: 'AI未開拓度', color: '#ec4899' },
            ]).map(({ key, label, color }) => (
              <div key={key} className="niche-slider-row">
                <span className="niche-slider-label" style={{ color }}>{label}</span>
                <input
                  type="range"
                  min={0}
                  max={100}
                  value={weights[key]}
                  onChange={(e) => handleWeightChange(key, parseInt(e.target.value))}
                  className="niche-slider"
                />
                <span className="niche-slider-value">{Math.round(weights[key] / total * 100)}%</span>
              </div>
            ))}
          </div>
        </div>
      )}

      <ResponsiveContainer width="100%" height={chartHeight}>
        <BarChart data={chartData} layout="vertical" margin={{ left: isMobile ? 10 : 100 }}>
          <CartesianGrid strokeDasharray="3 3" />
          <XAxis type="number" domain={[0, 100]} tick={{ fontSize: isMobile ? 10 : 12 }} />
          <YAxis
            type="category"
            dataKey="name"
            width={isMobile ? 60 : 90}
            tick={{ fontSize: isMobile ? 10 : 12 }}
            tickFormatter={(v) => truncate(v, labelLen)}
          />
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
