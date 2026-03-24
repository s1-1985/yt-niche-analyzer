import { useState, useEffect } from 'react';

interface Section {
  id: string;
  label: string;
}

const SECTIONS: Section[] = [
  { id: 'kpi', label: 'KPI' },
  { id: 'buzz', label: 'Buzz' },
  { id: 'niche', label: 'ニッチ判断' },
  { id: 'supply-demand', label: '需給分析' },
  { id: 'engagement', label: 'エンゲージ' },
  { id: 'strategy', label: '戦略' },
  { id: 'trend', label: 'トレンド' },
  { id: 'market', label: '市場構造' },
  { id: 'saturation', label: '飽和予測' },
  { id: 'table', label: 'サマリー' },
];

export function SectionNav() {
  const [active, setActive] = useState('kpi');
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const handleScroll = () => {
      setVisible(window.scrollY > 300);

      // Find active section
      let current = 'kpi';
      for (const section of SECTIONS) {
        const el = document.getElementById(`section-${section.id}`);
        if (el) {
          const rect = el.getBoundingClientRect();
          if (rect.top <= 120) {
            current = section.id;
          }
        }
      }
      setActive(current);
    };

    window.addEventListener('scroll', handleScroll, { passive: true });
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  if (!visible) return null;

  const scrollTo = (id: string) => {
    const el = document.getElementById(`section-${id}`);
    if (el) {
      el.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
  };

  return (
    <nav className="section-nav" aria-label="セクションナビゲーション">
      {SECTIONS.map((s) => (
        <button
          key={s.id}
          className={`section-nav-btn ${active === s.id ? 'active' : ''}`}
          onClick={() => scrollTo(s.id)}
          aria-current={active === s.id ? 'true' : undefined}
        >
          {s.label}
        </button>
      ))}
    </nav>
  );
}
