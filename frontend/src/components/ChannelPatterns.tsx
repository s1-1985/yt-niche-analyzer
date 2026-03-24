import { useEffect, useState, useMemo } from 'react';
import { supabase } from '../lib/supabase';
import { useIsMobile } from '../hooks/useIsMobile';
import {
  BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid,
} from 'recharts';
import type { ChannelRanking, VideoRanking } from '../types/database';

interface Props {
  topicId: string;
  topicName: string;
}

interface WordCount {
  word: string;
  count: number;
}

// 日本語ストップワード
const STOP_WORDS = new Set([
  'の', 'に', 'は', 'を', 'た', 'が', 'で', 'て', 'と', 'し', 'れ', 'さ', 'ある', 'いる',
  'する', 'も', 'な', 'こと', 'これ', 'それ', 'あれ', 'この', 'その', 'あの',
  'から', 'まで', 'より', 'など', 'について', 'ため', 'よう', 'もの', 'ところ',
  'the', 'a', 'an', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
  'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'shall', 'should',
  'may', 'might', 'must', 'can', 'could', 'of', 'in', 'to', 'for', 'with',
  'on', 'at', 'by', 'from', 'as', 'into', 'through', 'and', 'but', 'or',
  'not', 'no', 'it', 'you', 'he', 'she', 'we', 'they', 'my', 'your', 'his', 'her',
  'its', 'our', 'their', 'this', 'that', 'these', 'those', 'what', 'which', 'who',
]);

function extractWords(title: string): string[] {
  // Split by non-alphanumeric/non-Japanese characters
  return title
    .toLowerCase()
    .replace(/[【】「」『』（）()[\]{}|・、。,.!?！？]/g, ' ')
    .split(/\s+/)
    .filter((w) => w.length >= 2 && !STOP_WORDS.has(w) && !/^\d+$/.test(w));
}

export function ChannelPatterns({ topicId, topicName }: Props) {
  const isMobile = useIsMobile();
  const [channels, setChannels] = useState<ChannelRanking[]>([]);
  const [videos, setVideos] = useState<VideoRanking[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);

    Promise.all([
      supabase
        .from('channel_ranking')
        .select('*')
        .contains('topic_ids', [topicId])
        .order('subscriber_count', { ascending: false })
        .limit(50),
      supabase
        .from('video_ranking')
        .select('*')
        .contains('topic_ids', [topicId])
        .order('view_count', { ascending: false })
        .limit(200),
    ]).then(([cRes, vRes]) => {
      if (cancelled) return;
      setChannels((cRes.data as ChannelRanking[]) ?? []);
      setVideos((vRes.data as VideoRanking[]) ?? []);
      setLoading(false);
    });

    return () => { cancelled = true; };
  }, [topicId]);

  const patterns = useMemo(() => {
    if (channels.length === 0) return null;

    // Top channels (1K+ subscribers)
    const topChannels = channels.filter((c) => c.subscriber_count >= 1000);
    if (topChannels.length === 0) return null;

    // Average posting frequency (videos per week)
    const freqs = topChannels.map((c) => {
      const ageDays = Math.max(1, Math.floor((Date.now() - new Date(c.published_at).getTime()) / 86400000));
      return (c.video_count / ageDays) * 7;
    });
    const avgFreq = freqs.reduce((s, f) => s + f, 0) / freqs.length;

    // Average video duration
    const topChannelIds = new Set(topChannels.map((c) => c.id));
    const topVideos = videos.filter((v) => topChannelIds.has(v.channel_id));
    const avgDuration = topVideos.length > 0
      ? topVideos.reduce((s, v) => s + v.duration_seconds, 0) / topVideos.length
      : 0;

    // Title word frequency
    const wordCounts = new Map<string, number>();
    for (const v of topVideos) {
      const words = extractWords(v.title);
      for (const w of words) {
        wordCounts.set(w, (wordCounts.get(w) ?? 0) + 1);
      }
    }
    const topWords: WordCount[] = [...wordCounts.entries()]
      .filter(([, count]) => count >= 3)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 20)
      .map(([word, count]) => ({ word, count }));

    // Average title length
    const avgTitleLen = topVideos.length > 0
      ? Math.round(topVideos.reduce((s, v) => s + v.title.length, 0) / topVideos.length)
      : 0;

    return {
      channelCount: topChannels.length,
      avgFreq: Math.round(avgFreq * 10) / 10,
      avgDuration: Math.round(avgDuration),
      avgTitleLen,
      topWords,
    };
  }, [channels, videos]);

  if (loading) {
    return <div className="loading"><div className="spinner" /><p>パターン分析中...</p></div>;
  }

  if (!patterns) {
    return <p className="empty-msg">分析に必要なチャンネルデータが不足しています</p>;
  }

  const maxWordCount = patterns.topWords.length > 0 ? patterns.topWords[0].count : 1;
  const durationMin = Math.floor(patterns.avgDuration / 60);
  const durationSec = patterns.avgDuration % 60;

  return (
    <div className="ca-section">
      <p className="chart-desc">
        {topicName}で登録者1,000人以上のトップチャンネル({patterns.channelCount}ch)から抽出した成功パターン。
      </p>

      <div className="pattern-kpis">
        <div className="pattern-kpi">
          <div className="pattern-kpi-value">{patterns.avgFreq}</div>
          <div className="pattern-kpi-label">本/週</div>
          <div className="pattern-kpi-desc">平均投稿頻度</div>
        </div>
        <div className="pattern-kpi">
          <div className="pattern-kpi-value">{durationMin}:{durationSec.toString().padStart(2, '0')}</div>
          <div className="pattern-kpi-label">平均尺</div>
          <div className="pattern-kpi-desc">動画の平均長さ</div>
        </div>
        <div className="pattern-kpi">
          <div className="pattern-kpi-value">{patterns.avgTitleLen}</div>
          <div className="pattern-kpi-label">文字</div>
          <div className="pattern-kpi-desc">平均タイトル長</div>
        </div>
      </div>

      {patterns.topWords.length > 0 && (
        <>
          <h4 className="pattern-subtitle">タイトル頻出ワード TOP{Math.min(20, patterns.topWords.length)}</h4>
          {isMobile ? (
            <div className="tag-list">
              {patterns.topWords.map((w, i) => (
                <div key={w.word} className="tag-item">
                  <span className="tag-rank">#{i + 1}</span>
                  <span className="tag-name">{w.word}</span>
                  <div className="tag-bar-wrap">
                    <div className="tag-bar" style={{ width: `${(w.count / maxWordCount) * 100}%` }} />
                  </div>
                  <span className="tag-count">{w.count}回</span>
                </div>
              ))}
            </div>
          ) : (
            <ResponsiveContainer width="100%" height={Math.min(patterns.topWords.length * 28 + 40, 600)}>
              <BarChart data={patterns.topWords} layout="vertical" margin={{ left: 80 }}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis type="number" tick={{ fontSize: 11 }} />
                <YAxis type="category" dataKey="word" width={70} tick={{ fontSize: 11 }} />
                <Tooltip formatter={(v: number) => `${v}回`} />
                <Bar dataKey="count" fill="#6366f1" name="出現回数" radius={[0, 4, 4, 0]} />
              </BarChart>
            </ResponsiveContainer>
          )}
        </>
      )}
    </div>
  );
}
