import { useMemo } from 'react';
import { HelpButton } from './HelpButton';
import type { TopicSummary, TopicOverlap } from '../types/database';

interface Props {
  topics: TopicSummary[];
  overlap: TopicOverlap[];
  onTopicClick?: (topicId: string) => void;
}

interface CrossNiche {
  topicA: string;
  nameA: string;
  topicB: string;
  nameB: string;
  sharedChannels: number;
  combinedGapScore: number;
  avgLikeRate: number;
  totalChannels: number;
  opportunity: number;
}

export function CrossGenreScore({ topics, overlap, onTopicClick }: Props) {
  const crossNiches = useMemo(() => {
    const topicMap = new Map(topics.map((t) => [t.topic_id, t]));

    const results: CrossNiche[] = [];

    for (const o of overlap) {
      const tA = topicMap.get(o.topic_a);
      const tB = topicMap.get(o.topic_b);
      if (!tA || !tB) continue;
      if (tA.parent_id === null || tB.parent_id === null) continue;

      // Combined gap score: average of both gap scores, weighted by overlap
      const combinedGap = (tA.gap_score + tB.gap_score) / 2;
      const avgLike = (tA.like_rate_pct + tB.like_rate_pct) / 2;
      const totalCh = tA.total_channels + tB.total_channels;

      // Opportunity = high gap + high overlap + low total channels
      // Normalize: gap contributes positively, channels inversely
      const overlapBonus = Math.min(o.shared_channels / 5, 3); // Cap at 3x
      const opportunity = Math.round(combinedGap * (1 + overlapBonus * 0.1));

      results.push({
        topicA: o.topic_a,
        nameA: o.name_a ?? tA.topic_name,
        topicB: o.topic_b,
        nameB: o.name_b ?? tB.topic_name,
        sharedChannels: o.shared_channels,
        combinedGapScore: Math.round(combinedGap),
        avgLikeRate: Math.round(avgLike * 100) / 100,
        totalChannels: totalCh,
        opportunity,
      });
    }

    return results.sort((a, b) => b.opportunity - a.opportunity).slice(0, 15);
  }, [topics, overlap]);

  if (crossNiches.length === 0) return null;

  const maxOpp = crossNiches[0]?.opportunity ?? 1;

  return (
    <div className="chart-card">
      <div className="chart-title-row">
        <h3>クロスニッチ機会スコア</h3>
        <HelpButton
          title="クロスニッチ機会スコアとは？"
          content={'2つのジャンルの掛け合わせによる参入機会を数値化したものです。\n共有チャンネルが多い=オーディエンスの重複が大きい=掛け合わせコンテンツの需要あり。\nギャップスコアが高い=供給不足。\nスコアが高いほど「まだ誰もやっていない × 視聴者がいる」掛け合わせニッチです。\n例: フィットネス×料理 = 筋トレ飯チャンネル'}
        />
      </div>
      <p className="chart-desc">
        チャンネル重複データから算出した「掛け合わせニッチ」の参入機会ランキング
      </p>

      <div className="cross-genre-list">
        {crossNiches.map((cn, i) => (
          <div key={`${cn.topicA}-${cn.topicB}`} className="cross-genre-item">
            <span className="cross-genre-rank">#{i + 1}</span>
            <div className="cross-genre-names">
              <button className="overlap-topic" onClick={() => onTopicClick?.(cn.topicA)}>
                {cn.nameA}
              </button>
              <span className="overlap-x">&times;</span>
              <button className="overlap-topic" onClick={() => onTopicClick?.(cn.topicB)}>
                {cn.nameB}
              </button>
            </div>
            <div className="cross-genre-bar-wrap">
              <div
                className="cross-genre-bar"
                style={{ width: `${(cn.opportunity / maxOpp) * 100}%` }}
              />
            </div>
            <div className="cross-genre-stats">
              <span className="cross-genre-score">{cn.opportunity.toLocaleString()}</span>
              <span className="cross-genre-detail">
                Gap:{cn.combinedGapScore.toLocaleString()} / {cn.sharedChannels}ch共有
              </span>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
