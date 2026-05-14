import { RcloneError, type RcloneErrorResponse } from "./types";

export class RcloneClient {
  constructor(private baseUrl: string) {}

  async call<T>(endpoint: string, params: Record<string, unknown>): Promise<T> {
    const response = await fetch(`${this.baseUrl}/${endpoint}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(params),
    });

    if (!response.ok) {
      const errorBody = (await response.json()) as RcloneErrorResponse;
      throw new RcloneError(errorBody);
    }

    return response.json() as Promise<T>;
  }

  async healthCheck(): Promise<boolean> {
    try {
      await this.call("rc/noop", {});
      return true;
    } catch {
      return false;
    }
  }

  getBaseUrl(): string {
    return this.baseUrl;
  }

  setBaseUrl(url: string): void {
    this.baseUrl = url;
  }
}

// Singleton instance — port updated at runtime after daemon starts
export const rclone = new RcloneClient("http://localhost:5572");
