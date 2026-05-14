import {
  ArrowLeftRight,
  FolderOpen,
  HardDriveUpload,
  Pencil,
  Trash2,
} from "lucide-react";
import { useNavigate } from "react-router-dom";
import { RemoteIcon } from "@/components/remote-icon";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardAction,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import type { RemoteEntry } from "../hooks/use-remotes";

interface RemoteCardProps {
  remote: RemoteEntry;
  onEdit: (remote: RemoteEntry) => void;
  onDelete: (name: string) => void;
}

export function RemoteCard({ remote, onEdit, onDelete }: RemoteCardProps) {
  const navigate = useNavigate();

  return (
    <Card className="group relative">
      <CardHeader>
        <div className="flex items-center gap-3">
          <div className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-muted">
            <RemoteIcon
              type={remote.type}
              className="size-4 text-muted-foreground"
            />
          </div>
          <div className="min-w-0">
            <CardTitle className="truncate">{remote.name}</CardTitle>
            <CardDescription className="truncate">
              {remote.type}
            </CardDescription>
          </div>
        </div>
        <CardAction>
          <Tooltip>
            <TooltipTrigger
              render={
                <Button
                  variant="ghost"
                  size="icon-xs"
                  className="opacity-0 transition-opacity group-hover:opacity-100"
                  onClick={() => onDelete(remote.name)}
                />
              }
            >
              <Trash2 className="size-3.5 text-destructive" />
            </TooltipTrigger>
            <TooltipContent>Delete remote</TooltipContent>
          </Tooltip>
        </CardAction>
      </CardHeader>
      <CardFooter className="gap-1">
        <Tooltip>
          <TooltipTrigger
            render={
              <Button
                variant="ghost"
                size="icon-sm"
                onClick={() => onEdit(remote)}
              />
            }
          >
            <Pencil className="size-3.5" />
          </TooltipTrigger>
          <TooltipContent>Edit config</TooltipContent>
        </Tooltip>
        <Tooltip>
          <TooltipTrigger
            render={
              <Button
                variant="ghost"
                size="icon-sm"
                onClick={() => navigate(`/browser/${remote.name}`)}
              />
            }
          >
            <FolderOpen className="size-3.5" />
          </TooltipTrigger>
          <TooltipContent>Browse files</TooltipContent>
        </Tooltip>
        <Tooltip>
          <TooltipTrigger
            render={
              <Button
                variant="ghost"
                size="icon-sm"
                onClick={() => navigate(`/mounts?remote=${remote.name}`)}
              />
            }
          >
            <HardDriveUpload className="size-3.5" />
          </TooltipTrigger>
          <TooltipContent>Mount</TooltipContent>
        </Tooltip>
        <Tooltip>
          <TooltipTrigger
            render={
              <Button
                variant="ghost"
                size="icon-sm"
                onClick={() => navigate(`/copy-sync?src=${remote.name}:`)}
              />
            }
          >
            <ArrowLeftRight className="size-3.5" />
          </TooltipTrigger>
          <TooltipContent>Copy / Sync</TooltipContent>
        </Tooltip>
      </CardFooter>
    </Card>
  );
}
