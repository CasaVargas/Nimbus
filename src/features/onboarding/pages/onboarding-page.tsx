import { PageHeader } from "@/components/page-header";

export default function OnboardingPage() {
  return (
    <div>
      <PageHeader title="Welcome to StreamCloned" />
      <div className="p-6">
        <p className="text-muted-foreground">
          Setup wizard coming soon.
        </p>
      </div>
    </div>
  );
}
