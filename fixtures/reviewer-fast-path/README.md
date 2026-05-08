# Reviewer Fast-Path Fixture

These are test-only seeds and inputs for local review. They are deterministic mock keys, not production wallets.

Contents:

- `eligible.csv`: 10 claimant public keys, 100 tokens each.
- `wallet.seed`: claimant 1 seed used by the claim flow.
- `claimants/*.seed`: claimant seeds for repeatable negative and alternate-claim tests.
- `admin.seed`: deterministic admin/recovery seed for local scripts.
- `shielded_destination.json`: private destination packet used by the claim proof.
- `claim_destination_commitment.txt`: commitment for the destination packet.
- `fixture-keys.json`: public key and seed index for the fixture.

Install into the normal local state directory:

```bash
bash scripts/install-reviewer-fixture.sh
```

The installer writes the fixture into `${DISTRIBUTIONX_STATE_DIR:-target/distributionx-testnet}` and prints `SAMPLE_FIXTURE_OK` with the admin account and claimant count.
