import { ChevronRight, Home } from "lucide-react";
import { cn } from "@/lib/utils";

interface PathBreadcrumbProps {
  remote: string;
  path: string;
  onNavigate: (path: string) => void;
}

export function PathBreadcrumb({
  remote,
  path,
  onNavigate,
}: PathBreadcrumbProps) {
  const segments = path ? path.split("/").filter(Boolean) : [];

  return (
    <nav className="flex items-center gap-1 text-sm" aria-label="Breadcrumb">
      <button
        type="button"
        onClick={() => onNavigate("")}
        className={cn(
          "flex items-center gap-1 rounded-md px-1.5 py-0.5 font-medium transition-colors hover:bg-muted",
          segments.length === 0
            ? "text-foreground"
            : "text-muted-foreground",
        )}
      >
        <Home className="size-3.5" />
        <span>{remote}</span>
      </button>

      {segments.map((segment, index) => {
        const segmentPath = segments.slice(0, index + 1).join("/");
        const isLast = index === segments.length - 1;

        return (
          <span key={segmentPath} className="flex items-center gap-1">
            <ChevronRight className="size-3.5 text-muted-foreground" />
            <button
              type="button"
              onClick={() => onNavigate(segmentPath)}
              className={cn(
                "rounded-md px-1.5 py-0.5 transition-colors hover:bg-muted",
                isLast
                  ? "font-medium text-foreground"
                  : "text-muted-foreground",
              )}
            >
              {segment}
            </button>
          </span>
        );
      })}
    </nav>
  );
}
