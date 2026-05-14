import { create } from "zustand";
import { persist } from "zustand/middleware";

export interface Bookmark {
  id: string;
  remoteName: string;
  path: string;
  label: string;
  order: number;
}

interface BookmarkState {
  bookmarks: Bookmark[];
  addBookmark: (remoteName: string, path: string, label: string) => void;
  removeBookmark: (id: string) => void;
  renameBookmark: (id: string, label: string) => void;
  reorderBookmarks: (orderedIds: string[]) => void;
}

export const useBookmarkStore = create<BookmarkState>()(
  persist(
    (set) => ({
      bookmarks: [],

      addBookmark: (remoteName, path, label) =>
        set((state) => ({
          bookmarks: [
            ...state.bookmarks,
            {
              id: crypto.randomUUID(),
              remoteName,
              path,
              label,
              order: state.bookmarks.length,
            },
          ],
        })),

      removeBookmark: (id) =>
        set((state) => ({
          bookmarks: state.bookmarks
            .filter((b) => b.id !== id)
            .map((b, i) => ({ ...b, order: i })),
        })),

      renameBookmark: (id, label) =>
        set((state) => ({
          bookmarks: state.bookmarks.map((b) =>
            b.id === id ? { ...b, label } : b,
          ),
        })),

      reorderBookmarks: (orderedIds) =>
        set((state) => {
          const byId = new Map(state.bookmarks.map((b) => [b.id, b]));
          return {
            bookmarks: orderedIds
              .map((id, i) => {
                const b = byId.get(id);
                return b ? { ...b, order: i } : null;
              })
              .filter((b): b is Bookmark => b !== null),
          };
        }),
    }),
    { name: "nimbus-bookmarks" },
  ),
);
