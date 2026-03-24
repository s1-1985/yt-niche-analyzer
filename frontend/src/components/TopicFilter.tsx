import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';

interface Topic {
  id: string;
  name: string;
  name_ja: string | null;
  parent_id: string | null;
  category: string;
}

interface Props {
  selectedCategory: string | null;
  selectedTopicId: string | null;
  onCategoryChange: (cat: string | null) => void;
  onTopicChange: (topicId: string | null) => void;
}

const CATEGORY_LABELS: Record<string, string> = {
  Entertainment: 'エンタメ',
  Gaming: 'ゲーム',
  Knowledge: '知識',
  Lifestyle: 'ライフスタイル',
  Music: '音楽',
  Society: '社会',
  Sports: 'スポーツ',
};

export function TopicFilter({ selectedCategory, selectedTopicId, onCategoryChange, onTopicChange }: Props) {
  const [topics, setTopics] = useState<Topic[]>([]);

  useEffect(() => {
    let cancelled = false;
    supabase.from('topics').select('id, name, name_ja, parent_id, category')
      .then((res) => {
        if (cancelled || !res.data) return;
        setTopics(res.data as Topic[]);
      });
    return () => { cancelled = true; };
  }, []);

  const categories = Array.from(new Set(topics.filter((t) => t.parent_id === null).map((t) => t.category))).sort();

  const subTopics = selectedCategory
    ? topics.filter((t) => t.parent_id !== null && t.category === selectedCategory)
        .sort((a, b) => (a.name_ja ?? a.name).localeCompare(b.name_ja ?? b.name, 'ja'))
    : [];

  const handleCategoryChange = (value: string) => {
    if (value === '') {
      onCategoryChange(null);
      onTopicChange(null);
    } else {
      onCategoryChange(value);
      onTopicChange(null);
    }
  };

  const handleTopicChange = (value: string) => {
    onTopicChange(value === '' ? null : value);
  };

  // Display label
  const currentLabel = selectedTopicId
    ? topics.find((t) => t.id === selectedTopicId)?.name_ja ?? topics.find((t) => t.id === selectedTopicId)?.name ?? ''
    : selectedCategory
      ? `${CATEGORY_LABELS[selectedCategory] ?? selectedCategory} 全体`
      : '全ジャンル';

  return (
    <div className="topic-filter">
      <div className="topic-filter-row">
        <span className="topic-filter-label">ジャンル</span>
        <select
          className="topic-filter-select"
          value={selectedCategory ?? ''}
          onChange={(e) => handleCategoryChange(e.target.value)}
        >
          <option value="">全ジャンル</option>
          {categories.map((cat) => (
            <option key={cat} value={cat}>{CATEGORY_LABELS[cat] ?? cat}</option>
          ))}
        </select>

        {selectedCategory && subTopics.length > 0 && (
          <>
            <span className="topic-filter-arrow">&rsaquo;</span>
            <select
              className="topic-filter-select"
              value={selectedTopicId ?? ''}
              onChange={(e) => handleTopicChange(e.target.value)}
            >
              <option value="">カテゴリ全体で比較</option>
              {subTopics.map((t) => (
                <option key={t.id} value={t.id}>{t.name_ja ?? t.name}</option>
              ))}
            </select>
          </>
        )}
      </div>

      {(selectedCategory || selectedTopicId) && (
        <div className="topic-filter-badge">
          <span>{selectedTopicId ? '競合分析' : 'カテゴリ比較'}: {currentLabel}</span>
          <button
            className="topic-filter-clear"
            onClick={() => { onCategoryChange(null); onTopicChange(null); }}
          >
            ✕ リセット
          </button>
        </div>
      )}
    </div>
  );
}
