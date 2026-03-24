import { useCallback, useRef, useState } from "react";

export function useSelection(names: string[]) {
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const lastClickedRef = useRef<string | null>(null);

  const toggle = useCallback(
    (name: string, event: React.MouseEvent) => {
      const isMetaKey = event.metaKey || event.ctrlKey;
      const isShiftKey = event.shiftKey;

      setSelected((prev) => {
        const next = new Set(prev);

        if (isShiftKey && lastClickedRef.current) {
          const startIdx = names.indexOf(lastClickedRef.current);
          const endIdx = names.indexOf(name);
          if (startIdx !== -1 && endIdx !== -1) {
            const [from, to] =
              startIdx < endIdx
                ? [startIdx, endIdx]
                : [endIdx, startIdx];
            for (let i = from; i <= to; i++) {
              next.add(names[i]);
            }
          }
        } else if (isMetaKey) {
          if (next.has(name)) {
            next.delete(name);
          } else {
            next.add(name);
          }
        } else {
          next.clear();
          next.add(name);
        }

        return next;
      });

      lastClickedRef.current = name;
    },
    [names],
  );

  const clear = useCallback(() => {
    setSelected(new Set());
    lastClickedRef.current = null;
  }, []);

  const selectAll = useCallback(() => {
    setSelected(new Set(names));
  }, [names]);

  return { selected, toggle, clear, selectAll };
}
