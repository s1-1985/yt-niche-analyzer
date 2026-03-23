interface KpiCardProps {
  title: string;
  value: string | number;
  sub?: string;
  color?: string;
}

export function KpiCard({ title, value, sub, color = '#6366f1' }: KpiCardProps) {
  return (
    <div className="kpi-card">
      <div className="kpi-title">{title}</div>
      <div className="kpi-value" style={{ color }}>{value}</div>
      {sub && <div className="kpi-sub">{sub}</div>}
    </div>
  );
}
