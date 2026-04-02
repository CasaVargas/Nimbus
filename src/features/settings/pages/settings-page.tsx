import { PageHeader } from "@/components/page-header";
import { Separator } from "@/components/ui/separator";
import { AboutSection } from "../components/about-section";
import { AppearanceSection } from "../components/appearance-section";
import { RcloneSection } from "../components/rclone-section";
import { StorageUsage } from "../components/storage-usage";
import { TransferSection } from "../components/transfer-section";

export default function SettingsPage() {
  return (
    <div>
      <PageHeader title="Settings" description="Configure Nimbus preferences" />
      <div className="space-y-6 p-6">
        <AppearanceSection />
        <Separator />
        <RcloneSection />
        <Separator />
        <TransferSection />
        <Separator />
        <StorageUsage />
        <Separator />
        <AboutSection />
      </div>
    </div>
  );
}
