# LP-0003 rc5 PPE testnet evidence

Recorded on the live LEZ testnet RPC: `https://testnet.lez.logos.co`.

## Summary

- Fixed program id: `218a07eb268df922ded961fefd7d035752b44d05f4bb5172305fb0bc54506989`
- Deploy tx: `b4e31be3c5f9e784295869904e217b52da6bfbe81f2146dd756f9827263537bc`
- Token id: `Public/7B4bVaNhyiJARHCpLCpw6iZJyZY8Y1GmP52AMnx6Y6uA`
- Token source account: `Public/8Uy9A512TKB57Vp2xLoEdwrVQ7Kuy3nyzbqadHBDphAF`
- Token mint tx: `09844aa49ea37e7bd55e39803979c1dddce79216c6083dac5a4ec8dac9220a00`
- Distributions: 2
- Witness-private `claim_ppe` claims: 20
- Token settlement txs: 20

All setup txs and all 40 claim/token txs below were checked with `getTransaction`.

## Evidence files

- First distribution state: `target/distributionx-testnet-rc5-evidence`
- Second distribution state: `target/distributionx-testnet-rc5-evidence-c1`
- First distribution tx verification: `target/distributionx-testnet-rc5-evidence/evidence/gettransaction-b1.jsonl`
- Second distribution tx verification: `target/distributionx-testnet-rc5-evidence-c1/evidence/gettransaction-c1.jsonl`
- Setup tx verification: `target/distributionx-testnet-rc5-evidence/evidence/gettransaction-setup.jsonl`
- Per-claim receipts: `target/distributionx-testnet-rc5-evidence*/evidence/receipts/*.json`
- Raw claim logs: `target/distributionx-testnet-rc5-evidence*/evidence/logs/*.claim.log`

## Privacy path

The claim batches used `create-destination` per claimant, then `prepare-claim-tx`, then `claim` with the default PPE submit hook. The submit hook sends the `claim_ppe` instruction through `send_privacy_preserving_tx` in `scripts/local-submit.sh`. The public witness fields are local proving inputs for the PPE flow, not public transaction instruction data.

Relevant source references:

- `scripts/local-submit.sh`: `submit_claim_ppe`, `send_privacy_preserving_tx`
- `crates/distributionx-program/src/program.rs`: `claim_ppe`
- `methods/guest/src/bin/distributionx.rs`: guest-side `claim_ppe`

## Distributions

| Distribution | Airdrop id | Init tx | Fund tx | Funded | Claimed |
| --- | --- | --- | --- | ---: | ---: |
| `lp0003-rc5-b1` | `442ac2161fcbd709fb9f2aae55044fca43f676929ba3abc4247699ec8c533810` | `f27918090fd3c6652b3d877eca004048718c4b95502b6c8f73edc6f2f3c833de` | `46783c7b914cf3d4428c1958864acee70cc440925b91e0aa418b0e4d7dc48814` | 10 | 10 |
| `lp0003-rc5-c1` | `d02bd22cb5cc9e7b4e03df15b677da9aad2275c771264f807d446d2fd45c1734` | `10798686d95f83ed599f7168a4fb470338dd10c68eccaf60c7b6d1f43c434ad9` | `9d73cec1da90eb79208be77e2eb132490301aa750e02bde41f9c130baed37392` | 10 | 10 |

## Claims

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

## Verification counts

- Setup txs: 6/6 found by `getTransaction`
- `lp0003-rc5-b1` claim/token txs: 20/20 found by `getTransaction`
- `lp0003-rc5-c1` claim/token txs: 20/20 found by `getTransaction`
