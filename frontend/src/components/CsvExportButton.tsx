import type { TopicSummary, CompetitionConcentration, NewChannelSuccessRate, AiPenetration } from '../types/database';

interface Props {
  topics: TopicSummary[];
  competition: CompetitionConcentration[];
  successRate: NewChannelSuccessRate[];
  aiPenetration: AiPenetration[];
}

function escapeCsv(val: string | number | null | undefined): string {
  if (val === null || val === undefined) return '';
  const s = String(val);
  if (s.includes(',') || s.includes('"') || s.includes('\n')) {
    return `"${s.replace(/"/g, '""')}"`;
  }
  return s;
}

export function CsvExportButton({ topics, competition, successRate, aiPenetration }: Props) {
  const compMap = new Map(competition.map((c) => [c.topic_id, c.top5_share_pct]));
  const successMap = new Map(successRate.map((s) => [s.topic_id, s]));
  const aiMap = new Map(aiPenetration.map((a) => [a.topic_id, a.ai_penetration_pct]));

  const handleExport = () => {
    const headers = [
      'ジャンル', 'カテゴリ', '動画数', 'チャンネル数', '総再生数', '平均再生数',
      'ギャップスコア', 'いいね率(%)', 'コメント率(%)',
      '競合集中度(%)', '新規チャンネル数', '成功数', '成功率(%)', 'AI浸透度(%)',
    ];

    const subTopics = topics.filter((t) => t.parent_id !== null);

    const rows = subTopics.map((t) => {
      const succ = successMap.get(t.topic_id);
      return [
        t.name_ja ?? t.topic_name,
        t.category,
        t.total_videos,
        t.total_channels,
        t.total_views,
        t.avg_views,
        t.gap_score,
        t.like_rate_pct,
        t.comment_rate_pct,
        compMap.get(t.topic_id) ?? '',
        succ?.new_channel_count ?? '',
        succ?.successful_count ?? '',
        succ?.success_rate_pct ?? '',
        aiMap.get(t.topic_id) ?? '',
      ];
    });

    const bom = '\uFEFF';
    const csv = bom + headers.map(escapeCsv).join(',') + '\n' +
      rows.map((r) => r.map(escapeCsv).join(',')).join('\n');

    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `yt-niche-analysis-${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <button className="csv-export-btn" onClick={handleExport} title="フィルタ済みデータをCSVでダウンロード">
      CSV出力
    </button>
  );
}
