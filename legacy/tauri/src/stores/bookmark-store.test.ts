import { beforeEach, describe, expect, it } from "vitest";
import { useBookmarkStore } from "./bookmark-store";

describe("bookmarkStore", () => {
  beforeEach(() => {
    useBookmarkStore.setState({ bookmarks: [] });
  });

  it("adds a bookmark", () => {
    const { addBookmark } = useBookmarkStore.getState();
    addBookmark("gdrive", "Documents/Work", "Work Docs");

    const { bookmarks } = useBookmarkStore.getState();
    expect(bookmarks).toHaveLength(1);
    expect(bookmarks[0]).toMatchObject({
      remoteName: "gdrive",
      path: "Documents/Work",
      label: "Work Docs",
      order: 0,
    });
    expect(bookmarks[0].id).toBeDefined();
  });

  it("removes a bookmark", () => {
    const { addBookmark } = useBookmarkStore.getState();
    addBookmark("gdrive", "path1", "Bookmark 1");
    addBookmark("s3", "path2", "Bookmark 2");

    const id = useBookmarkStore.getState().bookmarks[0].id;
    useBookmarkStore.getState().removeBookmark(id);

    const { bookmarks } = useBookmarkStore.getState();
    expect(bookmarks).toHaveLength(1);
    expect(bookmarks[0].label).toBe("Bookmark 2");
  });

  it("renames a bookmark", () => {
    const { addBookmark } = useBookmarkStore.getState();
    addBookmark("gdrive", "path", "Old Name");

    const id = useBookmarkStore.getState().bookmarks[0].id;
    useBookmarkStore.getState().renameBookmark(id, "New Name");

    expect(useBookmarkStore.getState().bookmarks[0].label).toBe("New Name");
  });

  it("reorders bookmarks", () => {
    const { addBookmark } = useBookmarkStore.getState();
    addBookmark("a", "p1", "First");
    addBookmark("b", "p2", "Second");
    addBookmark("c", "p3", "Third");

    const ids = useBookmarkStore.getState().bookmarks.map((b) => b.id);
    useBookmarkStore.getState().reorderBookmarks([ids[2], ids[0], ids[1]]);

    const labels = useBookmarkStore.getState().bookmarks.map((b) => b.label);
    expect(labels).toEqual(["Third", "First", "Second"]);
  });
});
