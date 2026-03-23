import type { VideoType } from '../hooks/useFilteredQuery';

interface Props {
  value: VideoType;
  onChange: (v: VideoType) => void;
}

const OPTIONS: { value: VideoType; label: string }[] = [
  { value: 'all', label: 'すべて' },
  { value: 'normal', label: '通常動画' },
  { value: 'short', label: 'ショート' },
];

export function VideoTypeFilter({ value, onChange }: Props) {
  return (
    <div className="video-type-filter">
      <span className="time-filter-label">動画タイプ</span>
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
