import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';

interface Props {
  value: string | null;
  onChange: (country: string | null) => void;
}

interface CountryRow {
  country: string;
  channel_count: number;
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
  RU: 'ロシア',
  ES: 'スペイン',
  IT: 'イタリア',
  VN: 'ベトナム',
  PK: 'パキスタン',
  BD: 'バングラデシュ',
  NG: 'ナイジェリア',
  AR: 'アルゼンチン',
  CO: 'コロンビア',
  MY: 'マレーシア',
  SG: 'シンガポール',
  HK: '香港',
  NL: 'オランダ',
  SE: 'スウェーデン',
  PL: 'ポーランド',
  TR: 'トルコ',
  SA: 'サウジアラビア',
  AE: 'UAE',
  EG: 'エジプト',
  ZA: '南アフリカ',
  CL: 'チリ',
  PE: 'ペルー',
  NZ: 'ニュージーランド',
  UA: 'ウクライナ',
  CZ: 'チェコ',
  RO: 'ルーマニア',
  IL: 'イスラエル',
  NO: 'ノルウェー',
  DK: 'デンマーク',
  FI: 'フィンランド',
  BE: 'ベルギー',
  AT: 'オーストリア',
  CH: 'スイス',
  PT: 'ポルトガル',
  IE: 'アイルランド',
  NP: 'ネパール',
  LK: 'スリランカ',
  MM: 'ミャンマー',
  KH: 'カンボジア',
};

export function CountryFilter({ value, onChange }: Props) {
  const [countries, setCountries] = useState<CountryRow[]>([]);

  useEffect(() => {
    let cancelled = false;
    // channels テーブルから国別チャンネル数を集計
    supabase
      .from('channels')
      .select('country')
      .not('country', 'is', null)
      .then((res) => {
        if (cancelled || !res.data) return;
        // クライアント側で集計
        const counts = new Map<string, number>();
        for (const row of res.data as { country: string }[]) {
          counts.set(row.country, (counts.get(row.country) ?? 0) + 1);
        }
        const sorted = Array.from(counts.entries())
          .map(([country, channel_count]) => ({ country, channel_count }))
          .sort((a, b) => b.channel_count - a.channel_count);
        setCountries(sorted);
      });
    return () => { cancelled = true; };
  }, []);

  const label = (code: string) => COUNTRY_NAMES[code] ?? code;

  return (
    <div className="country-filter">
      <span className="topic-filter-label">国</span>
      <select
        className="topic-filter-select"
        value={value ?? ''}
        onChange={(e) => onChange(e.target.value === '' ? null : e.target.value)}
      >
        <option value="">指定しない</option>
        <option value="JP">日本</option>
        {countries
          .filter((c) => c.country !== 'JP')
          .map((c) => (
            <option key={c.country} value={c.country}>
              {label(c.country)}（{c.channel_count.toLocaleString()}）
            </option>
          ))}
      </select>
    </div>
  );
}
