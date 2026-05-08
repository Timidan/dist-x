#include "distributionx_client_impl.h"

#include <array>
#include <atomic>
#include <cstdio>
#include <cstdlib>
#ifdef __linux__
#include <dlfcn.h>
#endif
#include <filesystem>
#include <iomanip>
#include <map>
#include <memory>
#include <mutex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>

namespace {

std::string shellQuote(const std::string& value) {
    std::string out = "'";
    for (char ch : value) {
        if (ch == '\'') {
            out += "'\\''";
        } else {
            out += ch;
        }
    }
    out += "'";
    return out;
}

std::string jsonEscape(const std::string& value) {
    std::ostringstream escaped;
    for (unsigned char ch : value) {
        switch (ch) {
        case '"':
            escaped << "\\\"";
            break;
        case '\\':
            escaped << "\\\\";
            break;
        case '\b':
            escaped << "\\b";
            break;
        case '\f':
            escaped << "\\f";
            break;
        case '\n':
            escaped << "\\n";
            break;
        case '\r':
            escaped << "\\r";
            break;
        case '\t':
            escaped << "\\t";
            break;
        default:
            if (ch < 0x20) {
                escaped << "\\u" << std::hex << std::setw(4) << std::setfill('0')
                        << static_cast<int>(ch) << std::dec;
            } else {
                escaped << static_cast<char>(ch);
            }
        }
    }
    return escaped.str();
}

std::string jsonField(const std::string& value) {
    return "\"" + jsonEscape(value) + "\"";
}

std::string besideLibraryCliPath() {
#ifdef __linux__
    Dl_info info{};
    if (dladdr(reinterpret_cast<void*>(&besideLibraryCliPath), &info) && info.dli_fname) {
        const auto modulePath = std::filesystem::path(info.dli_fname);
        const auto candidate = modulePath.parent_path() / "distributionx-cli";
        if (std::filesystem::exists(candidate)) {
            return candidate.string();
        }
    }
#endif
    return {};
}

std::string projectRootCliPath() {
    auto dir = std::filesystem::current_path();
    while (!dir.empty()) {
        const auto cargoToml = dir / "Cargo.toml";
        const auto cliManifest = dir / "crates" / "distributionx-cli" / "Cargo.toml";
        if (std::filesystem::exists(cargoToml) && std::filesystem::exists(cliManifest)) {
            for (const auto& profile : {"release", "debug"}) {
                const auto candidate = dir / "target" / profile / "distributionx-cli";
                if (std::filesystem::exists(candidate)) {
                    return candidate.string();
                }
            }
        }
        if (!dir.has_parent_path() || dir == dir.parent_path()) {
            break;
        }
        dir = dir.parent_path();
    }
    return {};
}

std::string firstExistingPath() {
    if (const char* explicitPath = std::getenv("DISTRIBUTIONX_CLI")) {
        return explicitPath;
    }
    if (const auto besideLibrary = besideLibraryCliPath(); !besideLibrary.empty()) {
        return besideLibrary;
    }
    if (const auto projectRoot = projectRootCliPath(); !projectRoot.empty()) {
        return projectRoot;
    }
    for (const auto& candidate : {
             "target/release/distributionx-cli",
             "../target/release/distributionx-cli",
             "../../target/release/distributionx-cli",
             "target/debug/distributionx-cli",
             "../target/debug/distributionx-cli",
             "../../target/debug/distributionx-cli",
         }) {
        if (std::filesystem::exists(candidate)) {
            return candidate;
        }
    }
    return "distributionx-cli";
}

std::string projectRootForCli(const std::string& cliPath) {
    std::error_code ec;
    auto path = std::filesystem::absolute(std::filesystem::path(cliPath), ec);
    if (ec) {
        path = std::filesystem::path(cliPath);
    }
    if (std::filesystem::is_regular_file(path, ec)) {
        path = path.parent_path();
    }
    while (!path.empty()) {
        if (std::filesystem::exists(path / "Cargo.toml") &&
            std::filesystem::exists(path / "crates" / "distributionx-cli" / "Cargo.toml")) {
            return path.string();
        }
        if (!path.has_parent_path() || path == path.parent_path()) {
            break;
        }
        path = path.parent_path();
    }
    return {};
}

std::string runShell(const std::string& command) {
    std::array<char, 512> buffer{};
    std::string output;
    FILE* pipe = popen((command + " 2>&1").c_str(), "r");
    if (!pipe) {
        return "{\"status\":\"DISTRIBUTIONX_CLIENT_ERROR\",\"error\":\"popen failed\"}";
    }
    while (fgets(buffer.data(), static_cast<int>(buffer.size()), pipe) != nullptr) {
        output += buffer.data();
    }
    const int status = pclose(pipe);
    if (status != 0) {
        std::ostringstream json;
        json << "{\"status\":\"DISTRIBUTIONX_CLIENT_ERROR\",\"exit_status\":" << status
             << ",\"output\":" << jsonField(output) << "}";
        return json.str();
    }
    return output;
}

std::string runCliCommand(const std::string& args) {
    const std::string cli = firstExistingPath();
    const std::string root = projectRootForCli(cli);
    const std::string prefix = root.empty() ? "" : "cd " + shellQuote(root) + " && ";
    return runShell(prefix + "RISC0_DEV_MODE=0 " + shellQuote(cli) + " " + args);
}

} // namespace

struct DistributionxClientImpl::JobStore {
    struct Job {
        std::string operation;
        std::string status;
        std::string output;
    };

    std::mutex mutex;
    std::map<std::string, Job> jobs;
    std::atomic<unsigned long long> nextId{0};
};

DistributionxClientImpl::DistributionxClientImpl()
    : m_jobs(std::make_shared<JobStore>()) {}

DistributionxClientImpl::~DistributionxClientImpl() = default;

std::string DistributionxClientImpl::sampleFixture(const std::string& outDir) {
    return runCli("sample-fixture --out-dir " + shellQuote(outDir));
}

std::string DistributionxClientImpl::startSampleFixture(const std::string& outDir) {
    return startJob("sampleFixture", "sample-fixture --out-dir " + shellQuote(outDir));
}

std::string DistributionxClientImpl::createWallet(const std::string& state_dir) {
    return runCli("create-wallet --out-dir " + shellQuote(state_dir));
}

std::string DistributionxClientImpl::startCreateWallet(const std::string& state_dir) {
    return startJob("createWallet", "create-wallet --out-dir " + shellQuote(state_dir));
}

std::string DistributionxClientImpl::initDistribution(const std::string& csvPath, const std::string& distributor, const std::string& token, const std::string& rpc, const std::string& expiryUnix, const std::string& recovery) {
    return runCli("init --csv " + shellQuote(csvPath) +
                  " --distributor " + shellQuote(distributor) +
                  " --token " + shellQuote(token) +
                  " --rpc " + shellQuote(rpc) +
                  " --expiry " + shellQuote(expiryUnix) +
                  " --recovery " + shellQuote(recovery));
}

std::string DistributionxClientImpl::startInitDistribution(const std::string& csvPath, const std::string& distributor, const std::string& token, const std::string& rpc, const std::string& expiryUnix, const std::string& recovery) {
    return startJob("initDistribution",
                    "init --csv " + shellQuote(csvPath) +
                    " --distributor " + shellQuote(distributor) +
                    " --token " + shellQuote(token) +
                    " --rpc " + shellQuote(rpc) +
                    " --expiry " + shellQuote(expiryUnix) +
                    " --recovery " + shellQuote(recovery));
}

std::string DistributionxClientImpl::fund(const std::string& airdrop, const std::string& amount) {
    return runCli("fund --airdrop " + shellQuote(airdrop) + " --amount " + shellQuote(amount));
}

std::string DistributionxClientImpl::startFund(const std::string& airdrop, const std::string& amount) {
    return startJob("fund", "fund --airdrop " + shellQuote(airdrop) + " --amount " + shellQuote(amount));
}

std::string DistributionxClientImpl::queryTokenBalance(const std::string& rpc_url, const std::string& account, const std::string& token_id) {
    return runCli("query-token-balance --rpc " + shellQuote(rpc_url) +
                  " --account " + shellQuote(account) +
                  " --token " + shellQuote(token_id));
}

std::string DistributionxClientImpl::tokenId(const std::string& name) {
    return runCli("token-id --name " + shellQuote(name));
}

std::string DistributionxClientImpl::startTokenId(const std::string& name) {
    return startJob("tokenId", "token-id --name " + shellQuote(name));
}

std::string DistributionxClientImpl::loadDestinationPacket(const std::string& destinationPacketJsonPath) {
    return runCli("inspect-destination --destination-packet " + shellQuote(destinationPacketJsonPath));
}

std::string DistributionxClientImpl::checkEligibility(const std::string& airdrop, const std::string& bundlePath, const std::string& walletPath, const std::string& destinationPacketJsonPath) {
    return runCli("check-eligibility --airdrop " + shellQuote(airdrop) +
                  " --bundle " + shellQuote(bundlePath) +
                  " --wallet " + shellQuote(walletPath) +
                  " --destination-packet " + shellQuote(destinationPacketJsonPath));
}

std::string DistributionxClientImpl::startCheckEligibility(const std::string& airdrop, const std::string& bundlePath, const std::string& walletPath, const std::string& destinationPacketJsonPath) {
    return startJob("checkEligibility",
                    "check-eligibility --airdrop " + shellQuote(airdrop) +
                    " --bundle " + shellQuote(bundlePath) +
                    " --wallet " + shellQuote(walletPath) +
                    " --destination-packet " + shellQuote(destinationPacketJsonPath));
}

std::string DistributionxClientImpl::prove(const std::string& airdrop, const std::string& bundlePath, const std::string& walletPath, const std::string& destinationPacketJsonPath) {
    return runCli("prove --airdrop " + shellQuote(airdrop) +
                  " --bundle " + shellQuote(bundlePath) +
                  " --wallet " + shellQuote(walletPath) +
                  " --destination-packet " + shellQuote(destinationPacketJsonPath));
}

std::string DistributionxClientImpl::startProve(const std::string& airdrop, const std::string& bundlePath, const std::string& walletPath, const std::string& destinationPacketJsonPath) {
    return startJob("prove",
                    "prove --airdrop " + shellQuote(airdrop) +
                    " --bundle " + shellQuote(bundlePath) +
                    " --wallet " + shellQuote(walletPath) +
                    " --destination-packet " + shellQuote(destinationPacketJsonPath));
}

std::string DistributionxClientImpl::startInspectCsv(const std::string& csvPath) {
    return startJob("inspectCsv", "inspect-csv --csv " + shellQuote(csvPath));
}

std::string DistributionxClientImpl::jobStatus(const std::string& jobId) {
    const auto jobs = m_jobs;
    std::lock_guard<std::mutex> lock(jobs->mutex);
    const auto it = jobs->jobs.find(jobId);
    if (it == jobs->jobs.end()) {
        return "{\"status\":\"JOB_NOT_FOUND\",\"job_id\":" + jsonField(jobId) + "}";
    }
    const auto& job = it->second;
    return "{\"status\":\"" + job.status + "\",\"job_id\":" + jsonField(jobId) +
           ",\"operation\":" + jsonField(job.operation) +
           ",\"output\":" + jsonField(job.output) + "}";
}

std::string DistributionxClientImpl::verify(const std::string& airdrop, const std::string& proofPath) {
    return runCli("verify --airdrop " + shellQuote(airdrop) + " --proof " + shellQuote(proofPath));
}

std::string DistributionxClientImpl::startVerify(const std::string& airdrop, const std::string& proofPath) {
    return startJob("verify", "verify --airdrop " + shellQuote(airdrop) + " --proof " + shellQuote(proofPath));
}

std::string DistributionxClientImpl::claim(const std::string& airdrop, const std::string& proofPath, const std::string& relayer, const std::string& serializedLezTxPath) {
    return runCli("claim --airdrop " + shellQuote(airdrop) +
                  " --proof " + shellQuote(proofPath) +
                  " --relayer " + shellQuote(relayer) +
                  " --serialized-lez-tx " + shellQuote(serializedLezTxPath));
}

std::string DistributionxClientImpl::startClaim(const std::string& airdrop, const std::string& proofPath, const std::string& relayer, const std::string& serializedLezTxPath) {
    return startJob("claim",
                    "claim --airdrop " + shellQuote(airdrop) +
                    " --proof " + shellQuote(proofPath) +
                    " --relayer " + shellQuote(relayer) +
                    " --serialized-lez-tx " + shellQuote(serializedLezTxPath));
}

std::string DistributionxClientImpl::close(const std::string& airdrop) {
    return runCli("close --airdrop " + shellQuote(airdrop));
}

std::string DistributionxClientImpl::listAirdrops() {
    return runCli("list-airdrops");
}

std::string DistributionxClientImpl::inspectCsv(const std::string& csvPath) {
    return runCli("inspect-csv --csv " + shellQuote(csvPath));
}

std::string DistributionxClientImpl::walletPublicKey(const std::string& walletSeedPath) {
    return runCli("wallet-pubkey --wallet " + shellQuote(walletSeedPath));
}

std::string DistributionxClientImpl::setWallet(const std::string& fromPath, const std::string& toPath) {
    return runCli("set-wallet --from " + shellQuote(fromPath) + " --to " + shellQuote(toPath));
}

std::string DistributionxClientImpl::runDemo() {
    const std::string root = projectRootForCli(firstExistingPath());
    const std::string prefix = root.empty() ? "" : "cd " + shellQuote(root) + " && ";
    if (const char* script = std::getenv("DISTRIBUTIONX_DEMO_SCRIPT")) {
        return runShell(prefix + "RISC0_DEV_MODE=0 " + shellQuote(script));
    }
    return runShell(prefix + "RISC0_DEV_MODE=0 " + shellQuote("scripts/demo.sh"));
}

std::string DistributionxClientImpl::startJob(const std::string& operation, const std::string& args) {
    const auto jobs = m_jobs;
    const auto jobId = std::to_string(jobs->nextId.fetch_add(1) + 1);
    {
        std::lock_guard<std::mutex> lock(jobs->mutex);
        jobs->jobs[jobId] = JobStore::Job{operation, "JOB_RUNNING", ""};
    }

    std::thread([jobs, jobId, operation, args]() {
        const std::string output = runCliCommand(args);
        const bool ok = output.find("DISTRIBUTIONX_CLIENT_ERROR") == std::string::npos;
        std::lock_guard<std::mutex> lock(jobs->mutex);
        auto it = jobs->jobs.find(jobId);
        if (it != jobs->jobs.end()) {
            it->second.operation = operation;
            it->second.status = ok ? "JOB_OK" : "JOB_ERROR";
            it->second.output = output;
        }
    }).detach();

    return "{\"status\":\"JOB_STARTED\",\"job_id\":" + jsonField(jobId) +
           ",\"operation\":" + jsonField(operation) + "}";
}

std::string DistributionxClientImpl::runCli(const std::string& args) {
    return runCliCommand(args);
}
