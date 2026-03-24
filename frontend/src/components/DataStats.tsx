import { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';

interface Props {
  onClose: () => void;
}

interface TopicStats {
  topic_id: string;
  topic_name: string;
  name_ja: string | null;
  parent_id: string | null;
  category: string;
  total_videos: number;
  total_channels: number;
}

export function DataStats({ onClose }: Props) {
  const [data, setData] = useState<TopicStats[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const handler = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [onClose]);

  useEffect(() => {
    let cancelled = false;
    supabase.from('topic_summary').select('topic_id, topic_name, name_ja, parent_id, category, total_videos, total_channels')
      .then((res) => {
        if (cancelled) return;
        if (res.data) {
          setData(res.data as TopicStats[]);
        }
        setLoading(false);
      });
    return () => { cancelled = true; };
  }, []);

  const subs = data.filter((d) => d.parent_id !== null);
  const categories = Array.from(new Set(subs.map((d) => d.category)));

  const totalVideos = subs.reduce((s, d) => s + d.total_videos, 0);
  const totalChannels = subs.reduce((s, d) => s + d.total_channels, 0);

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-content datastats-modal" onClick={(e) => e.stopPropagation()}>
        <div className="modal-header">
          <h2>データベース</h2>
          <button className="modal-close" onClick={onClose}>✕</button>
        </div>
        <div className="modal-body">
          {loading && <div className="loading"><div className="spinner" /><p>読み込み中...</p></div>}
          {!loading && (
            <>
              <div className="datastats-summary">
                <div className="datastats-kpi">
                  <span className="datastats-kpi-value">{subs.length}</span>
                  <span className="datastats-kpi-label">ジャンル数</span>
                </div>
                <div className="datastats-kpi">
                  <span className="datastats-kpi-value">{totalVideos.toLocaleString()}</span>
                  <span className="datastats-kpi-label">総動画数</span>
                </div>
                <div className="datastats-kpi">
                  <span className="datastats-kpi-value">{totalChannels.toLocaleString()}</span>
                  <span className="datastats-kpi-label">総チャンネル数</span>
                </div>
              </div>

              {categories.sort().map((cat) => {
                const topics = subs.filter((d) => d.category === cat);
                const catVideos = topics.reduce((s, d) => s + d.total_videos, 0);
                const catChannels = topics.reduce((s, d) => s + d.total_channels, 0);
                return (
                  <div key={cat} className="datastats-category">
                    <div className="datastats-category-header">
                      <strong>{cat}</strong>
                      <span className="datastats-category-total">{catVideos.toLocaleString()}動画 / {catChannels.toLocaleString()}ch</span>
                    </div>
                    <div className="datastats-list">
                      {topics.sort((a, b) => b.total_videos - a.total_videos).map((t) => (
                        <div key={t.topic_id} className="datastats-row">
                          <span className="datastats-name">{t.name_ja ?? t.topic_name}</span>
                          <span className="datastats-count">{t.total_videos.toLocaleString()}動画</span>
                          <span className="datastats-count">{t.total_channels.toLocaleString()}ch</span>
                        </div>
                      ))}
                    </div>
                  </div>
                );
              })}
            </>
          )}
        </div>
      </div>
    </div>
  );
}
