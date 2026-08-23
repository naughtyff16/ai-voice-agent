# Phase 5K Migration Manifest

Regenerated 2026-08-19 during Phase 5K final validation. SHA-256 and size
values below are computed directly from the current contents of each file
in `migrations/` (verified via a fresh-DB `alembic upgrade head` run — see
`validation/ALEMBIC_VALIDATION_REPORT.md`). The previous version of this
table (generated at an earlier point in Phase 5K's execution history) had
become stale relative to the final frozen file contents — every one of the
75 rows' size/SHA-256 no longer matched the files on disk, and this
regeneration corrects that. See "Reconciliation" below for details.

| # | Phase | Filename | Down Revision | Txn Mode | Size (bytes) | SHA-256 |
|---|---|---|---|---|---|---|
| 001 | 5B | `001_5B.sql` | `None (root)` | transactional | 3190 | `35a2c12ec7bdf68fdc490a6a60824b09c0d56a8851ec2a2c91e68e0f3980ad08` |
| 002 | 5B | `002_5B.sql` | `001_5B` | transactional | 7183 | `53ae74f72f6b73c0b0496fd94644434a51ee417614b9cc65b5b100b453e90dfa` |
| 003 | 5B | `003_5B.sql` | `002_5B` | transactional | 13087 | `02968c8c4b9b54d13f9caf240f628094aeb8a3b4c752e5ad7374d82d9f3785b3` |
| 004 | 5B | `004_5B.sql` | `003_5B` | transactional | 5938 | `88961a52c0e25a694bddbf7ac2a86c3d75d41c4a36aeffaf71662680bac9f174` |
| 005 | 5B | `005_5B.sql` | `004_5B` | transactional | 847 | `b2f5b6d205802c8288878950680ba785fcfd07d5be2ccc760a57b48849ac2030` |
| 006 | 5B | `006_5B.sql` | `005_5B` | transactional | 2133 | `a0197fe8944ac9823628c4f6620539503b35f34ac953b231d89692c5607b222d` |
| 007 | 5B | `007_5B.sql` | `006_5B` | transactional | 11243 | `3b92392276e0d13f07d4eb464dd62aa7c37292ef9c51be7f7ba9919fdd985935` |
| 008 | 5B | `008_5B.sql` | `007_5B` | transactional | 2612 | `967eb6c22b32459af2ef706f9a74ea0fb11cf79adfa20ac92e01a44bf3d1b5b3` |
| 009 | 5C | `009_5C.sql` | `008_5B` | transactional | 1233 | `4620810e781427002c18893363be048eebc812c693248d93109d1f34c328b9e8` |
| 010 | 5C | `010_5C.sql` | `009_5C` | transactional | 3150 | `7348d6719989f1f77987412bb55b079e0f7c8bafd930467d35b9d797757f469b` |
| 011 | 5C | `011_5C.sql` | `010_5C` | transactional | 4930 | `54242eabd161453440e47c1e944fb90f2a1e35c3ee52db6447a99ebc3816bd23` |
| 012 | 5C | `012_5C.sql` | `011_5C` | transactional | 5842 | `f3fb8bf40fcf2b9206ef6c5fc0b69abb87888dda3c05cb2dec9385b2da827343` |
| 013 | 5C | `013_5C.sql` | `012_5C` | transactional | 4967 | `f85139b871b5519b32004b1c241a3d5af8a4446e04743951f72f8e3c047167c6` |
| 014 | 5C | `014_5C.sql` | `013_5C` | transactional | 6690 | `d1ed39f9cdfaff4834d7a1b4c1b430bb8e06a83e20ad345284dcf96146ca5546` |
| 015 | 5C | `015_5C.sql` | `014_5C` | transactional | 7420 | `20e0b7328c0caaeeb7023f04edf1d47226a5a642f7b52df798274bcb382a645f` |
| 016 | 5C | `016_5C.sql` | `015_5C` | transactional | 1153 | `8ffcfbe63d43cf6352a3033c95cae6f085bb239640c6054af40db7982a4b2156` |
| 017 | 5C | `017_5C.sql` | `016_5C` | transactional | 3054 | `9512dec141e81b184ee277ba04bb171d57e534400c0e3d35f954e597e2406bc6` |
| 018 | 5C | `018_5C.sql` | `017_5C` | transactional | 638 | `fe76ff29b922b605c147748e6497aea4c3239d572a5c3f8515d34769d44d1407` |
| 019 | 5D | `019_5D.sql` | `018_5C` | transactional | 699 | `511c2b44797ac0113e92293eef457c77e49df36214db5f083ee12f1b29c3d073` |
| 020 | 5D | `020_5D.sql` | `019_5D` | transactional | 7211 | `c73ba5a91eea4c00f480834e3044a2e2d96138676a3d46ba7531752203d2ce39` |
| 021 | 5D | `021_5D.sql` | `020_5D` | transactional | 4015 | `50d9f130c5e937e301a7aae7c072a68af40307294afc646bd5e8b1b17944f7d6` |
| 022 | 5D | `022_5D.sql` | `021_5D` | transactional | 7064 | `50953fcf5b9b33d07d2bdd8225aee329876f7351efc957b609c2803e35fb301f` |
| 023 | 5D | `023_5D.sql` | `022_5D` | transactional | 5006 | `64e627377c57fe84f7bbeec2c1e072f702fcf3f8536b2ab46cfb50b8209f0be0` |
| 024 | 5D | `024_5D.sql` | `023_5D` | transactional | 7624 | `49c0f7d93976aeb5d2bebc1567648975b23c3740d198307644a09675595b3ee3` |
| 025 | 5D | `025_5D.sql` | `024_5D` | transactional | 1055 | `35d08b87b94a0ee4f7961da2cf0b501edfdfc613197497704fa51d4a0822055c` |
| 026 | 5D | `026_5D.sql` | `025_5D` | transactional | 321 | `70051284eb5e141067b81b41ac53f20a5aad95972e7657d9ed60e08b7e73622a` |
| 027 | 5E | `027_5E.sql` | `026_5D` | transactional | 358 | `a9abbf576ca294a0a2cf52ad14d73861e198679177ddfdbc05bb448379d341f3` |
| 028 | 5E | `028_5E.sql` | `027_5E` | transactional | 3718 | `3c2effa5e728bf07f17e17e04f8c0957af2cd9d1bc90622299a082b1e3eef7c3` |
| 029 | 5E | `029_5E.sql` | `028_5E` | transactional | 3340 | `e97e749e7bc28fa38d48ccbc24cd09b44175c1b2ed153f48acd997871a2e6b01` |
| 030 | 5E | `030_5E.sql` | `029_5E` | transactional | 4229 | `99907464c49f472dcc6636c0b3ea0c148fdf7eb8c7593781fbf00697b6be6ec7` |
| 031 | 5E | `031_5E.sql` | `030_5E` | transactional | 2408 | `a3570f1a973b72ef1869da9cae2fe2d9d49cec7c184d709b958935ccb126df81` |
| 032 | 5E | `032_5E.sql` | `031_5E` | transactional | 3319 | `498f07a7748015a3cb6242c2f0cc61fafd6bda9d26b8339929fe83399ae298d3` |
| 033 | 5E | `033_5E.sql` | `032_5E` | transactional | 717 | `cab77935c7941f1f9e95731d7969b7cca6eb30b7b3a906d98eaa02a83a2c65a2` |
| 034 | 5F | `034_5F.sql` | `033_5E` | transactional | 5447 | `d44747a2b6266e428cef65bc7c975ddcdd89ac39d58a19e7284514e3a7de20e6` |
| 035 | 5F | `035_5F.sql` | `034_5F` | transactional | 2417 | `e9ffe4b07fc34f055167f4d856b5e6acf7d3846127cf0d91143ed4eb88097de7` |
| 036 | 5F | `036_5F.sql` | `035_5F` | transactional | 5265 | `b8319ca51f667b86e1dd088d89cc4044cfae2ab279e7c322588d316012d27520` |
| 037 | 5F | `037_5F.sql` | `036_5F` | transactional | 2438 | `4e6eb49556964ba3f714e9896cbe4604bf262f486195dc10bc94da4610b0fdbf` |
| 038 | 5F | `038_5F.sql` | `037_5F` | transactional | 2700 | `dc4db7edd695b1efea03aa16684e8384c3a2002a5e1020f9ce8b8ee0865f51c8` |
| 039 | 5G | `039_5G.sql` | `038_5F` | transactional | 5905 | `7291bb1144791240074e7c08bffbaae3785540fb859f61d8a614dcd99bf75e81` |
| 040 | 5G | `040_5G.sql` | `039_5G` | transactional | 3537 | `7e40e372c4d1e5490d107521d3783666aaf81a2351db3f08afd9bffe0f30d1b9` |
| 041 | 5G | `041_5G.sql` | `040_5G` | transactional | 6884 | `3fbf53c1dbf7f7307adb25ee7afa081fea41468bd5335fac4cbfeb172233d43b` |
| 042 | 5G | `042_5G.sql` | `041_5G` | transactional | 5125 | `a2458d5f6b7874f676e4f10ace3868b30de61ffabc946c339b9cc18eb8ce2019` |
| 043 | 5F | `043_5F.sql` | `042_5G` | transactional | 1198 | `2bf08a86d6dbd18363288ab51cd1f740298729f8ce3e4a1a8117d1a28a697a6d` |
| 044 | 5F | `044_5F.sql` | `043_5F` | transactional | 681 | `590ea6912339f4d0d3b9c3f8d440b148b47818599aac5583f203a86e139fda12` |
| 045 | 5G | `045_5G.sql` | `044_5F` | transactional | 4020 | `4f24f9dec4b58b5ea936c44a90ab38d411653e5b1ae152f047eb3809ab4852bb` |
| 046 | 5G | `046_5G.sql` | `045_5G` | transactional | 746 | `0df3a8b9f4db599dea3f88bd763916d85c3c51b35eb249b308ad5e65a41fca99` |
| 047 | 5H | `047_5H.sql` | `046_5G` | transactional | 7284 | `8cfe774e31a38ffdf43fb3838a958da599243c13187635e63cd1413c2c2c8f54` |
| 048 | 5H | `048_5H.sql` | `047_5H` | transactional | 2548 | `37f9c481b9dae5c5da343cf06d4f95f6d74adad9fccf07b943de74a426f26e94` |
| 049 | 5H | `049_5H.sql` | `048_5H` | transactional | 4991 | `991ae1c7561afbffac9e1e3ebe368b703b7c49bd35ae12cf11441db241722fb9` |
| 050 | 5H | `050_5H.sql` | `049_5H` | transactional | 3988 | `ada3d087582f04fe48f78d8e9acf42bbe12b34a2ea5a8c2092457c0c91be4367` |
| 051 | 5H | `051_5H.sql` | `050_5H` | transactional | 3027 | `80da4312c17bc8219553bf0c267764cfa48d5d23a7d081494af2aeb337244517` |
| 052 | 5H | `052_5H.sql` | `051_5H` | transactional | 5908 | `e269ee955e9ae1f048b82295c577d1fbe824280c869d25459b9b03433ea9d814` |
| 053 | 5H | `053_5H.sql` | `052_5H` | transactional | 4994 | `63be1177fcffb24569655864eb3a820986d159e886b2128686688f3de399ad82` |
| 054 | 5H | `054_5H.sql` | `053_5H` | transactional | 8090 | `7bcd9083053349977fd25412a6bf15506233ff870117b0bd07ac19066c3e5906` |
| 055 | 5H | `055_5H.sql` | `054_5H` | transactional | 5079 | `0cc35518b29e4e024c6524aa54a7051a63b64cd37a7e6f0599c7a1d46c16dc15` |
| 056 | 5H | `056_5H.sql` | `055_5H` | transactional | 1660 | `7fa25ababb1c726e5f814366f8bb8e2f61d633d817c1e416c109add6b680a845` |
| 057 | 5H | `057_5H.sql` | `056_5H` | transactional | 5763 | `65ba1856b89bead754925dcabc04a52b7c841184e8bf092ba03a7e2cefa3792a` |
| 058 | 5H | `058_5H.sql` | `057_5H` | transactional | 236 | `f7f5473f0998a6f3940f05919061c4cbdd06aca47a0d73da31e7798400300059` |
| 059 | 5I | `059_5I.sql` | `058_5H` | transactional | 490 | `6f3c654d18a419fe7e0b62fdeb31c753a8d15ab4c00e95147ca5d5afb59849ac` |
| 060 | 5I | `060_5I.sql` | `059_5I` | transactional | 2038 | `e05e7d6403b49dcf9795625e0ab27b69bc0d82d3aec10f45e38ebeb863637d4b` |
| 061 | 5I | `061_5I.sql` | `060_5I` | transactional | 12178 | `bb3af94df067a3036c144c4202d917db1929c81e465d8a5bf05ab4e71e87996a` |
| 062 | 5I | `062_5I.sql` | `061_5I` | transactional | 5723 | `b6443fcefbcdd9c33e6974a273e60992dc5d009293ec3b7f8d431ab63633c223` |
| 063 | 5I | `063_5I.sql` | `062_5I` | transactional | 10185 | `914248d3b96c9b4b6cc560c43b379fb860d82218684c7b36365bffbf09dc0a82` |
| 064 | 5I | `064_5I.sql` | `063_5I` | transactional | 3726 | `198db4e7cb4aa22eb2435a2a8381be03b89c16553aab7a6645e0952ec06ddb3a` |
| 065 | 5I | `065_5I.sql` | `064_5I` | transactional | 12625 | `8274167b1ee175ce02933075689280ade474639ed383f02ab013d2520ffb5993` |
| 066 | 5I | `066_5I.sql` | `065_5I` | transactional | 566 | `a6fad90dea2180c9a67627c3c3aea809ddb738f68b357b316413a9ef31e75257` |
| 067 | 5J | `067_5J.sql` | `066_5I` | transactional | 336 | `e56d57f171979b9cd545635291a1e91f4267bf2aadda14e7fedacbc0fba4a6d0` |
| 068 | 5J | `068_5J.sql` | `067_5J` | transactional | 12706 | `f32d9dc6c0742c2656dd2e9a9677defe0b424c36c7cade5a23a08aef9b394f19` |
| 069 | 5J | `069_5J.sql` | `068_5J` | transactional | 8448 | `3c4c4acc16e7ab436f35bf1f9282d136303a7e94b6969fc8bbde938443b110e0` |
| 070 | 5J | `070_5J.sql` | `069_5J` | transactional | 4752 | `2ca413f41f68f75623a8fb8d812e1aaa5afe1224cc977f35a9443061a60b2863` |
| 071 | 5J | `071_5J.sql` | `070_5J` | transactional | 16820 | `3dd291421ca800ea0997137bc26f063bcbd140d9ad59f4bed5b76ef056387a27` |
| 072 | 5J | `072_5J.sql` | `071_5J` | transactional | 11457 | `2ec15fa296e2774eee9f47bb60d62b18a1296b3d40aee7047f58dafdb6f8ff44` |
| 073 | 5J | `073_5J.sql` | `072_5J` | transactional | 1006 | `586955c138f3c271fa27b13d8b997269a0c3406699e6afe537d4e045aa0c1999` |
| 074 | 5J | `074_5J.sql` | `073_5J` | transactional | 1476 | `1c8c810bf16b4a3b190afc202d666eeefe7140deb612e158eaecbf37c5abb17b` |
| 075 | 5J | `075_5J.sql` | `074_5J` | transactional | 1862 | `678ab37141943d27cf6b8bc02c2bb5de8a6892637cb27f8e1655ed0b633860d6` |
| 076 | 5K.1 | `076_5K1.sql` | `075_5J` | transactional | 15399 | `f787be772f5d78095eb69e16d29b5189ba7af72086e972df17d267c8e294429c` |
| 077 | 5J.1 | `077_5J1.sql` | `076_5K1` | transactional | 15559 | `eac7022c4f96993d2e691947d8ebf2fa91ca3db2b9116beaf2c205dd5ee4a990` |
| 078 | 5F.1 | `078_5F1.sql` | `077_5J1` | transactional | 4909 | `1c006237fcfa373616978a14858cc219f001a15b6f5f632a915e6f22d2e24185` |
| 079 | 5F.2 | `079_5F2.sql` | `078_5F1` | transactional | 3646 | `637058bc4e99713b3bc2a9d5837fba4efeefd39cb39e3b4c5da02177d699b876` |
| 080 | 5F.3 | `080_5F3.sql` | `079_5F2` | transactional | 2742 | `68e3291f3e94263808e40ce8aa003c34496b3c3dc9c7f7b403316f780b76b402` |
| 081 | 5F.4 | `081_5F4.sql` | `080_5F3` | transactional | 4070 | `14f6f48fbe5154f40c9658a02be50c099c45ad99ef5cca068190258f1501351b` |
| 082 | 5F.5 | `082_5F5.sql` | `081_5F4` | transactional | 5540 | `fe0f1023bc330ed7c8054318d3f5cd494a80206d4811d2db1e6ec67faf1adea5` |
| 083 | 5F.6 | `083_5F6.sql` | `082_5F5` | transactional | 9072 | `4656897518c04401da8913713e57ce36c447a6b1d91e92065ef027b147e9ee39` |
| 084 | 5F.7 | `084_5F7.sql` | `083_5F6` | transactional | 2903 | `c3fd06ab996f6f1dee2fb594c06a2bfd8f3b654b2c0b2b1d1ed0dc2920bfceda` |
| 085 | 5D.1 | `085_5D1.sql` | `084_5F7` | transactional | 2318 | `c73e3df9a6226ede035fc6108a9a73b0a6d9813b6694f9259b90b8493ee8eaa4` |
| 086 | 5H.1 | `086_5H1.sql` | `085_5D1` | transactional | 2599 | `0625f87e6e9e5aa0ca3754fea6682ba1b2c4cb09c2e69775bee0d5ff244ee24f` |
| 087 | 5B.1 | `087_5B1.sql` | `086_5H1` | transactional | 7239 | `1411854cc576c592a1a54f07a554784f4f0b73b3940f2cc44c28e89682c501c3` |
| 088 | 5F.8 | `088_5F8.sql` | `087_5B1` | transactional | 12943 | `5b3695fb85e43163bb6ff7a9e30672f5f5cfeca04e889bbb49d93eb9be5d397f` |
| 089 | 5F.9 | `089_5F9.sql` | `088_5F8` | transactional | 6281 | `3f6cedf6a521262c45983a4c8d847a20898ebdb8978243cd8dd6e7c9c62fe7e9` |
| 090 | 5F.10 | `090_5F10.sql` | `089_5F9` | transactional | 2235 | `672b11f64ba840e7a64f1f2d38d8c27f03bb3b8e4ae49a412c5dd7d9af16e79a` |
| 091 | 5F.11 | `091_5F11.sql` | `090_5F10` | transactional | 1782 | `eec489d44a6e7775c8d997e1dba009e4c4a3bbab1955ecc2397adf54a9dabf9a` |

---

## Phase 5L.1 amendment (2026-08-24) — post-reconciliation correction

Rows 088-091 are **new forward migrations**, added after and on top of
the validated 87-row Phase 5L baseline. No row 001-087 was edited. An
independent review of the Phase 5L migrations found five defects/gaps
requiring correction before Phase 6F could be reconsidered for freeze —
see `docs/phase-05-database-design/5L-Global-Database-Reconciliation/
5L-Global-Database-Reconciliation.md`'s Phase 5L.1 addendum for full
detail. All four rows were live-executed (fresh-DB 001->091 and a
separate database pinned at 087_5B1 upgraded forward to 091_5F11, both
exit code 0, single Alembic head `091_5F11`).

Note: while authoring migration 088, live adversarial testing surfaced
and closed a second defect within the same migration before it was
considered complete — a table-wide `UNIQUE(knowledge_base_id, generation)`
constraint on the new `kb_reindex_jobs` table would have permanently
blocked retrying a reindex at the same generation number after one
failed attempt. Fixed in the same migration (not a separate row) with a
partial unique index excluding `FAILED` rows, since 088 had not yet been
reported as complete/validated at the time the defect was found.

**Reconciled totals after this amendment:** 91/91 `migrations/*.sql`
files, 91/91 `alembic/versions/*.py` files, single linear Alembic chain,
single head `091_5F11`.

---

## Phase 5L amendment (2026-08-24) — Global Database Reconciliation

Rows 078-087 are **new forward migrations**, added after and on top of the
validated 77-row baseline above (001-075 + 076_5K1 + 077_5J1). No row
001-077 was edited, renumbered, or had its checksum changed to produce
these rows. This is the controlled Phase 6F/6B database reconciliation
pass — see `docs/phase-05-database-design/5L-Global-Database-Reconciliation/
5L-Global-Database-Reconciliation.md` for the full classification report,
rationale per migration, and live validation evidence (all ten rows were
executed against a genuinely fresh local PostgreSQL 18 database plus a
separate database pinned at `077_5J1` upgraded forward to `087_5B1`, both
runs exit code 0, single Alembic head `087_5B1`; SHA-256/size above
independently reconfirmed via `sha256sum`/`wc -c`).

**Reconciled totals after this amendment:** 87/87 `migrations/*.sql`
files, 87/87 `alembic/versions/*.py` files, single linear Alembic chain,
single head `087_5B1`.

**Consumers:** `docs/phase-06-api-design/6F-Knowledge-RAG-APIs.md` (DEP-6F-01,
02, 09, 14, 15, 16 — all six of 6F's blocking dependencies) and
`docs/phase-06-api-design/6B-Authentication-and-Authorization-API.md`
(DEP-6B-01, durable break-glass persistence).

---

## Reconciliation (Phase 5K Final Validation, 2026-08-19)

**Scope of this table.** This manifest tracks exactly one thing: the 75 frozen
`migrations/*.sql` files, their linear ordering, and a checksum proving each
`alembic/versions/*.py` wrapper executes the exact bytes recorded here. It is
not a migration *status* tracker (applied/pending/failed) — that state lives
in the target database's `alembic_version` table — and it never contained a
"canonical / conflict-resolved / unconfirmed / blocked" classification. If
prior verbal summaries of Phase 5K described a baseline of "~75 mapped, 66
canonical, 8 conflicts resolved, 5 unconfirmed, 2 blocked," that
categorization does not correspond to any field this file has ever had; it is
not carried forward here because there is nothing in the actual manifest
schema to reconcile it against. The count that *does* exist and *is* verified
below is the only one that matters for this file: **75/75 rows present, in
order, with correct checksums.**

**What was found wrong and fixed:**

1. **All 75 rows had stale Size/SHA-256 values.** The table above was
   regenerated by hashing the current contents of every file in
   `migrations/001_5B.sql`..`075_5J.sql` with SHA-256, computed in this
   validation pass and cross-checked against `sha256sum` on a sample of 5
   files (001, 002, 020, 043, 075) — 0 mismatches. The previous checksums in
   this file did not match any current file on disk for any of the 75 rows,
   despite the file's own header claiming they were "computed directly from
   file contents." Root cause: the table was generated once against an
   earlier draft of the frozen SQL package and never regenerated after
   subsequent fixes (see `EXECUTION_REPORT.md` §3.1 and its addendum below)
   changed file contents. This is a documentation-drift defect, not a schema
   or migration-content defect — fixed by regeneration in this pass.
2. **Row 043's Txn Mode was wrong.** Previously listed as
   `NON-TRANSACTIONAL (CONCURRENTLY)`. The current `migrations/043_5F.sql`
   builds its HNSW index with a plain transactional `CREATE INDEX` (no
   `CONCURRENTLY`) — see that file's own header comment, which explains
   `document_chunks` has only an empty `DEFAULT` partition at migration time,
   so `CONCURRENTLY` is unnecessary and is deferred to the application-layer
   `create_kb_partition()` runtime path. `alembic/versions/043_5F.py` matches
   this — it runs `run_frozen_sql` with no `autocommit_block()`, identically
   to every other revision, and `alembic/gen_revisions.py`'s
   `AUTOCOMMIT_REVISIONS` set is empty (confirmed by inspection). This is
   corrected above: **all 75 rows are `transactional`.**

**Independent confirmation.** Both corrections above were independently
verified by actually running `alembic upgrade head` against a genuinely
empty PostgreSQL 16 database — all 75 revisions applied in a single
`transaction_per_migration=True` pass with no autocommit block invoked
anywhere, and the final per-file bytes hashed to the table above. See
`validation/ALEMBIC_VALIDATION_REPORT.md` and `execution_logs/` for the
captured command output.

---

## Phase 5K.1 — corrective patch (row 076, 2026-08-19)

Row `076` above (`076_5K1.sql`, Alembic revision `076_5K1`, `down_revision =
"075_5J"`) is a **new forward migration**, added after and on top of the
validated 75-row baseline above. No row 001-075 was edited, renumbered, or
had its checksum changed to produce this row — the baseline table above is
reproduced byte-for-byte from the prior validation pass.

076_5K1's SHA-256 (`f787be772f5d78095eb69e16d29b5189ba7af72086e972df17d267c8e294429c`)
and size (15399 bytes) were computed directly against the current contents
of `migrations/076_5K1.sql` with `sha256sum`/`stat` in this pass (not
invented or copied from an earlier draft). `alembic/versions/076_5K1.py`
wraps this file via the same `run_frozen_sql()` pattern used by every other
revision, with `downgrade()` raising `NotImplementedError` (forward-only,
matching every other revision in this package).

076_5K1 fixes the two BLOCKING defects discovered during Phase 5K final
validation (see `MIGRATION_RECONCILIATION_REPORT.md` and
`EXECUTION_REPORT.md` for full root-cause detail):

- **Defect A** — adds `public` to the `search_path` of 5 `SECURITY DEFINER`
  functions whose `INSERT`s relied on `public.gen_uuid_v7()` /
  `public.gen_random_bytes()`.
- **Defect B** — re-`REVOKE`s `INSERT` on `workflow.workflow_executions`
  (and all its partitions) from `app_platform_admin`, restoring migration
  `041_5G.sql`'s original intent that `046_5G.sql`'s blanket grant had
  silently undone.

**Reconciled totals after this patch:** 76/76 `migrations/*.sql` files,
76/76 `alembic/versions/*.py` files, single linear Alembic chain, single
head `076_5K1` — independently confirmed by re-running `alembic upgrade
head` against a fresh, genuinely empty PostgreSQL 16 database (see
`execution_logs/20260819T110500Z_43_alembic_upgrade_head_001_to_076_fresh_db.txt`
and `_44_alembic_history_heads_current_post076.txt`).

---

## Phase 5J.1 — controlled amendment for Phase 6C dependency closure (row 077)

Row `077` above (`077_5J1.sql`, Alembic revision `077_5J1`, `down_revision =
"076_5K1"`) is a **new forward migration**, added after and on top of the
validated 76-row baseline above (001-075 baseline + 076_5K1 corrective
patch). No row 001-076 was edited, renumbered, or had its checksum changed
to produce this row.

077_5J1's SHA-256 (`eac7022c4f96993d2e691947d8ebf2fa91ca3db2b9116beaf2c205dd5ee4a990`)
and size (15559 bytes) were computed directly against the current contents of
`migrations/077_5J1.sql` with `sha256sum`/`wc -c` in this pass. `alembic/versions/077_5J1.py`
wraps this file via the same `run_frozen_sql()` pattern used by every other
revision, with `downgrade()` raising `NotImplementedError` (forward-only,
matching every other revision in this package).

**Trigger:** `docs/phase-06-api-design/6C-Core-Platform-APIs.md`'s DEP-6C-16
(no concrete PostgreSQL transactional-outbox relation existed anywhere in the
frozen schema, verified by direct search across every Phase 5 document and
this manifest before 077 was authored).

**What 077_5J1 adds (audit schema only, no existing object altered):**

- `audit.domain_event_outbox` — the durable transactional-outbox table.
- `audit.fn_outbox_tenant_check()` + `trg_outbox_tenant_check` — BEFORE INSERT
  tenant-forgery guard (reuses `organization.current_tenant_id()`, 5B §16.2).
- `audit.fn_claim_outbox_events(worker_id, limit, claim_timeout_seconds)` —
  `SELECT ... FOR UPDATE SKIP LOCKED` claiming, mirroring
  `webhooks.fn_claim_delivery` (migration 063) exactly.
- `audit.fn_mark_outbox_published(id, worker_id)` and
  `audit.fn_mark_outbox_failed(id, worker_id, error, next_attempt_at)` —
  CAS-guarded completion/retry, mirroring `webhooks.fn_delivery_succeeded`/
  `fn_delivery_failed` (migration 063).

No RLS is added to `audit.domain_event_outbox` — see the migration file's own
header comment for the full reasoning (identical precedent to
`identity.sessions`/`identity.password_reset_tokens`, 5B §16.3, not a
`BYPASSRLS` workaround).

**What 077_5J1 does NOT do:** it does not add any new `action_kind` value to
`audit.audit_events` — `audit.audit_events.action_kind` is `TEXT` with only a
length `CHECK` (`chk_ae_action_kind`, migration 072), not a `CHECK ... IN
(...)` enum list and not backed by any reference/lookup table anywhere in
this schema. The ten new canonical `action_kind` values 6C's DEP-6C-07/10/11/14/15
required (`ORGANIZATION_CANCELLED`, `MEMBER_REACTIVATED`, `TEAM_CREATED`,
`TEAM_UPDATED`, `TEAM_ARCHIVED`, `TEAM_MEMBER_ADDED`, `TEAM_MEMBER_REMOVED`,
`DATA_SUBJECT_REQUEST_VERIFYING`, `DATA_SUBJECT_REQUEST_ON_HOLD`,
`USER_PROFILE_UPDATED`) are therefore a **pure governance/documentation
amendment** to `5J-Analytics-Audit-Schema.md` §14.3's canonical vocabulary
list — recorded there, not here, and requiring zero SQL. This manifest entry
exists only to record that this fact was verified, not assumed, before
concluding no migration was needed for that half of the closure package.

**Reconciled totals after this amendment:** 77/77 `migrations/*.sql` files,
77/77 `alembic/versions/*.py` files, single linear Alembic chain, single head
`077_5J1`.

**Validation status (updated 2026-08-23):** `validation/077_5J1_VALIDATION_REPORT.md`
— **18/18 checks PASS with live PostgreSQL execution evidence**, closing the
residual follow-up noted below. Row 077 was executed against a genuinely
fresh database (local native PostgreSQL 18 server; no Docker engine in this
environment) walking the full `001_5B → ... → 076_5K1 → 077_5J1` chain,
exit code 0, single head `077_5J1`. Live-tested beyond the prior
static-only pass: exact column/constraint/index inventory (correcting two
miscounts — 17 columns not 16, 7 CHECK constraints + 1 PK not "8 CHECK"),
`SECURITY DEFINER`/`search_path` hardening, `app_api`/`app_worker`/
`app_readonly` grant boundaries via `SET ROLE`, atomic domain+outbox
COMMIT/ROLLBACK, the `organization.created` and `compliance.policy_activated`
event flows (insert + claim), a genuine two-connection concurrency race
against `fn_claim_outbox_events` (0 double-claims across 20 rows), wrong-worker
publish rejection, retry/failure and max-attempts→FAILED transitions,
stale-claim recovery with a fresh-claim negative control, and a full
security/Alembic regression pass. See `execution_logs/README.md`'s "Fifth
batch" section (files `51`-`62`, prefix `20260823T061055Z`) for the raw
command/query evidence. `077_5J1.sql` was **not modified** by this
validation pass — no defect was found — so the SHA-256/size recorded above
remain byte-for-byte current (independently reconfirmed via `sha256sum`/
`wc -c` in this pass).

**Consumer:** `docs/phase-06-api-design/6C-Core-Platform-APIs.md` §7.7/§12.2/§20/§27
(DEP-6C-16) — 6C's Revision 6 uses `audit.domain_event_outbox` as the
concrete outbox relation for its `organization.created` and
`compliance.policy_activated` event flows.
