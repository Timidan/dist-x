#pragma once

#include <memory>
#include <string>

class DistributionxClientImpl {
public:
    DistributionxClientImpl();
    ~DistributionxClientImpl();

    std::string sampleFixture(const std::string& outDir);
    std::string startSampleFixture(const std::string& outDir);
    std::string createWallet(const std::string& state_dir);
    std::string startCreateWallet(const std::string& state_dir);
    std::string initDistribution(const std::string& csvPath, const std::string& distributor, const std::string& token, const std::string& rpc, const std::string& expiryUnix, const std::string& recovery);
    std::string startInitDistribution(const std::string& csvPath, const std::string& distributor, const std::string& token, const std::string& rpc, const std::string& expiryUnix, const std::string& recovery);
    std::string fund(const std::string& airdrop, const std::string& amount);
    std::string startFund(const std::string& airdrop, const std::string& amount);
    std::string queryTokenBalance(const std::string& rpc_url, const std::string& account, const std::string& token_id);
    std::string tokenId(const std::string& name);
    std::string startTokenId(const std::string& name);
    std::string loadDestinationPacket(const std::string& destinationPacketJsonPath);
    std::string checkEligibility(const std::string& airdrop, const std::string& bundlePath, const std::string& walletPath, const std::string& destinationPacketJsonPath);
    std::string startCheckEligibility(const std::string& airdrop, const std::string& bundlePath, const std::string& walletPath, const std::string& destinationPacketJsonPath);
    std::string prove(const std::string& airdrop, const std::string& bundlePath, const std::string& walletPath, const std::string& destinationPacketJsonPath);
    std::string startProve(const std::string& airdrop, const std::string& bundlePath, const std::string& walletPath, const std::string& destinationPacketJsonPath);
    std::string startInspectCsv(const std::string& csvPath);
    std::string jobStatus(const std::string& jobId);
    std::string verify(const std::string& airdrop, const std::string& proofPath);
    std::string startVerify(const std::string& airdrop, const std::string& proofPath);
    std::string claim(const std::string& airdrop, const std::string& proofPath, const std::string& relayer, const std::string& serializedLezTxPath);
    std::string startClaim(const std::string& airdrop, const std::string& proofPath, const std::string& relayer, const std::string& serializedLezTxPath);
    std::string close(const std::string& airdrop);
    std::string listAirdrops();
    std::string inspectCsv(const std::string& csvPath);
    std::string walletPublicKey(const std::string& walletSeedPath);
    std::string setWallet(const std::string& fromPath, const std::string& toPath);
    std::string runDemo();

private:
    struct JobStore;

    std::string startJob(const std::string& operation, const std::string& args);
    std::string runCli(const std::string& args);

    std::shared_ptr<JobStore> m_jobs;
};
