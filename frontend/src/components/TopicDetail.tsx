import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import type { VideoRanking, ChannelRanking } from '../types/database';
import type { VideoType } from '../hooks/useFilteredQuery';

interface Props {
  topicId: string;
  topicIds?: string[];
  topicName: string;
  videoType?: VideoType;
  onClose: () => void;
}

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

type Tab = 'buzz' | 'videos' | 'channels';

export function TopicDetail({ topicId, topicIds, topicName, videoType = 'all', onClose }: Props) {
  const [videos, setVideos] = useState<VideoRanking[]>([]);
  const [channels, setChannels] = useState<ChannelRanking[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [tab, setTab] = useState<Tab>('buzz');

  // When multiple topicIds are given (e.g. from overlap chart), use them all; otherwise use single topicId
  const filterTopicIds = topicIds && topicIds.length > 0 ? topicIds : [topicId];

  useEffect(() => {
    let cancelled = false;

    async function fetchData() {
      setLoading(true);
      setError(null);

      // .contains with multiple IDs checks that topic_ids array contains ALL of them
      const [vRes, cRes] = await Promise.all([
        supabase
          .from('video_ranking')
          .select('*')
          .contains('topic_ids', filterTopicIds)
          .order('view_count', { ascending: false })
          .limit(100),
        supabase
          .from('channel_ranking')
          .select('*')
          .contains('topic_ids', filterTopicIds)
          .order('subscriber_count', { ascending: false })
          .limit(100),
      ]);

      if (cancelled) return;

      if (vRes.error || cRes.error) {
        setError(vRes.error?.message || cRes.error?.message || 'データ取得エラー');
        setLoading(false);
        return;
      }

      let vData = (vRes.data as VideoRanking[]) ?? [];
      const cData = (cRes.data as ChannelRanking[]) ?? [];

      // Apply video type filter
      if (videoType === 'short') {
        vData = vData.filter((v) => v.duration_seconds <= 60);
      } else if (videoType === 'normal') {
        vData = vData.filter((v) => v.duration_seconds > 60);
      }

      setVideos(vData);
      setChannels(cData);
      setLoading(false);
    }

    fetchData();
    return () => { cancelled = true; };
  }, [topicId, topicIds?.join(','), videoType]);

  // Close on Escape key
  useEffect(() => {
    const handler = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [onClose]);

  // Filter out videos with obviously bad subscriber data (buzz score inflated by bad data)
  const reliableVideos = videos.filter((v) => {
    if (v.buzz_score > 100 && (v.channel_subscribers ?? 0) < 10) return false;
    return true;
  });

  const buzzVideos = [...reliableVideos]
    .filter((v) => v.buzz_score > 0)
    .sort((a, b) => b.buzz_score - a.buzz_score)
    .slice(0, 10);

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-content" onClick={(e) => e.stopPropagation()}>
        <div className="modal-header">
          <h2>{topicName}</h2>
          <div className="modal-stats">
            {!loading && (
              <>
                <span>{videos.length} 動画</span>
                <span>{channels.length} チャンネル</span>
              </>
            )}
          </div>
          <button className="modal-close" onClick={onClose}>✕</button>
        </div>

        <div className="modal-tabs">
          <button className={`modal-tab ${tab === 'buzz' ? 'active' : ''}`} onClick={() => setTab('buzz')}>
            Buzz動画
          </button>
          <button className={`modal-tab ${tab === 'videos' ? 'active' : ''}`} onClick={() => setTab('videos')}>
            全動画
          </button>
          <button className={`modal-tab ${tab === 'channels' ? 'active' : ''}`} onClick={() => setTab('channels')}>
            チャンネル
          </button>
        </div>

        {loading && (
          <div className="loading">
            <div className="spinner" />
            <p>データを読み込み中...</p>
          </div>
        )}

        {error && <div className="error-banner"><p>{error}</p></div>}

        {!loading && !error && tab === 'buzz' && (
          <div className="modal-body">
            <p className="chart-desc">
              Buzzスコア = 再生数 / チャンネル登録者数。高い = チャンネル規模に対して異常にバズった動画。パクるならこれ。
            </p>
            {buzzVideos.length === 0 ? (
              <p className="empty-msg">Buzz動画が見つかりません</p>
            ) : (
              <div className="video-list">
                {buzzVideos.map((v, i) => (
                  <a
                    key={v.id}
                    href={`https://www.youtube.com/watch?v=${v.id}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="video-card buzz-card"
                  >
                    <div className="video-rank buzz-rank">#{i + 1}</div>
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
                      <div className="stat-buzz">Buzz {v.buzz_score.toLocaleString()}x</div>
                      <div className="stat-views">{v.view_count.toLocaleString()} 再生</div>
                      <div className="stat-likes">{v.like_count.toLocaleString()} いいね</div>
                    </div>
                  </a>
                ))}
              </div>
            )}
          </div>
        )}

        {!loading && !error && tab === 'videos' && (
          <div className="modal-body">
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>#</th>
                    <th></th>
                    <th>タイトル</th>
                    <th>チャンネル</th>
                    <th>再生数</th>
                    <th>いいね</th>
                    <th>コメント</th>
                    <th>Buzz</th>
                    <th>投稿日</th>
                    <th>長さ</th>
                    <th>AI</th>
                  </tr>
                </thead>
                <tbody>
                  {videos.map((v, i) => (
                    <tr key={v.id}>
                      <td>{i + 1}</td>
                      <td>
                        <img className="table-thumb" src={thumbUrl(v)} alt="" loading="lazy" />
                      </td>
                      <td>
                        <a
                          href={`https://www.youtube.com/watch?v=${v.id}`}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="link"
                        >
                          {v.title.length > 50 ? v.title.slice(0, 50) + '...' : v.title}
                        </a>
                      </td>
                      <td>
                        <a
                          href={`https://www.youtube.com/channel/${v.channel_id}`}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="link"
                        >
                          {v.channel_title ?? '-'}
                        </a>
                      </td>
                      <td>{v.view_count.toLocaleString()}</td>
                      <td>{v.like_count.toLocaleString()}</td>
                      <td>{v.comment_count.toLocaleString()}</td>
                      <td>{v.buzz_score > 0 ? `${v.buzz_score}x` : '-'}</td>
                      <td className="nowrap">{timeAgo(v.published_at)}</td>
                      <td className="nowrap">{formatDuration(v.duration_seconds)}</td>
                      <td>{v.has_ai_keywords ? 'AI' : ''}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}

        {!loading && !error && tab === 'channels' && (
          <div className="modal-body">
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
                  {channels.map((ch, i) => (
                    <tr key={ch.id}>
                      <td>{i + 1}</td>
                      <td>
                        <a
                          href={`https://www.youtube.com/channel/${ch.id}`}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="link"
                        >
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
      </div>
    </div>
  );
}
