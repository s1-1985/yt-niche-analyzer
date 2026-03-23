import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';

export type TimePeriod = '24h' | '1w' | '1m' | '3m' | 'all';

interface QueryState<T> {
  data: T[];
  loading: boolean;
  error: string | null;
}

function getMinDate(period: TimePeriod): string | null {
  if (period === 'all') return null;
  const now = new Date();
  switch (period) {
    case '24h':
      now.setHours(now.getHours() - 24);
      break;
    case '1w':
      now.setDate(now.getDate() - 7);
      break;
    case '1m':
      now.setMonth(now.getMonth() - 1);
      break;
    case '3m':
      now.setMonth(now.getMonth() - 3);
      break;
  }
  return now.toISOString();
}

/**
 * RPC function経由でフィルタ付きクエリを実行するhook。
 * period === 'all' の場合はビュー(view)から直接取得（高速）。
 * それ以外の場合は fn_<view名> RPC関数を呼び出す。
 */
export function useFilteredQuery<T>(
  view: string,
  period: TimePeriod,
) {
  const [state, setState] = useState<QueryState<T>>({
    data: [],
    loading: true,
    error: null,
  });

  useEffect(() => {
    let cancelled = false;

    async function fetch() {
      setState((prev) => ({ ...prev, loading: true, error: null }));

      try {
        let data: T[] | null;
        let error: { message: string } | null;

        if (period === 'all') {
          // Use the view directly for "all time" (faster, no RPC overhead)
          const res = await supabase.from(view).select('*');
          data = res.data as T[] | null;
          error = res.error;
        } else {
          // Use the RPC function with date filter
          const minDate = getMinDate(period);
          const res = await supabase.rpc(`fn_${view}`, { p_min_date: minDate });
          data = res.data as T[] | null;
          error = res.error;
        }

        if (cancelled) return;

        if (error) {
          // If RPC function doesn't exist, fall back to view
          console.warn(`RPC fn_${view} failed, falling back to view:`, error.message);
          const res = await supabase.from(view).select('*');
          if (cancelled) return;
          if (res.error) {
            setState({ data: [], loading: false, error: res.error.message });
          } else {
            setState({ data: (res.data as T[]) ?? [], loading: false, error: null });
          }
        } else {
          setState({ data: data ?? [], loading: false, error: null });
        }
      } catch (err) {
        if (!cancelled) {
          setState({ data: [], loading: false, error: String(err) });
        }
      }
    }

    fetch();
    return () => {
      cancelled = true;
    };
  }, [view, period]);

  return state;
}
