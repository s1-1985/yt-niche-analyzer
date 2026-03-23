import { useState, useCallback } from 'react';
import { useSupabaseQuery } from './hooks/useSupabaseQuery';
import { KpiCard } from './components/KpiCard';
import { GapScoreChart } from './components/GapScoreChart';
import { CompetitionChart } from './components/CompetitionChart';
import { SuccessRateChart } from './components/SuccessRateChart';
import { AiPenetrationChart } from './components/AiPenetrationChart';
import { TopicTable } from './components/TopicTable';
import { TopicDetail } from './components/TopicDetail';
import type { TopicSummary, CompetitionConcentration, NewChannelSuccessRate, AiPenetration } from './types/database';
import './App.css';

function App() {
  const topics = useSupabaseQuery<TopicSummary>('topic_summary');
  const competition = useSupabaseQuery<CompetitionConcentration>('competition_concentration');
  const successRate = useSupabaseQuery<NewChannelSuccessRate>('new_channel_success_rate');
  const aiPen = useSupabaseQuery<AiPenetration>('ai_penetration');

  const [selectedTopicId, setSelectedTopicId] = useState<string | null>(null);

  const isLoading = topics.loading || competition.loading || successRate.loading || aiPen.loading;
  const hasError = topics.error || competition.error || successRate.error || aiPen.error;
  const isEmpty = !isLoading && !hasError && topics.data.length === 0;

  // KPI calculations
  const subTopics = topics.data.filter((t) => t.parent_id !== null);
  const totalVideos = subTopics.reduce((s, t) => s + t.total_videos, 0);
  const totalChannels = subTopics.reduce((s, t) => s + t.total_channels, 0);
  const topGap = subTopics.length > 0
    ? [...subTopics].sort((a, b) => b.gap_score - a.gap_score)[0]
    : null;
  const avgLikeRate = subTopics.length > 0
    ? (subTopics.reduce((s, t) => s + t.like_rate_pct, 0) / subTopics.length).toFixed(2)
    : '0';

  const handleTopicClick = useCallback((topicId: string) => {
    setSelectedTopicId(topicId);
  }, []);

  // Find topic name for the selected topic
  const selectedTopicName = selectedTopicId
    ? (() => {
        const t = topics.data.find((t) => t.topic_id === selectedTopicId);
        return t ? (t.name_ja ?? t.topic_name) : selectedTopicId;
      })()
    : '';

  return (
    <div className="app">
      <header className="header">
        <h1>YouTube Niche Analyzer</h1>
        <p>ジャンル別の需給ギャップ・競合分析ダッシュボード</p>
      </header>

      {isLoading && (
        <div className="loading">
          <div className="spinner" />
          <p>データを読み込み中...</p>
        </div>
      )}

      {hasError && (
        <div className="error-banner">
          <p>データ取得エラー: {topics.error || competition.error || successRate.error || aiPen.error}</p>
          <p className="error-hint">VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY が正しく設定されているか確認してください。</p>
        </div>
      )}

      {isEmpty && (
        <div className="empty-banner">
          <p>まだデータがありません。GitHub Actions の collect ワークフローを実行してデータを収集してください。</p>
        </div>
      )}

      {!isLoading && !hasError && topics.data.length > 0 && (
        <>
          <section className="kpi-grid">
            <KpiCard title="総動画数" value={totalVideos.toLocaleString()} />
            <KpiCard title="総チャンネル数" value={totalChannels.toLocaleString()} color="#10b981" />
            <KpiCard
              title="最大ギャップ"
              value={topGap ? (topGap.name_ja ?? topGap.topic_name) : '-'}
              sub={topGap ? `スコア: ${topGap.gap_score.toLocaleString()}` : undefined}
              color="#f59e0b"
            />
            <KpiCard title="平均いいね率" value={`${avgLikeRate}%`} color="#ec4899" />
          </section>

          <section className="charts">
            <GapScoreChart data={topics.data} onTopicClick={handleTopicClick} />
            <CompetitionChart data={competition.data} onTopicClick={handleTopicClick} />
            <SuccessRateChart data={successRate.data} onTopicClick={handleTopicClick} />
            <AiPenetrationChart data={aiPen.data} onTopicClick={handleTopicClick} />
          </section>

          <section className="table-section">
            <TopicTable data={topics.data} onTopicClick={handleTopicClick} />
          </section>
        </>
      )}

      {selectedTopicId && (
        <TopicDetail
          topicId={selectedTopicId}
          topicName={selectedTopicName}
          onClose={() => setSelectedTopicId(null)}
        />
      )}

      <footer className="footer">
        <p>YouTube Data API v3 + Supabase | Auto-collected daily via GitHub Actions</p>
      </footer>
    </div>
  );
}

export default App;
