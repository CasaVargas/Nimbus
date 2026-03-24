import { PageHeader } from "@/components/page-header";

export default function TransfersPage() {
  return (
    <div>
      <PageHeader
        title="Transfers"
        description="Monitor active file transfers"
      />
      <div className="p-6">
        <p className="text-muted-foreground">Transfer queue coming soon.</p>
      </div>
    </div>
  );
}
