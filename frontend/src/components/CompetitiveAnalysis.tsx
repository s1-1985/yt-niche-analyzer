import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import type { VideoRanking, ChannelRanking, ChannelGrowthEfficiency } from '../types/database';

interface Props {
  topicId: string;
  topicName: string;
  selectedCountry?: string | null;
}

type Tab = 'buzz' | 'popular' | 'channels' | 'growth' | 'outlier';

function formatDuration(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${m}:${s.toString().padStart(2, '0')}`;
}

function thumbUrl(video: { id: string; thumbnail_url: string | null }): string {
  return video.thumbnail_url || `https://i.ytimg.com/vi/${video.id}/mqdefault.jpg`;
}

function timeAgo(dateStr: string): string {
  const days = Math.floor((Date.now() - new Date(dateStr).getTime()) / 86400000);
  if (days === 0) return '今日';
  if (days < 7) return `${days}日前`;
  if (days < 30) return `${Math.floor(days / 7)}週間前`;
  return `${Math.floor(days / 30)}ヶ月前`;
}

export function CompetitiveAnalysis({ topicId, topicName, selectedCountry }: Props) {
  const [videos, setVideos] = useState<VideoRanking[]>([]);
  const [channels, setChannels] = useState<ChannelRanking[]>([]);
  const [growth, setGrowth] = useState<ChannelGrowthEfficiency[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [tab, setTab] = useState<Tab>('buzz');

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);

    Promise.all([
      supabase
        .from('video_ranking')
        .select('*')
        .contains('topic_ids', [topicId])
        .order('view_count', { ascending: false })
        .limit(200),
      supabase
        .from('channel_ranking')
        .select('*')
        .contains('topic_ids', [topicId])
        .order('subscriber_count', { ascending: false })
        .limit(200),
      supabase
        .from('channel_growth_efficiency')
        .select('*')
        .order('subs_per_day', { ascending: false })
        .limit(500),
    ]).then(([vRes, cRes, gRes]) => {
      if (cancelled) return;
      if (vRes.error || cRes.error) {
        setError(vRes.error?.message || cRes.error?.message || 'データ取得エラー');
        setLoading(false);
        return;
      }
      setVideos((vRes.data as VideoRanking[]) ?? []);
      setChannels((cRes.data as ChannelRanking[]) ?? []);
      // Filter growth data to this topic
      const allGrowth = (gRes.data as ChannelGrowthEfficiency[]) ?? [];
      setGrowth(allGrowth.filter((g) => g.topic_ids?.includes(topicId)));
      setLoading(false);
    });

    return () => { cancelled = true; };
  }, [topicId]);

  // Country filter: filter channels and videos by selected country
  const filteredChannels = selectedCountry
    ? channels.filter((ch) => ch.country === selectedCountry)
    : channels;

  const filteredChannelIds = selectedCountry
    ? new Set(filteredChannels.map((ch) => ch.id))
    : null;

  const filteredVideos = filteredChannelIds
    ? videos.filter((v) => filteredChannelIds.has(v.channel_id))
    : videos;

  const filteredGrowth = selectedCountry
    ? growth.filter((g) => g.country === selectedCountry)
    : growth;

  // Derived data
  const buzzVideos = [...filteredVideos]
    .filter((v) => v.buzz_score > 0)
    .sort((a, b) => b.buzz_score - a.buzz_score)
    .slice(0, 20);

  const popularVideos = [...filteredVideos]
    .sort((a, b) => b.view_count - a.view_count)
    .slice(0, 20);

  const topChannels = [...filteredChannels]
    .sort((a, b) => b.subscriber_count - a.subscriber_count)
    .slice(0, 20);

  const growthChannels = [...filteredGrowth]
    .filter((g) => g.age_days <= 365 && g.age_days > 0)
    .sort((a, b) => b.subs_per_day - a.subs_per_day)
    .slice(0, 20);

  // Outlier: low subscribers but high views per video
  const outlierChannels = [...filteredChannels]
    .filter((ch) => ch.subscriber_count > 0 && ch.video_count > 0)
    .map((ch) => ({
      ...ch,
      viewsPerVideo: Math.round(ch.view_count / ch.video_count),
      viewToSubRatio: Math.round((ch.view_count / ch.video_count) / ch.subscriber_count * 100) / 100,
    }))
    .filter((ch) => ch.viewToSubRatio > 1)
    .sort((a, b) => b.viewToSubRatio - a.viewToSubRatio)
    .slice(0, 20);

  // KPI
  const totalVideos = filteredVideos.length;
  const totalChannels = filteredChannels.length;
  const avgViews = totalVideos > 0
    ? Math.round(filteredVideos.reduce((s, v) => s + v.view_count, 0) / totalVideos)
    : 0;
  const avgLikeRate = totalVideos > 0
    ? (filteredVideos.reduce((s, v) => s + (v.view_count > 0 ? v.like_count / v.view_count * 100 : 0), 0) / totalVideos).toFixed(2)
    : '0';
  const aiCount = filteredVideos.filter((v) => v.has_ai_keywords).length;
  const aiPct = totalVideos > 0 ? Math.round(aiCount / totalVideos * 100) : 0;

  const tabs: { key: Tab; label: string; count: number }[] = [
    { key: 'buzz', label: 'Buzz動画', count: buzzVideos.length },
    { key: 'popular', label: '人気動画', count: popularVideos.length },
    { key: 'channels', label: '人気チャンネル', count: topChannels.length },
    { key: 'growth', label: '急成長チャンネル', count: growthChannels.length },
    { key: 'outlier', label: '穴場チャンネル', count: outlierChannels.length },
  ];

  return (
    <div className="competitive-analysis">
      <div className="ca-header">
        <h2 className="ca-title">{topicName} の競合分析</h2>
        <p className="ca-desc">このジャンル内の動画・チャンネルを深掘り分析</p>
      </div>

      {loading && (
        <div className="loading"><div className="spinner" /><p>データを読み込み中...</p></div>
      )}

      {error && <div className="error-banner"><p>{error}</p></div>}

      {!loading && !error && (
        <>
          <section className="kpi-grid">
            <div className="kpi-card">
              <div className="kpi-value">{totalVideos.toLocaleString()}</div>
              <div className="kpi-label">動画数</div>
            </div>
            <div className="kpi-card">
              <div className="kpi-value" style={{ color: '#10b981' }}>{totalChannels.toLocaleString()}</div>
              <div className="kpi-label">チャンネル数</div>
            </div>
            <div className="kpi-card">
              <div className="kpi-value" style={{ color: '#f59e0b' }}>{avgViews.toLocaleString()}</div>
              <div className="kpi-label">平均再生数</div>
            </div>
            <div className="kpi-card">
              <div className="kpi-value" style={{ color: '#ec4899' }}>{avgLikeRate}%</div>
              <div className="kpi-label">平均いいね率</div>
            </div>
            <div className="kpi-card">
              <div className="kpi-value" style={{ color: '#06b6d4' }}>{buzzVideos.length}</div>
              <div className="kpi-label">Buzz動画数</div>
            </div>
            <div className="kpi-card">
              <div className="kpi-value" style={{ color: '#8b5cf6' }}>{aiPct}%</div>
              <div className="kpi-label">AI動画率</div>
            </div>
          </section>

          <div className="ca-tabs">
            {tabs.map((t) => (
              <button
                key={t.key}
                className={`ca-tab ${tab === t.key ? 'active' : ''}`}
                onClick={() => setTab(t.key)}
              >
                {t.label}
                <span className="ca-tab-count">{t.count}</span>
              </button>
            ))}
          </div>

          {tab === 'buzz' && (
            <div className="ca-section">
              <p className="chart-desc">
                Buzzスコア = 再生数 ÷ 登録者数。チャンネル規模に対して異常にバズった動画。
              </p>
              {buzzVideos.length === 0 ? (
                <p className="empty-msg">Buzz動画がありません</p>
              ) : (
                <div className="video-list">
                  {buzzVideos.map((v, i) => (
                    <VideoCard key={v.id} video={v} rank={i + 1} showBuzz />
                  ))}
                </div>
              )}
            </div>
          )}

          {tab === 'popular' && (
            <div className="ca-section">
              <p className="chart-desc">
                このジャンルで最も再生されている動画 TOP20。
              </p>
              <div className="video-list">
                {popularVideos.map((v, i) => (
                  <VideoCard key={v.id} video={v} rank={i + 1} />
                ))}
              </div>
            </div>
          )}

          {tab === 'channels' && (
            <div className="ca-section">
              <p className="chart-desc">
                このジャンルの登録者数が多いチャンネル TOP20。
              </p>
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr>
                      <th>#</th>
                      <th>チャンネル名</th>
                      <th>登録者数</th>
                      <th>総再生数</th>
                      <th>動画数</th>
                      <th>国</th>
                      <th>開設日</th>
                    </tr>
                  </thead>
                  <tbody>
                    {topChannels.map((ch, i) => (
                      <tr key={ch.id}>
                        <td>{i + 1}</td>
                        <td>
                          <a href={`https://www.youtube.com/channel/${ch.id}`} target="_blank" rel="noopener noreferrer" className="link">
                            {ch.title}
                          </a>
                        </td>
                        <td>{ch.subscriber_count.toLocaleString()}</td>
                        <td>{ch.view_count.toLocaleString()}</td>
                        <td>{ch.video_count.toLocaleString()}</td>
                        <td>{ch.country ?? '-'}</td>
                        <td className="nowrap">{ch.published_at ? new Date(ch.published_at).toLocaleDateString('ja-JP') : '-'}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {tab === 'growth' && (
            <div className="ca-section">
              <p className="chart-desc">
                開設1年以内で登録者の伸びが速いチャンネル。「登録者/日」が高い = 急成長中。
              </p>
              {growthChannels.length === 0 ? (
                <p className="empty-msg">該当チャンネルがありません</p>
              ) : (
                <div className="table-wrap">
                  <table>
                    <thead>
                      <tr>
                        <th>#</th>
                        <th>チャンネル名</th>
                        <th>登録者数</th>
                        <th>登録者/日</th>
                        <th>再生/動画</th>
                        <th>開設</th>
                        <th>国</th>
                      </tr>
                    </thead>
                    <tbody>
                      {growthChannels.map((ch, i) => (
                        <tr key={ch.channel_id}>
                          <td>{i + 1}</td>
                          <td>
                            <a href={`https://www.youtube.com/channel/${ch.channel_id}`} target="_blank" rel="noopener noreferrer" className="link">
                              {ch.title}
                            </a>
                          </td>
                          <td>{ch.subscriber_count.toLocaleString()}</td>
                          <td className="highlight-value">+{Math.round(ch.subs_per_day).toLocaleString()}/日</td>
                          <td>{Math.round(ch.views_per_video).toLocaleString()}</td>
                          <td className="nowrap">{ch.age_days < 30 ? `${ch.age_days}日前` : `${Math.round(ch.age_days / 30)}ヶ月前`}</td>
                          <td>{ch.country ?? '-'}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          )}

          {tab === 'outlier' && (
            <div className="ca-section">
              <p className="chart-desc">
                登録者数に対して再生数が異常に多いチャンネル。「再生/動画÷登録者」が1以上 = 少ない登録者で多くの再生を獲得。参考になるコンテンツ戦略を持っている可能性。
              </p>
              {outlierChannels.length === 0 ? (
                <p className="empty-msg">該当チャンネルがありません</p>
              ) : (
                <div className="table-wrap">
                  <table>
                    <thead>
                      <tr>
                        <th>#</th>
                        <th>チャンネル名</th>
                        <th>登録者数</th>
                        <th>再生/動画</th>
                        <th>再生/動画÷登録者</th>
                        <th>動画数</th>
                        <th>国</th>
                      </tr>
                    </thead>
                    <tbody>
                      {outlierChannels.map((ch, i) => (
                        <tr key={ch.id}>
                          <td>{i + 1}</td>
                          <td>
                            <a href={`https://www.youtube.com/channel/${ch.id}`} target="_blank" rel="noopener noreferrer" className="link">
                              {ch.title}
                            </a>
                          </td>
                          <td>{ch.subscriber_count.toLocaleString()}</td>
                          <td>{ch.viewsPerVideo.toLocaleString()}</td>
                          <td className="highlight-value">{ch.viewToSubRatio.toLocaleString()}x</td>
                          <td>{ch.video_count.toLocaleString()}</td>
                          <td>{ch.country ?? '-'}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          )}
        </>
      )}
    </div>
  );
}

function VideoCard({ video: v, rank, showBuzz }: { video: VideoRanking; rank: number; showBuzz?: boolean }) {
  return (
    <a
      href={`https://www.youtube.com/watch?v=${v.id}`}
      target="_blank"
      rel="noopener noreferrer"
      className={`video-card ${showBuzz ? 'buzz-card' : ''}`}
    >
      <div className={`video-rank ${showBuzz ? 'buzz-rank' : ''}`}>#{rank}</div>
      <img className="video-thumb" src={thumbUrl(v)} alt="" loading="lazy" />
      <div className="video-info">
        <div className="video-title">{v.title}</div>
        <div className="video-meta">
          <span>{v.channel_title ?? 'Unknown'}</span>
          <span>登録者 {(v.channel_subscribers ?? 0).toLocaleString()}</span>
          <span>{timeAgo(v.published_at)}</span>
          <span>{formatDuration(v.duration_seconds)}</span>
        </div>
      </div>
      <div className="video-stats">
        {showBuzz && <div className="stat-buzz">Buzz {v.buzz_score.toLocaleString()}x</div>}
        <div className="stat-views">{v.view_count.toLocaleString()} 再生</div>
        <div className="stat-likes">{v.like_count.toLocaleString()} いいね</div>
      </div>
    </a>
  );
}
