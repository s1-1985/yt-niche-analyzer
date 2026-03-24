import { useState, useEffect } from 'react';
import {
  ScatterChart, Scatter, XAxis, YAxis, Tooltip, ResponsiveContainer,
  CartesianGrid, ZAxis, Label,
} from 'recharts';
import { useIsMobile } from '../hooks/useIsMobile';
import { HelpButton, HELP_TEXTS } from './HelpButton';
import { RankingList, type RankingItem } from './RankingList';
import { supabase } from '../lib/supabase';
import type { ChannelGrowthEfficiency } from '../types/database';
import type { TimePeriod, VideoType } from '../hooks/useFilteredQuery';

interface Props {
  period: TimePeriod;
  videoType?: VideoType;
  country?: string | null;
  onTopicClick?: (topicId: string) => void;
}

interface ChartEntry {
  name: string;
  age_months: number;
  subscriber_count: number;
  subs_per_day: number;
  views_per_video: number;
  topic_ids: string[];
}

function getMinDate(period: TimePeriod): string | null {
  if (period === 'all') return null;
  const now = new Date();
  switch (period) {
    case '24h': now.setHours(now.getHours() - 24); break;
    case '1w': now.setDate(now.getDate() - 7); break;
    case '1m': now.setMonth(now.getMonth() - 1); break;
    case '3m': now.setMonth(now.getMonth() - 3); break;
  }
  return now.toISOString();
}

export function ChannelGrowthChart({ period, videoType = 'all', country = null, onTopicClick }: Props) {
  const isMobile = useIsMobile();
  const [data, setData] = useState<ChannelGrowthEfficiency[]>([]);
  const [loading, setLoading] = useState(true);
  const [showList, setShowList] = useState(false);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    const minDate = getMinDate(period);
    const fetchData = async () => {
      let result;
      if (period === 'all' && videoType === 'all' && country === null) {
        result = await supabase.from('channel_growth_efficiency').select('*')
          .order('subs_per_day', { ascending: false }).limit(200);
      } else {
        result = await supabase.rpc('fn_channel_growth_efficiency', {
          p_min_date: minDate, p_video_type: videoType, p_country: country,
        });
      }
      if (cancelled) return;
      setData((result.data as ChannelGrowthEfficiency[])?.slice(0, 200) ?? []);
      setLoading(false);
    };
    fetchData();
    return () => { cancelled = true; };
  }, [period, videoType, country]);

  if (loading) return null;
  if (data.length === 0) return null;

  const chartData: ChartEntry[] = data.map((d) => ({
    name: d.title,
    age_months: Math.round(d.age_days / 30),
    subscriber_count: d.subscriber_count,
    subs_per_day: d.subs_per_day,
    views_per_video: d.views_per_video,
    topic_ids: d.topic_ids,
  }));

  const rankingItems: RankingItem[] = [...chartData]
    .sort((a, b) => b.subs_per_day - a.subs_per_day)
    .slice(0, 30)
    .map((d) => ({
      name: d.name,
      value: d.subs_per_day,
      sub: `${d.subscriber_count.toLocaleString()}登録 / ${d.age_months}ヶ月`,
      topic_id: d.topic_ids?.[0],
    }));

  return (
    <div className="chart-card">
      <div className="chart-title-row">
        <h3>チャンネル成長効率</h3>
        <HelpButton {...HELP_TEXTS.channelGrowth} />
      </div>
      <p className="chart-desc">チャンネル年齢 vs 登録者数。左上が短期間で急成長</p>
      <button className="view-toggle-btn" onClick={() => setShowList(!showList)}>
        {showList ? 'チャートに戻す' : 'ランキングで見る'}
      </button>

      {showList ? (
        <RankingList items={rankingItems} valueLabel="成長/日"
          valueFormatter={(v) => `${v}/日`} onItemClick={onTopicClick} />
      ) : (
        <>
          <div className="chart-axis-labels">
            <span>X: チャンネル年齢（月）</span>
            <span>Y: 登録者数</span>
          </div>
          <ResponsiveContainer width="100%" height={isMobile ? 300 : 400}>
            <ScatterChart margin={isMobile
              ? { left: 5, bottom: 5, right: 10, top: 5 }
              : { left: 20, bottom: 30, right: 20, top: 10 }
            }>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis type="number" dataKey="age_months" name="年齢" tick={{ fontSize: isMobile ? 9 : 11 }}>
                {!isMobile && <Label value="チャンネル年齢（月）" position="bottom" offset={10} style={{ fill: '#9ca3af', fontSize: 12 }} />}
              </XAxis>
              <YAxis type="number" dataKey="subscriber_count" name="登録者"
                tick={{ fontSize: isMobile ? 9 : 11 }} width={isMobile ? 40 : 60}
                tickFormatter={(v) => v >= 1000 ? `${(v / 1000).toFixed(0)}K` : v}>
                {!isMobile && <Label value="登録者数" angle={-90} position="insideLeft" offset={-5} style={{ fill: '#9ca3af', fontSize: 12 }} />}
              </YAxis>
              <ZAxis type="number" dataKey="views_per_video" range={isMobile ? [20, 150] : [30, 300]} name="動画あたり再生" />
              <Tooltip
                content={({ payload }) => {
                  if (!payload?.length) return null;
                  const d = payload[0].payload as ChartEntry;
                  return (
                    <div className="custom-tooltip">
                      <strong>{d.name}</strong>
                      <div>年齢: {d.age_months}ヶ月</div>
                      <div>登録者: {d.subscriber_count.toLocaleString()}</div>
                      <div>日あたり成長: {d.subs_per_day}/日</div>
                      <div className="tooltip-hint">クリックで詳細</div>
                    </div>
                  );
                }}
              />
              <Scatter data={chartData} fill="#f59e0b" fillOpacity={0.6} cursor="pointer"
                onClick={(entry: unknown) => {
                  const e = entry as ChartEntry;
                  if (e.topic_ids?.length > 0) onTopicClick?.(e.topic_ids[0]);
                }} />
            </ScatterChart>
          </ResponsiveContainer>
        </>
      )}
    </div>
  );
}
