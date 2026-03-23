import type { TopicSummary } from '../types/database';

interface Props {
  data: TopicSummary[];
  onTopicClick?: (topicId: string) => void;
}

export function TopicTable({ data, onTopicClick }: Props) {
  const sorted = [...data]
    .filter((d) => d.parent_id !== null)
    .sort((a, b) => b.gap_score - a.gap_score);

  return (
    <div className="chart-card">
      <h3>ジャンル別サマリー</h3>
      <p className="chart-desc">行をクリックすると動画・チャンネルの詳細を表示</p>
      <div className="table-wrap">
        <table>
          <thead>
            <tr>
              <th>ジャンル</th>
              <th>カテゴリ</th>
              <th>動画数</th>
              <th>チャンネル数</th>
              <th>平均再生</th>
              <th>ギャップ</th>
              <th>いいね率</th>
              <th>コメ率</th>
            </tr>
          </thead>
          <tbody>
            {sorted.map((row) => (
              <tr
                key={row.topic_id}
                className="clickable-row"
                onClick={() => onTopicClick?.(row.topic_id)}
              >
                <td>{row.name_ja ?? row.topic_name}</td>
                <td><span className={`badge badge-${row.category.toLowerCase()}`}>{row.category}</span></td>
                <td>{row.total_videos.toLocaleString()}</td>
                <td>{row.total_channels.toLocaleString()}</td>
                <td>{row.avg_views.toLocaleString()}</td>
                <td><strong>{row.gap_score.toLocaleString()}</strong></td>
                <td>{row.like_rate_pct}%</td>
                <td>{row.comment_rate_pct}%</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
