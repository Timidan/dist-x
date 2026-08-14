#![allow(clippy::useless_vec)]
#![cfg_attr(test, allow(dead_code))]

use distributionx_circuit::{verify_claim_constraints, ClaimJournal, ClaimWitness};
use distributionx_wallet_ref::MerklePathNode;
use lee_core::account::{Account, Data};
use risc0_binfmt::Digestible;
use risc0_zkvm::{InnerReceipt, MaybePruned, Receipt, ReceiptClaim, VerifierContext};
use spel_framework::prelude::*;

const STATUS_ACTIVE: u8 = 0;
const STATUS_CLOSED: u8 = 1;
const TREE_DEPTH: u8 = 20;

const E_AIRDROP_CLOSED: u32 = 1;
const E_AIRDROP_ID_MISMATCH: u32 = 2;
const E_ROOT_MISMATCH: u32 = 3;
const E_BUCKET_OUT_OF_RANGE: u32 = 4;
const E_BAD_PROOF: u32 = 5;
const E_ALREADY_CLAIMED: u32 = 6;
const E_VAULT_INSUFFICIENT: u32 = 7;
const E_DISTRIBUTOR_ONLY: u32 = 9;
const E_TREE_DEPTH_INVALID: u32 = 10;
const E_BUCKET_TABLE_INVALID: u32 = 11;
const E_BUCKET_AMOUNT_ZERO: u32 = 12;
const E_IMAGE_ID_MISMATCH: u32 = 13;
const E_BAD_DESTINATION_COMMITMENT: u32 = 14;
const E_OVERFLOW: u32 = 15;
const E_EXPIRY_INVALID: u32 = 16;
const E_NULLIFIER_MISMATCH: u32 = 17;

const EXPECTED_IMAGE_ID_WORDS: [u32; 8] = [
    1478923427, 2690089008, 3813642956, 2843112924, 1202024679, 2466696796, 737877087, 376872330,
];
const EXPECTED_IMAGE_ID: [u8; 32] = image_id_words_to_bytes(EXPECTED_IMAGE_ID_WORDS);

const fn image_id_words_to_bytes(words: [u32; 8]) -> [u8; 32] {
    let mut out = [0u8; 32];
    let mut word_index = 0;
    while word_index < 8 {
        let bytes = words[word_index].to_le_bytes();
        let offset = word_index * 4;
        out[offset] = bytes[0];
        out[offset + 1] = bytes[1];
        out[offset + 2] = bytes[2];
        out[offset + 3] = bytes[3];
        word_index += 1;
    }
    out
}

#[derive(Clone, Debug, PartialEq, Eq, BorshSerialize, BorshDeserialize)]
struct AirdropState {
    airdrop_id: [u8; 32],
    distributor: [u8; 32],
    token_id: [u8; 32],
    merkle_root: [u8; 32],
    tree_depth: u8,
    bucket_table_hash: [u8; 32],
    bucket_table: Vec<u64>,
    vault: [u8; 32],
    image_id: [u8; 32],
    expiry_unix: i64,
    recovery_address: [u8; 32],
    total_funded: u64,
    total_claimed: u64,
    created_at: i64,
    status: u8,
}

#[derive(Clone, Debug, PartialEq, Eq, BorshSerialize, BorshDeserialize)]
struct NullifierState {
    claimed_at: i64,
}

fn program_error(code: u32, message: &str) -> SpelError {
    SpelError::custom(code, message)
}

fn account_id(account: &AccountWithMetadata) -> [u8; 32] {
    *account.account_id.value()
}

fn read_airdrop(account: &AccountWithMetadata) -> Result<AirdropState, SpelError> {
    if account.account.data.is_empty() {
        return Err(program_error(
            E_AIRDROP_ID_MISMATCH,
            "airdrop account is not initialized",
        ));
    }
    AirdropState::try_from_slice(account.account.data.as_ref()).map_err(|_| {
        SpelError::DeserializationError {
            account_index: 0,
            message: "invalid DistributionX airdrop state".to_string(),
        }
    })
}

fn write_data<T: BorshSerialize>(mut account: Account, value: &T) -> Result<Account, SpelError> {
    let mut bytes = Vec::new();
    value
        .serialize(&mut bytes)
        .map_err(|err| SpelError::SerializationError {
            message: err.to_string(),
        })?;
    account.data = Data::try_from(bytes).map_err(|err| SpelError::SerializationError {
        message: err.to_string(),
    })?;
    Ok(account)
}

fn checked_add_u64(a: u64, b: u64) -> Result<u64, SpelError> {
    a.checked_add(b)
        .ok_or_else(|| program_error(E_OVERFLOW, "u64 addition overflow"))
}

fn checked_add_u128(a: u128, b: u128) -> Result<u128, SpelError> {
    a.checked_add(b)
        .ok_or_else(|| program_error(E_OVERFLOW, "u128 addition overflow"))
}

fn checked_sub_u128(a: u128, b: u128) -> Result<u128, SpelError> {
    a.checked_sub(b)
        .ok_or_else(|| program_error(E_VAULT_INSUFFICIENT, "vault balance is insufficient"))
}

fn ensure_distributor(
    state: &AirdropState,
    distributor: &AccountWithMetadata,
) -> Result<(), SpelError> {
    if account_id(distributor) != state.distributor {
        return Err(program_error(
            E_DISTRIBUTOR_ONLY,
            "only the airdrop distributor can perform this action",
        ));
    }
    Ok(())
}

fn ensure_airdrop_id(state: &AirdropState, airdrop_id: [u8; 32]) -> Result<(), SpelError> {
    if state.airdrop_id != airdrop_id {
        return Err(program_error(
            E_AIRDROP_ID_MISMATCH,
            "airdrop id does not match state",
        ));
    }
    Ok(())
}

fn ensure_vault(state: &AirdropState, vault: &AccountWithMetadata) -> Result<(), SpelError> {
    if account_id(vault) != state.vault {
        return Err(program_error(
            E_AIRDROP_ID_MISMATCH,
            "vault account does not match airdrop state",
        ));
    }
    Ok(())
}

fn ensure_active(state: &AirdropState, now_unix: i64) -> Result<(), SpelError> {
    if state.status != STATUS_ACTIVE || now_unix >= state.expiry_unix {
        return Err(program_error(
            E_AIRDROP_CLOSED,
            "airdrop is closed or expired",
        ));
    }
    Ok(())
}

fn with_claim_expiry(output: SpelOutput, expiry_unix: i64) -> SpelResult {
    let expiry_millis = u64::try_from(expiry_unix)
        .ok()
        .and_then(|seconds| seconds.checked_mul(1_000))
        .ok_or_else(|| program_error(E_OVERFLOW, "airdrop expiry milliseconds overflow"))?;
    Ok(output.with_timestamp_validity_window(..expiry_millis))
}

fn verify_claim_witness(
    journal: &ClaimJournal,
    claimant_address: [u8; 32],
    salt: [u8; 32],
    claim_sig: Vec<u8>,
    merkle_siblings: Vec<[u8; 32]>,
    merkle_path_is_right: Vec<bool>,
) -> Result<(), SpelError> {
    if merkle_siblings.len() != TREE_DEPTH as usize
        || merkle_path_is_right.len() != TREE_DEPTH as usize
    {
        return Err(program_error(
            E_TREE_DEPTH_INVALID,
            "claim merkle path must have depth 20",
        ));
    }

    let merkle_path = merkle_siblings
        .into_iter()
        .zip(merkle_path_is_right)
        .map(|(sibling, is_right)| MerklePathNode { sibling, is_right })
        .collect();
    let claim_sig = claim_sig
        .try_into()
        .map_err(|_| program_error(E_BAD_PROOF, "claim signature must be 64 bytes"))?;
    let witness = ClaimWitness {
        address: claimant_address,
        salt,
        claim_sig,
        merkle_path,
    };

    verify_claim_constraints(journal, &witness).map_err(|_| {
        program_error(
            E_BAD_PROOF,
            "claim witness failed DistributionX constraints",
        )
    })?;
    Ok(())
}

fn verify_claim_receipt(receipt_bytes: &[u8]) -> Result<ClaimJournal, SpelError> {
    #[cfg(test)]
    if let Some(journal_bytes) = receipt_bytes.strip_prefix(TEST_VERIFIED_JOURNAL_PREFIX) {
        return bincode::deserialize(journal_bytes)
            .map_err(|_| program_error(E_BAD_PROOF, "test claim journal could not be decoded"));
    }

    let receipt: Receipt = bincode::deserialize(receipt_bytes)
        .map_err(|_| program_error(E_BAD_PROOF, "claim receipt could not be decoded"))?;
    let claim = match &receipt.inner {
        InnerReceipt::Groth16(inner) => {
            if inner.verifier_parameters != receipt.metadata.verifier_parameters {
                return Err(program_error(
                    E_BAD_PROOF,
                    "claim receipt metadata mismatch",
                ));
            }
            inner
                .verify_integrity_with_context(&VerifierContext::default())
                .map_err(|_| {
                    program_error(E_BAD_PROOF, "claim receipt failed Risc0 verification")
                })?;
            inner
                .claim
                .as_value()
                .map_err(|_| {
                    program_error(E_BAD_PROOF, "claim receipt claim could not be decoded")
                })?
                .clone()
        }
        _ => {
            return Err(program_error(
                E_BAD_PROOF,
                "claim receipt must be a Risc0 Groth16 receipt",
            ));
        }
    };
    let expected_claim = ReceiptClaim::ok(
        EXPECTED_IMAGE_ID_WORDS,
        MaybePruned::Pruned(receipt.journal.digest::<risc0_zkvm::sha::Impl>()),
    );
    if claim.digest::<risc0_zkvm::sha::Impl>() != expected_claim.digest::<risc0_zkvm::sha::Impl>() {
        return Err(program_error(
            E_BAD_PROOF,
            "claim receipt does not match expected Risc0 method and journal",
        ));
    }
    receipt
        .journal
        .decode()
        .map_err(|_| program_error(E_BAD_PROOF, "claim receipt journal could not be decoded"))
}

#[cfg(test)]
const TEST_VERIFIED_JOURNAL_PREFIX: &[u8] = b"distributionx-test-verified-journal-v1:";

#[lez_program]
mod distributionx {
    #[instruction]
    pub fn init_airdrop(
        #[account(init, pda = [literal("airdrop"), arg("airdrop_id")])]
        airdrop: AccountWithMetadata,
        #[account(init, pda = [literal("vault"), arg("airdrop_id")])] vault: AccountWithMetadata,
        #[account(signer)] distributor: AccountWithMetadata,
        airdrop_id: [u8; 32],
        token_id: [u8; 32],
        merkle_root: [u8; 32],
        tree_depth: u8,
        bucket_table_hash: [u8; 32],
        bucket_table: Vec<u64>,
        image_id: [u8; 32],
        expiry_unix: i64,
        recovery_address: [u8; 32],
        now_unix: i64,
    ) -> SpelResult {
        if tree_depth != TREE_DEPTH {
            return Err(program_error(
                E_TREE_DEPTH_INVALID,
                "DistributionX tree depth must be 20",
            ));
        }
        if bucket_table.is_empty() || bucket_table.len() > 32 {
            return Err(program_error(
                E_BUCKET_TABLE_INVALID,
                "bucket table must contain between 1 and 32 amounts",
            ));
        }
        if bucket_table.iter().any(|amount| *amount == 0) {
            return Err(program_error(
                E_BUCKET_AMOUNT_ZERO,
                "bucket amounts must be non-zero",
            ));
        }
        if image_id != EXPECTED_IMAGE_ID {
            return Err(program_error(
                E_IMAGE_ID_MISMATCH,
                "unexpected DistributionX Risc0 method image id",
            ));
        }
        if expiry_unix <= now_unix {
            return Err(program_error(
                E_EXPIRY_INVALID,
                "airdrop expiry must be in the future",
            ));
        }

        let state = AirdropState {
            airdrop_id,
            distributor: account_id(&distributor),
            token_id,
            merkle_root,
            tree_depth,
            bucket_table_hash,
            bucket_table,
            vault: account_id(&vault),
            image_id,
            expiry_unix,
            recovery_address,
            total_funded: 0,
            total_claimed: 0,
            created_at: now_unix,
            status: STATUS_ACTIVE,
        };

        Ok(SpelOutput::execute(
            vec![
                write_data(airdrop.account, &state)?,
                vault.account,
                distributor.account,
            ],
            vec![],
        ))
    }

    #[instruction]
    pub fn fund(
        #[account(mut, pda = [literal("airdrop"), arg("airdrop_id")])] airdrop: AccountWithMetadata,
        #[account(mut, pda = [literal("vault"), arg("airdrop_id")])] vault: AccountWithMetadata,
        #[account(signer)] distributor: AccountWithMetadata,
        airdrop_id: [u8; 32],
        amount: u64,
        now_unix: i64,
    ) -> SpelResult {
        if amount == 0 {
            return Err(program_error(
                E_BUCKET_AMOUNT_ZERO,
                "fund amount must be non-zero",
            ));
        }
        let mut state = read_airdrop(&airdrop)?;
        ensure_airdrop_id(&state, airdrop_id)?;
        ensure_active(&state, now_unix)?;
        ensure_distributor(&state, &distributor)?;
        ensure_vault(&state, &vault)?;

        let new_total = checked_add_u64(state.total_funded, amount)?;
        if vault.account.balance < u128::from(new_total) {
            return Err(program_error(
                E_VAULT_INSUFFICIENT,
                "vault balance is lower than requested funded total",
            ));
        }
        state.total_funded = new_total;

        Ok(SpelOutput::execute(
            vec![
                write_data(airdrop.account, &state)?,
                vault.account,
                distributor.account,
            ],
            vec![],
        ))
    }

    #[instruction]
    pub fn claim(
        #[account(mut, pda = [literal("airdrop"), arg("airdrop_id")])] airdrop: AccountWithMetadata,
        #[account(init, pda = [literal("nullifier"), arg("airdrop_id"), arg("nullifier")])]
        nullifier_record: AccountWithMetadata,
        #[account(mut, pda = [literal("vault"), arg("airdrop_id")])] vault: AccountWithMetadata,
        airdrop_id: [u8; 32],
        nullifier: [u8; 32],
        receipt_bytes: Vec<u8>,
        now_unix: i64,
    ) -> SpelResult {
        if nullifier_record.account.data.is_empty() == false {
            return Err(program_error(
                E_ALREADY_CLAIMED,
                "nullifier account is already initialized",
            ));
        }

        let mut state = read_airdrop(&airdrop)?;
        ensure_airdrop_id(&state, airdrop_id)?;
        ensure_active(&state, now_unix)?;
        ensure_vault(&state, &vault)?;

        let journal = verify_claim_receipt(&receipt_bytes)?;
        if journal.airdrop_id != airdrop_id {
            return Err(program_error(
                E_AIRDROP_ID_MISMATCH,
                "claim receipt airdrop id mismatch",
            ));
        }
        if journal.nullifier != nullifier {
            return Err(program_error(
                E_NULLIFIER_MISMATCH,
                "claim receipt nullifier mismatch",
            ));
        }
        if journal.merkle_root != state.merkle_root {
            return Err(program_error(E_ROOT_MISMATCH, "merkle root mismatch"));
        }
        if journal.bucket_id as usize >= state.bucket_table.len() {
            return Err(program_error(
                E_BUCKET_OUT_OF_RANGE,
                "bucket id is outside the configured table",
            ));
        }
        if journal.claim_destination_commitment == [0u8; 32] {
            return Err(program_error(
                E_BAD_DESTINATION_COMMITMENT,
                "destination commitment must be non-zero",
            ));
        }

        let amount = state.bucket_table[journal.bucket_id as usize];
        let new_total_claimed = checked_add_u64(state.total_claimed, amount)?;
        if new_total_claimed > state.total_funded || vault.account.balance < u128::from(amount) {
            return Err(program_error(
                E_VAULT_INSUFFICIENT,
                "vault cannot cover claim amount",
            ));
        }
        state.total_claimed = new_total_claimed;

        let mut vault_post = vault.account;
        vault_post.balance = checked_sub_u128(vault_post.balance, u128::from(amount))?;

        let nullifier_state = NullifierState {
            claimed_at: now_unix,
        };
        let mut nullifier_post = write_data(nullifier_record.account, &nullifier_state)?;
        nullifier_post.balance = checked_add_u128(nullifier_post.balance, u128::from(amount))?;

        with_claim_expiry(
            SpelOutput::execute(
                vec![
                    write_data(airdrop.account, &state)?,
                    nullifier_post,
                    vault_post,
                ],
                vec![],
            ),
            state.expiry_unix,
        )
    }

    #[instruction]
    #[allow(clippy::too_many_arguments)]
    pub fn claim_private(
        #[account(mut, pda = [literal("airdrop"), arg("airdrop_id")])] airdrop: AccountWithMetadata,
        #[account(init, pda = [literal("nullifier"), arg("airdrop_id"), arg("nullifier")])]
        nullifier_record: AccountWithMetadata,
        #[account(mut, pda = [literal("vault"), arg("airdrop_id")])] vault: AccountWithMetadata,
        airdrop_id: [u8; 32],
        bucket_id: u8,
        nullifier: [u8; 32],
        claim_destination_commitment: [u8; 32],
        claimant_address: [u8; 32],
        salt: [u8; 32],
        claim_sig: Vec<u8>,
        merkle_siblings: Vec<[u8; 32]>,
        merkle_path_is_right: Vec<bool>,
        now_unix: i64,
    ) -> SpelResult {
        if nullifier_record.account.data.is_empty() == false {
            return Err(program_error(
                E_ALREADY_CLAIMED,
                "nullifier account is already initialized",
            ));
        }
        if claim_destination_commitment == [0u8; 32] {
            return Err(program_error(
                E_BAD_DESTINATION_COMMITMENT,
                "destination commitment must be non-zero",
            ));
        }

        let mut state = read_airdrop(&airdrop)?;
        ensure_airdrop_id(&state, airdrop_id)?;
        ensure_active(&state, now_unix)?;
        ensure_vault(&state, &vault)?;
        if bucket_id as usize >= state.bucket_table.len() {
            return Err(program_error(
                E_BUCKET_OUT_OF_RANGE,
                "bucket id is outside the configured table",
            ));
        }

        let journal = ClaimJournal::new(
            airdrop_id,
            state.merkle_root,
            bucket_id,
            nullifier,
            claim_destination_commitment,
        );
        verify_claim_witness(
            &journal,
            claimant_address,
            salt,
            claim_sig,
            merkle_siblings,
            merkle_path_is_right,
        )?;

        let amount = state.bucket_table[bucket_id as usize];
        let new_total_claimed = checked_add_u64(state.total_claimed, amount)?;
        if new_total_claimed > state.total_funded || vault.account.balance < u128::from(amount) {
            return Err(program_error(
                E_VAULT_INSUFFICIENT,
                "vault cannot cover claim amount",
            ));
        }
        state.total_claimed = new_total_claimed;

        let mut vault_post = vault.account;
        vault_post.balance = checked_sub_u128(vault_post.balance, u128::from(amount))?;

        let nullifier_state = NullifierState {
            claimed_at: now_unix,
        };
        let mut nullifier_post = write_data(nullifier_record.account, &nullifier_state)?;
        nullifier_post.balance = checked_add_u128(nullifier_post.balance, u128::from(amount))?;

        with_claim_expiry(
            SpelOutput::execute(
                vec![
                    write_data(airdrop.account, &state)?,
                    nullifier_post,
                    vault_post,
                ],
                vec![],
            ),
            state.expiry_unix,
        )
    }

    #[instruction]
    #[allow(clippy::too_many_arguments)]
    pub fn claim_ppe(
        #[account(mut, pda = [literal("airdrop"), arg("airdrop_id")])] airdrop: AccountWithMetadata,
        #[account(init, pda = [literal("nullifier"), arg("airdrop_id"), arg("nullifier")])]
        nullifier_record: AccountWithMetadata,
        #[account(mut, pda = [literal("vault"), arg("airdrop_id")])] vault: AccountWithMetadata,
        #[account(init)] recipient: AccountWithMetadata,
        airdrop_id: [u8; 32],
        bucket_id: u8,
        nullifier: [u8; 32],
        claim_destination_commitment: [u8; 32],
        claimant_address: [u8; 32],
        salt: [u8; 32],
        claim_sig: Vec<u8>,
        merkle_siblings: Vec<[u8; 32]>,
        merkle_path_is_right: Vec<bool>,
        now_unix: i64,
    ) -> SpelResult {
        if !nullifier_record.account.data.is_empty() {
            return Err(program_error(
                E_ALREADY_CLAIMED,
                "nullifier account is already initialized",
            ));
        }
        if claim_destination_commitment == [0u8; 32]
            || account_id(&recipient) != claim_destination_commitment
        {
            return Err(program_error(
                E_BAD_DESTINATION_COMMITMENT,
                "destination commitment must match the private recipient account",
            ));
        }

        let mut state = read_airdrop(&airdrop)?;
        ensure_airdrop_id(&state, airdrop_id)?;
        ensure_active(&state, now_unix)?;
        ensure_vault(&state, &vault)?;
        if bucket_id as usize >= state.bucket_table.len() {
            return Err(program_error(
                E_BUCKET_OUT_OF_RANGE,
                "bucket id is outside the configured table",
            ));
        }

        let journal = ClaimJournal::new(
            airdrop_id,
            state.merkle_root,
            bucket_id,
            nullifier,
            claim_destination_commitment,
        );
        verify_claim_witness(
            &journal,
            claimant_address,
            salt,
            claim_sig,
            merkle_siblings,
            merkle_path_is_right,
        )?;

        let amount = state.bucket_table[bucket_id as usize];
        let new_total_claimed = checked_add_u64(state.total_claimed, amount)?;
        if new_total_claimed > state.total_funded || vault.account.balance < u128::from(amount) {
            return Err(program_error(
                E_VAULT_INSUFFICIENT,
                "vault cannot cover claim amount",
            ));
        }
        state.total_claimed = new_total_claimed;

        let mut vault_post = vault.account;
        vault_post.balance = checked_sub_u128(vault_post.balance, u128::from(amount))?;

        let nullifier_state = NullifierState {
            claimed_at: now_unix,
        };
        let nullifier_post = write_data(nullifier_record.account, &nullifier_state)?;

        let mut recipient_post = recipient.account;
        recipient_post.balance = checked_add_u128(recipient_post.balance, u128::from(amount))?;

        with_claim_expiry(
            SpelOutput::execute(
                vec![
                    write_data(airdrop.account, &state)?,
                    nullifier_post,
                    vault_post,
                    recipient_post,
                ],
                vec![],
            ),
            state.expiry_unix,
        )
    }

    #[instruction]
    pub fn close(
        #[account(mut, pda = [literal("airdrop"), arg("airdrop_id")])] airdrop: AccountWithMetadata,
        #[account(mut, pda = [literal("vault"), arg("airdrop_id")])] vault: AccountWithMetadata,
        #[account(mut)] recovery: AccountWithMetadata,
        #[account(signer)] distributor: AccountWithMetadata,
        airdrop_id: [u8; 32],
    ) -> SpelResult {
        let mut state = read_airdrop(&airdrop)?;
        ensure_airdrop_id(&state, airdrop_id)?;
        ensure_distributor(&state, &distributor)?;
        ensure_vault(&state, &vault)?;
        if account_id(&recovery) != state.recovery_address {
            return Err(program_error(
                E_DISTRIBUTOR_ONLY,
                "recovery account does not match airdrop state",
            ));
        }

        state.status = STATUS_CLOSED;
        let mut vault_post = vault.account;
        let mut recovery_post = recovery.account;
        recovery_post.balance = checked_add_u128(recovery_post.balance, vault_post.balance)?;
        vault_post.balance = 0;

        Ok(SpelOutput::execute(
            vec![
                write_data(airdrop.account, &state)?,
                vault_post,
                recovery_post,
                distributor.account,
            ],
            vec![],
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use distributionx_tree::{h_empty, h_leaf, h_node, h_null};

    const AIRDROP_ID: [u8; 32] = [1; 32];
    const VAULT_ID: [u8; 32] = [2; 32];
    const NULLIFIER_RECORD_ID: [u8; 32] = [8; 32];
    const DESTINATION: [u8; 32] = [9; 32];
    const SALT: [u8; 32] = [3; 32];
    const CLAIMANT_ADDRESS: [u8; 32] = [
        202, 147, 172, 23, 5, 24, 112, 113, 214, 123, 131, 199, 255, 14, 254, 129, 8, 232, 236, 69,
        48, 87, 93, 119, 38, 135, 147, 51, 219, 218, 190, 124,
    ];
    const CLAIM_SIGNATURE: [u8; 64] = [
        52, 58, 153, 234, 74, 221, 176, 25, 132, 247, 100, 169, 238, 159, 77, 238, 72, 23, 217,
        182, 168, 115, 240, 157, 25, 249, 127, 233, 139, 198, 225, 145, 151, 78, 224, 58, 87, 15,
        197, 32, 59, 25, 153, 76, 20, 46, 179, 163, 206, 75, 200, 199, 71, 87, 125, 21, 251, 114,
        140, 118, 5, 203, 248, 6,
    ];
    const CLAIM_AMOUNT: u64 = 100;
    const NOW_UNIX: i64 = 100;
    const EXPIRY_UNIX: i64 = 1_700_000_123;
    const EXPIRY_MILLIS: u64 = 1_700_000_123_000;

    #[derive(Clone)]
    struct ClaimFixture {
        airdrop: AccountWithMetadata,
        nullifier_record: AccountWithMetadata,
        vault: AccountWithMetadata,
        recipient: AccountWithMetadata,
        journal: ClaimJournal,
        merkle_path: Vec<MerklePathNode>,
    }

    impl ClaimFixture {
        fn claim(&self) -> SpelResult {
            let mut receipt_bytes = TEST_VERIFIED_JOURNAL_PREFIX.to_vec();
            receipt_bytes
                .extend(bincode::serialize(&self.journal).expect("serialize test claim journal"));
            distributionx::claim(
                self.airdrop.clone(),
                self.nullifier_record.clone(),
                self.vault.clone(),
                AIRDROP_ID,
                self.journal.nullifier,
                receipt_bytes,
                NOW_UNIX,
            )
        }

        fn claim_private(&self) -> SpelResult {
            distributionx::claim_private(
                self.airdrop.clone(),
                self.nullifier_record.clone(),
                self.vault.clone(),
                AIRDROP_ID,
                0,
                self.journal.nullifier,
                DESTINATION,
                CLAIMANT_ADDRESS,
                SALT,
                CLAIM_SIGNATURE.to_vec(),
                self.merkle_path.iter().map(|node| node.sibling).collect(),
                self.merkle_path.iter().map(|node| node.is_right).collect(),
                NOW_UNIX,
            )
        }

        fn claim_ppe(&self) -> SpelResult {
            distributionx::claim_ppe(
                self.airdrop.clone(),
                self.nullifier_record.clone(),
                self.vault.clone(),
                self.recipient.clone(),
                AIRDROP_ID,
                0,
                self.journal.nullifier,
                DESTINATION,
                CLAIMANT_ADDRESS,
                SALT,
                CLAIM_SIGNATURE.to_vec(),
                self.merkle_path.iter().map(|node| node.sibling).collect(),
                self.merkle_path.iter().map(|node| node.is_right).collect(),
                NOW_UNIX,
            )
        }
    }

    fn account_with_id(account: Account, id: [u8; 32]) -> AccountWithMetadata {
        AccountWithMetadata::new(account, false, lee_core::account::AccountId::new(id))
    }

    fn claim_fixture(expiry_unix: i64) -> ClaimFixture {
        let mut merkle_path = Vec::with_capacity(TREE_DEPTH as usize);
        let mut empty_subtree = h_empty();
        let mut merkle_root = h_leaf(CLAIMANT_ADDRESS, 0, SALT);
        for _ in 0..TREE_DEPTH {
            merkle_path.push(MerklePathNode {
                sibling: empty_subtree,
                is_right: false,
            });
            merkle_root = h_node(merkle_root, empty_subtree);
            empty_subtree = h_node(empty_subtree, empty_subtree);
        }

        let state = AirdropState {
            airdrop_id: AIRDROP_ID,
            distributor: [4; 32],
            token_id: [5; 32],
            merkle_root,
            tree_depth: TREE_DEPTH,
            bucket_table_hash: [6; 32],
            bucket_table: vec![CLAIM_AMOUNT],
            vault: VAULT_ID,
            image_id: EXPECTED_IMAGE_ID,
            expiry_unix,
            recovery_address: [7; 32],
            total_funded: CLAIM_AMOUNT,
            total_claimed: 0,
            created_at: 0,
            status: STATUS_ACTIVE,
        };
        let airdrop_account = write_data(Account::default(), &state).expect("serialize airdrop");
        let vault_account = Account {
            balance: u128::from(CLAIM_AMOUNT),
            ..Account::default()
        };
        let journal = ClaimJournal::new(AIRDROP_ID, merkle_root, 0, h_null(SALT), DESTINATION);

        ClaimFixture {
            airdrop: account_with_id(airdrop_account, [10; 32]),
            nullifier_record: account_with_id(Account::default(), NULLIFIER_RECORD_ID),
            vault: account_with_id(vault_account, VAULT_ID),
            recipient: account_with_id(Account::default(), DESTINATION),
            journal,
            merkle_path,
        }
    }

    fn assert_expiry_window(variant: &str, output: SpelOutput) {
        let window = output.timestamp_validity_window;
        assert_eq!(window.start(), None, "{variant} lower bound");
        assert_eq!(window.end(), Some(EXPIRY_MILLIS), "{variant} upper bound");
        assert!(
            window.is_valid_for(EXPIRY_MILLIS - 1),
            "{variant} must remain valid immediately before expiry"
        );
        assert!(
            !window.is_valid_for(EXPIRY_MILLIS),
            "{variant} expiry must be exclusive"
        );
    }

    fn assert_overflow(variant: &str, result: SpelResult) {
        match result {
            Err(SpelError::Custom { code, .. }) => {
                assert_eq!(code, E_OVERFLOW, "{variant} overflow error code")
            }
            other => panic!("{variant} must fail closed on expiry overflow: {other:?}"),
        }
    }

    #[test]
    fn every_claim_output_ends_at_the_exclusive_airdrop_expiry() {
        let fixture = claim_fixture(EXPIRY_UNIX);
        for (variant, result) in [
            ("claim", fixture.claim()),
            ("claim_private", fixture.claim_private()),
            ("claim_ppe", fixture.claim_ppe()),
        ] {
            assert_expiry_window(variant, result.expect("valid claim fixture"));
        }
    }

    #[test]
    fn every_claim_variant_fails_closed_when_expiry_milliseconds_overflow() {
        let fixture = claim_fixture(i64::MAX);
        for (variant, result) in [
            ("claim", fixture.claim()),
            ("claim_private", fixture.claim_private()),
            ("claim_ppe", fixture.claim_ppe()),
        ] {
            assert_overflow(variant, result);
        }
    }

    #[test]
    fn __lssa_idl_print() {
        println!("--- LSSA IDL BEGIN distributionx ---");
        println!("{}", super::PROGRAM_IDL_JSON);
        println!("--- LSSA IDL END distributionx ---");
    }
}
