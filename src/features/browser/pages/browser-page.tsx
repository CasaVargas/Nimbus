import { PageHeader } from "@/components/page-header";

export default function BrowserPage() {
  return (
    <div>
      <PageHeader
        title="Browser"
        description="Browse files on your remotes"
      />
      <div className="p-6">
        <p className="text-muted-foreground">File browser coming soon.</p>
      </div>
    </div>
  );
}
