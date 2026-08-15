# Current LEZ public-testnet evidence

Verified on `https://testnet.lez.logos.co` at `2026-08-15T22:39:56Z`. The endpoint was healthy and its built-ins matched pinned LEZ v0.2.4 commit `47eba256479f6f785acbd138834340703cd03401`; the endpoint does not expose an exact server revision.

## Current run summary

- Release and execution source: `v0.1.0` / `74f81ab9ee74ba533d3a8fa01cba9f67153f6385`
- Read-only verifier source: `fb61565fd7f8d3409ff65f7e2f4a7297cd56078a`
- Immutable quote SHA-256: `a87b55a6f683be2e3c7570e939cb4ab928b5730f627723396def98a41d8756de`
- Program id: `4bf08c88a91871ecf69ff08af42591a597c51142cbc1f9c6fbbb7d2e888d9ee3`
- [Deploy transaction](https://validatorinfo.com/networks/logos-testnet/tx/2186b9ba9e95e4926f2800e88b5d0653bda3d1669414f0a19c6daf0798576181/expand): `2186b9ba9e95e4926f2800e88b5d0653bda3d1669414f0a19c6daf0798576181`, LEZ block 8138
- Two native-token distributions, ten included `claim_ppe` claims each
- Approved writes: 5-write smoke + 22-write finish = 27 unique included transactions
- Proof mode: `RISC0_DEV_MODE=0`; custom-token settlement disabled; no close transaction

The machine-readable source of truth is the [public manifest](./testnet-evidence/v0.1.0/manifest.json). Its sibling [`rpc/`](./testnet-evidence/v0.1.0/rpc) directory contains all 27 capture-time `getTransaction` responses. Only this scrubbed public tree is committed; claimant wallets, eligibility rows, proofs, destinations, serialized transactions, receipts, and quote-time working state remain private.

## Current distributions

| Distribution id | Init | Prefund | Fund | Claims |
| --- | --- | --- | --- | ---: |
| `205a0aad874f9271d886959a0ea11f92f2c0888078e88c2a93f9836d7b1ab9f1` | [8139](https://validatorinfo.com/networks/logos-testnet/tx/550dae320cf6b76a1e7491af2235b8f28000d01554716d17dc24a77391217927/expand) | [8140](https://validatorinfo.com/networks/logos-testnet/tx/a396cd392776d2ca30df463c7c6e2d85be4b1a22f88752312496f198e2b7ffe0/expand) | [8141](https://validatorinfo.com/networks/logos-testnet/tx/e9751d8a642301925f8dce7f74fc62020dbfd3bd4884638eb5021b50e335934f/expand) | 10 |
| `cbc73c81147b593fd2d9e37c32aed86bf6b66a332254da47024fb4b6dbbca92a` | [9034](https://validatorinfo.com/networks/logos-testnet/tx/de685d70bbe56400b31ed211f75d2b091fa897dcff57b1f4df443212cba2f251/expand) | [9035](https://validatorinfo.com/networks/logos-testnet/tx/f8a6224f7d778ef9a7132012237f81543491ed2a4ceb6a4aeffd1eb5a542807f/expand) | [9036](https://validatorinfo.com/networks/logos-testnet/tx/012eb32ca504c8ca77d35d047704ca0cadb1077f58993d4b0c8454587aa90581/expand) | 10 |

## Current claims

Every link is the corresponding public-testnet transaction; the exact hashes and capture-time RPC bodies are also in the manifest and `rpc/` directory.

| Distribution | Claim | Included transaction | LEZ block |
| --- | ---: | --- | ---: |
| A | 01 | [d33d…798b](https://validatorinfo.com/networks/logos-testnet/tx/d33d097bf6035104f7df87a3e303ec6c917ccc5b4ac32a492325293bd1ff798b/expand) | 8169 |
| A | 02 | [ccd8…3791](https://validatorinfo.com/networks/logos-testnet/tx/ccd8e3de2d2cacf2dbf330fc44a5f831bc135e681088e05cfb7dbec460ba3791/expand) | 8795 |
| A | 03 | [dab2…94be](https://validatorinfo.com/networks/logos-testnet/tx/dab2199c142358832b6560d798faac5530a9cff449b81d49b7793c467b8f94be/expand) | 8822 |
| A | 04 | [5036…b197](https://validatorinfo.com/networks/logos-testnet/tx/50364c663e900bc1a2e33dc28aa15d966e2a43cefeba3cbcf6e30d89d4c6b197/expand) | 8852 |
| A | 05 | [74ab…989c](https://validatorinfo.com/networks/logos-testnet/tx/74abdc3b13a44ac5ea7ee6693c8c4758f73ee604b5fd4e9aeb8a818cd97b989c/expand) | 8881 |
| A | 06 | [54a7…7632](https://validatorinfo.com/networks/logos-testnet/tx/54a7642e3e3cb3c53143862e7b1b0c05c35582204512c6b0ea0866c23b707632/expand) | 8911 |
| A | 07 | [c760…7139](https://validatorinfo.com/networks/logos-testnet/tx/c7607b50d7cc59f697e3e041cc003ac03df9d141964eec8f8b0889f93e087139/expand) | 8941 |
| A | 08 | [33ac…fa70](https://validatorinfo.com/networks/logos-testnet/tx/33ac0fd25fc59c3b0ffba34131e0414c7cf45c8081559ce24384689802b7fa70/expand) | 8971 |
| A | 09 | [1a8d…e4fb](https://validatorinfo.com/networks/logos-testnet/tx/1a8d2ef84dac83b94aa6345da6b1fc8e07c5b61c49a50fb6ccf2ef419769e4fb/expand) | 9000 |
| A | 10 | [6e0d…f1e2](https://validatorinfo.com/networks/logos-testnet/tx/6e0df1cae4ab6032f62f33ca8516f5aba4c05b514d3dbb2001983949dffdf1e2/expand) | 9029 |
| B | 01 | [b938…708a](https://validatorinfo.com/networks/logos-testnet/tx/b938e06ec8085f3878ab6683f769350c9067445f6560ce8687ab65bfdd9f708a/expand) | 9065 |
| B | 02 | [727c…41f3](https://validatorinfo.com/networks/logos-testnet/tx/727cdba3ca431a9abb2df1cbef82157a9acba1c18034e2a08fe93bbbd8c941f3/expand) | 9094 |
| B | 03 | [f113…3a8e](https://validatorinfo.com/networks/logos-testnet/tx/f113f0900a5cf0b7947f6ce29e7ac5ceec13aa3b77a3d2a435ad595379543a8e/expand) | 9123 |
| B | 04 | [3963…df1b](https://validatorinfo.com/networks/logos-testnet/tx/3963fb37bdeb885598a7b8968bd3ec7eb5331c779ca1faa506e9d4f052b9df1b/expand) | 9152 |
| B | 05 | [937a…dcc4](https://validatorinfo.com/networks/logos-testnet/tx/937ac7e738679848afc29ea7db265e0a100501bf77cee73bb7dfac6305fedcc4/expand) | 9180 |
| B | 06 | [0bdd…6e2a](https://validatorinfo.com/networks/logos-testnet/tx/0bdd3935114b9f40d2c79af3b6e4e0497dfeed80428cc7f8b2124a3645de6e2a/expand) | 9205 |
| B | 07 | [f1d9…590c](https://validatorinfo.com/networks/logos-testnet/tx/f1d93cc336e21193b7dfe64ddcbc0cb8c3ba0146663e8ab998b0c1827517590c/expand) | 9230 |
| B | 08 | [5944…5600](https://validatorinfo.com/networks/logos-testnet/tx/5944b7542eccc806c2788353a81ab9ec0864d2f4e7c426893d8517b582b95600/expand) | 9255 |
| B | 09 | [42a5…ee59](https://validatorinfo.com/networks/logos-testnet/tx/42a536de61a8f69429be8604cc16a1d8e662e0d34dc2e3d4530c79d9b70fee59/expand) | 9281 |
| B | 10 | [ff91…3866](https://validatorinfo.com/networks/logos-testnet/tx/ff9188d3ca86d92cfd39b1e8a0de2599af39c7309de68e408896f1912a993866/expand) | 9307 |

## Historical LP-0003 rc5 archive

Recorded on the same RPC before a later testnet reset. This archive is retained for provenance, not as current-network evidence.

### Historical summary

- Fixed program id: `218a07eb268df922ded961fefd7d035752b44d05f4bb5172305fb0bc54506989`
- Deploy tx: `b4e31be3c5f9e784295869904e217b52da6bfbe81f2146dd756f9827263537bc`
- Token id: `Public/7B4bVaNhyiJARHCpLCpw6iZJyZY8Y1GmP52AMnx6Y6uA`
- Token source account: `Public/8Uy9A512TKB57Vp2xLoEdwrVQ7Kuy3nyzbqadHBDphAF`
- Token mint tx: `09844aa49ea37e7bd55e39803979c1dddce79216c6083dac5a4ec8dac9220a00`
- Distributions: 2
- Witness-private `claim_ppe` claims: 20
- Token settlement txs: 20

All setup txs and all 40 claim/token txs below were checked with `getTransaction` at capture time.

### Historical evidence files

The witness-free verification artifacts are committed under [`docs/testnet-evidence/`](./testnet-evidence) (`b1/` = `lp0003-rc5-b1`, `c1/` = `lp0003-rc5-c1`):

- `getTransaction` verification (every setup + claim/token tx, each `found: true`): [`b1/gettransaction-*.jsonl`](./testnet-evidence/b1), [`c1/gettransaction-*.jsonl`](./testnet-evidence/c1)
- Per-claim receipts (public-execution CU = 504401, with claim + token tx ids): `docs/testnet-evidence/{b1,c1}/receipts/*.json`
- Per-claim summaries: `docs/testnet-evidence/{b1,c1}/claims.jsonl`
- Raw claim / prepare / destination logs: `docs/testnet-evidence/{b1,c1}/logs/*.log`

These artifacts carry no witness data: the eligible address, row salt, claim signature, and Merkle path do not appear in them. The transaction responses are preserved as capture-time evidence; the current RPC no longer resolves the old IDs.

The per-distribution working state (`target/distributionx-testnet-rc5-evidence{,-c1}/`) — wallet seeds, claimant keystores, and encrypted bundles — is intentionally **not** committed because it holds private keys. It is regenerated locally by the evidence run and is not needed to verify the on-chain result.

### Historical privacy path

The claim batches used `create-destination` per claimant, then `prepare-claim-tx`, then `claim` with the default PPE submit hook. The submit hook sends the `claim_ppe` instruction through `send_privacy_preserving_tx` in `scripts/local-submit.sh`. The public witness fields are local proving inputs for the PPE flow, not public transaction instruction data.

Relevant source references:

- `scripts/local-submit.sh`: `submit_claim_ppe`, `send_privacy_preserving_tx`
- `crates/distributionx-program/src/program.rs`: `claim_ppe`
- `methods/guest/src/bin/distributionx.rs`: guest-side `claim_ppe`

### Historical distributions

| Distribution | Airdrop id | Init tx | Fund tx | Funded | Claimed |
| --- | --- | --- | --- | ---: | ---: |
| `lp0003-rc5-b1` | `442ac2161fcbd709fb9f2aae55044fca43f676929ba3abc4247699ec8c533810` | `f27918090fd3c6652b3d877eca004048718c4b95502b6c8f73edc6f2f3c833de` | `46783c7b914cf3d4428c1958864acee70cc440925b91e0aa418b0e4d7dc48814` | 10 | 10 |
| `lp0003-rc5-c1` | `d02bd22cb5cc9e7b4e03df15b677da9aad2275c771264f807d446d2fd45c1734` | `10798686d95f83ed599f7168a4fb470338dd10c68eccaf60c7b6d1f43c434ad9` | `9d73cec1da90eb79208be77e2eb132490301aa750e02bde41f9c130baed37392` | 10 | 10 |

### Historical claims

| Distribution | Claim | PPE claim tx | Token settlement tx | CU |
| --- | ---: | --- | --- | ---: |
| `lp0003-rc5-b1` | 01 | `18632790129b7045ac5e08f23859d03a2a0007f03a7b835281920fff719bed23` | `89f54e3f2970a3abde3e570b5e507c84f4d1550152bf83bcd790c2ac2d6ec1c3` | 504401 |
| `lp0003-rc5-b1` | 02 | `e0a42bb79e0e55b7dbf0c22c904dfdac82c9b2459b68ce06a8def8e6f25c7326` | `0933a5db08fb7b9484e74d54953d23fb06437bd532579d5d7895783faa8de098` | 504401 |
| `lp0003-rc5-b1` | 03 | `77a17826ac6877fcfdf2d1c8f8458015abbe3db1f5dd68942bbfa5328eb794c8` | `6ed185f4ef680337dd745563611e4380ff18b3c212672d108160260c2a42e503` | 504401 |
| `lp0003-rc5-b1` | 04 | `7e602ae8ff78394bf30f72801ad5dd3d8b1bf3373457b8db0eadabdf31bb3105` | `3a53c764c93d7898a13d561b580813433ab245ab5edc5223a4e5bf390d689c5e` | 504401 |
| `lp0003-rc5-b1` | 05 | `548a28e6bcb50640d0c479e17f788bb6a092a3ab58259308de2d429b69bb1b28` | `bcf00573a7b26b0500207929521876b653f88a5539ef8ccb18f6dd3b12a8f019` | 504401 |
| `lp0003-rc5-b1` | 06 | `fdb756cb6b6c110604d811db1871480221ca48ddc51cc0b5b2721294660c65e9` | `15be5f23e10437c0e945378bdbfe90a65c950c2ab06af7f0d372102c8a2f4d5c` | 504401 |
| `lp0003-rc5-b1` | 07 | `b5203cc05ace5f8247918127c1fe388185fb55574ff6950834c5ffb646d94c90` | `04710b3b95755e88b79180c6c239cc29870e04a29b5f8812c7d0a58b9baeeeca` | 504401 |
| `lp0003-rc5-b1` | 08 | `0f38506d80f86b41d93d6f79c09eab851f7ea71788eace759271c159fa791aa2` | `a8cb9eeac394be9b5ffe26e544ee4e48839e182496dfadcec6b573d55347d815` | 504401 |
| `lp0003-rc5-b1` | 09 | `d4a35de58eef2e19bc592b1d81f1e5bab4eb642fb01b0309665c90515ceb43e3` | `c44ad3efa3f7d87fe5ab971819736a7900635d4912d1b4b7006f4a97ebd586bb` | 504401 |
| `lp0003-rc5-b1` | 10 | `7995c65f02e9141d6f2f132af598af192fd83526fe318fa3c62e0fb38ea19ad4` | `0879b14c5d4556ab55bc46137d0c188c9450bdf78ef88cfcc50fe720f009e80c` | 504401 |
| `lp0003-rc5-c1` | 01 | `5452afe34dd73569d5ade83fe18b557dfb88a2277c7f38bfe7add985857913e2` | `ecedd76d90514c1b0ab5ea69dd5daed2fa05e42759349de7d878907a24c2e2a8` | 504401 |
| `lp0003-rc5-c1` | 02 | `7aee1ebf8a187179cbaa1dc247ed12ab101dc5abf61e0a5e48fc5e5522c08ea3` | `08d614e8242b5ea11c95d3b3a2ce4fb23cb3a20f222bdfa5e9a7975a18638727` | 504401 |
| `lp0003-rc5-c1` | 03 | `53960d669e02cf1779701a5707da3136a562cd7d5c2885ea1e79743014dadb1c` | `c9fc614ec54b79581ff66c1cf3262b920b1f58dd7483210442f3f27eb5c30819` | 504401 |
| `lp0003-rc5-c1` | 04 | `134b0932a6a1ec4190f77599f59e700742f71c156e9753a8e77c60cc8355cef1` | `060cdd0ef47cd1cb7ab7127fbdedd6fd3085b793d6f2882cce8af4b80e1115bc` | 504401 |
| `lp0003-rc5-c1` | 05 | `2b1de467fdbb269de5f2fd01ec987fc5f54caccd0339cbc92673dd96f1c09bb8` | `ecfe42f1b54807d852048a4096b2e24367cd58ba316c51fa131e448139af4c63` | 504401 |
| `lp0003-rc5-c1` | 06 | `658cc5859075d1eea2fb3be4f8cb29ae7ffa574f041f1feb236f0596053a72f4` | `dd3767104f191d9fcaab0bc58e25a8198c0f82210ce7ce9a4985e929af210b27` | 504401 |
| `lp0003-rc5-c1` | 07 | `f6820319a502d1ce7a1e721989c44e8cfe6fa7b2db75bfd6a8afd72d8c0bfd10` | `ba3485c4660077ab11c9a5c1ed53e4a3f3f7ef9b0a4228197ba960f573011535` | 504401 |
| `lp0003-rc5-c1` | 08 | `b960457802dd8823d4e82436beed1356a11824197a386ea69dc1c34004cd178f` | `464af02558476b681a1b86f1282594f84fca085fe2312819db18161a9472a7f7` | 504401 |
| `lp0003-rc5-c1` | 09 | `1a6ffc648fd32d43e5111f5350b77e1e7b6693b3a5289de5f6ba888cabf88bfc` | `1f8818a36f5e3dfc5a4de2662a8620d5fb0940adf1afd04f5f84ecd343ae0c19` | 504401 |
| `lp0003-rc5-c1` | 10 | `c2a71a2d4c22da97fef895005dc4f2a774da5b82e9985c6413cdccdfab6dc0bf` | `33e0bb36317b1240f89877849a48933ecd5c8e42a551d38e5f5f5da82b40b5fa` | 504401 |

### Historical capture-time verification counts

- Setup txs: 6/6 found by `getTransaction`
- `lp0003-rc5-b1` claim/token txs: 20/20 found by `getTransaction`
- `lp0003-rc5-c1` claim/token txs: 20/20 found by `getTransaction`
