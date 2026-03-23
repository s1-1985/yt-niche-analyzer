import { useState } from 'react';
import type {
  TopicSummary, CompetitionConcentration, NewChannelSuccessRate, AiPenetration,
  TopicDurationStats, TopicChannelSize, TopicPublishDay, TopicCountryDistribution,
  TopicPopularTag, TopicOverlap,
} from '../types/database';
import type { TimePeriod } from '../hooks/useFilteredQuery';

interface Props {
  period: TimePeriod;
  topics: TopicSummary[];
  competition: CompetitionConcentration[];
  successRate: NewChannelSuccessRate[];
  aiPenetration: AiPenetration[];
  duration: TopicDurationStats[];
  channelSize: TopicChannelSize[];
  publishDay: TopicPublishDay[];
  countryDist: TopicCountryDistribution[];
  tags: TopicPopularTag[];
  overlap: TopicOverlap[];
}

const PERIOD_LABELS: Record<TimePeriod, string> = {
  '24h': '直近24時間',
  '1w': '直近1週間',
  '1m': '直近1ヶ月',
  '3m': '直近3ヶ月',
  'all': '全期間',
};

function buildPrompt(props: Props): string {
  const {
    period, topics, competition, successRate, aiPenetration,
    duration, channelSize, publishDay, countryDist, tags, overlap,
  } = props;

  const sub = topics.filter((t) => t.parent_id !== null);
  const compMap = new Map(competition.map((c) => [c.topic_id, c]));
  const successMap = new Map(successRate.map((s) => [s.topic_id, s]));
  const aiMap = new Map(aiPenetration.map((a) => [a.topic_id, a]));
  // Build niche score ranking
  const scored = sub.map((t) => {
    const comp = compMap.get(t.topic_id);
    const succ = successMap.get(t.topic_id);
    const ai = aiMap.get(t.topic_id);
    const gapN = sub.length > 1 ? (t.gap_score - Math.min(...sub.map((s) => s.gap_score))) / (Math.max(...sub.map((s) => s.gap_score)) - Math.min(...sub.map((s) => s.gap_score)) || 1) * 100 : 50;
    const compN = comp ? 100 - comp.top5_share_pct : 50;
    const succN = succ ? succ.success_rate_pct : 0;
    const aiN = ai ? 100 - ai.ai_penetration_pct : 50;
    const nicheScore = Math.round(gapN * 0.3 + compN * 0.25 + succN * 0.25 + aiN * 0.2);
    return { ...t, nicheScore, comp, succ, ai };
  }).sort((a, b) => b.nicheScore - a.nicheScore);

  // Day of week analysis
  const DAY_NAMES = ['日', '月', '火', '水', '木', '金', '土'];
  const dayAgg = new Map<number, { count: number; views: number }>();
  for (const row of publishDay) {
    const cur = dayAgg.get(row.dow) ?? { count: 0, views: 0 };
    cur.count += row.video_count;
    cur.views += row.avg_views * row.video_count;
    dayAgg.set(row.dow, cur);
  }
  const dayRanking = Array.from(dayAgg.entries())
    .map(([dow, v]) => ({ day: DAY_NAMES[dow], avgViews: v.count > 0 ? Math.round(v.views / v.count) : 0 }))
    .sort((a, b) => b.avgViews - a.avgViews);

  // Country summary
  const countryAgg = new Map<string, number>();
  for (const row of countryDist) {
    countryAgg.set(row.country, (countryAgg.get(row.country) ?? 0) + row.channel_count);
  }
  const topCountries = Array.from(countryAgg.entries())
    .sort((a, b) => b[1] - a[1])
    .slice(0, 10);

  // Tags per topic (top 3 topics with their tags)
  const tagsByTopic = new Map<string, string[]>();
  for (const t of tags) {
    if (!tagsByTopic.has(t.topic_id)) tagsByTopic.set(t.topic_id, []);
    tagsByTopic.get(t.topic_id)!.push(t.tag);
  }

  // Overlap
  const topOverlap = overlap
    .sort((a, b) => b.shared_channels - a.shared_channels)
    .slice(0, 10);

  const lines: string[] = [];

  lines.push(`# YouTube ニッチ分析レポート（${PERIOD_LABELS[period]}のデータ）`);
  lines.push('');
  lines.push('以下はYouTubeのジャンル別分析データです。このデータをもとに、新規YouTubeチャンネルとして「どのジャンルで、どんな動画を、どのように作るべきか」を具体的に提案してください。');
  lines.push('');
  lines.push('## 提案に含めてほしい内容:');
  lines.push('1. **参入すべきジャンル TOP3**（理由つき）');
  lines.push('2. **各ジャンルの具体的な動画企画案**（3本ずつ、タイトル案・内容・ターゲット視聴者）');
  lines.push('3. **推奨動画尺**（ジャンルごと）');
  lines.push('4. **推奨投稿曜日・頻度**');
  lines.push('5. **使うべきタグ**');
  lines.push('6. **差別化戦略**（競合との差別化ポイント）');
  lines.push('7. **成長ロードマップ**（0→1000登録者までの戦略）');
  lines.push('8. **AI活用の余地**（AI浸透度が低いジャンルでのAI活用戦略）');
  lines.push('9. **隣接ニッチ展開**（将来的に広げるべきジャンル）');
  lines.push('');

  // === Niche Score Ranking ===
  lines.push('## ニッチスコアランキング（総合評価 / 100点）');
  lines.push('| 順位 | ジャンル | カテゴリ | スコア | 需給ギャップ | 競合集中(Top5%) | 新規成功率 | AI浸透度 | 平均再生数 |');
  lines.push('|------|---------|---------|--------|------------|---------------|-----------|---------|-----------|');
  for (let i = 0; i < Math.min(scored.length, 20); i++) {
    const t = scored[i];
    lines.push(
      `| ${i + 1} | ${t.name_ja ?? t.topic_name} | ${t.category} | ${t.nicheScore} | ${t.gap_score.toLocaleString()} | ${t.comp?.top5_share_pct ?? '-'}% | ${t.succ?.success_rate_pct ?? '-'}% | ${t.ai?.ai_penetration_pct ?? '-'}% | ${t.avg_views.toLocaleString()} |`
    );
  }
  lines.push('');

  // === Duration Stats ===
  if (duration.length > 0) {
    lines.push('## 動画尺分析');
    lines.push('| ジャンル | 平均尺(秒) | 中央値(秒) | ショート(~60s) | ミドル(1~10分) | ロング(10分~) |');
    lines.push('|---------|-----------|-----------|--------------|--------------|-------------|');
    for (const d of duration.filter((d) => d.parent_id !== null).slice(0, 15)) {
      lines.push(
        `| ${d.name_ja ?? d.topic_name} | ${d.avg_duration} | ${d.median_duration} | ${d.short_count} | ${d.medium_count} | ${d.long_count} |`
      );
    }
    lines.push('');
  }

  // === Channel Size Distribution ===
  if (channelSize.length > 0) {
    lines.push('## チャンネル規模分布');
    lines.push('| ジャンル | 小(<1K) | 中(1K-10K) | 大(10K-100K) | メガ(100K+) |');
    lines.push('|---------|---------|-----------|-------------|------------|');
    for (const s of channelSize.filter((s) => s.parent_id !== null).slice(0, 15)) {
      lines.push(
        `| ${s.name_ja ?? s.topic_name} | ${s.small_pct}% | ${s.medium_pct}% | ${s.large_pct}% | ${s.mega_pct}% |`
      );
    }
    lines.push('');
  }

  // === Publish Day ===
  if (dayRanking.length > 0) {
    lines.push('## 投稿曜日と平均再生数');
    for (const d of dayRanking) {
      lines.push(`- ${d.day}曜日: 平均 ${d.avgViews.toLocaleString()} 再生`);
    }
    lines.push('');
  }

  // === Country ===
  if (topCountries.length > 0) {
    lines.push('## 国別チャンネル分布 TOP10');
    for (const [country, count] of topCountries) {
      lines.push(`- ${country}: ${count} チャンネル`);
    }
    lines.push('');
  }

  // === Tags ===
  if (tagsByTopic.size > 0) {
    lines.push('## ジャンル別人気タグ');
    const topScoredIds = scored.slice(0, 10).map((s) => s.topic_id);
    for (const tid of topScoredIds) {
      const topicTags = tagsByTopic.get(tid);
      const topic = scored.find((s) => s.topic_id === tid);
      if (topicTags && topic) {
        lines.push(`- **${topic.name_ja ?? topic.topic_name}**: ${topicTags.join(', ')}`);
      }
    }
    lines.push('');
  }

  // === Overlap ===
  if (topOverlap.length > 0) {
    lines.push('## ジャンル間のチャンネル重複（隣接ニッチ）');
    for (const o of topOverlap) {
      lines.push(`- ${o.name_a} × ${o.name_b}: ${o.shared_channels} チャンネル共有`);
    }
    lines.push('');
  }

  // === Engagement ===
  lines.push('## エンゲージメント分析');
  lines.push('| ジャンル | いいね率 | コメント率 | 深度(コメント/いいね) |');
  lines.push('|---------|---------|-----------|-------------------|');
  for (const t of sub.sort((a, b) => {
    const depthA = a.like_rate_pct > 0 ? a.comment_rate_pct / a.like_rate_pct : 0;
    const depthB = b.like_rate_pct > 0 ? b.comment_rate_pct / b.like_rate_pct : 0;
    return depthB - depthA;
  }).slice(0, 15)) {
    const depth = t.like_rate_pct > 0
      ? Math.round((t.comment_rate_pct / t.like_rate_pct) * 1000) / 10
      : 0;
    lines.push(
      `| ${t.name_ja ?? t.topic_name} | ${t.like_rate_pct}% | ${t.comment_rate_pct}% | ${depth} |`
    );
  }
  lines.push('');

  lines.push('---');
  lines.push('上記のデータに基づき、具体的で実行可能な提案を日本語でお願いします。データの数字を引用しながら、なぜその戦略が有効なのかの根拠も示してください。');

  return lines.join('\n');
}

export function AiPromptCopyButton(props: Props) {
  const [copied, setCopied] = useState(false);
  const [showPreview, setShowPreview] = useState(false);

  const prompt = buildPrompt(props);

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(prompt);
      setCopied(true);
      setTimeout(() => setCopied(false), 2500);
    } catch {
      // Fallback
      const textarea = document.createElement('textarea');
      textarea.value = prompt;
      document.body.appendChild(textarea);
      textarea.select();
      document.execCommand('copy');
      document.body.removeChild(textarea);
      setCopied(true);
      setTimeout(() => setCopied(false), 2500);
    }
  };

  return (
    <div className="ai-prompt-section">
      <div className="ai-prompt-header">
        <h3>AI分析プロンプト生成</h3>
        <p className="chart-desc">
          現在の分析データをAI（ChatGPT / Claude等）に読み込ませて「結局どんな動画を作ればいいのか」を具体的に解析させよう
        </p>
      </div>
      <div className="ai-prompt-actions">
        <button className="ai-prompt-copy-btn" onClick={handleCopy}>
          {copied ? 'コピーしました!' : 'AIプロンプトをクリップボードにコピー'}
        </button>
        <button
          className="ai-prompt-preview-btn"
          onClick={() => setShowPreview(!showPreview)}
        >
          {showPreview ? 'プレビューを閉じる' : 'プレビューを見る'}
        </button>
      </div>
      <p className="ai-prompt-hint">
        コピーしたテキストをそのままChatGPTやClaudeに貼り付けるだけで、分析に基づいた具体的な動画企画案が返ってきます
      </p>
      {showPreview && (
        <pre className="ai-prompt-preview">{prompt}</pre>
      )}
    </div>
  );
}
