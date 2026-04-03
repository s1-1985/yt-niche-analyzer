import { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';
import { HelpButton, HELP_TEXTS } from './HelpButton';
import type { KeywordOpportunity } from '../types/database';
import type { TimePeriod, VideoType } from '../hooks/useFilteredQuery';

interface Props {
  period: TimePeriod;
  videoType?: VideoType;
  country?: string | null;
}

function getMinDate(period: TimePeriod): string | null {
  if (period === 'all') return null;
  const now = new Date();
  switch (period) {
    case '24h': now.setHours(now.getHours() - 24); break;
    case '1w': now.setDate(now.getDate() - 7); break;
    case '1m': now.setMonth(now.getMonth() - 1); break;
    case '3m': now.setMonth(now.getMonth() - 3); break;
  }
  return now.toISOString();
}

function scoreColor(score: number, max: number): string {
  const ratio = score / max;
  if (ratio > 0.7) return '#10b981';
  if (ratio > 0.4) return '#f59e0b';
  return '#6366f1';
}

function demandSupplyLabel(avgViews: number, channelCount: number): { label: string; color: string } {
  const ratio = avgViews / Math.max(channelCount, 1);
  if (ratio > 50000) return { label: '超穴場', color: '#10b981' };
  if (ratio > 10000) return { label: '穴場', color: '#34d399' };
  if (ratio > 3000) return { label: '狙い目', color: '#f59e0b' };
  return { label: '激戦', color: '#ef4444' };
}

export function KeywordOpportunityChart({ period, videoType = 'all', country = null }: Props) {
  const [data, setData] = useState<KeywordOpportunity[]>([]);
  const [loading, setLoading] = useState(true);
  const [showCount, setShowCount] = useState<20 | 50 | 100>(20);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);

    const minDate = getMinDate(period);
    supabase.rpc('fn_keyword_opportunity', {
      p_min_date: minDate,
      p_video_type: videoType,
      p_country: country,
      p_topic_id: null,
    }).then((res) => {
      if (cancelled) return;
      setData((res.data as KeywordOpportunity[]) ?? []);
      setLoading(false);
    });

    return () => { cancelled = true; };
  }, [period, videoType, country]);

  if (loading) return <div className="chart-card"><div className="loading"><div className="spinner" /><p>読み込み中...</p></div></div>;
  if (data.length === 0) {
    return (
      <div className="chart-card keyword-opportunity">
        <div className="chart-title-row">
          <h3>お宝キーワード発見</h3>
          <HelpButton {...HELP_TEXTS.keywordOpportunity} />
        </div>
        <p className="empty-msg">キーワードデータがまだありません。SQL migration (migrate_keyword_analysis.sql) の実行が必要です。</p>
      </div>
    );
  }

  const maxScore = data[0]?.keyword_score ?? 1;
  const visible = data.slice(0, showCount);

  return (
    <div className="chart-card keyword-opportunity">
      <div className="chart-title-row">
        <h3>お宝キーワード発見</h3>
        <HelpButton {...HELP_TEXTS.keywordOpportunity} />
      </div>
      <p className="chart-desc">
        需要が高く競合が少ない「狙い目キーワード」をスコア順にランキング
      </p>

      <div className="keyword-show-selector">
        {([20, 50, 100] as const).map((n) => (
          <button key={n}
            className={`buzz-period-btn ${showCount === n ? 'active' : ''}`}
            onClick={() => setShowCount(n)}>
            TOP {n}
          </button>
        ))}
      </div>

      <div className="keyword-list">
        <div className="keyword-list-header">
          <span className="kw-col-rank">#</span>
          <span className="kw-col-tag">キーワード</span>
          <span className="kw-col-score">スコア</span>
          <span className="kw-col-bar" />
          <span className="kw-col-views">平均再生</span>
          <span className="kw-col-comp">競合CH</span>
          <span className="kw-col-buzz">拡散度</span>
          <span className="kw-col-label">判定</span>
        </div>
        {visible.map((kw) => {
          const ds = demandSupplyLabel(kw.avg_views, kw.channel_count);
          return (
            <div key={kw.tag} className="keyword-item">
              <span className="kw-col-rank">#{kw.rank}</span>
              <span className="kw-col-tag kw-tag-name">{kw.tag}</span>
              <span className="kw-col-score">{kw.keyword_score.toLocaleString()}</span>
              <span className="kw-col-bar">
                <div className="kw-score-bar"
                  style={{
                    width: `${Math.min(100, (kw.keyword_score / maxScore) * 100)}%`,
                    backgroundColor: scoreColor(kw.keyword_score, maxScore),
                  }} />
              </span>
              <span className="kw-col-views">{kw.avg_views.toLocaleString()}</span>
              <span className="kw-col-comp">{kw.channel_count}</span>
              <span className="kw-col-buzz">{kw.avg_buzz_score}x</span>
              <span className="kw-col-label">
                <span className="kw-ds-badge" style={{ backgroundColor: ds.color }}>{ds.label}</span>
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
}
