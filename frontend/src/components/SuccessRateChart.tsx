import {
  ScatterChart, Scatter, XAxis, YAxis, Tooltip, ResponsiveContainer,
  CartesianGrid, ZAxis,
} from 'recharts';
import type { NewChannelSuccessRate } from '../types/database';

interface Props {
  data: NewChannelSuccessRate[];
}

export function SuccessRateChart({ data }: Props) {
  const chartData = data
    .filter((d) => d.new_channel_count > 0)
    .map((d) => ({
      name: d.name_ja ?? d.topic_name,
      new_channels: d.new_channel_count,
      success_rate: d.success_rate_pct,
      successful: d.successful_count,
    }));

  return (
    <div className="chart-card">
      <h3>新規チャンネル成功率</h3>
      <p className="chart-desc">過去1年に開設されたチャンネルのうち登録者1,000人超の割合</p>
      <ResponsiveContainer width="100%" height={400}>
        <ScatterChart margin={{ left: 20, bottom: 20 }}>
          <CartesianGrid strokeDasharray="3 3" />
          <XAxis type="number" dataKey="new_channels" name="新規チャンネル数" />
          <YAxis type="number" dataKey="success_rate" name="成功率" unit="%" />
          <ZAxis type="number" dataKey="successful" range={[40, 400]} name="成功数" />
          <Tooltip
            content={({ payload }) => {
              if (!payload?.length) return null;
              const d = payload[0].payload as (typeof chartData)[number];
              return (
                <div className="custom-tooltip">
                  <strong>{d.name}</strong>
                  <div>新規: {d.new_channels}ch</div>
                  <div>成功率: {d.success_rate}%</div>
                  <div>成功数: {d.successful}ch</div>
                </div>
              );
            }}
          />
          <Scatter data={chartData} fill="#10b981" />
        </ScatterChart>
      </ResponsiveContainer>
    </div>
  );
}
