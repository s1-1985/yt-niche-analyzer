import { useIsMobile } from '../hooks/useIsMobile';

export interface RankingItem {
  name: string;
  value: number;
  sub?: string;
  topic_id?: string;
}

interface Props {
  items: RankingItem[];
  valueLabel: string;
  valueFormatter?: (v: number) => string;
  onItemClick?: (topicId: string) => void;
}

export function RankingList({ items, valueLabel, valueFormatter, onItemClick }: Props) {
  const isMobile = useIsMobile();
  const maxVal = items.length > 0 ? Math.max(...items.map((i) => Math.abs(i.value))) : 1;
  const fmt = valueFormatter ?? ((v: number) => v.toLocaleString());

  return (
    <div className="ranking-list">
      <div className="ranking-header-row">
        <span className="ranking-h-rank">#</span>
        <span className="ranking-h-name">ジャンル</span>
        <span className="ranking-h-bar"></span>
        <span className="ranking-h-value">{valueLabel}</span>
      </div>
      {items.map((item, i) => (
        <div
          key={i}
          className={`ranking-row ${item.topic_id ? 'ranking-clickable' : ''}`}
          onClick={() => item.topic_id && onItemClick?.(item.topic_id)}
        >
          <span className="ranking-rank">{i + 1}</span>
          <span className="ranking-name" title={item.name}>
            {isMobile && item.name.length > 8 ? item.name.slice(0, 8) + '…' : item.name}
          </span>
          <div className="ranking-bar-wrap">
            <div
              className="ranking-bar"
              style={{ width: `${(Math.abs(item.value) / maxVal) * 100}%` }}
            />
          </div>
          <span className="ranking-value">{fmt(item.value)}</span>
          {item.sub && <span className="ranking-sub">{item.sub}</span>}
        </div>
      ))}
      {items.length === 0 && <div className="empty-msg">データなし</div>}
    </div>
  );
}
