use sha2::{Digest, Sha256};

pub fn h_leaf(addr: [u8; 32], bucket: u8, salt: [u8; 32]) -> [u8; 32] {
    let mut h = Sha256::new();
    h.update(b"logos-distributionx/leaf-v1");
    h.update(addr);
    h.update([bucket]);
    h.update(salt);
    h.finalize().into()
}

pub fn h_empty() -> [u8; 32] {
    let mut h = Sha256::new();
    h.update(b"logos-distributionx/empty-v1");
    h.finalize().into()
}

pub fn h_node(left: [u8; 32], right: [u8; 32]) -> [u8; 32] {
    let mut h = Sha256::new();
    h.update(b"logos-distributionx/node-v1");
    h.update(left);
    h.update(right);
    h.finalize().into()
}

pub fn h_null(salt: [u8; 32]) -> [u8; 32] {
    let mut h = Sha256::new();
    h.update(b"logos-distributionx/null-v1");
    h.update(salt);
    h.finalize().into()
}
