import {
  ScatterChart, Scatter, XAxis, YAxis, Tooltip, ResponsiveContainer,
  CartesianGrid, ZAxis,
} from 'recharts';
import { useIsMobile } from '../hooks/useIsMobile';
import type { NewChannelSuccessRate } from '../types/database';

interface Props {
  data: NewChannelSuccessRate[];
  onTopicClick?: (topicId: string) => void;
}

interface ChartEntry {
  name: string;
  new_channels: number;
  success_rate: number;
  successful: number;
  topic_id: string;
}

export function SuccessRateChart({ data, onTopicClick }: Props) {
  const isMobile = useIsMobile();
  const chartData: ChartEntry[] = data
    .filter((d) => d.new_channel_count > 0)
    .map((d) => ({
      name: d.name_ja ?? d.topic_name,
      new_channels: d.new_channel_count,
      success_rate: d.success_rate_pct,
      successful: d.successful_count,
      topic_id: d.topic_id,
    }));

  return (
    <div className="chart-card">
      <h3>新規チャンネル成功率</h3>
      <p className="chart-desc">過去1年に開設されたチャンネルのうち登録者1,000人超の割合（クリックで詳細）</p>
      <ResponsiveContainer width="100%" height={isMobile ? 300 : 400}>
        <ScatterChart margin={isMobile
          ? { left: 5, bottom: 5, right: 10, top: 5 }
          : { left: 20, bottom: 20 }
        }>
          <CartesianGrid strokeDasharray="3 3" />
          <XAxis type="number" dataKey="new_channels" name="新規チャンネル数" tick={{ fontSize: isMobile ? 9 : 12 }} />
          <YAxis
            type="number"
            dataKey="success_rate"
            name="成功率"
            unit="%"
            tick={{ fontSize: isMobile ? 9 : 12 }}
            width={isMobile ? 35 : 60}
          />
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
          <Scatter
            data={chartData}
            fill="#10b981"
            cursor="pointer"
            onClick={(entry: unknown) => onTopicClick?.((entry as ChartEntry).topic_id)}
          />
        </ScatterChart>
      </ResponsiveContainer>
    </div>
  );
}
