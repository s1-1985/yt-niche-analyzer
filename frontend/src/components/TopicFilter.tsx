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

  const handleCategoryChange = (cat: string | null) => {
    onCategoryChange(cat);
    onTopicChange(null);
  };

  return (
    <div className="topic-filter">
      <div className="topic-filter-row">
        <span className="topic-filter-label">ジャンル</span>
        <div className="topic-filter-buttons">
          <button
            className={`topic-filter-btn ${!selectedCategory ? 'active' : ''}`}
            onClick={() => handleCategoryChange(null)}
          >
            全体
          </button>
          {categories.map((cat) => (
            <button
              key={cat}
              className={`topic-filter-btn ${selectedCategory === cat && !selectedTopicId ? 'active' : ''} ${selectedCategory === cat && selectedTopicId ? 'active-parent' : ''}`}
              onClick={() => handleCategoryChange(cat === selectedCategory ? null : cat)}
            >
              {cat}
            </button>
          ))}
        </div>
      </div>

      {selectedCategory && subTopics.length > 0 && (
        <div className="topic-filter-row sub">
          <span className="topic-filter-label">サブジャンル</span>
          <div className="topic-filter-buttons sub-buttons">
            <button
              className={`topic-filter-btn ${!selectedTopicId ? 'active' : ''}`}
              onClick={() => onTopicChange(null)}
            >
              全サブ
            </button>
            {subTopics.map((t) => (
              <button
                key={t.id}
                className={`topic-filter-btn ${selectedTopicId === t.id ? 'active' : ''}`}
                onClick={() => onTopicChange(t.id === selectedTopicId ? null : t.id)}
              >
                {t.name_ja ?? t.name}
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
