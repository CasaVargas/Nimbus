import { describe, expect, it } from "vitest";
import { parseRcloneConf } from "./ini-parser";

describe("parseRcloneConf", () => {
  it("parses a single remote", () => {
    const input = `[myremote]
type = drive
client_id = xxx
client_secret = yyy
`;
    const result = parseRcloneConf(input);
    expect(result).toEqual([
      {
        name: "myremote",
        type: "drive",
        parameters: { client_id: "xxx", client_secret: "yyy" },
      },
    ]);
  });

  it("parses multiple remotes", () => {
    const input = `[gdrive]
type = drive
scope = drive

[s3bucket]
type = s3
provider = AWS
region = us-east-1
`;
    const result = parseRcloneConf(input);
    expect(result).toHaveLength(2);
    expect(result[0].name).toBe("gdrive");
    expect(result[0].type).toBe("drive");
    expect(result[0].parameters).toEqual({ scope: "drive" });
    expect(result[1].name).toBe("s3bucket");
    expect(result[1].type).toBe("s3");
    expect(result[1].parameters).toEqual({
      provider: "AWS",
      region: "us-east-1",
    });
  });

  it("ignores comments and blank lines", () => {
    const input = `# This is a comment

[myremote]
type = drive
# another comment
token = abc
`;
    const result = parseRcloneConf(input);
    expect(result).toHaveLength(1);
    expect(result[0].parameters).toEqual({ token: "abc" });
  });

  it("returns empty array for empty input", () => {
    expect(parseRcloneConf("")).toEqual([]);
  });

  it("handles values with equals signs", () => {
    const input = `[crypt]
type = crypt
password = obscured=abc123==
`;
    const result = parseRcloneConf(input);
    expect(result[0].parameters.password).toBe("obscured=abc123==");
  });
});
