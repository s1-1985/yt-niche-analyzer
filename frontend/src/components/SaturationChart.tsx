import { useEffect, useState, useMemo } from 'react';
import {
  BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid, Cell,
} from 'recharts';
import { supabase } from '../lib/supabase';
import { useIsMobile } from '../hooks/useIsMobile';
import { HelpButton } from './HelpButton';
import type { TopicSummary, AiPenetration } from '../types/database';

interface Props {
  topics: TopicSummary[];
  aiPenetration: AiPenetration[];
  onTopicClick?: (topicId: string) => void;
}

interface ChannelRow {
  published_at: string;
  topic_ids: string[];
}

interface SaturationEntry {
  name: string;
  topic_id: string;
  currentChannels: number;
  monthlyGrowthRate: number;
  aiPct: number;
  predicted6m: number;
  saturationRisk: 'low' | 'medium' | 'high';
}

function truncate(s: string, max: number): string {
  return s.length > max ? s.slice(0, max) + '\u2026' : s;
}

export function SaturationChart({ topics, aiPenetration, onTopicClick }: Props) {
  const isMobile = useIsMobile();
  const [channels, setChannels] = useState<ChannelRow[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);

    // Fetch channels published in last 12 months
    const since = new Date();
    since.setMonth(since.getMonth() - 12);

    supabase
      .from('channels')
      .select('published_at, topic_ids')
      .gte('published_at', since.toISOString())
      .then((res) => {
        if (cancelled) return;
        setChannels((res.data as ChannelRow[]) ?? []);
        setLoading(false);
      });

    return () => { cancelled = true; };
  }, []);

  const chartData = useMemo(() => {
    const subTopics = topics.filter((t) => t.parent_id !== null);
    const aiMap = new Map(aiPenetration.map((a) => [a.topic_id, a.ai_penetration_pct]));

    const now = Date.now();
    const threeMonthsAgo = now - 90 * 86400000;
    const sixMonthsAgo = now - 180 * 86400000;

    const entries: SaturationEntry[] = subTopics.map((t) => {
      // Count channels in this topic for different periods
      const topicChannels = channels.filter((c) =>
        c.topic_ids?.includes(t.topic_id) && c.published_at,
      );

      const recent3m = topicChannels.filter((c) =>
        new Date(c.published_at).getTime() > threeMonthsAgo,
      ).length;

      const prev3m = topicChannels.filter((c) => {
        const ts = new Date(c.published_at).getTime();
        return ts > sixMonthsAgo && ts <= threeMonthsAgo;
      }).length;

      // Monthly growth rate
      const recentMonthly = recent3m / 3;
      const prevMonthly = prev3m / 3;
      const growthRate = prevMonthly > 0
        ? (recentMonthly - prevMonthly) / prevMonthly
        : recentMonthly > 0 ? 1 : 0;

      const aiPct = aiMap.get(t.topic_id) ?? 0;

      // Predict 6-month channel count
      // current channels + projected new channels (monthly rate * 6, adjusted by growth)
      const projected = Math.round(
        t.total_channels + recentMonthly * 6 * (1 + growthRate * 0.5),
      );

      // Saturation risk
      const growthPct = Math.round(growthRate * 100);
      let risk: 'low' | 'medium' | 'high' = 'low';
      if (growthPct > 30 || (growthPct > 15 && aiPct > 20)) {
        risk = 'high';
      } else if (growthPct > 10 || aiPct > 15) {
        risk = 'medium';
      }

      return {
        name: t.name_ja ?? t.topic_name,
        topic_id: t.topic_id,
        currentChannels: t.total_channels,
        monthlyGrowthRate: growthPct,
        aiPct,
        predicted6m: projected,
        saturationRisk: risk,
      };
    });

    return entries
      .filter((e) => e.currentChannels > 0)
      .sort((a, b) => b.monthlyGrowthRate - a.monthlyGrowthRate)
      .slice(0, isMobile ? 10 : 20);
  }, [topics, aiPenetration, channels, isMobile]);

  if (loading || chartData.length === 0) return null;

  const riskColor = (risk: string) => {
    switch (risk) {
      case 'high': return '#ef4444';
      case 'medium': return '#f59e0b';
      default: return '#10b981';
    }
  };

  const riskLabel = (risk: string) => {
    switch (risk) {
      case 'high': return '高リスク';
      case 'medium': return '中リスク';
      default: return '低リスク';
    }
  };

  const itemCount = chartData.length;
  const chartHeight = isMobile ? itemCount * 36 + 40 : 500;

  return (
    <div className="chart-card">
      <div className="chart-title-row">
        <h3>飽和予測 (6ヶ月後)</h3>
        <HelpButton
          title="飽和予測の見方"
          content={'直近3ヶ月のチャンネル増加率とAI浸透率の変化から、6ヶ月後の競合密度を推定しています。\n赤(高リスク)=チャンネルの増加ペースが速く、近い将来飽和する可能性が高い。\n黄(中リスク)=やや増加傾向。参入タイミングを見極める必要あり。\n緑(低リスク)=安定しており、急な飽和の心配は少ない。\nルールベースの簡易推定であり、実際の市場動向とは異なる場合があります。'}
        />
      </div>
      <p className="chart-desc">
        チャンネル月次増加率 (%) と AI浸透度から6ヶ月後の競合密度を推定
      </p>

      <ResponsiveContainer width="100%" height={chartHeight}>
        <BarChart
          data={chartData}
          layout="vertical"
          margin={{ left: isMobile ? 10 : 100 }}
        >
          <CartesianGrid strokeDasharray="3 3" />
          <XAxis type="number" tick={{ fontSize: isMobile ? 10 : 12 }} label={{ value: 'チャンネル増加率 (%)', position: 'insideBottom', offset: -5, fontSize: 11 }} />
          <YAxis
            type="category"
            dataKey="name"
            width={isMobile ? 60 : 90}
            tick={{ fontSize: isMobile ? 10 : 12 }}
            tickFormatter={(v) => truncate(v, isMobile ? 6 : 14)}
          />
          <Tooltip
            content={({ payload }) => {
              if (!payload?.length) return null;
              const d = payload[0].payload as SaturationEntry;
              return (
                <div className="custom-tooltip">
                  <strong>{d.name}</strong>
                  <div>現在: {d.currentChannels.toLocaleString()}ch</div>
                  <div>月次増加率: {d.monthlyGrowthRate > 0 ? '+' : ''}{d.monthlyGrowthRate}%</div>
                  <div>AI浸透度: {d.aiPct}%</div>
                  <div>6ヶ月後予測: {d.predicted6m.toLocaleString()}ch</div>
                  <div style={{ color: riskColor(d.saturationRisk), fontWeight: 700, marginTop: 4 }}>
                    {riskLabel(d.saturationRisk)}
                  </div>
                  <div className="tooltip-hint">クリックで詳細</div>
                </div>
              );
            }}
          />
          <Bar
            dataKey="monthlyGrowthRate"
            name="月次増加率(%)"
            radius={[0, 4, 4, 0]}
            cursor="pointer"
            onClick={(entry: unknown) => onTopicClick?.((entry as SaturationEntry).topic_id)}
          >
            {chartData.map((entry, index) => (
              <Cell key={index} fill={riskColor(entry.saturationRisk)} />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>

      <div className="saturation-legend">
        <span className="saturation-legend-item">
          <span className="matrix-legend-dot" style={{ background: '#ef4444' }} /> 高リスク (増加率30%+ or 増加率15%+AI20%+)
        </span>
        <span className="saturation-legend-item">
          <span className="matrix-legend-dot" style={{ background: '#f59e0b' }} /> 中リスク (増加率10%+ or AI15%+)
        </span>
        <span className="saturation-legend-item">
          <span className="matrix-legend-dot" style={{ background: '#10b981' }} /> 低リスク
        </span>
      </div>
    </div>
  );
}
