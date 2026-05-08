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

async function hasText(app, text) {
  const res = await app.findByProperty("text", text);
  return !res.error && res.matches && res.matches.length > 0;
}

async function expectAnyText(app, texts, description) {
  await app.waitFor(async () => {
    for (const text of texts) {
      if (await hasText(app, text)) return;
    }
    throw new Error(`Expected one of ${JSON.stringify(texts)}`);
  }, { timeout: 30000, interval: 500, description });
}

test("distributor setup exposes the normal signer token and CSV controls", async (app) => {
  await app.expectTexts(["DistributionX", "Create distribution"]);
  await app.click("Create distribution");
  await app.expectTexts(["Use local signer", "RPC suggestions", "Localnet 127.0.0.1:3040"]);
  if (process.env.DISTRIBUTIONX_TEST_HELPERS === "1") {
    await app.click("Use local signer");
    await expectAnyText(app, ["Local signer selected"], "signer helper result");
  }
  await app.click("Continue");
  await app.expectTexts(["Distribution name", "Eligibility CSV", "Test token", "Generate sample CSV", "Validate CSV", "Initialize"]);
  if (process.env.DISTRIBUTIONX_TEST_HELPERS === "1") {
    await app.click("Test token");
    await expectAnyText(app, ["Token id ready"], "token helper result");
  }
});

run();
