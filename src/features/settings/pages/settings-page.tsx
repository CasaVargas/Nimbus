import { PageHeader } from "@/components/page-header";
import { Separator } from "@/components/ui/separator";
import { AppearanceSection } from "../components/appearance-section";
import { RcloneSection } from "../components/rclone-section";
import { TransferSection } from "../components/transfer-section";
import { AboutSection } from "../components/about-section";

export default function SettingsPage() {
  return (
    <div>
      <PageHeader
        title="Settings"
        description="Configure StreamCloned preferences"
      />
      <div className="space-y-6 p-6">
        <AppearanceSection />
        <Separator />
        <RcloneSection />
        <Separator />
        <TransferSection />
        <Separator />
        <AboutSection />
      </div>
    </div>
  );
}
