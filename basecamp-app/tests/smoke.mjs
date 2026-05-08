const { dirname, isAbsolute, resolve } = await import("node:path");
const { writeFileSync, mkdirSync, existsSync, readdirSync } = await import("node:fs");
const { fileURLToPath } = await import("node:url");

const testDir = dirname(fileURLToPath(import.meta.url));
const rootDir = resolve(testDir, "../..");

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

function saveScreenshot(name, shot) {
  const outDir = process.env.DISTRIBUTIONX_QML_SCREENSHOT_DIR || resolve(process.cwd(), "docs/run-logs/qml");
  try {
    mkdirSync(outDir, { recursive: true });
    if (shot.image) {
      writeFileSync(resolve(outDir, `${name}.png`), Buffer.from(shot.image, "base64"));
    }
  } catch {
  }
}

function rootPath(value) {
  return isAbsolute(value) ? value : resolve(rootDir, value);
}

test("landing exposes the three normal-mode actions and reaches the claim screen", async (app) => {
  await app.expectTexts(["DistributionX", "DISTRIBUTOR", "RECIPIENT", "Create distribution", "Claim distribution", "View distributions →"]);
  await app.click("Claim distribution");
  await app.expectTexts(["Claim tokens", "Distribution", "Browse", "Use link", "Claim key", "Generate key", "Destination", "Balance", "STATUS", "Claim now"]);
  const prefilled = [];
  if (process.env.DISTRIBUTIONX_CLAIM_LINK) prefilled.push(process.env.DISTRIBUTIONX_CLAIM_LINK);
  if (process.env.DISTRIBUTIONX_CLAIM_BUNDLE) prefilled.push(rootPath(process.env.DISTRIBUTIONX_CLAIM_BUNDLE));
  if (prefilled.length > 0) await app.expectTexts(prefilled);
  saveScreenshot("smoke-claim-screen", await app.screenshot());
});

run();
