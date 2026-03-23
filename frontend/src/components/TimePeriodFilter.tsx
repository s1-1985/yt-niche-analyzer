import type { TimePeriod } from '../hooks/useFilteredQuery';

interface Props {
  value: TimePeriod;
  onChange: (period: TimePeriod) => void;
}

const OPTIONS: { value: TimePeriod; label: string }[] = [
  { value: '24h', label: '24時間' },
  { value: '1w', label: '1週間' },
  { value: '1m', label: '1ヶ月' },
  { value: '3m', label: '3ヶ月' },
  { value: 'all', label: '全期間' },
];

export function TimePeriodFilter({ value, onChange }: Props) {
  return (
    <div className="time-filter">
      <span className="time-filter-label">分析期間:</span>
      <div className="time-filter-buttons">
        {OPTIONS.map((opt) => (
          <button
            key={opt.value}
            className={`time-filter-btn ${value === opt.value ? 'active' : ''}`}
            onClick={() => onChange(opt.value)}
          >
            {opt.label}
          </button>
        ))}
      </div>
    </div>
  );
}
