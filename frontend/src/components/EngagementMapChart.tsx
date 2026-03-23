import { useState } from 'react';
import {
  ScatterChart, Scatter, XAxis, YAxis, Tooltip, ResponsiveContainer,
  CartesianGrid, ZAxis, Label,
} from 'recharts';
import { useIsMobile } from '../hooks/useIsMobile';
import { HelpButton, HELP_TEXTS } from './HelpButton';
import { RankingList, type RankingItem } from './RankingList';
import type { TopicSummary } from '../types/database';

interface Props {
  data: TopicSummary[];
  onTopicClick?: (topicId: string) => void;
}

interface ChartEntry {
  name: string;
  like_rate: number;
  comment_rate: number;
  total_videos: number;
  engagement_score: number;
  topic_id: string;
}

export function EngagementMapChart({ data, onTopicClick }: Props) {
  const isMobile = useIsMobile();
  const [showList, setShowList] = useState(false);

  const chartData: ChartEntry[] = data
    .filter((d) => d.parent_id !== null && d.like_rate_pct > 0)
    .map((d) => ({
      name: d.name_ja ?? d.topic_name,
      like_rate: d.like_rate_pct,
      comment_rate: d.comment_rate_pct,
      total_videos: d.total_videos,
      engagement_score: Math.round((d.like_rate_pct + d.comment_rate_pct * 10) * 100) / 100,
      topic_id: d.topic_id,
    }));

  const rankingItems: RankingItem[] = [...chartData]
    .sort((a, b) => b.engagement_score - a.engagement_score)
    .map((d) => ({
      name: d.name,
      value: d.engagement_score,
      sub: `いいね${d.like_rate}% / コメ${d.comment_rate}%`,
      topic_id: d.topic_id,
    }));

  return (
    <div className="chart-card">
      <div className="chart-title-row">
        <h3>エンゲージメント品質マップ</h3>
        <HelpButton {...HELP_TEXTS.engagementMap} />
      </div>
      <p className="chart-desc">
        右上が高エンゲージメント。コメント率が高い = コミュニティが活発
      </p>
      <button className="view-toggle-btn" onClick={() => setShowList(!showList)}>
        {showList ? 'チャートに戻す' : 'ランキングで見る'}
      </button>

      {showList ? (
        <RankingList items={rankingItems} valueLabel="エンゲージ"
          onItemClick={onTopicClick} />
      ) : (
        <>
          <div className="chart-axis-labels">
            <span>X: いいね率(%)</span>
            <span>Y: コメント率(%)</span>
          </div>
          <ResponsiveContainer width="100%" height={isMobile ? 300 : 400}>
            <ScatterChart margin={isMobile
              ? { left: 5, bottom: 5, right: 10, top: 5 }
              : { left: 20, bottom: 30, right: 20, top: 10 }
            }>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis type="number" dataKey="like_rate" name="いいね率" unit="%" tick={{ fontSize: isMobile ? 9 : 11 }}>
                {!isMobile && <Label value="いいね率 (%)" position="bottom" offset={10} style={{ fill: '#9ca3af', fontSize: 12 }} />}
              </XAxis>
              <YAxis type="number" dataKey="comment_rate" name="コメント率" unit="%"
                tick={{ fontSize: isMobile ? 9 : 11 }} width={isMobile ? 35 : 60}>
                {!isMobile && <Label value="コメント率 (%)" angle={-90} position="insideLeft" offset={-5} style={{ fill: '#9ca3af', fontSize: 12 }} />}
              </YAxis>
              <ZAxis type="number" dataKey="total_videos" range={isMobile ? [30, 200] : [50, 400]} name="動画数" />
              <Tooltip
                content={({ payload }) => {
                  if (!payload?.length) return null;
                  const d = payload[0].payload as ChartEntry;
                  return (
                    <div className="custom-tooltip">
                      <strong>{d.name}</strong>
                      <div>いいね率: {d.like_rate}%</div>
                      <div>コメント率: {d.comment_rate}%</div>
                      <div>動画数: {d.total_videos}</div>
                      <div className="tooltip-hint">クリックで詳細</div>
                    </div>
                  );
                }}
              />
              <Scatter data={chartData} fill="#8b5cf6" cursor="pointer"
                onClick={(entry: unknown) => onTopicClick?.((entry as ChartEntry).topic_id)} />
            </ScatterChart>
          </ResponsiveContainer>
        </>
      )}
    </div>
  );
}
