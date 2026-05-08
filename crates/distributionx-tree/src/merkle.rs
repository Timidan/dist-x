use crate::hash::{h_empty, h_node};
use distributionx_wallet_ref::MerklePathNode;

pub const TREE_DEPTH: usize = 20;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MerklePath {
    pub nodes: Vec<MerklePathNode>,
}

#[derive(Clone, Debug)]
pub struct MerkleTree {
    levels: Vec<Vec<[u8; 32]>>,
}

impl MerkleTree {
    pub fn from_leaves(mut leaves: Vec<[u8; 32]>) -> Self {
        let capacity = 1usize << TREE_DEPTH;
        assert!(leaves.len() <= capacity);
        leaves.resize(capacity, h_empty());
        let mut levels = vec![leaves];
        for depth in 0..TREE_DEPTH {
            let prev = &levels[depth];
            let mut next = Vec::with_capacity(prev.len() / 2);
            for pair in prev.chunks_exact(2) {
                next.push(h_node(pair[0], pair[1]));
            }
            levels.push(next);
        }
        Self { levels }
    }

    pub fn depth(&self) -> usize {
        TREE_DEPTH
    }

    pub fn root(&self) -> [u8; 32] {
        self.levels[TREE_DEPTH][0]
    }

    pub fn path(&self, index: usize) -> Option<MerklePath> {
        if index >= self.levels[0].len() {
            return None;
        }
        let mut idx = index;
        let mut nodes = Vec::with_capacity(TREE_DEPTH);
        for level in 0..TREE_DEPTH {
            let sibling_idx = if idx.is_multiple_of(2) {
                idx + 1
            } else {
                idx - 1
            };
            nodes.push(MerklePathNode {
                sibling: self.levels[level][sibling_idx],
                is_right: !idx.is_multiple_of(2),
            });
            idx /= 2;
        }
        Some(MerklePath { nodes })
    }

    pub fn verify(&self, index: usize, leaf: [u8; 32], path: &MerklePath) -> bool {
        if path.nodes.len() != TREE_DEPTH {
            return false;
        }
        let mut idx = index;
        let mut cur = leaf;
        for node in &path.nodes {
            cur = if idx.is_multiple_of(2) {
                h_node(cur, node.sibling)
            } else {
                h_node(node.sibling, cur)
            };
            idx /= 2;
        }
        cur == self.root()
    }
}
