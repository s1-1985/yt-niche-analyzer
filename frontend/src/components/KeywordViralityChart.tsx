import { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';
import { HelpButton, HELP_TEXTS } from './HelpButton';
import type { KeywordVirality } from '../types/database';
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

function viralBadge(viralRatePct: number): { label: string; color: string } {
  if (viralRatePct >= 60) return { label: '超拡散', color: '#ef4444' };
  if (viralRatePct >= 40) return { label: '高拡散', color: '#f59e0b' };
  if (viralRatePct >= 20) return { label: '中拡散', color: '#6366f1' };
  return { label: '低拡散', color: '#64748b' };
}

function buzzBar(score: number, max: number): string {
  if (max <= 0) return '0%';
  return `${Math.min(100, (score / max) * 100)}%`;
}

export function KeywordViralityChart({ period, videoType = 'all', country = null }: Props) {
  const [data, setData] = useState<KeywordVirality[]>([]);
  const [loading, setLoading] = useState(true);
  const [showCount, setShowCount] = useState<20 | 50 | 100>(20);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);

    const minDate = getMinDate(period);
    supabase.rpc('fn_keyword_virality', {
      p_min_date: minDate,
      p_video_type: videoType,
      p_country: country,
      p_topic_id: null,
    }).then((res) => {
      if (cancelled) return;
      setData((res.data as KeywordVirality[]) ?? []);
      setLoading(false);
    });

    return () => { cancelled = true; };
  }, [period, videoType, country]);

  if (loading) return <div className="chart-card"><div className="loading"><div className="spinner" /><p>読み込み中...</p></div></div>;
  if (data.length === 0) {
    return (
      <div className="chart-card keyword-virality">
        <div className="chart-title-row">
          <h3>キーワード拡散ランキング</h3>
          <HelpButton {...HELP_TEXTS.keywordVirality} />
        </div>
        <p className="empty-msg">キーワードデータがまだありません。SQL migration (migrate_keyword_analysis.sql) の実行が必要です。</p>
      </div>
    );
  }

  const maxVirality = data[0]?.virality_score ?? 1;
  const visible = data.slice(0, showCount);

  return (
    <div className="chart-card keyword-virality">
      <div className="chart-title-row">
        <h3>キーワード拡散ランキング</h3>
        <HelpButton {...HELP_TEXTS.keywordVirality} />
      </div>
      <p className="chart-desc">
        おすすめに載りやすいキーワード。拡散度 = 登録者数を超えた再生 × エンゲージメント
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
          <span className="kw-col-score">拡散スコア</span>
          <span className="kw-col-bar" />
          <span className="kw-col-views">平均再生</span>
          <span className="kw-col-buzz">Buzz倍率</span>
          <span className="kw-col-comp">拡散率</span>
          <span className="kw-col-label">判定</span>
        </div>
        {visible.map((kw) => {
          const badge = viralBadge(kw.viral_rate_pct);
          return (
            <div key={kw.tag} className="keyword-item">
              <span className="kw-col-rank">#{kw.rank}</span>
              <span className="kw-col-tag kw-tag-name">{kw.tag}</span>
              <span className="kw-col-score">{Number(kw.virality_score).toLocaleString()}</span>
              <span className="kw-col-bar">
                <div className="kw-score-bar virality-bar"
                  style={{ width: buzzBar(kw.virality_score, maxVirality) }} />
              </span>
              <span className="kw-col-views">{kw.avg_views.toLocaleString()}</span>
              <span className="kw-col-buzz">{kw.avg_buzz_score}x</span>
              <span className="kw-col-comp">{kw.viral_rate_pct}%</span>
              <span className="kw-col-label">
                <span className="kw-ds-badge" style={{ backgroundColor: badge.color }}>{badge.label}</span>
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
}
