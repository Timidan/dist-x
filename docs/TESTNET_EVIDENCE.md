# Current LEZ public-testnet evidence

Verified on `https://testnet.lez.logos.co` at `2026-08-15T22:39:56Z`. The endpoint was healthy and its built-ins matched pinned LEZ v0.2.4 commit `47eba256479f6f785acbd138834340703cd03401`; the endpoint does not expose an exact server revision.

## Current run summary

- Release and execution source: `v0.1.0` / `74f81ab9ee74ba533d3a8fa01cba9f67153f6385`
- Read-only verifier source: `fb61565fd7f8d3409ff65f7e2f4a7297cd56078a`
- Immutable quote SHA-256: `a87b55a6f683be2e3c7570e939cb4ab928b5730f627723396def98a41d8756de`
- Program id: `4bf08c88a91871ecf69ff08af42591a597c51142cbc1f9c6fbbb7d2e888d9ee3`
- [Deploy transaction](https://explorer.testnet.lez.logos.co/transaction/2186b9ba9e95e4926f2800e88b5d0653bda3d1669414f0a19c6daf0798576181): `2186b9ba9e95e4926f2800e88b5d0653bda3d1669414f0a19c6daf0798576181`, LEZ block 8138
- Two native-token distributions, ten included `claim_ppe` claims each
- Approved writes: 5-write smoke + 22-write finish = 27 unique included transactions
- Proof mode: `RISC0_DEV_MODE=0`; custom-token settlement disabled; no close transaction

The machine-readable source of truth is the [public manifest](./testnet-evidence/v0.1.0/manifest.json). Its sibling [`rpc/`](./testnet-evidence/v0.1.0/rpc) directory contains all 27 capture-time `getTransaction` responses. Only this scrubbed public tree is committed; claimant wallets, eligibility rows, proofs, destinations, serialized transactions, receipts, and quote-time working state remain private.

## Current distributions

| Distribution id | Init | Prefund | Fund | Claims |
| --- | --- | --- | --- | ---: |
| `205a0aad874f9271d886959a0ea11f92f2c0888078e88c2a93f9836d7b1ab9f1` | [8139](https://explorer.testnet.lez.logos.co/transaction/550dae320cf6b76a1e7491af2235b8f28000d01554716d17dc24a77391217927) | [8140](https://explorer.testnet.lez.logos.co/transaction/a396cd392776d2ca30df463c7c6e2d85be4b1a22f88752312496f198e2b7ffe0) | [8141](https://explorer.testnet.lez.logos.co/transaction/e9751d8a642301925f8dce7f74fc62020dbfd3bd4884638eb5021b50e335934f) | 10 |
| `cbc73c81147b593fd2d9e37c32aed86bf6b66a332254da47024fb4b6dbbca92a` | [9034](https://explorer.testnet.lez.logos.co/transaction/de685d70bbe56400b31ed211f75d2b091fa897dcff57b1f4df443212cba2f251) | [9035](https://explorer.testnet.lez.logos.co/transaction/f8a6224f7d778ef9a7132012237f81543491ed2a4ceb6a4aeffd1eb5a542807f) | [9036](https://explorer.testnet.lez.logos.co/transaction/012eb32ca504c8ca77d35d047704ca0cadb1077f58993d4b0c8454587aa90581) | 10 |

## Current claims

Every link is the corresponding public-testnet transaction; the exact hashes and capture-time RPC bodies are also in the manifest and `rpc/` directory.

| Distribution | Claim | Included transaction | LEZ block |
| --- | ---: | --- | ---: |
| A | 01 | [d33d…798b](https://explorer.testnet.lez.logos.co/transaction/d33d097bf6035104f7df87a3e303ec6c917ccc5b4ac32a492325293bd1ff798b) | 8169 |
| A | 02 | [ccd8…3791](https://explorer.testnet.lez.logos.co/transaction/ccd8e3de2d2cacf2dbf330fc44a5f831bc135e681088e05cfb7dbec460ba3791) | 8795 |
| A | 03 | [dab2…94be](https://explorer.testnet.lez.logos.co/transaction/dab2199c142358832b6560d798faac5530a9cff449b81d49b7793c467b8f94be) | 8822 |
| A | 04 | [5036…b197](https://explorer.testnet.lez.logos.co/transaction/50364c663e900bc1a2e33dc28aa15d966e2a43cefeba3cbcf6e30d89d4c6b197) | 8852 |
| A | 05 | [74ab…989c](https://explorer.testnet.lez.logos.co/transaction/74abdc3b13a44ac5ea7ee6693c8c4758f73ee604b5fd4e9aeb8a818cd97b989c) | 8881 |
| A | 06 | [54a7…7632](https://explorer.testnet.lez.logos.co/transaction/54a7642e3e3cb3c53143862e7b1b0c05c35582204512c6b0ea0866c23b707632) | 8911 |
| A | 07 | [c760…7139](https://explorer.testnet.lez.logos.co/transaction/c7607b50d7cc59f697e3e041cc003ac03df9d141964eec8f8b0889f93e087139) | 8941 |
| A | 08 | [33ac…fa70](https://explorer.testnet.lez.logos.co/transaction/33ac0fd25fc59c3b0ffba34131e0414c7cf45c8081559ce24384689802b7fa70) | 8971 |
| A | 09 | [1a8d…e4fb](https://explorer.testnet.lez.logos.co/transaction/1a8d2ef84dac83b94aa6345da6b1fc8e07c5b61c49a50fb6ccf2ef419769e4fb) | 9000 |
| A | 10 | [6e0d…f1e2](https://explorer.testnet.lez.logos.co/transaction/6e0df1cae4ab6032f62f33ca8516f5aba4c05b514d3dbb2001983949dffdf1e2) | 9029 |
| B | 01 | [b938…708a](https://explorer.testnet.lez.logos.co/transaction/b938e06ec8085f3878ab6683f769350c9067445f6560ce8687ab65bfdd9f708a) | 9065 |
| B | 02 | [727c…41f3](https://explorer.testnet.lez.logos.co/transaction/727cdba3ca431a9abb2df1cbef82157a9acba1c18034e2a08fe93bbbd8c941f3) | 9094 |
| B | 03 | [f113…3a8e](https://explorer.testnet.lez.logos.co/transaction/f113f0900a5cf0b7947f6ce29e7ac5ceec13aa3b77a3d2a435ad595379543a8e) | 9123 |
| B | 04 | [3963…df1b](https://explorer.testnet.lez.logos.co/transaction/3963fb37bdeb885598a7b8968bd3ec7eb5331c779ca1faa506e9d4f052b9df1b) | 9152 |
| B | 05 | [937a…dcc4](https://explorer.testnet.lez.logos.co/transaction/937ac7e738679848afc29ea7db265e0a100501bf77cee73bb7dfac6305fedcc4) | 9180 |
| B | 06 | [0bdd…6e2a](https://explorer.testnet.lez.logos.co/transaction/0bdd3935114b9f40d2c79af3b6e4e0497dfeed80428cc7f8b2124a3645de6e2a) | 9205 |
| B | 07 | [f1d9…590c](https://explorer.testnet.lez.logos.co/transaction/f1d93cc336e21193b7dfe64ddcbc0cb8c3ba0146663e8ab998b0c1827517590c) | 9230 |
| B | 08 | [5944…5600](https://explorer.testnet.lez.logos.co/transaction/5944b7542eccc806c2788353a81ab9ec0864d2f4e7c426893d8517b582b95600) | 9255 |
| B | 09 | [42a5…ee59](https://explorer.testnet.lez.logos.co/transaction/42a536de61a8f69429be8604cc16a1d8e662e0d34dc2e3d4530c79d9b70fee59) | 9281 |
| B | 10 | [ff91…3866](https://explorer.testnet.lez.logos.co/transaction/ff9188d3ca86d92cfd39b1e8a0de2599af39c7309de68e408896f1912a993866) | 9307 |
