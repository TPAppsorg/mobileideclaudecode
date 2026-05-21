import { describe, it, expect } from "vitest";
import { runClaude } from "../src/claude.js";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const mockCliPath = path.join(__dirname, "mock-cli.js");

describe("claude subprocess execution", () => {
  it("should successfully run mock CLI and return parsed output", async () => {
    const { result } = runClaude("hello", mockCliPath);
    const res = await result;
    
    expect(res.exitCode).toBe(0);
    expect(res.output).toContain("Hello from mock Claude CLI!");
    expect(res.stats).toBeDefined();
    expect(res.stats?.inputTokens).toBe(15);
  });

  it("should support streaming chunk callbacks", async () => {
    const chunks: string[] = [];
    const { result } = runClaude("stream", mockCliPath, {
      onChunk: (chunk) => chunks.push(chunk)
    });
    
    const res = await result;
    
    expect(res.exitCode).toBe(0);
    expect(res.output).toContain("This is a streamed mock response.");
    expect(chunks.length).toBeGreaterThan(1);
    expect(chunks.join("")).toContain("This is a streamed mock response.");
  });

  it("should handle tool events in stdout json stream", async () => {
    const { result } = runClaude("tool", mockCliPath);
    const res = await result;
    
    expect(res.exitCode).toBe(0);
    expect(res.output).toContain("run_command echo 'Hello from mock CLI tool'");
  });

  it("should capture and bubble up exit codes", async () => {
    const { result } = runClaude("exit-code-77", mockCliPath);
    const res = await result;
    
    expect(res.exitCode).toBe(77);
  });

  it("should parse and capture errors in stdout stream and exit with code 1", async () => {
    const { result } = runClaude("error", mockCliPath);
    const res = await result;
    
    expect(res.exitCode).toBe(1);
    expect(res.errors).toBeDefined();
    expect(res.errors?.[0]?.message).toBe("Mock error requested by prompt");
  });
});
