import {
  BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid,
} from 'recharts';
import { useIsMobile } from '../hooks/useIsMobile';
import type { TopicCountryDistribution } from '../types/database';

interface Props {
  data: TopicCountryDistribution[];
}

interface ChartEntry {
  country: string;
  channel_count: number;
  total_subscribers: number;
}

const COUNTRY_NAMES: Record<string, string> = {
  JP: '日本',
  US: 'アメリカ',
  KR: '韓国',
  IN: 'インド',
  GB: 'イギリス',
  TW: '台湾',
  TH: 'タイ',
  PH: 'フィリピン',
  ID: 'インドネシア',
  BR: 'ブラジル',
  CA: 'カナダ',
  AU: 'オーストラリア',
  DE: 'ドイツ',
  FR: 'フランス',
  MX: 'メキシコ',
  Unknown: '不明',
};

function truncate(s: string, max: number): string {
  return s.length > max ? s.slice(0, max) + '…' : s;
}

export function CountryChart({ data }: Props) {
  const isMobile = useIsMobile();

  // Aggregate across all topics by country
  const byCountry = new Map<string, { channels: number; subs: number }>();
  for (const row of data) {
    const cur = byCountry.get(row.country) ?? { channels: 0, subs: 0 };
    cur.channels += row.channel_count;
    cur.subs += row.total_subscribers;
    byCountry.set(row.country, cur);
  }

  const itemCount = isMobile ? 10 : 15;
  const chartData: ChartEntry[] = Array.from(byCountry.entries())
    .map(([country, vals]) => ({
      country: COUNTRY_NAMES[country] ?? country,
      channel_count: vals.channels,
      total_subscribers: vals.subs,
    }))
    .sort((a, b) => b.channel_count - a.channel_count)
    .slice(0, itemCount);

  const chartHeight = isMobile ? itemCount * 36 + 40 : 400;

  return (
    <div className="chart-card">
      <h3>国別チャンネル分布</h3>
      <p className="chart-desc">
        チャンネルの所在国。日本の割合が少ないジャンル = 日本語コンテンツの穴がある可能性
      </p>
      <ResponsiveContainer width="100%" height={chartHeight}>
        <BarChart data={chartData} layout="vertical" margin={{ left: isMobile ? 10 : 100 }}>
          <CartesianGrid strokeDasharray="3 3" />
          <XAxis type="number" tick={{ fontSize: isMobile ? 10 : 11 }} />
          <YAxis
            type="category"
            dataKey="country"
            width={isMobile ? 60 : 90}
            tick={{ fontSize: isMobile ? 10 : 12 }}
            tickFormatter={(v) => truncate(v, isMobile ? 6 : 20)}
          />
          <Tooltip
            content={({ payload }) => {
              if (!payload?.length) return null;
              const d = payload[0].payload as ChartEntry;
              return (
                <div className="custom-tooltip">
                  <strong>{d.country}</strong>
                  <div>チャンネル数: {d.channel_count.toLocaleString()}</div>
                  <div>総登録者: {d.total_subscribers.toLocaleString()}</div>
                </div>
              );
            }}
          />
          <Bar
            dataKey="channel_count"
            fill="#22d3ee"
            name="チャンネル数"
            radius={[0, 4, 4, 0]}
          />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
