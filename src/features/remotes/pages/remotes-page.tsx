import { CloudOff, Plus, Upload } from "lucide-react";
import { useCallback, useState } from "react";
import { EmptyState } from "@/components/empty-state";
import { PageHeader } from "@/components/page-header";
import { Skeleton } from "@/components/skeleton";
import { Button } from "@/components/ui/button";
import { AddRemoteDialog } from "../components/add-remote-dialog";
import { DeleteRemoteDialog } from "../components/delete-remote-dialog";
import { EditRemoteDialog } from "../components/edit-remote-dialog";
import { ImportConfigDialog } from "../components/import-config-dialog";
import { RemoteCard } from "../components/remote-card";
import {
  type RemoteEntry,
  useDeleteRemote,
  useRemotes,
} from "../hooks/use-remotes";

export default function RemotesPage() {
  const { data: remotes, isLoading, isError, error } = useRemotes();
  const deleteMutation = useDeleteRemote();
  const [deleteTarget, setDeleteTarget] = useState<string | null>(null);
  const [editTarget, setEditTarget] = useState<RemoteEntry | null>(null);
  const [showAdd, setShowAdd] = useState(false);
  const [showImport, setShowImport] = useState(false);

  const handleDeleteConfirm = useCallback(() => {
    if (!deleteTarget) return;
    deleteMutation.mutate(deleteTarget, {
      onSuccess: () => setDeleteTarget(null),
    });
  }, [deleteTarget, deleteMutation]);

  return (
    <div className="flex flex-1 flex-col">
      <PageHeader
        title="Remotes"
        description="Manage your cloud storage connections"
        actions={
          <div className="flex items-center gap-2">
            <Button
              size="sm"
              variant="outline"
              onClick={() => setShowImport(true)}
            >
              <Upload className="size-4" data-icon="inline-start" />
              Import Config
            </Button>
            <Button size="sm" onClick={() => setShowAdd(true)}>
              <Plus className="size-4" data-icon="inline-start" />
              Add Remote
            </Button>
          </div>
        }
      />

      <div className="flex-1 p-6">
        {isLoading && (
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {Array.from({ length: 6 }).map((_, i) => (
              <div key={i} className="rounded-xl border p-4 space-y-3">
                <div className="flex items-center gap-3">
                  <Skeleton className="size-9 rounded-lg" />
                  <div className="space-y-1.5 flex-1">
                    <Skeleton className="h-4 w-24" />
                    <Skeleton className="h-3 w-16" />
                  </div>
                </div>
                <div className="flex gap-1">
                  <Skeleton className="size-8 rounded-md" />
                  <Skeleton className="size-8 rounded-md" />
                  <Skeleton className="size-8 rounded-md" />
                </div>
              </div>
            ))}
          </div>
        )}

        {isError && (
          <EmptyState
            icon={CloudOff}
            title="Failed to load remotes"
            description={error?.message ?? "An unknown error occurred."}
          />
        )}

        {remotes && remotes.length === 0 && (
          <EmptyState
            icon={CloudOff}
            title="No remotes configured"
            description="Add a remote to connect to cloud storage, SFTP servers, or local paths."
            action={
              <Button size="sm" onClick={() => setShowAdd(true)}>
                <Plus className="size-4" data-icon="inline-start" />
                Add Remote
              </Button>
            }
          />
        )}

        {remotes && remotes.length > 0 && (
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {remotes.map((remote) => (
              <RemoteCard
                key={remote.name}
                remote={remote}
                onEdit={setEditTarget}
                onDelete={setDeleteTarget}
              />
            ))}
          </div>
        )}
      </div>

      <DeleteRemoteDialog
        name={deleteTarget}
        open={deleteTarget !== null}
        onOpenChange={(open) => {
          if (!open) setDeleteTarget(null);
        }}
        onConfirm={handleDeleteConfirm}
        isPending={deleteMutation.isPending}
      />

      <AddRemoteDialog open={showAdd} onClose={() => setShowAdd(false)} />

      <ImportConfigDialog open={showImport} onOpenChange={setShowImport} />

      <EditRemoteDialog
        remote={editTarget}
        onClose={() => setEditTarget(null)}
      />
    </div>
  );
}
