export interface ParsedRemote {
  name: string;
  type: string;
  parameters: Record<string, string>;
}

export function parseRcloneConf(content: string): ParsedRemote[] {
  const remotes: ParsedRemote[] = [];
  let current: { name: string; params: Record<string, string> } | null = null;

  for (const rawLine of content.split("\n")) {
    const line = rawLine.trim();

    if (line === "" || line.startsWith("#") || line.startsWith(";")) {
      continue;
    }

    const sectionMatch = line.match(/^\[(.+)\]$/);
    if (sectionMatch) {
      if (current) {
        remotes.push({
          name: current.name,
          type: current.params.type ?? "unknown",
          parameters: Object.fromEntries(
            Object.entries(current.params).filter(([k]) => k !== "type"),
          ),
        });
      }
      current = { name: sectionMatch[1], params: {} };
      continue;
    }

    if (current) {
      const eqIndex = line.indexOf("=");
      if (eqIndex !== -1) {
        const key = line.slice(0, eqIndex).trim();
        const value = line.slice(eqIndex + 1).trim();
        current.params[key] = value;
      }
    }
  }

  if (current) {
    remotes.push({
      name: current.name,
      type: current.params.type ?? "unknown",
      parameters: Object.fromEntries(
        Object.entries(current.params).filter(([k]) => k !== "type"),
      ),
    });
  }

  return remotes;
}
