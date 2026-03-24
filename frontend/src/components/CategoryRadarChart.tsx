import { useState } from 'react';
import {
  RadarChart, Radar, PolarGrid, PolarAngleAxis, PolarRadiusAxis,
  ResponsiveContainer, Legend, Tooltip,
} from 'recharts';
import { useIsMobile } from '../hooks/useIsMobile';
import { HelpButton, HELP_TEXTS } from './HelpButton';
import type { TopicSummary, CompetitionConcentration, NewChannelSuccessRate, AiPenetration } from '../types/database';

interface Props {
  topics: TopicSummary[];
  competition: CompetitionConcentration[];
  successRate: NewChannelSuccessRate[];
  aiPenetration: AiPenetration[];
}

interface RadarEntry {
  metric: string;
  [category: string]: string | number;
}

function normalize(val: number, min: number, max: number): number {
  if (max === min) return 50;
  return Math.round(Math.max(0, Math.min(100, ((val - min) / (max - min)) * 100)));
}

const CATEGORY_COLORS: Record<string, string> = {
  Music: '#a78bfa', Gaming: '#34d399', Sports: '#fbbf24',
  Entertainment: '#f472b6', Lifestyle: '#818cf8', Society: '#22d3ee', Knowledge: '#c084fc',
};

export function CategoryRadarChart({ topics, competition, successRate, aiPenetration }: Props) {
  const isMobile = useIsMobile();
  const [selectedCats, setSelectedCats] = useState<Set<string>>(new Set());
  const subTopics = topics.filter((t) => t.parent_id !== null);

  const compMap = new Map(competition.map((c) => [c.topic_id, c.top5_share_pct]));
  const successMap = new Map(successRate.map((s) => [s.topic_id, s.success_rate_pct]));
  const aiMap = new Map(aiPenetration.map((a) => [a.topic_id, a.ai_penetration_pct]));

  const categories = new Map<string, {
    gap: number[]; engagement: number[]; competition: number[];
    success: number[]; ai: number[]; volume: number[];
  }>();

  for (const t of subTopics) {
    if (!categories.has(t.category)) {
      categories.set(t.category, { gap: [], engagement: [], competition: [], success: [], ai: [], volume: [] });
    }
    const cat = categories.get(t.category)!;
    cat.gap.push(t.gap_score);
    cat.engagement.push(t.like_rate_pct + t.comment_rate_pct * 10);
    cat.competition.push(100 - (compMap.get(t.topic_id) ?? 50));
    cat.success.push(successMap.get(t.topic_id) ?? 0);
    cat.ai.push(100 - (aiMap.get(t.topic_id) ?? 0));
    cat.volume.push(t.avg_views);
  }

  const avg = (arr: number[]) => arr.length > 0 ? arr.reduce((a, b) => a + b, 0) / arr.length : 0;

  const catData = Array.from(categories.entries()).map(([name, vals]) => ({
    name,
    gap: avg(vals.gap), engagement: avg(vals.engagement), competition: avg(vals.competition),
    success: avg(vals.success), ai: avg(vals.ai), volume: avg(vals.volume),
  }));

  const metrics = ['gap', 'engagement', 'competition', 'success', 'ai', 'volume'] as const;
  const metricLabels: Record<string, string> = {
    gap: 'ギャップ', engagement: 'エンゲジ', competition: '参入性',
    success: '成功率', ai: 'AI未開拓', volume: '再生数',
  };

  const ranges = Object.fromEntries(metrics.map((m) => {
    const vals = catData.map((c) => c[m]);
    return [m, { min: vals.length > 0 ? Math.min(...vals) : 0, max: vals.length > 0 ? Math.max(...vals) : 0 }];
  }));

  const radarData: RadarEntry[] = metrics.map((m) => {
    const entry: RadarEntry = { metric: metricLabels[m] };
    for (const cat of catData) {
      entry[cat.name] = normalize(cat[m], ranges[m].min, ranges[m].max);
    }
    return entry;
  });

  // On mobile, show category selector; default to showing all if nothing selected
  const toggleCat = (name: string) => {
    setSelectedCats((prev) => {
      const next = new Set(prev);
      if (next.has(name)) next.delete(name);
      else next.add(name);
      return next;
    });
  };

  const visibleCats = selectedCats.size === 0
    ? catData
    : catData.filter((c) => selectedCats.has(c.name));

  return (
    <div className="chart-card">
      <div className="chart-title-row">
        <h3>カテゴリ比較レーダー</h3>
        <HelpButton {...HELP_TEXTS.categoryRadar} />
      </div>
      <p className="chart-desc">
        大カテゴリ間の6軸比較。カテゴリをタップして絞り込み
      </p>

      <div className="category-selector">
        {catData.map((cat) => (
          <button key={cat.name}
            className={`cat-btn ${selectedCats.size === 0 || selectedCats.has(cat.name) ? 'active' : ''}`}
            style={{
              borderColor: CATEGORY_COLORS[cat.name],
              ...(selectedCats.has(cat.name) ? { background: CATEGORY_COLORS[cat.name], color: '#fff' } : {}),
            }}
            onClick={() => toggleCat(cat.name)}>
            {cat.name}
          </button>
        ))}
      </div>

      <ResponsiveContainer width="100%" height={isMobile ? 300 : 450}>
        <RadarChart data={radarData} margin={isMobile
          ? { top: 10, right: 20, bottom: 10, left: 20 }
          : { top: 20, right: 30, bottom: 20, left: 30 }
        }>
          <PolarGrid stroke="#2a2d3e" />
          <PolarAngleAxis dataKey="metric" tick={{ fontSize: isMobile ? 10 : 11, fill: '#9ca3af' }} />
          <PolarRadiusAxis angle={90} domain={[0, 100]} tick={false} axisLine={false} />
          <Tooltip />
          {visibleCats.map((cat) => (
            <Radar key={cat.name} name={cat.name} dataKey={cat.name}
              stroke={CATEGORY_COLORS[cat.name] ?? '#6366f1'}
              fill={CATEGORY_COLORS[cat.name] ?? '#6366f1'}
              fillOpacity={visibleCats.length <= 2 ? 0.2 : 0.1}
              strokeWidth={2} />
          ))}
          {!isMobile && <Legend />}
        </RadarChart>
      </ResponsiveContainer>
    </div>
  );
}
