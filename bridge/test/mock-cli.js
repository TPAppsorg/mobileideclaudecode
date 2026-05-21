#!/usr/bin/env node

/**
 * Mock CLI for Claude Code Mobile Bridge testing.
 * Simulates stream-json outputs for prompts.
 */

const args = process.argv.slice(2);
const prompt = args[args.length - 1] || "";

async function run() {
  // Emit system init event
  console.log(JSON.stringify({
    type: "system",
    subtype: "init",
    session_id: "mock-session-id"
  }));

  if (prompt.includes("error")) {
    console.log(JSON.stringify({ type: "error", message: "Mock error requested by prompt" }));
    process.exit(1);
  }

  if (prompt.includes("exit-code")) {
    const match = prompt.match(/exit-code-(\d+)/);
    const code = match ? parseInt(match[1], 10) : 42;
    process.exit(code);
  }

  if (prompt.includes("tool")) {
    console.log(JSON.stringify({
      type: "tool_use",
      name: "run_command",
      parameters: { command: "echo 'Hello from mock CLI tool'" }
    }));
    await new Promise(r => setTimeout(r, 100));
    console.log(JSON.stringify({
      type: "message",
      role: "assistant",
      content: "\n• run_command echo 'Hello from mock CLI tool'\n"
    }));
  }

  if (prompt.includes("sleep")) {
    await new Promise(r => setTimeout(r, 10000));
  }

  // Stream message chunks
  let chunks = ["Hello from mock Claude CLI!"];
  if (prompt.includes("long-stream")) {
    chunks = Array.from({ length: 100 }, (_, i) => `chunk-${i} `);
  } else if (prompt.includes("stream")) {
    chunks = ["This ", "is ", "a ", "streamed ", "mock ", "response."];
  }

  for (const chunk of chunks) {
    console.log(JSON.stringify({
      type: "content_block_delta",
      delta: { text: chunk }
    }));
    if (prompt.includes("stream") || prompt.includes("long-stream")) {
      await new Promise(r => setTimeout(r, 30));
    }
  }

  // Emit result stats
  console.log(JSON.stringify({
    type: "result",
    session_id: "mock-session-id",
    stats: {
      input_tokens: 15,
      output_tokens: chunks.length * 2,
      total_tokens: 15 + chunks.length * 2
    }
  }));

  process.exit(0);
}

run().catch(err => {
  console.error(err);
  process.exit(1);
});
