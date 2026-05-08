const { resolve } = await import("node:path");
const { existsSync, readdirSync } = await import("node:fs");

function frameworkPath() {
  const candidates = [];
  if (process.env.LOGOS_QT_MCP) {
    candidates.push(resolve(process.env.LOGOS_QT_MCP, "test-framework/framework.mjs"));
  }
  candidates.push(resolve(process.cwd(), "result-mcp/test-framework/framework.mjs"));
  try {
    candidates.push(...readdirSync("/nix/store")
      .filter((name) => name.endsWith("-logos-qt-mcp"))
      .sort()
      .map((name) => `/nix/store/${name}/test-framework/framework.mjs`));
  } catch {
  }
  const framework = candidates.find((candidate) => existsSync(candidate));
  if (!framework) throw new Error("LOGOS_QT_MCP is not set and logos-qt-mcp was not found");
  return framework;
}

const { test, run } = await import(frameworkPath());

test("primary UI flows are reachable", async (app) => {
  await app.expectTexts(["DistributionX", "Create distribution", "Claim distribution", "View distributions →"]);

  await app.click("Create distribution");
  await app.expectTexts(["Distributor signing account", "Use local signer", "RPC suggestions"]);
  await app.click("Continue");
  await app.expectTexts(["Upload the eligibility list", "Distribution name", "Eligibility CSV", "Validate CSV", "Initialize"]);
  await app.click("←");
  await app.click("←");
  await app.expectTexts(["DistributionX", "Create distribution"]);

  await app.click("Claim distribution");
  await app.expectTexts(["Claim tokens", "Claim key", "Destination", "STATUS", "Claim now"]);
  await app.click("←");
  await app.expectTexts(["DistributionX", "Create distribution"]);

  await app.click("View distributions →");
  await app.expectTexts(["DISTRIBUTION", "CLAIMED TOKENS", "POOL REMAINING", "REGISTRY ENTRY"]);
});

run();
