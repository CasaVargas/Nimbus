import { useState } from "react";
import {
  FolderPlus,
  Upload,
  List,
  LayoutGrid,
  Filter,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

export type ViewMode = "list" | "grid";

interface BrowserToolbarProps {
  viewMode: ViewMode;
  onViewModeChange: (mode: ViewMode) => void;
  onNewFolder: () => void;
  onUpload: () => void;
  filter: string;
  onFilterChange: (value: string) => void;
}

export function BrowserToolbar({
  viewMode,
  onViewModeChange,
  onNewFolder,
  onUpload,
  filter,
  onFilterChange,
}: BrowserToolbarProps) {
  const [showFilter, setShowFilter] = useState(false);

  return (
    <div className="flex flex-col gap-2">
      <div className="flex items-center gap-2">
        <div className="flex items-center rounded-lg border border-input">
          <Button
            variant={viewMode === "list" ? "secondary" : "ghost"}
            size="icon-sm"
            onClick={() => onViewModeChange("list")}
            aria-label="List view"
            className="rounded-r-none"
          >
            <List />
          </Button>
          <Button
            variant={viewMode === "grid" ? "secondary" : "ghost"}
            size="icon-sm"
            onClick={() => onViewModeChange("grid")}
            aria-label="Grid view"
            className="rounded-l-none"
          >
            <LayoutGrid />
          </Button>
        </div>

        <div className="flex-1" />

        <Button
          variant="ghost"
          size="icon-sm"
          onClick={() => setShowFilter((v) => !v)}
          aria-label="Toggle filter"
        >
          <Filter />
        </Button>

        <Button variant="outline" size="sm" onClick={onNewFolder}>
          <FolderPlus data-icon="inline-start" />
          New Folder
        </Button>

        <Button variant="outline" size="sm" onClick={onUpload}>
          <Upload data-icon="inline-start" />
          Upload
        </Button>
      </div>

      {showFilter && (
        <Input
          placeholder="Filter this folder..."
          value={filter}
          onChange={(e) => onFilterChange(e.target.value)}
          className="max-w-xs"
          autoFocus
        />
      )}
    </div>
  );
}
