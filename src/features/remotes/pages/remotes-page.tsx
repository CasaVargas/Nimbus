import { useState, useCallback } from "react";
import { Plus, CloudOff, Loader2 } from "lucide-react";
import { PageHeader } from "@/components/page-header";
import { EmptyState } from "@/components/empty-state";
import { Button } from "@/components/ui/button";
import { RemoteCard } from "../components/remote-card";
import { DeleteRemoteDialog } from "../components/delete-remote-dialog";
import { useRemotes, useDeleteRemote } from "../hooks/use-remotes";

export default function RemotesPage() {
  const { data: remotes, isLoading, isError, error } = useRemotes();
  const deleteMutation = useDeleteRemote();
  const [deleteTarget, setDeleteTarget] = useState<string | null>(null);

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
          <Button size="sm">
            <Plus className="size-4" data-icon="inline-start" />
            Add Remote
          </Button>
        }
      />

      <div className="flex-1 p-6">
        {isLoading && (
          <div className="flex flex-1 items-center justify-center py-16">
            <Loader2 className="size-6 animate-spin text-muted-foreground" />
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
              <Button size="sm">
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
    </div>
  );
}
