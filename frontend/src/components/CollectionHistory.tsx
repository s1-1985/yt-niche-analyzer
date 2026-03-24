import { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';
import type { CollectionLog } from '../types/database';

interface Props {
  onClose: () => void;
}

interface TopicName {
  id: string;
  name_ja: string | null;
  name: string;
  category: string;
}

export function CollectionHistory({ onClose }: Props) {
  const [logs, setLogs] = useState<CollectionLog[]>([]);
  const [topicMap, setTopicMap] = useState<Map<string, TopicName>>(new Map());
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const handler = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [onClose]);

  useEffect(() => {
    let cancelled = false;
    async function fetchData() {
      try {
        const [logRes, topicRes] = await Promise.all([
          supabase
            .from('collection_log')
            .select('*')
            .order('collected_at', { ascending: false })
            .limit(100),
          supabase
            .from('topics')
            .select('id, name, name_ja, category'),
        ]);

        if (cancelled) return;

        const map = new Map<string, TopicName>();
        if (topicRes.data) {
          for (const t of topicRes.data as TopicName[]) {
            map.set(t.id, t);
          }
        }
        setTopicMap(map);
        setLogs((logRes.data as CollectionLog[]) ?? []);
      } catch {
        // silently fail - empty state will show
      } finally {
        if (!cancelled) setLoading(false);
      }
    }
    fetchData();
    return () => { cancelled = true; };
  }, []);

  function getTopicLabel(topicId: string): string {
    const t = topicMap.get(topicId);
    return t ? (t.name_ja ?? t.name) : topicId;
  }

  function getCategoryLabel(topicId: string): string | null {
    const t = topicMap.get(topicId);
    return t?.category ?? null;
  }

  // Group by date
  const grouped = new Map<string, CollectionLog[]>();
  for (const log of logs) {
    const date = new Date(log.collected_at).toLocaleDateString('ja-JP');
    if (!grouped.has(date)) grouped.set(date, []);
    grouped.get(date)!.push(log);
  }

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-content" onClick={(e) => e.stopPropagation()}>
        <div className="modal-header">
          <h2>データ更新履歴</h2>
          <button className="modal-close" onClick={onClose}>✕</button>
        </div>
        <div className="modal-body">
          {loading && <div className="loading"><div className="spinner" /><p>読み込み中...</p></div>}
          {!loading && logs.length === 0 && <p className="empty-msg">更新履歴がありません</p>}
          {!loading && Array.from(grouped.entries()).map(([date, dayLogs]) => {
            const totalVideos = dayLogs.reduce((s, l) => s + l.videos_collected, 0);
            const totalChannels = dayLogs.reduce((s, l) => s + l.channels_collected, 0);
            const totalQuota = dayLogs.reduce((s, l) => s + l.quota_used, 0);
            return (
              <div key={date} className="history-group">
                <div className="history-date">
                  <strong>{date}</strong>
                  <span className="history-summary">
                    {dayLogs.length}ジャンル / {totalVideos}動画 / {totalChannels}チャンネル / Quota {totalQuota}
                  </span>
                </div>
                <div className="history-items">
                  {dayLogs.map((log) => {
                    const category = getCategoryLabel(log.topic_id);
                    return (
                      <div key={log.id} className="history-item">
                        <span className="history-time">
                          {new Date(log.collected_at).toLocaleTimeString('ja-JP', { hour: '2-digit', minute: '2-digit' })}
                        </span>
                        {category && <span className="history-category">{category}</span>}
                        <span className="history-topic">{getTopicLabel(log.topic_id)}</span>
                        <span className="history-stat">{log.videos_collected}動画</span>
                        <span className="history-stat">{log.channels_collected}ch</span>
                      </div>
                    );
                  })}
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
