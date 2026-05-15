import { ExternalLinkIcon } from "lucide-react";
import { Button } from "@/components/ui/button";

const APP_VERSION = "0.1.0";
const GITHUB_URL = "https://github.com/nimbus/nimbus";

export function AboutSection() {
  return (
    <div className="space-y-4">
      <div>
        <h3 className="text-sm font-medium">About</h3>
        <p className="text-xs text-muted-foreground">Nimbus v{APP_VERSION}</p>
      </div>
      <div className="flex items-center gap-4">
        <Button
          variant="outline"
          size="sm"
          onClick={() => window.open(GITHUB_URL, "_blank")}
        >
          <ExternalLinkIcon data-icon="inline-start" />
          GitHub
        </Button>
      </div>
    </div>
  );
}
