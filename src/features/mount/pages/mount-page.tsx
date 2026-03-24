import { PageHeader } from "@/components/page-header";

export default function MountPage() {
  return (
    <div>
      <PageHeader
        title="Mounts"
        description="Mount remotes as local drives"
      />
      <div className="p-6">
        <p className="text-muted-foreground">Mount manager coming soon.</p>
      </div>
    </div>
  );
}
