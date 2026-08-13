const { existsSync, readdirSync } = await import("node:fs");
const { resolve } = await import("node:path");

function frameworkPath() {
  const candidates = [];
  if (process.env.LOGOS_QT_MCP) {
    candidates.push(resolve(process.env.LOGOS_QT_MCP, "test-framework/framework.mjs"));
  }
  try {
    candidates.push(...readdirSync("/nix/store")
      .filter((name) => name.endsWith("-logos-qt-mcp"))
      .sort()
      .map((name) => `/nix/store/${name}/test-framework/framework.mjs`));
  } catch {
  }
  const framework = candidates.find((candidate) => existsSync(candidate));
  if (!framework) throw new Error("logos-qt-mcp test framework was not found");
  return framework;
}

const { test, run } = await import(frameworkPath());

test("installed LGX loads the UI and answers through distributionx_client", async (app) => {
  await app.waitFor(async () => {
    const ready = await app.findByProperty("clientModuleReady", true);
    if (ready.error || !ready.matches || ready.matches.length === 0) {
      throw new Error("distributionx_client did not answer listAirdrops");
    }
  }, { timeout: 20000, description: "installed distributionx_client API readiness" });
  await app.expectTexts(["DistributionX", "Create distribution", "Claim distribution"]);
});

run();
