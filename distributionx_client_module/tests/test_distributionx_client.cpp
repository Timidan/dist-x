#include <logos_test.h>

#include "../src/distributionx_client_impl.h"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string>
#include <unistd.h>

namespace {

std::string installFakeCli() {
    const auto path = std::filesystem::temp_directory_path() /
        ("distributionx-fake-cli-" + std::to_string(getpid()) + ".sh");
    std::ofstream script(path);
    script << "#!/bin/sh\n"
           << "set -eu\n"
           << "case \"$1\" in\n"
           << "  sample-fixture)\n"
           << "    echo '{\"status\":\"SAMPLE_FIXTURE_OK\"}'\n"
           << "    ;;\n"
           << "  create-wallet)\n"
           << "    test \"$2\" = '--out-dir'\n"
           << "    echo \"{\\\"status\\\":\\\"CREATE_WALLET_OK\\\",\\\"account\\\":\\\"Public/fake\\\",\\\"wallet_seed_path\\\":\\\"$3/wallet.seed\\\"}\"\n"
           << "    ;;\n"
           << "  token-id)\n"
           << "    test \"$2\" = '--name'\n"
           << "    echo \"{\\\"status\\\":\\\"TOKEN_ID_OK\\\",\\\"token_id\\\":\\\"Public/faketoken\\\",\\\"name\\\":\\\"$3\\\"}\"\n"
           << "    ;;\n"
           << "  mint-token)\n"
           << "    test \"$2\" = '--name'\n"
           << "    test \"$4\" = '--total-supply'\n"
           << "    echo \"{\\\"status\\\":\\\"TOKEN_MINTED\\\",\\\"token_id\\\":\\\"Public/faketoken\\\",\\\"supply_account_id\\\":\\\"Public/fakesupply\\\",\\\"total_supply\\\":\\\"$5\\\"}\"\n"
           << "    ;;\n"
           << "  inspect-csv)\n"
           << "    test \"$2\" = '--csv'\n"
           << "    echo '{\"status\":\"CSV_OK\",\"row_count\":1,\"total_amount\":100}'\n"
           << "    ;;\n"
           << "  *)\n"
           << "    echo '{\"status\":\"DISTRIBUTIONX_CLIENT_ERROR\",\"error\":\"unexpected fake cli command\"}'\n"
           << "    exit 2\n"
           << "    ;;\n"
           << "esac\n";
    script.close();
    std::filesystem::permissions(
        path,
        std::filesystem::perms::owner_exec | std::filesystem::perms::owner_read |
            std::filesystem::perms::owner_write,
        std::filesystem::perm_options::add);
    setenv("DISTRIBUTIONX_CLI", path.c_str(), 1);
    return path.string();
}

std::filesystem::path installFakeDemoProject() {
    const auto root = std::filesystem::temp_directory_path() /
        ("distributionx-demo-project-" + std::to_string(getpid()));
    std::filesystem::remove_all(root);
    std::filesystem::create_directories(root / "crates" / "distributionx-cli");
    std::filesystem::create_directories(root / "target" / "debug");
    std::filesystem::create_directories(root / "scripts");
    {
        std::ofstream manifest(root / "Cargo.toml");
        manifest << "[workspace]\n";
    }
    {
        std::ofstream manifest(root / "crates" / "distributionx-cli" / "Cargo.toml");
        manifest << "[package]\nname = \"distributionx-cli\"\nversion = \"0.1.0\"\n";
    }
    const auto cli = root / "target" / "debug" / "distributionx-cli";
    {
        std::ofstream binary(cli);
        binary << "#!/bin/sh\nexit 0\n";
    }
    std::filesystem::permissions(
        cli,
        std::filesystem::perms::owner_exec | std::filesystem::perms::owner_read |
            std::filesystem::perms::owner_write,
        std::filesystem::perm_options::add);

    const auto script = root / "scripts" / "demo.sh";
    {
        std::ofstream demo(script);
        demo << "#!/bin/sh\n"
             << "mode=\"${1:-localnet}\"\n"
             << "echo \"{\\\"status\\\":\\\"DEMO_OK\\\",\\\"mode\\\":\\\"$mode\\\",\\\"pwd\\\":\\\"$(pwd)\\\"}\"\n";
    }
    std::filesystem::permissions(
        script,
        std::filesystem::perms::owner_exec | std::filesystem::perms::owner_read |
            std::filesystem::perms::owner_write,
        std::filesystem::perm_options::add);

    setenv("DISTRIBUTIONX_CLI", cli.string().c_str(), 1);
    unsetenv("DISTRIBUTIONX_DEMO_SCRIPT");
    return root;
}

} // namespace

LOGOS_TEST(module_reports_cli_results_or_clear_cli_errors) {
    DistributionxClientImpl impl;
    auto result = impl.sampleFixture("target/distributionx-module-test");
    LOGOS_ASSERT_TRUE(result.find("SAMPLE_FIXTURE_OK") != std::string::npos ||
                      result.find("DISTRIBUTIONX_CLIENT_ERROR") != std::string::npos);
}

LOGOS_TEST(module_exposes_wallet_creation) {
    installFakeCli();
    DistributionxClientImpl impl;
    auto result = impl.createWallet("target/distributionx-module-test");
    LOGOS_ASSERT_CONTAINS(result, "CREATE_WALLET_OK");
    LOGOS_ASSERT_CONTAINS(result, "Public/fake");
    LOGOS_ASSERT_CONTAINS(result, "target/distributionx-module-test/wallet.seed");
}

LOGOS_TEST(module_exposes_token_id_generation) {
    installFakeCli();
    DistributionxClientImpl impl;
    auto result = impl.tokenId("demo-token");
    LOGOS_ASSERT_CONTAINS(result, "TOKEN_ID_OK");
    LOGOS_ASSERT_CONTAINS(result, "Public/faketoken");
    LOGOS_ASSERT_CONTAINS(result, "demo-token");
}

LOGOS_TEST(module_exposes_token_minting) {
    installFakeCli();
    DistributionxClientImpl impl;
    auto result = impl.mintToken("demo-token", "3000");
    LOGOS_ASSERT_CONTAINS(result, "TOKEN_MINTED");
    LOGOS_ASSERT_CONTAINS(result, "Public/faketoken");
    LOGOS_ASSERT_CONTAINS(result, "Public/fakesupply");
}

LOGOS_TEST(module_reports_missing_background_jobs) {
    DistributionxClientImpl impl;
    auto result = impl.jobStatus("missing");
    LOGOS_ASSERT_CONTAINS(result, "JOB_NOT_FOUND");
}

LOGOS_TEST(module_exposes_background_csv_inspection) {
    installFakeCli();
    DistributionxClientImpl impl;
    auto started = impl.startInspectCsv("eligible.csv");
    LOGOS_ASSERT_CONTAINS(started, "JOB_STARTED");
    auto status = impl.jobStatus("1");
    for (int attempt = 0; attempt < 20 && status.find("JOB_RUNNING") != std::string::npos; ++attempt) {
        usleep(10000);
        status = impl.jobStatus("1");
    }
    LOGOS_ASSERT_CONTAINS(status, "JOB_OK");
    LOGOS_ASSERT_CONTAINS(status, "CSV_OK");
}

LOGOS_TEST(module_run_demo_uses_tracked_demo_script) {
    const auto root = installFakeDemoProject();
    DistributionxClientImpl impl;
    auto result = impl.runDemo();
    LOGOS_ASSERT_CONTAINS(result, "DEMO_OK");
    LOGOS_ASSERT_CONTAINS(result, "localnet");
    LOGOS_ASSERT_CONTAINS(result, root.string());
    std::filesystem::remove_all(root);
}
