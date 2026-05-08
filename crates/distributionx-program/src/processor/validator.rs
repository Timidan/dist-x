use crate::errors::*;
use crate::state::Airdrop;
use distributionx_circuit::ClaimJournal;
use risc0_zkvm::Receipt;

pub const EXPECTED_IMAGE_ID_WORDS: [u32; 8] = [
    2021700558, 3694440392, 3417518589, 1406597505, 2646892967, 2203840848, 319733246, 2797217385,
];
pub const EXPECTED_IMAGE_ID: [u8; 32] = image_id_words_to_bytes(EXPECTED_IMAGE_ID_WORDS);

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

#[derive(Clone, Debug)]
pub struct InitAirdropArgs {
    pub distributor: [u8; 32],
    pub token_id: [u8; 32],
    pub merkle_root: [u8; 32],
    pub bucket_table_hash: [u8; 32],
    pub bucket_table: Vec<u64>,
    pub vault: [u8; 32],
    pub image_id: [u8; 32],
    pub expiry_unix: i64,
    pub recovery_address: [u8; 32],
    pub nonce: u64,
}

impl InitAirdropArgs {
    pub fn valid_for_test() -> Self {
        Self {
            distributor: [1; 32],
            token_id: [2; 32],
            merkle_root: [3; 32],
            bucket_table_hash: [4; 32],
            bucket_table: vec![100],
            vault: [5; 32],
            image_id: EXPECTED_IMAGE_ID,
            expiry_unix: 1_000,
            recovery_address: [6; 32],
            nonce: 7,
        }
    }
}

pub fn init_airdrop(args: InitAirdropArgs, now: i64) -> Result<Airdrop, ProgramErrorCode> {
    if args.bucket_table.is_empty() || args.bucket_table.len() > 32 {
        return Err(ProgramErrorCode(E_BUCKET_TABLE_INVALID));
    }
    if args.bucket_table.contains(&0) {
        return Err(ProgramErrorCode(E_BUCKET_AMOUNT_ZERO));
    }
    if args.image_id != EXPECTED_IMAGE_ID {
        return Err(ProgramErrorCode(E_IMAGE_ID_MISMATCH));
    }
    if args.expiry_unix <= now {
        return Err(ProgramErrorCode(E_EXPIRY_INVALID));
    }
    Ok(Airdrop {
        distributor: args.distributor,
        token_id: args.token_id,
        merkle_root: args.merkle_root,
        tree_depth: 20,
        bucket_table_hash: args.bucket_table_hash,
        bucket_table: args.bucket_table,
        vault: args.vault,
        image_id: args.image_id,
        expiry_unix: args.expiry_unix,
        recovery_address: args.recovery_address,
        total_funded: 0,
        total_claimed: 0,
        created_at: now,
        status: 0,
    })
}

pub fn fund(airdrop: &mut Airdrop, amount: u64) -> Result<(), ProgramErrorCode> {
    airdrop.total_funded = airdrop
        .total_funded
        .checked_add(amount)
        .ok_or(ProgramErrorCode(E_OVERFLOW))?;
    Ok(())
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct VerifiedClaimJournal {
    journal: ClaimJournal,
}

impl VerifiedClaimJournal {
    pub fn from_risc0_receipt(receipt_bytes: &[u8]) -> Result<Self, ProgramErrorCode> {
        let receipt: Receipt =
            bincode::deserialize(receipt_bytes).map_err(|_| ProgramErrorCode(E_BAD_PROOF))?;
        receipt
            .verify(EXPECTED_IMAGE_ID_WORDS)
            .map_err(|_| ProgramErrorCode(E_BAD_PROOF))?;
        let journal = receipt
            .journal
            .decode()
            .map_err(|_| ProgramErrorCode(E_BAD_PROOF))?;
        Ok(Self { journal })
    }

    pub fn journal(&self) -> &ClaimJournal {
        &self.journal
    }

    #[doc(hidden)]
    pub fn from_verified_journal_unchecked(journal: ClaimJournal) -> Self {
        Self { journal }
    }
}

pub fn claim(
    airdrop: &Airdrop,
    airdrop_id: [u8; 32],
    nullifier: [u8; 32],
    verified_claim: &VerifiedClaimJournal,
    vault_balance: u64,
) -> Result<u64, ProgramErrorCode> {
    let journal = verified_claim.journal();
    if airdrop.status != 0 {
        return Err(ProgramErrorCode(E_AIRDROP_CLOSED));
    }
    if journal.airdrop_id != airdrop_id {
        return Err(ProgramErrorCode(E_AIRDROP_ID_MISMATCH));
    }
    if journal.nullifier != nullifier {
        return Err(ProgramErrorCode(E_NULLIFIER_MISMATCH));
    }
    if journal.merkle_root != airdrop.merkle_root {
        return Err(ProgramErrorCode(E_ROOT_MISMATCH));
    }
    if journal.bucket_id as usize >= airdrop.bucket_table.len() {
        return Err(ProgramErrorCode(E_BUCKET_OUT_OF_RANGE));
    }
    let amount = airdrop.bucket_table[journal.bucket_id as usize];
    if vault_balance < amount {
        return Err(ProgramErrorCode(E_VAULT_INSUFFICIENT));
    }
    Ok(amount)
}

pub fn close(airdrop: &mut Airdrop, caller: [u8; 32]) -> Result<[u8; 32], ProgramErrorCode> {
    if caller != airdrop.distributor {
        return Err(ProgramErrorCode(E_DISTRIBUTOR_ONLY));
    }
    airdrop.status = 1;
    Ok(airdrop.recovery_address)
}
