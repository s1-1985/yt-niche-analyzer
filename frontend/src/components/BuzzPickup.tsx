import { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';
import type { VideoRanking } from '../types/database';

interface TopicName {
  id: string;
  name_ja: string | null;
  name: string;
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

export function BuzzPickup() {
  const [videos, setVideos] = useState<VideoRanking[]>([]);
  const [topicMap, setTopicMap] = useState<Map<string, string>>(new Map());
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [days, setDays] = useState<7 | 14 | 30>(7);

  useEffect(() => {
    let cancelled = false;
    supabase.from('topics').select('id, name, name_ja').then((res) => {
      if (cancelled) return;
      if (res.error) return;
      const map = new Map<string, string>();
      if (res.data) {
        for (const t of res.data as TopicName[]) {
          map.set(t.id, t.name_ja ?? t.name);
        }
      }
      setTopicMap(map);
    });
    return () => { cancelled = true; };
  }, []);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);

    const since = new Date();
    since.setDate(since.getDate() - days);

    supabase
      .from('video_ranking')
      .select('*')
      .gte('published_at', since.toISOString())
      .gt('buzz_score', 0)
      .order('buzz_score', { ascending: false })
      .limit(20)
      .then((res) => {
        if (cancelled) return;
        if (res.error) {
          setError(res.error.message);
          setLoading(false);
          return;
        }
        setVideos((res.data as VideoRanking[]) ?? []);
        setLoading(false);
      });

    return () => { cancelled = true; };
  }, [days]);

  function getGenreTags(topicIds: string[]): string[] {
    return topicIds
      .map((id) => topicMap.get(id))
      .filter((n): n is string => !!n);
  }

  return (
    <div className="chart-card buzz-pickup">
      <div className="buzz-pickup-header">
        <div>
          <h3 className="chart-title">Buzz動画ピックアップ</h3>
          <p className="chart-desc">
            ジャンル横断で、短期間に急激にバズった動画をピックアップ
          </p>
        </div>
        <div className="buzz-period-selector">
          {([7, 14, 30] as const).map((d) => (
            <button
              key={d}
              className={`buzz-period-btn ${days === d ? 'active' : ''}`}
              onClick={() => setDays(d)}
            >
              {d}日
            </button>
          ))}
        </div>
      </div>

      {loading ? (
        <div className="loading"><div className="spinner" /><p>読み込み中...</p></div>
      ) : error ? (
        <div className="error-banner"><p>{error}</p></div>
      ) : videos.length === 0 ? (
        <p className="empty-msg">該当する動画がありません</p>
      ) : (
        <div className="video-list">
          {videos.map((v, i) => (
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
                  <span>登録者 {v.channel_subscribers.toLocaleString()}</span>
                  <span>{timeAgo(v.published_at)}</span>
                  <span>{formatDuration(v.duration_seconds)}</span>
                </div>
                <div className="buzz-genre-tags">
                  {getGenreTags(v.topic_ids).map((name) => (
                    <span key={name} className="buzz-genre-tag">{name}</span>
                  ))}
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
  );
}
