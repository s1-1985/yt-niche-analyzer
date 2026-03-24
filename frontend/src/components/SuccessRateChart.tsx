import { useState, useEffect, useMemo } from 'react';
import {
  ScatterChart, Scatter, XAxis, YAxis, Tooltip, ResponsiveContainer,
  CartesianGrid, ZAxis,
} from 'recharts';
import { supabase } from '../lib/supabase';
import { useIsMobile } from '../hooks/useIsMobile';
import { HelpButton, HELP_TEXTS } from './HelpButton';
import { RankingList, type RankingItem } from './RankingList';
import type { NewChannelSuccessRate } from '../types/database';

interface Props {
  data: NewChannelSuccessRate[];
  onTopicClick?: (topicId: string) => void;
}

interface ChannelRow {
  id: string;
  published_at: string;
  topic_ids: string[];
  subscriber_count: number;
}

interface ChartEntry {
  name: string;
  new_channels: number;
  success_rate: number;
  successful: number;
  topic_id: string;
}

const THRESHOLDS = [
  { value: 1000, label: '1K' },
  { value: 5000, label: '5K' },
  { value: 10000, label: '10K' },
] as const;

export function SuccessRateChart({ data, onTopicClick }: Props) {
  const isMobile = useIsMobile();
  const [showList, setShowList] = useState(false);
  const [threshold, setThreshold] = useState(1000);
  const [channels, setChannels] = useState<ChannelRow[]>([]);
  const [channelsLoaded, setChannelsLoaded] = useState(false);

  // Load channel data for custom thresholds
  useEffect(() => {
    if (threshold === 1000) {
      setChannelsLoaded(false);
      return;
    }
    if (channelsLoaded) return;

    let cancelled = false;
    const oneYearAgo = new Date();
    oneYearAgo.setFullYear(oneYearAgo.getFullYear() - 1);

    supabase
      .from('channel_ranking')
      .select('id, published_at, topic_ids, subscriber_count')
      .gte('published_at', oneYearAgo.toISOString())
      .then((res) => {
        if (cancelled) return;
        setChannels((res.data as ChannelRow[]) ?? []);
        setChannelsLoaded(true);
      });

    return () => { cancelled = true; };
  }, [threshold, channelsLoaded]);

  const chartData: ChartEntry[] = useMemo(() => {
    if (threshold === 1000) {
      // Use existing server-computed data
      return data
        .filter((d) => d.new_channel_count > 0)
        .map((d) => ({
          name: d.name_ja ?? d.topic_name,
          new_channels: d.new_channel_count,
          success_rate: d.success_rate_pct,
          successful: d.successful_count,
          topic_id: d.topic_id,
        }));
    }

    if (!channelsLoaded) return [];

    // Compute client-side for custom threshold
    // Get topic names from original data
    const topicNames = new Map(data.map((d) => [d.topic_id, d.name_ja ?? d.topic_name]));

    const topicStats = new Map<string, { total: number; success: number }>();

    for (const ch of channels) {
      for (const tid of ch.topic_ids ?? []) {
        if (!topicNames.has(tid)) continue;
        const stats = topicStats.get(tid) ?? { total: 0, success: 0 };
        stats.total++;
        if (ch.subscriber_count >= threshold) {
          stats.success++;
        }
        topicStats.set(tid, stats);
      }
    }

    return [...topicStats.entries()]
      .filter(([, stats]) => stats.total > 0)
      .map(([tid, stats]) => ({
        name: topicNames.get(tid) ?? tid,
        new_channels: stats.total,
        success_rate: Math.round((stats.success / stats.total) * 1000) / 10,
        successful: stats.success,
        topic_id: tid,
      }));
  }, [data, threshold, channels, channelsLoaded]);

  const rankingItems: RankingItem[] = [...chartData]
    .sort((a, b) => b.success_rate - a.success_rate)
    .map((d) => ({
      name: d.name,
      value: d.success_rate,
      sub: `${d.successful}/${d.new_channels}ch成功`,
      topic_id: d.topic_id,
    }));

  const thresholdLabel = threshold >= 1000 ? `${threshold / 1000}K` : threshold.toString();

  return (
    <div className="chart-card">
      <div className="chart-title-row">
        <h3>新規チャンネル成功率</h3>
        <HelpButton {...HELP_TEXTS.successRate} />
      </div>
      <p className="chart-desc">過去1年に開設されたチャンネルのうち登録者{thresholdLabel}人超の割合</p>

      <div className="success-controls">
        <div className="success-threshold">
          <span className="success-threshold-label">成功閾値:</span>
          {THRESHOLDS.map((t) => (
            <button
              key={t.value}
              className={`buzz-period-btn ${threshold === t.value ? 'active' : ''}`}
              onClick={() => setThreshold(t.value)}
            >
              {t.label}
            </button>
          ))}
        </div>
        <button className="view-toggle-btn" onClick={() => setShowList(!showList)}>
          {showList ? 'チャートに戻す' : 'ランキングで見る'}
        </button>
      </div>

      {threshold !== 1000 && !channelsLoaded && (
        <div className="loading"><div className="spinner" /><p>再計算中...</p></div>
      )}

      {(threshold === 1000 || channelsLoaded) && (
        showList ? (
          <RankingList items={rankingItems} valueLabel="成功率"
            valueFormatter={(v) => `${v}%`} onItemClick={onTopicClick} />
        ) : (
          <>
            <div className="chart-axis-labels">
              <span>X: 新規チャンネル数</span>
              <span>Y: 成功率(%)</span>
            </div>
            <ResponsiveContainer width="100%" height={isMobile ? 300 : 400}>
              <ScatterChart margin={isMobile
                ? { left: 5, bottom: 5, right: 10, top: 5 }
                : { left: 20, bottom: 20 }
              }>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis type="number" dataKey="new_channels" name="新規ch数" tick={{ fontSize: isMobile ? 9 : 12 }} />
                <YAxis type="number" dataKey="success_rate" name="成功率" unit="%"
                  tick={{ fontSize: isMobile ? 9 : 12 }} width={isMobile ? 35 : 60} />
                <ZAxis type="number" dataKey="successful" range={isMobile ? [30, 200] : [40, 400]} name="成功数" />
                <Tooltip
                  content={({ payload }) => {
                    if (!payload?.length) return null;
                    const d = payload[0].payload as ChartEntry;
                    return (
                      <div className="custom-tooltip">
                        <strong>{d.name}</strong>
                        <div>新規: {d.new_channels}ch</div>
                        <div>成功率: {d.success_rate}%</div>
                        <div>成功数: {d.successful}ch</div>
                        <div className="tooltip-hint">クリックで詳細</div>
                      </div>
                    );
                  }}
                />
                <Scatter data={chartData} fill="#10b981" cursor="pointer"
                  onClick={(entry: unknown) => onTopicClick?.((entry as ChartEntry).topic_id)} />
              </ScatterChart>
            </ResponsiveContainer>
          </>
        )
      )}
    </div>
  );
}
