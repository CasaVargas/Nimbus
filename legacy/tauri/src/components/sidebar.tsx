import {
  ArrowUpDown,
  Copy,
  Database,
  FolderHeart,
  FolderOpen,
  HardDrive,
  PanelLeft,
  PanelLeftClose,
  Settings,
  X,
} from "lucide-react";
import { NavLink, useNavigate } from "react-router-dom";
import { Button } from "@/components/ui/button";
import {
  Tooltip,
  TooltipContent,
  TooltipProvider,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { cn } from "@/lib/utils";
import { useAppStore } from "@/stores/app-store";
import { useBookmarkStore } from "@/stores/bookmark-store";

const navItems = [
  { to: "/", icon: HardDrive, label: "Remotes", end: true },
  { to: "/browser", icon: FolderOpen, label: "Browser" },
  { to: "/copy-sync", icon: Copy, label: "Copy / Sync" },
  { to: "/transfers", icon: ArrowUpDown, label: "Transfers" },
  { to: "/mounts", icon: Database, label: "Mounts" },
  { to: "/settings", icon: Settings, label: "Settings" },
];

export function Sidebar() {
  const collapsed = useAppStore((s) => s.sidebarCollapsed);
  const toggleSidebar = useAppStore((s) => s.toggleSidebar);
  const bookmarks = useBookmarkStore((s) => s.bookmarks);
  const removeBookmark = useBookmarkStore((s) => s.removeBookmark);
  const navigate = useNavigate();

  return (
    <TooltipProvider delay={0}>
      <aside
        className={cn(
          "flex h-screen flex-col border-r bg-sidebar transition-[width] duration-200",
          collapsed ? "w-16" : "w-56",
        )}
      >
        <div
          className={cn(
            "flex h-14 items-center border-b px-4",
            collapsed ? "justify-center" : "justify-between",
          )}
        >
          {!collapsed && (
            <span className="text-sm font-semibold tracking-tight">Nimbus</span>
          )}
          <Button
            variant="ghost"
            size="icon"
            className="h-8 w-8"
            onClick={toggleSidebar}
          >
            {collapsed ? (
              <PanelLeft className="h-4 w-4" />
            ) : (
              <PanelLeftClose className="h-4 w-4" />
            )}
          </Button>
        </div>

        <nav className="flex flex-1 flex-col gap-1 p-2">
          {navItems.map((item) => (
            <Tooltip key={item.to}>
              <TooltipTrigger
                render={
                  <NavLink
                    to={item.to}
                    end={item.end}
                    className={({ isActive }) =>
                      cn(
                        "flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors",
                        "hover:bg-accent hover:text-accent-foreground",
                        isActive
                          ? "bg-accent text-accent-foreground"
                          : "text-muted-foreground",
                        collapsed && "justify-center px-0",
                      )
                    }
                  />
                }
              >
                <item.icon className="h-4 w-4 shrink-0" />
                {!collapsed && <span>{item.label}</span>}
              </TooltipTrigger>
              {collapsed && (
                <TooltipContent side="right">{item.label}</TooltipContent>
              )}
            </Tooltip>
          ))}

          {bookmarks.length > 0 && (
            <div className="mt-2 border-t pt-2">
              {!collapsed && (
                <span className="px-3 py-1 text-xs font-medium text-muted-foreground">
                  Bookmarks
                </span>
              )}
              {[...bookmarks]
                .sort((a, b) => a.order - b.order)
                .map((bookmark) => (
                  <Tooltip key={bookmark.id}>
                    <TooltipTrigger
                      render={
                        <button
                          type="button"
                          onClick={() =>
                            navigate(
                              `/browser?remote=${encodeURIComponent(bookmark.remoteName)}&path=${encodeURIComponent(bookmark.path)}`,
                            )
                          }
                          className={cn(
                            "group flex w-full items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors",
                            "hover:bg-accent hover:text-accent-foreground",
                            "text-muted-foreground",
                            collapsed && "justify-center px-0",
                          )}
                        />
                      }
                    >
                      <FolderHeart className="h-4 w-4 shrink-0" />
                      {!collapsed && (
                        <>
                          <span className="flex-1 truncate text-left">
                            {bookmark.label}
                          </span>
                          <button
                            type="button"
                            onClick={(e) => {
                              e.stopPropagation();
                              removeBookmark(bookmark.id);
                            }}
                            className="invisible ml-auto h-4 w-4 shrink-0 rounded group-hover:visible hover:text-foreground"
                          >
                            <X className="h-4 w-4" />
                          </button>
                        </>
                      )}
                    </TooltipTrigger>
                    {collapsed && (
                      <TooltipContent side="right">
                        {bookmark.label} — {bookmark.remoteName}:{bookmark.path}
                      </TooltipContent>
                    )}
                  </Tooltip>
                ))}
            </div>
          )}
        </nav>
      </aside>
    </TooltipProvider>
  );
}
