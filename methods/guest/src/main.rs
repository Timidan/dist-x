use distributionx_circuit::{verify_claim_constraints, ClaimJournal, ClaimWitness};

fn main() {
    let journal: ClaimJournal = risc0_zkvm::guest::env::read();
    let witness: ClaimWitness = risc0_zkvm::guest::env::read();
    // distributionx-circuit mirrors distributionx-tree: is_right is true when the current node is the right child.
    verify_claim_constraints(&journal, &witness).expect("DistributionX constraints failed");
    risc0_zkvm::guest::env::commit(&journal);
}
