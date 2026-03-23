import { useState, useEffect } from 'react';
import {
  ScatterChart, Scatter, XAxis, YAxis, Tooltip, ResponsiveContainer,
  CartesianGrid, ZAxis, Label,
} from 'recharts';
import { supabase } from '../lib/supabase';
import type { ChannelGrowthEfficiency } from '../types/database';

interface Props {
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

export function ChannelGrowthChart({ onTopicClick }: Props) {
  const [data, setData] = useState<ChannelGrowthEfficiency[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    supabase
      .from('channel_growth_efficiency')
      .select('*')
      .order('subs_per_day', { ascending: false })
      .limit(200)
      .then(({ data: d }) => {
        setData((d as ChannelGrowthEfficiency[]) ?? []);
        setLoading(false);
      });
  }, []);

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

  return (
    <div className="chart-card">
      <h3>チャンネル成長効率</h3>
      <p className="chart-desc">
        チャンネル年齢（月）vs 登録者数。左上にいるチャンネルは短期間で急成長（クリックで詳細）
      </p>
      <ResponsiveContainer width="100%" height={400}>
        <ScatterChart margin={{ left: 20, bottom: 30, right: 20, top: 10 }}>
          <CartesianGrid strokeDasharray="3 3" />
          <XAxis type="number" dataKey="age_months" name="チャンネル年齢" tick={{ fontSize: 11 }}>
            <Label value="チャンネル年齢（月）" position="bottom" offset={10} style={{ fill: '#9ca3af', fontSize: 12 }} />
          </XAxis>
          <YAxis
            type="number"
            dataKey="subscriber_count"
            name="登録者数"
            tick={{ fontSize: 11 }}
            tickFormatter={(v) => v >= 1000 ? `${(v / 1000).toFixed(0)}K` : v}
          >
            <Label value="登録者数" angle={-90} position="insideLeft" offset={-5} style={{ fill: '#9ca3af', fontSize: 12 }} />
          </YAxis>
          <ZAxis type="number" dataKey="views_per_video" range={[30, 300]} name="動画あたり再生" />
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
                  <div>動画あたり再生: {d.views_per_video.toLocaleString()}</div>
                  <div className="tooltip-hint">クリックで詳細</div>
                </div>
              );
            }}
          />
          <Scatter
            data={chartData}
            fill="#f59e0b"
            fillOpacity={0.6}
            cursor="pointer"
            onClick={(entry: unknown) => {
              const e = entry as ChartEntry;
              if (e.topic_ids?.length > 0) onTopicClick?.(e.topic_ids[0]);
            }}
          />
        </ScatterChart>
      </ResponsiveContainer>
    </div>
  );
}
