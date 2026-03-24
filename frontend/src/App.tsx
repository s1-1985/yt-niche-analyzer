import { useState, useCallback, useEffect, useMemo } from 'react';
import { useFilteredQuery, type TimePeriod, type VideoType } from './hooks/useFilteredQuery';
import { supabase } from './lib/supabase';
import { TimePeriodFilter } from './components/TimePeriodFilter';
import { VideoTypeFilter } from './components/VideoTypeFilter';
import { TopicFilter } from './components/TopicFilter';
import { CountryFilter } from './components/CountryFilter';
import { KpiCard } from './components/KpiCard';
import { NicheScoreChart } from './components/NicheScoreChart';
import { GapScoreChart } from './components/GapScoreChart';
import { EntryMatrixChart } from './components/EntryMatrixChart';
import { CompetitionChart } from './components/CompetitionChart';
import { SuccessRateChart } from './components/SuccessRateChart';
import { EngagementMapChart } from './components/EngagementMapChart';
import { EngagementDepthChart } from './components/EngagementDepthChart';
import { AiPenetrationChart } from './components/AiPenetrationChart';
import { DurationChart } from './components/DurationChart';
import { ChannelSizeChart } from './components/ChannelSizeChart';
import { CategoryRadarChart } from './components/CategoryRadarChart';
import { PublishDayChart } from './components/PublishDayChart';
import { ChannelGrowthChart } from './components/ChannelGrowthChart';
import { TopTagsChart } from './components/TopTagsChart';
import { CountryChart } from './components/CountryChart';
import { TopicOverlapChart } from './components/TopicOverlapChart';
import { AiPromptCopyButton } from './components/AiPromptCopyButton';
import { TopicTable } from './components/TopicTable';
import { TopicDetail } from './components/TopicDetail';
import { CollectionHistory } from './components/CollectionHistory';
import { DataStats } from './components/DataStats';
import { BuzzPickup } from './components/BuzzPickup';
import { CompetitiveAnalysis } from './components/CompetitiveAnalysis';
import type {
  TopicSummary, CompetitionConcentration, NewChannelSuccessRate, AiPenetration,
  TopicDurationStats, TopicChannelSize, TopicPublishDay, TopicCountryDistribution,
  TopicPopularTag, TopicOverlap,
} from './types/database';
import './App.css';

function App() {
  const [period, setPeriod] = useState<TimePeriod>('all');
  const [videoType, setVideoType] = useState<VideoType>('all');

  // Country filter state
  const [selectedCountry, setSelectedCountry] = useState<string | null>(null);

  // Genre filter state
  const [selectedCategory, setSelectedCategory] = useState<string | null>(null);
  const [selectedGenreId, setSelectedGenreId] = useState<string | null>(null);

  const topics = useFilteredQuery<TopicSummary>('topic_summary', period, videoType);
  const competition = useFilteredQuery<CompetitionConcentration>('competition_concentration', period, videoType);
  const successRate = useFilteredQuery<NewChannelSuccessRate>('new_channel_success_rate', period, videoType);
  const aiPen = useFilteredQuery<AiPenetration>('ai_penetration', period, videoType);
  const duration = useFilteredQuery<TopicDurationStats>('topic_duration_stats', period, videoType);
  const channelSize = useFilteredQuery<TopicChannelSize>('topic_channel_size', period, videoType);
  const publishDay = useFilteredQuery<TopicPublishDay>('topic_publish_day', period, videoType);
  const countryDist = useFilteredQuery<TopicCountryDistribution>('topic_country_distribution', period, videoType);

  const [selectedTopicId, setSelectedTopicId] = useState<string | null>(null);
  const [showHistory, setShowHistory] = useState(false);
  const [showDataStats, setShowDataStats] = useState(false);

  const [tagsData, setTagsData] = useState<TopicPopularTag[]>([]);
  const [overlapData, setOverlapData] = useState<TopicOverlap[]>([]);

  const [lastUpdated, setLastUpdated] = useState<string | null>(null);
  useEffect(() => {
    supabase.from('collection_log').select('collected_at')
      .order('collected_at', { ascending: false }).limit(1)
      .then((res) => {
        const d = res.data as { collected_at: string }[] | null;
        if (d && d.length > 0) setLastUpdated(d[0].collected_at);
      });
  }, []);

  const isLoading = topics.loading || competition.loading || successRate.loading || aiPen.loading;
  const hasError = topics.error || competition.error || successRate.error || aiPen.error;
  const isEmpty = !isLoading && !hasError && topics.data.length === 0;

  // Filter data by selected category
  const filterByCategory = useCallback(<T extends { topic_id?: string; topic_name?: string; name_ja?: string | null; parent_id?: string | null; category?: string }>(
    data: T[],
  ): T[] => {
    if (!selectedCategory) return data;
    return data.filter((d) => {
      if ('category' in d && d.category) return d.category === selectedCategory;
      // For types without category, look up from topics
      const topic = topics.data.find((t) => t.topic_id === (d as { topic_id?: string }).topic_id);
      return topic ? topic.category === selectedCategory : true;
    });
  }, [selectedCategory, topics.data]);

  // Filtered data for charts
  const fTopics = useMemo(() => filterByCategory(topics.data), [filterByCategory, topics.data]);
  const fCompetition = useMemo(() => filterByCategory(competition.data), [filterByCategory, competition.data]);
  const fSuccessRate = useMemo(() => filterByCategory(successRate.data), [filterByCategory, successRate.data]);
  const fAiPen = useMemo(() => filterByCategory(aiPen.data), [filterByCategory, aiPen.data]);
  const fDuration = useMemo(() => filterByCategory(duration.data), [filterByCategory, duration.data]);
  const fChannelSize = useMemo(() => filterByCategory(channelSize.data), [filterByCategory, channelSize.data]);
  const fPublishDay = useMemo(() => filterByCategory(publishDay.data), [filterByCategory, publishDay.data]);
  const fCountryDist = useMemo(() => filterByCategory(countryDist.data), [filterByCategory, countryDist.data]);

  // KPI calculations (from filtered data)
  const subTopics = fTopics.filter((t) => t.parent_id !== null);
  const totalVideos = subTopics.reduce((s, t) => s + t.total_videos, 0);
  const totalChannels = subTopics.reduce((s, t) => s + t.total_channels, 0);
  const topGap = subTopics.length > 0
    ? [...subTopics].sort((a, b) => b.gap_score - a.gap_score)[0]
    : null;
  const avgLikeRate = subTopics.length > 0
    ? (subTopics.reduce((s, t) => s + t.like_rate_pct, 0) / subTopics.length).toFixed(2)
    : '0';

  const fCompSub = fCompetition.filter((c) => {
    const t = topics.data.find((t) => t.topic_id === c.topic_id);
    return t ? t.parent_id !== null : true;
  });
  const lowestComp = fCompSub.length > 0
    ? [...fCompSub].sort((a, b) => a.top5_share_pct - b.top5_share_pct)[0]
    : null;

  const fSuccSub = fSuccessRate.filter((s) => s.new_channel_count >= 3);
  const bestSuccess = fSuccSub.length > 0
    ? [...fSuccSub].sort((a, b) => b.success_rate_pct - a.success_rate_pct)[0]
    : null;

  const handleTopicClick = useCallback((topicId: string) => {
    setSelectedTopicId(topicId);
  }, []);

  const selectedTopicName = selectedTopicId
    ? (() => {
        const t = topics.data.find((t) => t.topic_id === selectedTopicId);
        return t ? (t.name_ja ?? t.topic_name) : selectedTopicId;
      })()
    : '';

  // Competitive analysis mode: selected genre name
  const selectedGenreName = selectedGenreId
    ? (() => {
        const t = topics.data.find((t) => t.topic_id === selectedGenreId);
        return t ? (t.name_ja ?? t.topic_name) : selectedGenreId;
      })()
    : '';

  const isCompetitiveMode = !!selectedGenreId;

  return (
    <div className="app">
      <header className="header">
        <h1>YouTube Niche Analyzer</h1>
        <p>ジャンル別の需給ギャップ・競合分析ダッシュボード</p>
        {lastUpdated && (
          <div className="last-updated">
            <span>最終更新: {new Date(lastUpdated).toLocaleString('ja-JP')}</span>
            <button className="history-btn" onClick={() => setShowHistory(true)}>更新履歴</button>
            <button className="history-btn" onClick={() => setShowDataStats(true)}>データベース</button>
          </div>
        )}
        <div className="top-filter-row">
          <CountryFilter value={selectedCountry} onChange={setSelectedCountry} />
          <TopicFilter
            selectedCategory={selectedCategory}
            selectedTopicId={selectedGenreId}
            onCategoryChange={setSelectedCategory}
            onTopicChange={setSelectedGenreId}
          />
        </div>
        {!isCompetitiveMode && (
          <div className="filter-row">
            <TimePeriodFilter value={period} onChange={setPeriod} />
            <VideoTypeFilter value={videoType} onChange={setVideoType} />
          </div>
        )}
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

      {/* Competitive Analysis Mode */}
      {!isLoading && !hasError && isCompetitiveMode && (
        <CompetitiveAnalysis topicId={selectedGenreId} topicName={selectedGenreName} selectedCountry={selectedCountry} />
      )}

      {/* Dashboard Mode (cross-genre comparison) */}
      {!isLoading && !hasError && !isCompetitiveMode && fTopics.length > 0 && (
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
            <KpiCard
              title="最低競合集中"
              value={lowestComp ? (lowestComp.name_ja ?? lowestComp.topic_name) : '-'}
              sub={lowestComp ? `Top5占有: ${lowestComp.top5_share_pct}%` : undefined}
              color="#06b6d4"
            />
            <KpiCard
              title="新規成功率TOP"
              value={bestSuccess ? (bestSuccess.name_ja ?? bestSuccess.topic_name) : '-'}
              sub={bestSuccess ? `成功率: ${bestSuccess.success_rate_pct}%` : undefined}
              color="#10b981"
            />
          </section>

          {!selectedCategory && (
            <section className="charts-full">
              <BuzzPickup />
            </section>
          )}

          <div className="section-divider">
            <h2 className="section-title">参入ジャンルの総合判断</h2>
            <p className="section-desc">まずはここを見て、どのジャンルに参入すべきかの大枠を掴む</p>
          </div>

          <section className="charts-full">
            <NicheScoreChart
              topics={fTopics} competition={fCompetition}
              successRate={fSuccessRate} aiPenetration={fAiPen}
              onTopicClick={handleTopicClick}
            />
          </section>

          <section className="charts">
            <EntryMatrixChart topics={fTopics} competition={fCompetition} onTopicClick={handleTopicClick} />
            {!selectedCategory && (
              <CategoryRadarChart topics={fTopics} competition={fCompetition}
                successRate={fSuccessRate} aiPenetration={fAiPen} />
            )}
          </section>

          <div className="section-divider">
            <h2 className="section-title">需給と競合の詳細分析</h2>
            <p className="section-desc">需要・供給・競合の具体的な数値で深掘り</p>
          </div>

          <section className="charts">
            <GapScoreChart data={fTopics} onTopicClick={handleTopicClick} />
            <CompetitionChart data={fCompetition} onTopicClick={handleTopicClick} />
          </section>

          <section className="charts">
            <SuccessRateChart data={fSuccessRate} onTopicClick={handleTopicClick} />
            <AiPenetrationChart data={fAiPen} onTopicClick={handleTopicClick} />
          </section>

          <div className="section-divider">
            <h2 className="section-title">エンゲージメント分析</h2>
            <p className="section-desc">視聴者の反応の質を見て、伸びやすいジャンルを特定</p>
          </div>

          <section className="charts">
            <EngagementMapChart data={fTopics} onTopicClick={handleTopicClick} />
            <EngagementDepthChart data={fTopics} onTopicClick={handleTopicClick} />
          </section>

          <div className="section-divider">
            <h2 className="section-title">コンテンツ戦略</h2>
            <p className="section-desc">参入先が決まったら、どんな動画を作るかの戦略を立てる</p>
          </div>

          {(fDuration.length > 0 || fChannelSize.length > 0) && (
            <section className="charts">
              {fDuration.length > 0 && <DurationChart data={fDuration} onTopicClick={handleTopicClick} />}
              {fChannelSize.length > 0 && <ChannelSizeChart data={fChannelSize} onTopicClick={handleTopicClick} />}
            </section>
          )}

          {fPublishDay.length > 0 && (
            <section className="charts">
              <PublishDayChart data={fPublishDay} />
              <ChannelGrowthChart period={period} videoType={videoType} onTopicClick={handleTopicClick} />
            </section>
          )}

          <div className="section-divider">
            <h2 className="section-title">市場の構造分析</h2>
            <p className="section-desc">タグ・国別・ジャンル相関から市場構造を理解</p>
          </div>

          <section className="charts">
            <TopTagsChart period={period} videoType={videoType} onTagsLoaded={setTagsData} onTopicClick={handleTopicClick} />
            {fCountryDist.length > 0 && <CountryChart data={fCountryDist} />}
          </section>

          <section className="charts-full">
            <TopicOverlapChart period={period} videoType={videoType} onOverlapLoaded={setOverlapData} onTopicClick={handleTopicClick} />
          </section>

          <section className="table-section">
            <TopicTable data={fTopics} onTopicClick={handleTopicClick} />
          </section>

          <section className="ai-prompt-wrapper">
            <AiPromptCopyButton
              period={period} topics={fTopics} competition={fCompetition}
              successRate={fSuccessRate} aiPenetration={fAiPen}
              duration={fDuration} channelSize={fChannelSize}
              publishDay={fPublishDay} countryDist={fCountryDist}
              tags={tagsData} overlap={overlapData}
            />
          </section>
        </>
      )}

      {selectedTopicId && (
        <TopicDetail topicId={selectedTopicId} topicName={selectedTopicName}
          onClose={() => setSelectedTopicId(null)} />
      )}

      {showHistory && <CollectionHistory onClose={() => setShowHistory(false)} />}
      {showDataStats && <DataStats onClose={() => setShowDataStats(false)} />}

      <footer className="footer">
        <p>YouTube Data API v3 + Supabase | Auto-collected daily via GitHub Actions</p>
      </footer>
    </div>
  );
}

export default App;
