import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';

interface QueryState<T> {
  data: T[];
  loading: boolean;
  error: string | null;
}

export function useSupabaseQuery<T>(
  view: string,
  orderBy?: { column: string; ascending?: boolean },
  limit?: number,
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

      let query = supabase.from(view).select('*');
      if (orderBy) {
        query = query.order(orderBy.column, {
          ascending: orderBy.ascending ?? false,
        });
      }
      if (limit) {
        query = query.limit(limit);
      }

      const { data, error } = await query;

      if (cancelled) return;

      if (error) {
        setState({ data: [], loading: false, error: error.message });
      } else {
        setState({ data: (data as T[]) ?? [], loading: false, error: null });
      }
    }

    fetch();
    return () => {
      cancelled = true;
    };
  }, [view, orderBy?.column, orderBy?.ascending, limit]);

  return state;
}
