const { resolve } = await import("node:path");
const { writeFileSync, mkdirSync, existsSync, readdirSync } = await import("node:fs");

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

test("claim screen reports backend errors without marking success", async (app) => {
  await app.expectTexts(["Claim distribution"]);
  await app.click("Claim distribution");
  await app.click("Claim now");
  await app.waitFor(
    async () => app.expectTexts(["Needs attention"]),
    { timeout: 10000, interval: 500, description: "backend error visible" }
  );
  saveScreenshot("claim-error", await app.screenshot());
});

run();
