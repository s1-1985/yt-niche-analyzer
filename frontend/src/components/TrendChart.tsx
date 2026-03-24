import { useState, useEffect, useMemo } from 'react';
import {
  LineChart, Line, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid,
} from 'recharts';
import { supabase } from '../lib/supabase';
import { useIsMobile } from '../hooks/useIsMobile';
import { HelpButton } from './HelpButton';

interface VideoRow {
  published_at: string;
  topic_ids: string[];
}

interface TopicInfo {
  id: string;
  name: string;
  name_ja: string | null;
  parent_id: string | null;
}

interface Props {
  onTopicClick?: (topicId: string) => void;
}

const COLORS = ['#6366f1', '#10b981', '#f59e0b', '#ec4899', '#06b6d4', '#8b5cf6', '#ef4444', '#14b8a6'];

function getWeekKey(date: Date): string {
  const d = new Date(date);
  const day = d.getDay();
  const diff = d.getDate() - day + (day === 0 ? -6 : 1);
  d.setDate(diff);
  return d.toISOString().slice(0, 10);
}

export function TrendChart({ onTopicClick }: Props) {
  const isMobile = useIsMobile();
  const [videos, setVideos] = useState<VideoRow[]>([]);
  const [topics, setTopics] = useState<TopicInfo[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedTopics, setSelectedTopics] = useState<string[]>([]);
  const [weeks, setWeeks] = useState<12 | 8 | 4>(12);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);

    const since = new Date();
    since.setDate(since.getDate() - weeks * 7);

    Promise.all([
      supabase
        .from('videos')
        .select('published_at, topic_ids')
        .gte('published_at', since.toISOString()),
      supabase.from('topics').select('id, name, name_ja, parent_id'),
    ]).then(([vRes, tRes]) => {
      if (cancelled) return;
      const vData = (vRes.data as VideoRow[]) ?? [];
      const tData = (tRes.data as TopicInfo[]) ?? [];
      setVideos(vData);
      setTopics(tData);

      // Auto-select top 5 topics by video count
      if (selectedTopics.length === 0) {
        const counts = new Map<string, number>();
        for (const v of vData) {
          for (const tid of v.topic_ids ?? []) {
            counts.set(tid, (counts.get(tid) ?? 0) + 1);
          }
        }
        const subs = tData.filter((t) => t.parent_id !== null);
        const top5 = [...subs]
          .sort((a, b) => (counts.get(b.id) ?? 0) - (counts.get(a.id) ?? 0))
          .slice(0, 5)
          .map((t) => t.id);
        setSelectedTopics(top5);
      }
      setLoading(false);
    });

    return () => { cancelled = true; };
  }, [weeks]);

  const chartData = useMemo(() => {
    const weekMap = new Map<string, Record<string, number>>();

    for (const v of videos) {
      if (!v.published_at) continue;
      const weekKey = getWeekKey(new Date(v.published_at));

      if (!weekMap.has(weekKey)) weekMap.set(weekKey, {});
      const week = weekMap.get(weekKey)!;

      for (const tid of v.topic_ids ?? []) {
        if (selectedTopics.includes(tid)) {
          week[tid] = (week[tid] ?? 0) + 1;
        }
      }
    }

    return [...weekMap.entries()]
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([week, counts]) => ({
        week: week.slice(5),
        ...counts,
      }));
  }, [videos, selectedTopics]);

  const topicNameMap = useMemo(() => {
    const m = new Map<string, string>();
    for (const t of topics) m.set(t.id, t.name_ja ?? t.name);
    return m;
  }, [topics]);

  const subTopics = useMemo(
    () => topics.filter((t) => t.parent_id !== null).sort((a, b) =>
      (a.name_ja ?? a.name).localeCompare(b.name_ja ?? b.name, 'ja')),
    [topics],
  );

  const toggleTopic = (id: string) => {
    setSelectedTopics((prev) =>
      prev.includes(id)
        ? prev.filter((t) => t !== id)
        : [...prev, id].slice(-8),
    );
  };

  if (loading) return null;
  if (videos.length === 0) return null;

  return (
    <div className="chart-card">
      <div className="chart-title-row">
        <h3>新規動画投稿トレンド</h3>
        <HelpButton
          title="新規動画投稿トレンドの見方"
          content={'ジャンル別の週次新規動画投稿数の推移を表示します。\n増加傾向のジャンル=注目が集まっている or 参入者が増えている。\n減少傾向のジャンル=熱が冷めている or 安定期。\n急増しているジャンルは競合が増えるリスクがありますが、市場自体が成長している可能性もあります。'}
        />
      </div>
      <p className="chart-desc">
        ジャンル別の週次新規動画投稿数の推移（最大8ジャンル選択可）
      </p>

      <div className="trend-controls">
        <div className="buzz-period-selector">
          {([4, 8, 12] as const).map((w) => (
            <button
              key={w}
              className={`buzz-period-btn ${weeks === w ? 'active' : ''}`}
              onClick={() => setWeeks(w)}
            >
              {w}週
            </button>
          ))}
        </div>
      </div>

      <div className="tag-topic-selector">
        {subTopics.map((t) => (
          <button
            key={t.id}
            className={`tag-topic-btn ${selectedTopics.includes(t.id) ? 'active' : ''}`}
            onClick={() => toggleTopic(t.id)}
          >
            {t.name_ja ?? t.name}
          </button>
        ))}
      </div>

      <ResponsiveContainer width="100%" height={isMobile ? 280 : 350}>
        <LineChart data={chartData} margin={{ left: 0, right: 10, top: 5, bottom: 5 }}>
          <CartesianGrid strokeDasharray="3 3" />
          <XAxis dataKey="week" tick={{ fontSize: isMobile ? 9 : 11 }} />
          <YAxis tick={{ fontSize: isMobile ? 9 : 11 }} width={isMobile ? 30 : 40} />
          <Tooltip
            content={({ payload, label }) => {
              if (!payload?.length) return null;
              return (
                <div className="custom-tooltip">
                  <strong>{label}</strong>
                  {payload.map((p) => (
                    <div key={p.dataKey as string} style={{ color: p.color }}>
                      {topicNameMap.get(p.dataKey as string) ?? p.dataKey}: {p.value}本
                    </div>
                  ))}
                </div>
              );
            }}
          />
          {selectedTopics.map((tid, i) => (
            <Line
              key={tid}
              type="monotone"
              dataKey={tid}
              stroke={COLORS[i % COLORS.length]}
              strokeWidth={2}
              dot={{ r: 3 }}
              connectNulls
            />
          ))}
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}
