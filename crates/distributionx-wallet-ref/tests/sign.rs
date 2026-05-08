use distributionx_wallet_ref::storage::{seed_from_mnemonic_for_test, KeychainSeedStore};
use distributionx_wallet_ref::{claim_message, DistributionXKeystore, InMemoryKeystore};
use ed25519_dalek::{Signature, VerifyingKey};

#[test]
fn sign_claim_uses_distributionx_domain_and_strict_ed25519() {
    let seed = [9u8; 32];
    let ks = InMemoryKeystore::from_seed(seed).unwrap();
    let airdrop_id = [1u8; 32];
    let claim_destination_commitment = [2u8; 32];
    let sig = ks.sign_claim(airdrop_id, claim_destination_commitment);
    let vk = VerifyingKey::from_bytes(&ks.public_ed25519()).unwrap();
    vk.verify_strict(
        &claim_message(airdrop_id, claim_destination_commitment),
        &Signature::from_bytes(&sig),
    )
    .unwrap();
}

#[test]
fn public_x25519_is_derived_from_ed25519_public_key() {
    let ks = InMemoryKeystore::from_seed([42u8; 32]).unwrap();
    assert_ne!(ks.public_x25519(), [0u8; 32]);
    assert_ne!(ks.public_x25519(), ks.public_ed25519());
}

#[test]
fn bip39_phrase_imports_to_32_byte_seed_material() {
    let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";
    let seed = seed_from_mnemonic_for_test(phrase).unwrap();
    assert_eq!(seed.len(), 32);
}

#[test]
fn keychain_service_and_account_names_are_stable() {
    let store = KeychainSeedStore::new("distributionx-test-airdrop");
    assert_eq!(store.service_name(), "logos-distributionx-wallet-ref");
    assert_eq!(store.account_name(), "distributionx-test-airdrop");
}
