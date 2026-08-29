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
| 092 | 5F.12 | `092_5F12.sql` | `091_5F11` | transactional | 7071 | `3e93ea7841a526740ad7d891c6e17c3685d8df7a38130600a3ae628deb1e8c9d` |
| 093 | 5D.2 | `093_5D2.sql` | `092_5F12` | transactional | 21461 | `60c67499d4ed3b688265ae253fef554571272c4cb871be7767a2009375e72513` |
| 094 | 5D.3 | `094_5D3.sql` | `093_5D2` | transactional | 7502 | `4bb74bc7dc5ffe5700744411d3ea60d368c95eedadde6daba3a318f3d128d68b` |
| 095 | 5D.4 | `095_5D4.sql` | `094_5D3` | transactional | 5484 | `694a01d3af46d1df48c94a4e099954e450029edb06460a6f7421dd5a2d766d1b` |
| 096 | 5B.2 | `096_5B2.sql` | `095_5D4` | transactional | 2543 | `1d79ad3aa068eccb7d3181773bae61e4157ef37eb221e8777c7597c1a975bffc` |
| 097 | 5D.5 | `097_5D5.sql` | `096_5B2` | transactional | 13681 | `1ebb277a8551b648cec8f085edc0dae5596ad2c54b8b348f58d8323a05f13fe1` |
| 098 | 5E.1 | `098_5E1.sql` | `097_5D5` | transactional | 16943 | `aad468ae59b50bf0a3b8c29e99b248268198ed8a5c3f3fb896b69d0911b7afd6` |
| 099 | 5C.1 | `099_5C1.sql` | `098_5E1` | transactional | 63844 | `3dcf9b245b1a352069d3ff70da2a5af625f968c4ec728adc70ae0265f623310f` |
| 100 | 5G.1 | `100_5G1.sql` | `099_5C1` | transactional | 80135 | `9b52e7ffac8534faee64f6f9972dc1bc924d95147f3bbc28dd19b30dde2e7f55` |
| 101 | 5I.1 | `101_5I1.sql` | `100_5G1` | transactional | 59973 | `e23c58d8cc8e233cfb353371b606c91ecdfc90700ce03fd36046c9e43b1f0d89` |

---

## Phase 6J FINAL Blocker Remediation (2026-08-29) — `101_5I1.sql`, PostgreSQL 18 LIVE-VALIDATED

Row 101 (`101_5I1.sql`, Alembic revision `101_5I1`, `down_revision = "100_5G1"`) is a new, additive-only forward migration, amended in place through **two** remediation passes against `docs/phase-06-api-design/6J-Integrations-Webhooks-Plugins-APIs.md` (both 2026-08-29, same day — same "amended in place, never applied to any real/production database" policy already used for `100_5G1.sql`). No row 001-100 is edited, renumbered, or reordered. Full narrative, rationale, and per-finding detail: `validation/6J_FINAL_BLOCKER_REMEDIATION_VALIDATION_REPORT.md`. SHA-256/size in the table above reflect the final, twice-amended, live-validated content.

**First pass added:** integration-connection and plugin-installation lifecycle functions (closing DEP-6J-01/02), the OAuth-callback tenant-bootstrap function, webhook dual-secret rotation, `oauth_attempts.connection_id`/`failure_reason`, `webhook_endpoints.previous_signing_secret_ref`/`previous_secret_expires_at`, and 5 `EXECUTE`-grant widenings (removing the internal-RPC pattern the pre-remediation 6J document had proposed, ADR-6J-01).

**Second pass (this row amended in place again) closed three further P0s an independent review found in the first pass**, plus one major defect the second pass's own live testing discovered:

1. **`SECURITY DEFINER` tenant-forgery.** Every `app_api`-callable, `p_organization_id`-taking function — the 6 new integration-lifecycle functions, the 4 new plugin-lifecycle functions, `fn_rotate_webhook_secret`, and (via `CREATE OR REPLACE`, same signature) 8 pre-existing 059-066 functions (`fn_create_integration_connection`, `fn_rotate_integration_credential`, `fn_redeem_oauth_attempt`, `fn_create_plugin_installation`, `fn_activate_plugin`, `fn_uninstall_plugin`, `fn_upgrade_plugin`, `fn_replay_webhook_delivery`) — now requires `organization.current_tenant_id() = p_organization_id` before touching any row, fail-closed if tenant context is unset. **Live-proven**, not merely asserted: a full adversarial tenant-forgery matrix (11 tests — forged org, no tenant context, mismatched resource, across integration/plugin/webhook function families) all resolved correctly; see the validation report §8.
2. **OAuth token-exchange-failure state-machine contradiction.** `fn_fail_oauth_callback_state` is now unambiguously scoped to pre-redemption denial only; a new `fn_record_oauth_exchange_failure` function handles post-redemption token-exchange failure without reopening the consumed `state` for reuse (`status` stays `REDEEMED`; a new `exchange_failed_at` column records the failure). **Live-proven**: the exact contradiction scenario (fail an already-`REDEEMED` attempt) correctly rejected; the correct post-redemption path correctly recorded the failure while leaving `status='REDEEMED'` — validation report §9.
3. **OAuth state/provider binding.** `fn_redeem_oauth_callback_state`/`fn_fail_oauth_callback_state` now take `p_expected_definition_id` and verify it against the attempt's own `definition_id` **before** consuming `state` — a state issued for one provider presented at a different provider's callback route is rejected without being consumed, remaining redeemable later through the correct route. **Live-proven** exactly this way — validation report §9, tests OA-4/OA-5.
4. **`public.gen_uuid_v7()` missing `search_path` — MAJOR, live-discovered, platform-wide-impact, out of 6J's original scope.** `gen_uuid_v7()` (`001_5B.sql`) has no `SET search_path` of its own and calls the unqualified `gen_random_bytes()` (installed by `pgcrypto` into `public`); when invoked nested inside **any** `SECURITY DEFINER` function whose own `SET search_path` excludes `public` — confirmed live: **84 of the 99** `SECURITY DEFINER` functions across the entire 001-100 baseline fit this description — it fails with `function gen_random_bytes(integer) does not exist`. This is a **pre-existing defect in the frozen 001-100 baseline**, reproduced via a minimal repro against the exact unmodified `061_5I.sql` search_path pattern, not something 6J introduced. Fixed here (in-scope because it is a hard prerequisite for `101_5I1`'s own functions to work at all): `CREATE OR REPLACE FUNCTION public.gen_uuid_v7() ... SET search_path = public, pg_catalog` — not `SECURITY DEFINER`, so no privilege boundary changes; fixes all 84 affected functions transitively. **A full audit of which of the other 83 functions (outside `integrations`/`plugins`/`webhooks`) actually exercise the broken path in practice is out of this migration's scope** and is recorded as a forward finding for the owning phases. Full detail: validation report §6.

**Why the OAuth fix never required removing RLS from `oauth_attempts`:** unchanged from the first pass's own reasoning — `oauth_attempts`/`integration_connections` keep `ENABLE + FORCE ROW LEVEL SECURITY`; every `SECURITY DEFINER` function executes under its owning role's privileges (`app_migration`, confirmed `BYPASSRLS` in `001_5B.sql` and the `077_5J1` validation pass), so RLS was never the actual obstacle — this pass's live testing (validation report §14) independently re-confirms RLS enforcement is fully intact for ordinary, non-`SECURITY DEFINER` access (`app_api` sees only its own tenant's rows; zero rows with no tenant context set; direct `UPDATE`/`DELETE` denied).

**Live-database validation status: PostgreSQL 18.6 (not 16 — disclosed engine-version deviation), fully live-validated this pass.** Fresh-database `alembic upgrade head` (full `001_5B → … → 101_5I1` chain, 101 revisions): **PASS, exit 0.** Incremental (`100_5G1` pinned, then `101_5I1` applied alone): **PASS, exit 0** for both steps. Single Alembic head (`101_5I1`), `current == head`, linear history. `downgrade -1` correctly raises `NotImplementedError`, transaction rolls back cleanly, database remains at head. Full adversarial test matrix — tenant-forgery (11/11), OAuth (14/14), integration-connection lifecycle (all legal/illegal/idempotent transitions), plugin-installation lifecycle (all legal/illegal/idempotent transitions, including live-proven version-pinning capability-reset), webhook dual-secret rotation, a genuine two-process concurrency race for inbound-event dedup (`INSERT ... ON CONFLICT DO NOTHING RETURNING id`, exactly one of two simultaneous processes wins), RLS isolation, full privilege matrix (`PUBLIC EXECUTE = false` on all 34 functions), full `SECURITY DEFINER` inventory (owner/`BYPASSRLS`/`search_path` for all 34), and a targeted regression spot-check (outbox insert + tenant-forgery guard, `fn_claim_delivery` worker-only scoping, 6I's own `workflow_definitions` RLS) — **all PASS.** Raw execution logs (14 files, prefix `20260829T210000Z_`): `execution_logs/README.md`'s directory listing; full narrative and per-test detail: `validation/6J_FINAL_BLOCKER_REMEDIATION_VALIDATION_REPORT.md`.

**Not performed / disclosed limitations (full list in the validation report §17-§20):** SSRF/application-layer tests (no deployed application code exists in this repo to test against — untestable at the DB layer by construction, not skipped); a full re-run of every historical 001-100 test file (targeted spot-checks only); an audit of the other 83 `gen_uuid_v7`-affected functions outside `integrations`/`plugins`/`webhooks`; 6I's own `graph_json` node-config schema does not yet define the `plugin_installation_id`/`plugin_version_id` fields 6J's plugin-version-pinning design (ADR-6J-09) targets — disclosed as an explicit, unresolved **cross-phase coordination item** (6I is frozen, out of 6J's authority to amend), not silently claimed closed.

---

## Phase 6I FINAL PRIVILEGE CLEANUP (2026-08-29) — app_platform_admin cannot start Workflow executions, PostgreSQL 16 live-validated

`100_5G1.sql` amended in place a fourth time — never applied to any
real/production database, same policy as the three prior passes.
SHA-256/size updated in the table above; `revision`/`down_revision`
unchanged.

**Trigger:** the FINAL MICRO-REMEDIATION pass reviewed, but explicitly
declined to decide unilaterally, whether `app_platform_admin`'s
`EXECUTE` grant on `workflow.fn_start_workflow_execution()` — inherited
unmodified from the original, frozen `041_5G.sql` — should be revoked,
since the function is already fully tenant/archive/version-safe for any
caller and no invariant was bypassed by the grant (a pure product-policy
question, not a technical gap). The product owner has now made the
authoritative decision: `app_platform_admin` must not be able to
directly start a live `WorkflowExecution`.

**What this pass changes:** exactly one `GRANT` statement.
`REVOKE ALL ... FROM PUBLIC` is confirmed unchanged (still in effect);
`GRANT EXECUTE ... TO app_api, app_worker, app_platform_admin` becomes
`GRANT EXECUTE ... TO app_api, app_worker`. No change to the function
body, tenant validation, `ARCHIVED` locking (`FOR SHARE OF wd`),
duplicate-start semantics (`STARTED`/`REPLAYED_EXISTING`/
`VERSION_CONFLICT`), or advisory-lock behavior — privilege-only.

**Final privilege matrix for this function:**

| Role | EXECUTE |
|---|---|
| `app_api` | ✅ |
| `app_worker` | ✅ |
| `app_platform_admin` | ❌ (revoked, this pass) |
| `app_readonly` | ❌ (never granted) |
| `PUBLIC` | ❌ (unchanged) |

**PostgreSQL 16 validation (live, this pass — same disposable-instance
approach, torn down at the end of this batch):**

- Fresh (`voice_agent_pg16_finalfresh4`, full `001_5B → … → 100_5G1`):
  **PASS, exit 0**, single head `100_5G1`.
  `execution_logs/20260829T050000Z_58_..._60_*.txt`.
- Incremental (`voice_agent_pg16_incremental4`, pinned at `099_5C1`, then
  `100_5G1` alone): **PASS, exit 0** for both steps.
  `..._61_*.txt`, `..._62_*.txt`.
- `alembic history`: single linear 100-entry chain, no branch. `..._63_*.txt`.

**Privilege and regression evidence:**

| Area | Evidence file | Result |
|---|---|---|
| Grant confirmation (`app_platform_admin` absent, `PUBLIC` denied, `app_api`/`app_worker` present) | `..._53_*.txt` | PASS |
| `app_platform_admin` direct call → `permission denied for function fn_start_workflow_execution` (function body never executes) | `..._55_*.txt` | PASS |
| Legitimate runtime role (`app_api`) start succeeds; duplicate same session+version → `REPLAYED_EXISTING` | `..._54_*.txt` | PASS |
| `app_worker` start still succeeds | `..._56_*.txt` | PASS |
| Archive/StartExecution Race A (Start wins, Archive measurably waits 0.48s, execution stays `ACTIVE`) and Race B (Archive wins, subsequent Start rejected); different-version conflict (`VERSION_CONFLICT`) | `..._57_*.txt` | 6/6 PASS |

**Reconciled totals after this amendment:** 100/100 `migrations/*.sql`
files, 100/100 `alembic/versions/*.py` files, single linear Alembic
chain, single head `100_5G1` (unchanged revision id — content amended in
place a fourth time).

**Consumer:** `docs/phase-06-api-design/6I-Workflow-APIs.md` (Phase 6I
FINAL PRIVILEGE CLEANUP pass) — resolves the `USER DECISION REQUIRED`
item §65.3 raised, closing it with the product owner's own authoritative
decision rather than a unilateral one.

---

## Phase 6I FINAL MICRO-REMEDIATION (2026-08-29) — SUBMITTING hard-stop closure, mandatory exact-draft publish precondition, PostgreSQL 16 live-validated

`100_5G1.sql` is amended in place a third time — same revision policy as
its own header states and as `099_5C1.sql`'s own six-pass precedent
establishes: never applied to any real/production database, so there is
no frozen version to preserve. SHA-256/size in the table above are
updated to the file's current contents; `revision`/`down_revision`
unchanged.

**Trigger:** an independent review of the FINAL Blocker Remediation
pass' own new capabilities found two further defects — Blocker A
(`fn_record_node_failed()` still permitted `SUBMITTING -> FAILED` for an
ordinary worker, and `FAILED` is a reclaimable state, so an uncertain or
actually-successful post-submission outcome could be turned into an
automatically-retryable one, defeating the durable `SUBMITTING`
boundary) and Blocker B (`fn_publish_workflow()`'s
`p_expected_updated_at TIMESTAMPTZ DEFAULT NULL` let a caller bypass the
exact-draft concurrency precondition entirely by omitting the argument).

**What this pass changes:**

- **Blocker A:** `fn_record_node_failed()` (`DROP` + `CREATE`, `BOOLEAN`
  → `TABLE(recorded, reason)` return-type change) now accepts **only**
  `CLAIMED -> FAILED`. A `SUBMITTING -> FAILED` attempt is rejected with
  a distinguishable `reason = 'NOT_FAILABLE_AFTER_SUBMISSION'` (never a
  bare, ambiguous `FALSE`) and the row remains `SUBMITTING`, unmoved. An
  uncertain post-submission outcome has exactly one legal ordinary-worker
  destination now: `fn_record_node_ambiguous()` (unchanged, still a hard
  stop). `fn_record_node_succeeded()`/`fn_record_node_ambiguous()`
  themselves are untouched by this pass.
- **Blocker B:** `fn_publish_workflow()`'s `p_expected_updated_at` loses
  its `DEFAULT NULL` and gains an explicit, defensive `IS NULL` guard
  (`RAISE EXCEPTION`) inside the function body — a removed default alone
  does not stop an authorized caller from passing a literal `NULL`,
  since PostgreSQL never `NOT NULL`-constrains function parameters the
  way table columns are constrained. No unconditional runtime publish
  route exists any longer; every publish requires the row's real current
  `updated_at`.

**Reviewed, not silently decided:** `app_platform_admin`'s `EXECUTE`
grant on `fn_start_workflow_execution` — traced to the original, frozen
`041_5G.sql`, never introduced or altered by any 6I remediation pass —
was left **unchanged**. Unlike every other privilege change in this
migration, revoking it would not close an invariant bypass (the function
is already fully tenant/archive/version-safe for any caller); it would
be a business-policy restriction on platform-admin's role scope, which
this pass declines to decide unilaterally. Flagged explicitly in
`6I-Workflow-APIs.md` as an open, non-blocking product-policy question.

**PostgreSQL 16 validation (live, this pass — same disposable-instance
approach, torn down at the end of this batch):**

- Fresh (`voice_agent_pg16_finalfresh3`, full `001_5B → … → 100_5G1`):
  **PASS, exit 0**, single head `100_5G1`.
  `execution_logs/20260829T040000Z_46_..._48_*.txt`.
- Incremental (`voice_agent_pg16_incremental3`, pinned at `099_5C1`, then
  `100_5G1` alone): **PASS, exit 0** for both steps.
  `..._49_*.txt`, `..._50_*.txt`.
- `alembic history`: single linear 100-entry chain, no branch. `..._51_*.txt`.
- `downgrade()`: raises `NotImplementedError` (message updated for this
  pass' own additions); database remains at `100_5G1` afterward.
  `..._52_*.txt`.

**Functional and regression test evidence (all against genuine
PostgreSQL 16.10):**

| Area | Evidence file | Result |
|---|---|---|
| `CLAIMED -> FAILED` allowed, safely reclaimable; wrong-holder distinguished | `..._37_*.txt` | PASS |
| `SUBMITTING -> FAILED` rejected (`NOT_FAILABLE_AFTER_SUBMISSION`), row stays `SUBMITTING`, still `NOT_CLAIMABLE_SUBMITTING` afterward | `..._37_*.txt` | PASS |
| `SUBMITTING -> AMBIGUOUS` still allowed, still a hard stop | `..._37_*.txt` | PASS |
| `SUBMITTING -> SUCCEEDED` still allowed, terminal, no reclaim | `..._37_*.txt` | PASS |
| `NULL` publish precondition → exception, zero versions created | `..._38_*.txt` | PASS |
| Stale publish precondition → `PRECONDITION_FAILED`, zero versions created | `..._38_*.txt` | PASS |
| Correct publish precondition → `PUBLISHED` | `..._38_*.txt` | PASS |
| Re-publish with the now-stale prior precondition → `PRECONDITION_FAILED`, no extra version | `..._38_*.txt` | PASS |
| Full concurrency regression (duplicate claim, out-of-order checkpoint, simultaneous StartExecution, Archive-vs-draft, concurrent publish with shared precondition) — 9/9, zero regressions | `..._39_*.txt` | PASS |
| Archive/StartExecution race regression (Race A/B, duplicate/version-conflict semantics, cross-tenant) — 7/7 | `..._40_*.txt` | PASS |
| Side-effect tenant/identity security regression (wrong tenant/started_at/checkpoint-seq/terminal, cross-tenant on all 4 previously-fixed functions, direct DML) — 10/10 | `..._41_*.txt` | PASS |
| Publish privilege regression across all 3 roles (raw INSERT/UPDATE denied, admin `EXECUTE` denied, `NULL`-precondition direct call denied) — 7/7 | `..._42_*.txt` | PASS |
| Admin bypass regression (`workflow_executions`/`workflow_versions`/`node_execution_claims` UPDATE/DELETE denied; legitimate SELECT; superuser identity-reassignment still trigger-rejected) — 6/6 | `..._43_*.txt` | PASS |
| Full `SECURITY DEFINER` inventory (all 12 functions) | `..._45_*.txt` | `fn_record_node_failed` grantee list unchanged (`app_api, app_worker`); `fn_start_workflow_execution` still shows `app_platform_admin` (left unchanged, per the flagged review above) |
| Tenant isolation regression | `..._44_*.txt` | 6/6 PASS |

**Reconciled totals after this amendment:** 100/100 `migrations/*.sql`
files, 100/100 `alembic/versions/*.py` files, single linear Alembic
chain, single head `100_5G1` (unchanged revision id — content amended in
place a third time).

**Consumer:** `docs/phase-06-api-design/6I-Workflow-APIs.md` (Phase 6I
FINAL MICRO-REMEDIATION pass) — closes INV-6I-SE-07/08/09/10 and
INV-6I-PUB-04/05/06 with live evidence.

---

## Phase 6I FINAL Blocker Remediation (2026-08-29) — guarded Workflow publish/archive, Archive/StartExecution serialization, side-effect claim tenant/identity integrity, PostgreSQL 16 live-validated

`100_5G1.sql` is amended in place a second time — identical revision
policy to `099_5C1.sql`'s own six-pass history: this file has still never
been applied to any real/production database (every validation pass runs
against a disposable, throwaway local PostgreSQL 16 instance, torn down
at the end of each batch), so there is no frozen, already-applied version
to preserve, and a fresh `101_5G2.sql` would only fragment one coherent
Workflow-safety migration across two files for no benefit. SHA-256 and
byte size in the table above are updated to the file's new contents;
`down_revision`/`revision` (`099_5C1` → `100_5G1`) are unchanged.

**Trigger:** a second, adversarial pass over `6I-Workflow-APIs.md`'s own
first remediation found three further defects in that pass' own new
functions/grants — Blocker E (ordinary runtime roles still held raw DML
sufficient to bypass guarded Workflow publishing entirely: `app_api`/
`app_worker` retained plain `INSERT` on `workflow_versions`, and the
pre-existing `039_5G.sql` `fn_workflow_publish()` remained callable with
any already-existing `version_id`, letting ordinary code "publish" a
stale or fabricated version without version-number allocation or graph
validation), Blocker F (`fn_start_workflow_execution()`'s ARCHIVED check
was an unlocked `SELECT`, sharing no real serialization point with
`ArchiveWorkflow`'s own row `UPDATE`), and Blocker G (four of the five
Part-A side-effect functions never cross-checked their caller-supplied
`p_organization_id` against `organization.current_tenant_id()`, and
`fn_claim_node_execution` never validated its caller-supplied execution
identity/checkpoint-sequence/node-reference against the real
`WorkflowExecution` row).

**What this pass adds/changes, on top of the first pass' additions
(same table list, no new table):**

- **Blocker E:** `REVOKE INSERT ON workflow.workflow_versions FROM
  app_api, app_worker`; `workflow_definitions`' table-level `UPDATE` is
  revoked from `app_api`/`app_worker` and re-granted only on `(name,
  description, draft_graph)` — `status`/`published_version_id` become
  unwritable by any runtime role via raw DML, full stop. The old
  `fn_workflow_publish(UUID,UUID,UUID)` is dropped outright (superseded,
  not left inert-but-dangerous). New `fn_publish_workflow()` — one
  guarded, `FOR UPDATE`-serialized, tenant-safe, exact-draft-precondition
  (`p_expected_updated_at`) transaction owning the entire publish flow
  end to end (row lock → ARCHIVED check → precondition check →
  version-number allocation → snapshot → insert → definition update),
  `EXECUTE`-granted to `app_api` only (not `app_worker` — Publish is a
  synchronous, user-initiated REST action in 4E/6I's own model, not a
  worker-initiated capability, so the grant is deliberately narrower than
  its predecessor's). New `fn_archive_workflow()` restores Archive's
  ability to write `status` (as its owner, not as `app_api`) despite the
  column-privilege revoke — idempotent, `EXECUTE`-granted to `app_api`
  only.
- **Blocker F:** `fn_start_workflow_execution()`'s version/definition
  lookup now takes `FOR SHARE OF wd`, sharing the `WorkflowDefinition`
  row as a genuine serialization point with `fn_archive_workflow()`'s own
  `UPDATE` (which needs the conflicting `FOR NO KEY UPDATE` lock).
- **Blocker G:** `fn_begin_node_submission()`, `fn_record_node_succeeded()`,
  `fn_record_node_ambiguous()`, `fn_record_node_failed()` all gained the
  explicit `organization.current_tenant_id()` cross-check
  `fn_claim_node_execution`/`fn_checkpoint_workflow_execution`/
  `fn_start_workflow_execution` already had. `fn_claim_node_execution`
  additionally now reads the real `WorkflowExecution` row `FOR SHARE`
  (same tenant, `ACTIVE`, `checkpoint_seq + 1` match required) and checks
  the claimed `node_id`/`node_type` against the execution's own pinned
  `graph_json` before ever creating or reclaiming a claim.

**Live-discovered defects found and fixed within this same pass (proven
by direct execution, not assumed):**

1. **Column-level `REVOKE UPDATE (col) ... FROM role` has no effect when
   that role also holds a table-level `UPDATE` grant on the same table.**
   The first attempt at Blocker E's fix (`REVOKE UPDATE (status,
   published_version_id) ...`, leaving `040_5G.sql`'s table-level
   `UPDATE` grant untouched) was live-tested and proven **not** to block
   either column — both a raw `UPDATE ... SET published_version_id = ...`
   and `UPDATE ... SET status = 'PUBLISHED'` still succeeded as `app_api`.
   Fixed by revoking the table-level grant first, then re-granting
   `UPDATE` on only the three safe columns.
2. **`fn_publish_workflow`'s `RETURNS TABLE` OUT parameter `version_number`
   collided with `workflow_versions.version_number`** — the identical
   "column reference is ambiguous" class of defect `099_5C1.sql`'s own
   header comment documents for `fn_claim_dispatch_for_provider_submission`.
   Reproduced live on the very first functional test; fixed with the
   same `#variable_conflict use_column` pragma.

**PostgreSQL 16 validation (live, this pass — same disposable-instance
approach as the first pass, torn down at the end of this batch):**

- Fresh (`voice_agent_pg16_finalfresh2`, full `001_5B → … → 100_5G1`):
  **PASS, exit 0**, single head `100_5G1`.
  `execution_logs/20260829T033000Z_30_..._32_*.txt`.
- Incremental (`voice_agent_pg16_incremental2`, pinned at `099_5C1`, then
  `100_5G1` alone): **PASS, exit 0** for both steps.
  `..._33_*.txt`, `..._34_*.txt`.
- `alembic history`: single linear 100-entry chain, no branch. `..._35_*.txt`.
- `downgrade()`: raises `NotImplementedError` as designed (message updated
  to describe the FINAL pass' own additions); database remains at
  `100_5G1` afterward. `..._36_*.txt`.

**Functional and adversarial test evidence (all against genuine
PostgreSQL 16.10):**

| Area | Evidence file | Result |
|---|---|---|
| Raw-DML publish bypass (INSERT workflow_versions, UPDATE published_version_id/status) | `..._20_*.txt` | 5/5 DENIED/absent as required; ordinary column (`draft_graph`) still writable |
| `fn_publish_workflow`/`fn_archive_workflow` functional (publish/republish/stale-ETag/archive/idempotent-archive/publish-on-archived/not-found/cross-tenant) | `..._21_*.txt` | 12/12 PASS |
| `app_worker` denied `EXECUTE` on `fn_publish_workflow` | `..._22_*.txt` | PASS |
| Two genuine concurrent publishers of the same workflow → unique, sequential version numbers | `..._23_*.txt` (test D1) | PASS |
| Race A — StartExecution locks first, Archive measurably waits (0.49s observed), existing execution stays valid | `..._23_*.txt` (test D2) | PASS |
| Race B — Archive committed first, subsequent StartExecution against that version rejected | `..._23_*.txt` (test D3) | PASS |
| `fn_claim_node_execution` identity/checkpoint/graph validation (wrong seq, wrong `started_at`, unknown node, node-type mismatch, nonexistent execution, terminal execution) | `..._24_*.txt` | 7/7 PASS |
| Four previously-unguarded functions' new tenant checks (forged org on begin/succeeded/ambiguous/failed) | `..._25_*.txt` | 6/6 PASS |
| Full regression of the first pass' concurrency suite (duplicate claim race, out-of-order checkpoint, simultaneous StartExecution, Archive-vs-draft-update via the new guarded function) | `..._26_*.txt` | 13/13 PASS, no regression |
| `app_platform_admin` bypass regression (8 vectors incl. new `fn_publish_workflow` EXECUTE-denied) | `..._27_*.txt` | 8/8 PASS |
| Full `SECURITY DEFINER` inventory (owner, `prosecdef`, `search_path`, `PUBLIC EXECUTE`, grantees) — all 12 Workflow/Prompt functions, old and new | `..._28_*.txt` | All `PUBLIC EXECUTE = false`; every grantee list matches this document's own stated design |
| Tenant isolation regression (Org B / no-tenant-context vs. definitions/executions/claims) | `..._29_*.txt` | 6/6 PASS, fail-closed confirmed |

**Reconciled totals after this amendment:** 100/100 `migrations/*.sql`
files, 100/100 `alembic/versions/*.py` files, single linear Alembic
chain, single head `100_5G1` (unchanged revision id — content amended in
place, per the revision policy stated above).

**Consumer:** `docs/phase-06-api-design/6I-Workflow-APIs.md` (Phase 6I
FINAL Blocker Remediation pass) — closes the document's own §41
INV-6I-PUB-01/02/03, INV-6I-START-01..04, and INV-6I-SE-01..05 invariants
with live evidence.

---

## Phase 6I Blocker Remediation (2026-08-29) — Workflow durable node-side-effect idempotency, monotonic checkpoint CAS, admin-DML hardening, Archive terminal-immutability, PostgreSQL 16 live-validated

Row 100 (`100_5G1.sql`, Alembic revision `100_5G1`, `down_revision = "099_5C1"`) is a new, additive-only forward migration closing four blockers found by `docs/phase-06-api-design/6I-Workflow-APIs.md`'s own Phase 6I Blocker Remediation pass — no row 001-099 is edited, renumbered, or reordered.

**Trigger:** the first-pass `6I-Workflow-APIs.md` correctly *found* (but did not close) two genuine production-safety gaps — no durable per-attempt idempotency claim for side-effecting Workflow nodes, and an `app_platform_admin` direct-DML bypass of `fn_workflow_publish()`'s guards — and additionally left the stale-checkpoint race analyzed-but-unresolved and its own concurrency matrix self-contradictory on the Archive-vs-draft-update race. This migration closes all four.

**What 100_5G1 adds (workflow schema, plus two narrowly-scoped identity-trigger hardenings in `workflow`/`prompt` and privilege REVOKEs — no other schema touched):**

- **Blocker A (side-effecting node re-execution after crash/Redis-loss):** `workflow.node_execution_claims` — a durable `CLAIMED -> SUBMITTING -> SUCCEEDED | FAILED | AMBIGUOUS` state machine for `TOOL_CALL`/`TRANSFER`/`HUMAN_TRANSFER` node evaluations, structurally mirroring `voice.call_dispatch_keys` (`099_5C1.sql`) exactly, including the same "once SUBMITTING, never auto-reclaimed regardless of lease staleness" invariant. Identity is `(organization_id, workflow_execution_id, target_checkpoint_seq, node_id)` — stable across worker restart because `target_checkpoint_seq` is derived from Part B's new `checkpoint_seq` column (last-committed + 1), not a freshly-computed attempt counter. Five guarded `SECURITY DEFINER` functions: `fn_claim_node_execution()`, `fn_begin_node_submission()`, `fn_record_node_succeeded()`, `fn_record_node_ambiguous()`, `fn_record_node_failed()`. No runtime role holds direct DML beyond `SELECT`. `voice.tool_executions` is unmodified (Option B of 6I §8 — the new table references it only via an opaque `downstream_ref TEXT`). `WEBHOOK`/`API_CALL` remain execution-blocked pending 6J regardless of this table's existence (6I ADR-6I-04, unchanged).
- **Blocker B (stale/out-of-order PostgreSQL checkpoint can move a WorkflowExecution backward):** `workflow.workflow_executions.checkpoint_seq BIGINT NOT NULL DEFAULT 0` — a durable, per-execution monotonic Turn counter, enforced non-decreasing by BOTH the new guarded CAS function `fn_checkpoint_workflow_execution()` (returns `APPLIED | STALE_CHECKPOINT | EXECUTION_TERMINAL | NOT_FOUND`) AND, as an independent, DB-level second layer, a hardened `workflow.prevent_execution_mutation()` trigger that rejects `NEW.checkpoint_seq < OLD.checkpoint_seq` unconditionally — live-proven to hold even for the `postgres` superuser bypassing every grant. `fn_complete_workflow_execution()`/`fn_fail_workflow_execution()` are the new sole legal terminal-state transitions.
- **Blocker A/6I-§26/§27 (`fn_start_workflow_execution()` revised, DROP + CREATE across a return-type change — identical precedent to `099_5C1.sql`'s own `DROP FUNCTION IF EXISTS voice.fn_reconcile_dispatch_outcome(...)`):** now returns `TABLE(execution_id, execution_started_at, outcome)` with `outcome IN ('STARTED','REPLAYED_EXISTING','VERSION_CONFLICT')` instead of raising on the benign duplicate-active-session race, and additionally rejects starting a new execution when the `WorkflowVersion`'s parent `WorkflowDefinition` is `ARCHIVED` — closing the resolve-then-archive-then-start race at the durable serialization point itself.
- **Blocker C (`app_platform_admin` direct-DML bypass):** `app_platform_admin` reduced to `SELECT`-only on `workflow.workflow_definitions`, `workflow.workflow_versions`, `workflow.workflow_executions` (its parent AND every existing partition — a defensive per-partition `REVOKE` loop, live-discovered necessary in this same pass: a parent-level `REVOKE` alone left every pre-existing partition's own separately-inherited ACL untouched, identical in kind to the reasoning `076_5K1.sql`'s own header comment already gives for why its INSERT revoke had to walk `pg_inherits` explicitly), and the new `workflow.node_execution_claims`; `app_api`/`app_worker` additionally lose `UPDATE` on `workflow_executions` (Part B's guarded functions are now the sole mutation path); `prompt.prompt_versions` given the identical `app_platform_admin` reduction (the disclosed sibling gap found by the same review). No new guarded admin-override function is added — a future administrative correction belongs to 6M through its own guarded/audited operation (6I §16), not a reopened blanket grant.
- **Blocker D (Archive-vs-draft-update race could mutate an ARCHIVED `WorkflowDefinition`):** `workflow.prevent_wf_version_mutation()` and `prompt.prevent_pv_mutation()` hardened to also guard their identity columns (`workflow_definition_id`/`prompt_template_id`, `organization_id`) — the exact class of gap the *already-corrected* `workflow_executions` trigger (`039_5G.sql`, per the 5K corrections) was hardened to close for its own table, never symmetrically applied to `workflow_versions`/`prompt_versions` until now. A new `workflow.prevent_archived_definition_mutation()` `BEFORE UPDATE` trigger makes `ARCHIVED` unconditionally terminal for every mutable field on `workflow_definitions`, live-proven to reject both a queued, already-in-flight competing `UPDATE` (genuine two-connection race) and a raw superuser `UPDATE` bypassing every grant.

**Live-discovered defects found and fixed within this same pass (not merely designed, then assumed correct):**

1. `fn_claim_node_execution()`'s `SET search_path = workflow, organization, pg_catalog` omitted `public` — an exact recurrence of `076_5K1.sql`'s own Group-1 defect class (an `INSERT` into a table whose `id` column defaults to `public.gen_uuid_v7()`, which itself makes an unqualified internal call to pgcrypto's `public.gen_random_bytes()`). Reproduced live on the very first functional test (`ERROR: function gen_random_bytes(integer) does not exist`) before being fixed to `SET search_path = workflow, organization, public, pg_catalog`, matching `076_5K1.sql`'s own documented safe ordering (own schema, `organization`, `pg_catalog`, `public` last).
2. The parent-table-only `REVOKE UPDATE, DELETE ON workflow.workflow_executions FROM app_platform_admin` (and the `app_api`/`app_worker` `UPDATE` revoke) left every pre-existing monthly partition's own, separately-inherited grant fully intact — confirmed live via `information_schema.role_table_grants` before the defensive per-partition `pg_inherits` loop was added, then reconfirmed closed afterward on a from-scratch re-run.

**PostgreSQL 16 validation (live, this pass — no Docker engine available, reconfirmed; native PostgreSQL 16.10 built from the EDB binaries-only distribution at `C:\Users\Dell\pgval16\pgsql`, port 5433, `pgvector` 0.8.0 built from source via the same MSVC 14.51.36231 toolchain used by the prior `PG16_MIGRATION_VALIDATION_REPORT.md` pass, torn down at the end of this batch):**

- Fresh-database validation (`voice_agent_pg16_finalfresh`, full `001_5B -> ... -> 099_5C1 -> 100_5G1` chain): **PASS, exit code 0.** Single Alembic head `100_5G1`. Raw output: `execution_logs/20260829T020000Z_12_6i_FINAL_pg16_fresh_001_to_100.txt`, `..._13_6i_FINAL_alembic_heads.txt`, `..._14_6i_FINAL_alembic_current.txt`.
- Incremental validation (`voice_agent_pg16_incremental`, pinned at `099_5C1` first, then `100_5G1` applied alone): **PASS, exit code 0** for both steps. Raw output: `execution_logs/20260829T020000Z_15_6i_FINAL_pg16_incremental_001_to_099.txt`, `..._16_6i_FINAL_pg16_incremental_099_to_100.txt`, `..._17_6i_FINAL_alembic_history.txt` (single linear 100-entry chain, `<base> -> 001_5B -> ... -> 100_5G1`, no branch).
- `downgrade()` correctly raises `NotImplementedError` (forward-only, matching every other revision in this package), and the failed-downgrade transaction correctly rolls back cleanly, leaving the database at `100_5G1` (head) — `execution_logs/20260829T020000Z_18_6i_downgrade_not_implemented.txt`.

**Functional and adversarial test evidence (all against genuine PostgreSQL 16.10, `voice_agent_pg16_fresh`):**

| Area | Evidence file | Result |
|---|---|---|
| `fn_start_workflow_execution()` deterministic outcomes (fresh/replay/conflict/archived-reject) | `..._03_6i_start_execution_outcomes.txt` | 4/4 PASS |
| `fn_checkpoint_workflow_execution()` CAS (sequential APPLIED/STALE/duplicate/terminal/not-found) | `..._04_6i_checkpoint_cas_tests.txt` | 9/9 PASS |
| Tenant-forgery rejection (`fn_checkpoint_workflow_execution`, `fn_start_workflow_execution`) | `..._05_6i_tenant_forgery_tests.txt` | 2/2 PASS |
| `checkpoint_seq` backward-write rejected by the TRIGGER itself, as `postgres` superuser | `..._06_6i_trigger_backward_seq_part1/2.txt` | PASS |
| `node_execution_claims` state machine (claim/reclaim/SUBMITTING-hard-stop/AMBIGUOUS-hard-stop/FAILED-retry/lease-expiry/cross-tenant-forgery/direct-DML-denied) | `..._07_6i_node_claim_state_machine.txt` | 14/14 PASS |
| Genuine two-connection/thread concurrency (duplicate claim race, out-of-order checkpoint commit, simultaneous `StartExecution` race, Archive-vs-draft-update race) | `..._08_6i_concurrency_python_harness.txt` | 13/13 PASS |
| `app_platform_admin` direct-DML bypass — all nine previously-exploitable vectors | `..._09_6i_admin_bypass_tests.txt` | 9/9 DENIED as required; legitimate `SELECT` confirmed still working |
| `workflow_versions`/`prompt_versions` identity-reassignment rejected by trigger, as `postgres` superuser | `..._10_6i_version_identity_trigger_superuser.txt` | 3/3 PASS |
| Tenant isolation regression (Org A/Org B/no-tenant-context) across all three tables + the new claim table | `..._11_6i_tenant_isolation_regression.txt` | 5/5 PASS, fail-closed confirmed |
| Checkpoint with a wrong partition/`started_at` hint | `..._19_6i_checkpoint_wrong_partition_hint.txt` | `NOT_FOUND`, as required |

**Reconciled totals after this amendment:** 100/100 `migrations/*.sql` files, 100/100 `alembic/versions/*.py` files, single linear Alembic chain, single head `100_5G1`.

**Consumer:** `docs/phase-06-api-design/6I-Workflow-APIs.md` (Phase 6I Blocker Remediation pass) — the document's own §30/§37/§38/§20-22 findings are what this migration closes; the document itself is updated in the same pass to reflect `RESOLVED` status and remove the prior, invalid "APPROVED WITH BLOCKER" verdict.

---

## Phase 6H Final Admin-DML Hardening (2026-08-29) — remove platform-admin direct DML bypass, PostgreSQL 16 live-validated

Both `098_5E1.sql` and `099_5C1.sql` corrected in place once more — still
never applied to any production database, so the disclosed migration
policy (edit in place, no `100_5E2.sql`/`100_5C2.sql`) continues to apply.
Every prior privilege-hardening pass restricted a *different* role
(`app_worker`'s `INSERT` on the campaign identity table; `app_api`/
`app_worker`'s `INSERT` on the Voice dispatch table; then `EXECUTE` on the
reconciliation functions for `app_api`/`app_worker`, and later further
split by provenance) — but `app_platform_admin`'s own original `GRANT
SELECT, INSERT, UPDATE, DELETE` on both tables, present since each table
was first created, was never touched by any of them. That grant could
bypass every invariant built on top of it: a direct `UPDATE ... SET
dispatch_state = 'FAILED' WHERE dispatch_state = 'CONFIRMED'` would reopen
a known-accepted call for a second physical telephony attempt, and a
direct `UPDATE ... SET reconciliation_source = 'PROVIDER_CALLBACK'` would
forge the very provenance boundary the two most recent passes just
established — both completely invisible to, and unenforced by, any guarded
function, since a raw `UPDATE` never calls one.

**The fix:** `app_platform_admin`'s `INSERT`/`UPDATE`/`DELETE` grant is
removed from both `voice.call_dispatch_keys` and `campaign.
campaign_contact_identities`; `SELECT` is retained on both (an explicit,
still-legitimate diagnostics/support need). Removing these grants does not
impair `fn_reconcile_dispatch_by_operator()` at all — like every other
guarded function in this schema, it is `SECURITY DEFINER`, owned by the
migration-running role, and needs no direct table grant to keep writing.
The identical, already-established reasoning (`app_worker`'s own
`fn_enqueue_contact()` call working with zero direct grant) applies
unchanged.

**Live-validated on a fourth, genuinely independent PostgreSQL 16.10
instance** (the sixth/seventh/eighth batches' own instances had each
already been torn down): fresh-database and incremental `alembic upgrade`
both exit code 0, single head `099_5C1` unchanged. Direct catalog
inspection (`information_schema.role_table_grants`) confirms `app_api`,
`app_worker`, `app_readonly`, and `app_platform_admin` all hold `SELECT`
only on both tables, before any test runs. `app_platform_admin` is denied
`permission denied` on direct `INSERT`, `UPDATE` (including the specific
provenance-forgery attempt and the specific `CONFIRMED → FAILED` reopen
attempt), and `DELETE` against `voice.call_dispatch_keys`, and on direct
`INSERT` against `campaign.campaign_contact_identities` — while `SELECT`
against a live `CONFIRMED` row succeeds. The legitimate guarded paths are
unaffected: `app_platform_admin` calling `fn_reconcile_dispatch_by_operator
()` on a genuine `AMBIGUOUS` row with real evidence succeeds; the same
function against an already-`CONFIRMED` row correctly returns
`reconciled=false`; `app_voice_reconciler` calling `fn_reconcile_dispatch_
from_provider()` succeeds identically. `app_api`/`app_worker`/
`app_voice_reconciler` remain denied on direct DML, unchanged. The full
prior-pass regression suite (expired-`CLAIMED` recovery, both hard stops,
replay/mismatch/cross-tenant idempotency) was re-run and reproduced
unchanged. Full transcripts: `execution_logs/README.md`'s "Ninth batch";
`validation/VOICE_DISPATCH_VALIDATION_REPORT.md` and `validation/
CAMPAIGN_PRIVILEGE_VALIDATION_REPORT.md`, both updated.

**Reconciled totals after this amendment:** 99/99 `migrations/*.sql` files
(unchanged count), single linear chain, single head `099_5C1`. No function
body changed in either file — only the two `GRANT` statements per table.

`098_5E1.sql`: 16943 bytes, SHA-256
`aad468ae59b50bf0a3b8c29e99b248268198ed8a5c3f3fb896b69d0911b7afd6`.
`099_5C1.sql`: 63844 bytes, SHA-256
`3dcf9b245b1a352069d3ff70da2a5af625f968c4ec728adc70ae0265f623310f`.

**Consumer:** `docs/phase-06-api-design/6H-Campaign-APIs.md` (Revision 7)
§18.4, §49.9c; `docs/phase-06-api-design/6D-Voice-Call-Agent-APIs.md`
§28.10a; `docs/phase-05-database-design/5C-Voice-Schema.md`.

---

## Phase 6H Final Micro-Fix (2026-08-28) — non-forgeable reconciliation provenance, PostgreSQL 16 live-validated

`099_5C1.sql` corrected in place a fifth time — still never applied to any
production database, so the disclosed migration policy (edit in place, no
`100_5C2.sql`) continues to apply. The Final Micro-Remediation pass above
correctly restricted reconciliation to two roles but left a caller-supplied
`p_reconciliation_source` parameter that either authorized caller could set
to any of the three legal values — meaning `app_voice_reconciler` (the
automated path) could pass `'OPERATOR'`, or `app_platform_admin` (the
operator path) could pass `'PROVIDER_CALLBACK'`, producing an audit trail
that misrepresents which trusted path actually made the physical-redial
authorization decision.

**The fix:** `voice.fn_reconcile_dispatch_outcome()` is dropped and
replaced by three functions:

1. **`voice.fn_reconcile_dispatch_outcome_internal()`** — the actual
   state-transition + audit mechanism (identical logic to the prior single
   function), but granted `EXECUTE` to **no role at all**. Reachable only
   via the two wrappers below, which invoke it under their own `SECURITY
   DEFINER` owner privileges — the identical bridge-function pattern
   already used for `fn_new_uuid_v7()`.
2. **`voice.fn_reconcile_dispatch_from_provider()`** — `EXECUTE`: `app_
   voice_reconciler` only. Accepts a source parameter restricted, by a
   `CHECK` inside the function body, to `PROVIDER_CALLBACK`/
   `PROVIDER_LOOKUP` — `'OPERATOR'` is rejected with an exception even
   though the caller holds `EXECUTE`, because the *value* is invalid, not
   because the *caller* lacks privilege. Hardcodes `actor_type='WORKER'`.
3. **`voice.fn_reconcile_dispatch_by_operator()`** — `EXECUTE`: `app_
   platform_admin` only. Takes **no source parameter at all** —
   `'OPERATOR'` and `actor_type='PLATFORM_ADMIN'` are hardcoded inside the
   function body, so there is no parameter by which a caller could request
   provider provenance.

This makes which provenance category a given credential can ever produce a
property of the database schema itself, not of caller-supplied metadata or
application-layer trust.

**Live-validated on a third, genuinely independent PostgreSQL 16.10
instance** (the sixth and seventh batches' own instances had already been
torn down): fresh-database and incremental `alembic upgrade` both exit code
0, single head `099_5C1` unchanged. The critical proof: `app_voice_
reconciler`, while genuinely holding `EXECUTE` on `fn_reconcile_dispatch_
from_provider`, calling it with `p_provider_source = 'OPERATOR'` was
rejected by the function's own internal `CHECK` — not merely denied by a
missing grant. `app_voice_reconciler` calling `fn_reconcile_dispatch_by_
operator` at all was denied at the privilege layer (no grant exists).
`app_platform_admin` calling `fn_reconcile_dispatch_from_provider` at all
was denied at the privilege layer, symmetrically. Genuine reconciliation
through each path recorded the correct, function-determined provenance
and `actor_type`, confirmed by direct query against both `voice.
call_dispatch_keys` and `audit.audit_events`. `CONFIRMED → FAILED` and
cross-tenant reconciliation were both attempted through *both* functions
and refused every time. The operator path's evidence requirement for
`FAILED` was confirmed identical to the provider path's (shared internal
check). The full prior-pass regression suite (expired-`CLAIMED` recovery,
the `SUBMITTING` hard-stop, replay/mismatch/cross-tenant idempotency, the
synchronous `AMBIGUOUS` path) was re-run and reproduced unchanged. Full
transcripts: `execution_logs/README.md`'s "Eighth batch";
`validation/VOICE_DISPATCH_VALIDATION_REPORT.md`.

**Reconciled totals after this amendment:** 99/99 `migrations/*.sql` files
(unchanged count), single linear chain, single head `099_5C1`, 10
`voice.fn_*` functions (up from 8 — one function replaced by three), 6
PostgreSQL roles (unchanged from the prior pass — no new role introduced
this time; the fix is entirely a function-boundary split using the
existing `app_voice_reconciler`/`app_platform_admin` roles).

`099_5C1.sql`: 61703 bytes, SHA-256
`f5e0352e3407dd318c36351cedb98546b5c6adf464a48c81aa49da37b4fc3c0c`.

**Consumer:** `docs/phase-06-api-design/6H-Campaign-APIs.md` (Revision 6)
§18.4, §49.9b; `docs/phase-06-api-design/6D-Voice-Call-Agent-APIs.md`
§28.10a.

---

## Phase 6H Final Micro-Remediation (2026-08-28) — reconciliation authorization boundary, provenance, PostgreSQL 16 live-validated

`099_5C1.sql` corrected in place a fourth time — still never applied to any
production database, so the disclosed migration policy (edit in place, no
`100_5C2.sql`) continues to apply. The prior (Final Blocker Remediation)
pass closed the P0 double-dial hazard with a durable `SUBMITTING` boundary
and a new `voice.fn_reconcile_dispatch_outcome()` resolution function — but
granted that function's `EXECUTE` privilege to `app_api` and `app_worker`,
the two broad, shared-by-everything application roles. Because this
function can transition `SUBMITTING`/`AMBIGUOUS` to `FAILED`, and a
`FAILED` row is immediately re-claimable for a fresh physical provider
attempt, that grant meant **any** ordinary application or worker code path
could unilaterally re-authorize a second physical telephony attempt for an
ambiguous call — the exact class of defect this whole remediation exists to
prevent, just relocated to the reconciliation function itself.

**What changed, closing this gap:**

1. **New role, `app_voice_reconciler`** (`LOGIN`, `NOT BYPASSRLS`, no table
   DML, no membership elsewhere). The existing five-role catalog (`001_5B.
   sql`: `app_api`, `app_worker`, `app_readonly`, `app_migration`,
   `app_platform_admin`) was inspected first; none was narrow enough for
   this one capability (`app_api`/`app_worker` are too broad; `app_readonly`
   cannot write; `app_platform_admin` is correct for the human/operator path
   but far broader than a single automated function needs). Its entire
   privilege surface is `USAGE` on schema `voice` plus `EXECUTE` on exactly
   one function — nothing else.
2. **`EXECUTE` on `voice.fn_reconcile_dispatch_outcome()` revoked from
   `app_api`/`app_worker`, granted only to `app_voice_reconciler`
   (the automated provider-callback/provider-lookup path) and
   `app_platform_admin`** (the existing break-glass/operator role,
   `087_5B1.sql` — reusing it rather than inventing a second new role for
   the human path).
3. **New required provenance field, `p_reconciliation_source`** (`
   'PROVIDER_CALLBACK' | 'PROVIDER_LOOKUP' | 'OPERATOR'`), persisted to a
   new column, `voice.call_dispatch_keys.reconciliation_source`, with an
   all-or-nothing `CHECK` constraint tying it to `reconciled_by`/
   `reconciled_at`. This is evidentiary metadata, never authorization —
   `p_reconciled_by` and `p_reconciliation_source` are never read in any
   `IF`/`CASE`/`WHERE` clause that decides anything; a caller cannot forge
   privilege by passing `p_reconciled_by = 'admin'` (live-proven: an
   `app_api` call with exactly that forged value still fails at the
   `permission denied` stage, before the function body ever executes).
4. **`FAILED` reconciliation now requires a non-empty evidence description**
   (`p_note`), enforced both in the function body and by a new `CHECK`
   constraint (`chk_cdk_reconciled_failed_has_evidence`, defense in depth) —
   "no evidence at all" is now structurally impossible for a reconciled
   `FAILED` row. This cannot verify the evidence is *true* (no database
   can) — that is what the `EXECUTE`-privilege boundary is for — it only
   closes the "silently blank" failure mode.
5. **A durable audit event (`VOICE_DISPATCH_RECONCILED`, via
   `audit.fn_insert_audit_event()`, 5J §14.2's sole legal write path) is now
   written synchronously for every successful reconciliation** — closing
   the prior complete absence of audit evidence for this safety-critical
   transition. `action_kind` is `TEXT` with only a length `CHECK`
   (`chk_ae_action_kind`), identical precedent to every prior phase's own
   new value — zero additional schema change (§G of `099_5C1.sql`).
6. **Allowed source states re-verified, unchanged**: only `SUBMITTING` and
   `AMBIGUOUS` — `CONFIRMED → FAILED` (reopening a known-accepted call) was
   already structurally impossible before this pass and remains so; **live-
   proven this pass**, not merely re-asserted: an authorized-role attempt to
   reconcile an already-`CONFIRMED` row returned `reconciled=false`, the row
   unchanged.

**Live-validated on a genuinely fresh, disposable PostgreSQL 16.10 instance**
(the prior pass's own instance had already been torn down per its documented
cleanup — this is an independently rebuilt instance, same method: binaries-
only distribution, `pgvector` built from source via the local MSVC
toolchain): fresh-database and incremental `alembic upgrade` both exit code
0, single head `099_5C1`; direct execution of the reconciliation function as
`app_api` and `app_worker` both fail with `permission denied`; the
authorized role successfully resolves `AMBIGUOUS → CONFIRMED` and a separate
`AMBIGUOUS → FAILED` (with the `FAILED` row then genuinely re-claimable,
proving retry is really reopened); two no-evidence `FAILED` attempts
correctly rejected; a `CONFIRMED`-row reconciliation attempt correctly
refused; a cross-tenant attempt correctly refused, non-disclosingly, with no
mutation; provenance and the audit event both confirmed present and
accurate by direct query; the full sixth-batch regression suite (expired-
`CLAIMED` recovery, the `SUBMITTING` hard-stop, replay/mismatch/cross-tenant
idempotency) re-run and unchanged. Full transcripts:
`execution_logs/README.md`'s "Seventh batch";
`validation/VOICE_DISPATCH_VALIDATION_REPORT.md`.

**Reconciled totals after this amendment:** 99/99 `migrations/*.sql` files
(unchanged count — no new row added), single linear chain, single head
`099_5C1`, 6 PostgreSQL roles (`app_api`, `app_worker`, `app_readonly`,
`app_migration`, `app_platform_admin`, `app_voice_reconciler` — the last one
new this pass).

**Consumer:** `docs/phase-06-api-design/6H-Campaign-APIs.md` (Revision 5)
§18.4, §49.9a; `docs/phase-06-api-design/6D-Voice-Call-Agent-APIs.md`
§28.10a.

---

## Phase 6H Final Blocker Remediation (2026-08-28) — provider-submission-boundary hardening, privilege bypass closure, idempotency tenant/payload validation, PostgreSQL 16 live-validated

Same two rows (`098_5E1.sql`, `099_5C1.sql`) corrected in place a third
time — both are still disclosed as never having been applied to any
production database, so there is still no frozen, already-applied version
of either file to preserve, and the migration policy explicitly stated in
the prior entry below (edit in place, do not renumber) continues to apply
unchanged. An independent, adversarial final freeze review found that the
*previous* pass's fix for Blocker #3/Blocker C, while a genuine
improvement, still permitted a specific and serious failure: a `CLAIMED`
row's lease expiring was the only signal used to decide re-claimability,
and `CLAIMED` covered the entire span up to and including the moment the
provider was actually contacted — so a worker that crashed **after** the
provider received the request would eventually have its row re-claimed by
another worker, which would call the provider again and could physically
dial the customer twice. Four blockers were identified and closed in this
pass, all live-validated on a genuinely separate PostgreSQL 16.10 instance
(the declared production baseline — every prior 6H pass had validated only
against PostgreSQL 18):

1. **Blocker A — expired-CLAIMED double-dial hazard (P0).** `voice.
   call_dispatch_keys.dispatch_state` gained a new state, `SUBMITTING`,
   entered only via a new function, `voice.fn_begin_provider_submission()`,
   which the caller's contract requires committing **before** ever
   invoking `TelephonyPort.place_call()`. `voice.
   fn_claim_dispatch_for_provider_submission()`'s reclaim predicate now
   excludes `SUBMITTING` unconditionally, regardless of lease staleness —
   only `RESERVED`, `FAILED`, and a lease-expired `CLAIMED` row (none of
   which have any evidence the provider was ever contacted) are
   automatically retryable. Live-proven: a `CLAIMED` row whose lease
   expires before `fn_begin_provider_submission` is ever called is safely
   re-claimed (attempt_count increments, call not lost); a `SUBMITTING`
   row whose lease expires is provably **not** re-claimable
   (`NOT_CLAIMABLE_SUBMITTING`) even though nothing else has touched it —
   the direct empirical closure of the P0 defect. A new function, `voice.
   fn_reconcile_dispatch_outcome()`, gives a genuine, identity-correlated
   (not lease-owner-correlated) resolution path for a `SUBMITTING` or
   `AMBIGUOUS` row via a delayed provider callback or a bounded
   operator/provider-lookup decision — live-proven resolving both a stuck
   `SUBMITTING` row to `CONFIRMED` and a stuck `AMBIGUOUS` row to `FAILED`
   (with the latter then genuinely re-claimable, proving the two states
   are not merely the same thing under different names).
2. **Blocker B — direct INSERT bypass on `campaign.
   campaign_contact_identities`.** `app_worker`'s `INSERT` grant is
   removed; only `SELECT` remains for `app_worker`/`app_api`/
   `app_readonly`. The only legal write path is `campaign.
   fn_enqueue_contact()` (`SECURITY DEFINER`, unaffected by the grant
   change since it runs as the migration-owning role). Live-proven: direct
   `INSERT` as `app_worker` now fails with `permission denied`; the guarded
   function, and its pre-existing idempotency and cross-tenant guards,
   remain fully functional.
3. **Blocker C — direct INSERT bypass on `voice.call_dispatch_keys`.**
   Same fix, same reasoning: `app_api`/`app_worker`'s `INSERT` grant is
   removed; only `SELECT` remains. Every dispatch-state-machine row and
   transition now provably requires going through one of the eight guarded
   `voice.fn_*` functions. Live-proven: direct `INSERT` as both
   `app_worker` and `app_api` now fails with `permission denied`.
4. **Blocker D — idempotency replay tenant/payload validation.** `voice.
   fn_initiate_outbound_call_idempotent()` now computes a canonical,
   versioned SHA-256 `payload_fingerprint` (via `public.digest()`) from the
   actual immutable request fields on every call — never accepted as a
   caller-supplied value — and persists it with the dispatch key. On
   replay: a different `organization_id` raises a non-disclosing exception
   (this function is `SECURITY DEFINER` and bypasses RLS entirely, so this
   explicit check is the *entire* tenant-isolation guarantee for a replay,
   not defense-in-depth); a different `payload_fingerprint` under the same
   key returns `outcome = 'IDEMPOTENCY_KEY_REUSE_MISMATCH'` (6A §16.2's
   existing global error semantic, reused at this domain layer rather than
   inventing new vocabulary) with no session identity disclosed; a genuine
   same-tenant, same-payload replay returns the original call
   (`outcome = 'REPLAYED'`). All three live-proven, including the
   cross-tenant case producing a generic, non-disclosing error message.

**Function count correction (also closed in this pass):** `099_5C1.py`'s
`downgrade()` docstring previously said "five new voice.fn_* functions,"
already stale even before this pass (the file defined six). This pass adds
two more (`fn_begin_provider_submission`, `fn_reconcile_dispatch_outcome`)
for a directly-queried total of **eight** `voice.fn_*` functions — every
reference to this count, across `099_5C1.py`, `6D-Voice-Call-Agent-APIs.md`,
and `6H-Campaign-APIs.md`, is corrected to `8`, verified by
`SELECT count(*) FROM pg_proc ...` rather than re-asserted from memory.

**PostgreSQL 16 live validation performed in this pass** (full detail in
`validation/PG16_MIGRATION_VALIDATION_REPORT.md`,
`validation/VOICE_DISPATCH_VALIDATION_REPORT.md`,
`validation/CAMPAIGN_PRIVILEGE_VALIDATION_REPORT.md`,
`validation/SECURITY_DEFINER_VALIDATION_REPORT.md`, and
`execution_logs/README.md`'s "Sixth batch"): the EDB full installer for
PostgreSQL 16.10 genuinely failed in this environment ("the requested
operation requires elevation" — a real, disclosed failure, not smoothed
over); the binaries-only distribution was used instead (no service
registration, no elevation needed), `pgvector` was built from source
against it via the locally available MSVC toolchain (pgvector is not
bundled in the binaries-only zip), and all three required extensions
(`vector`, `pgcrypto`, `pg_stat_statements`) were confirmed loadable before
any migration ran. Fresh-database `alembic upgrade head` (`001_5B →
099_5C1`): **PASS**, exit code 0. Incremental upgrade from a database
pinned at `097_5D5`: **PASS**, exit code 0. Single Alembic head `099_5C1`
confirmed both ways. Genuine two-connection concurrency races (not
simulated): provider-dispatch claim ownership (exactly one winner);
`CampaignContact` duplicate enqueue (exactly one winner, regression check —
this logic was not modified by this pass). `pg_proc`/
`has_function_privilege` inspection: all 11 `SECURITY DEFINER` functions
touched by 098/099 confirmed with their documented minimal `search_path`
and `PUBLIC EXECUTE` denied on every one.

**What remains an accepted, disclosed limitation, unchanged from the prior
pass:** whether the telephony provider itself received and acted on a
single network call whose own response was lost cannot be resolved by any
platform-side database mechanism alone — bounded by 6D's pre-existing
provider-retry contract (3B §19) and `fn_reconcile_dispatch_outcome`'s
dependency on the provider adapter actually supporting reference
echo-back, not verified for Exotel specifically in this or any prior pass.

**Reconciled totals after this amendment:** 99/99 `migrations/*.sql` files
(unchanged count — no new row added, both existing rows corrected in
place), single linear chain, single head `099_5C1`, now live-validated on
both PostgreSQL 18 (prior pass) and PostgreSQL 16 (this pass, the declared
production baseline).

**Consumer:** `docs/phase-06-api-design/6H-Campaign-APIs.md` (Revision 4)
§18, §32, §46-§47, §49-§53; `docs/phase-06-api-design/6D-Voice-Call-Agent-APIs.md`
§28.10a.

---

## Phase 6H Campaign Final Remediation (2026-08-28) — dispatch concurrency-safety amendment, live-validated

Two new **forward** migrations, added after and on top of the validated 97-row
Phase 6G Follow-up baseline. No row 001–097 was edited. Both are additive-only
inside their respective already-frozen schemas (`campaign`, `voice`) — no
existing table, column, constraint, index, or grant from `027_5E.sql`–
`033_5E.sql` or `009_5C.sql`–`018_5C.sql` is altered.

This entry supersedes an earlier same-day pass at these two row numbers.
Neither `098_5E1.sql` nor `099_5C1.sql` had ever been applied to any real
database when the earlier pass was superseded, so both are corrected in
place rather than carried forward to `100_5E2.sql`/`101_5C2.sql` — there is
no frozen, already-applied version of either file to preserve. **Unlike the
earlier pass, this one was live-executed** against a disposable local
PostgreSQL 18 database (a real `uv`-managed Python 3.14 environment with
`alembic==1.19.1`/`sqlalchemy==2.0.52`/`psycopg==3.3.4`, installed for this
validation only, not committed to the repository) — full detail, transcripts,
and exact commands in `docs/phase-06-api-design/6H-Campaign-APIs.md` §49.

**Fixes carried in this pass, beyond the two migrations' original scope:**

1. **SECURITY DEFINER `search_path` hardening (found and reproduced live
   before being fixed, not assumed).** `campaign.fn_enqueue_contact()` and
   `campaign.fn_reserve_dispatch()` called the platform's shared
   `gen_uuid_v7()` (`001_5B.sql`, lives in `public`) without `public` in
   their own restrictive `search_path`. Live-reproduced failure:
   `function gen_random_bytes(integer) does not exist` — because
   `gen_uuid_v7()` itself calls `gen_random_bytes()` (pgcrypto) unqualified
   with no `SET search_path` of its own, inheriting the *caller's*
   search_path at execution time; qualifying only the outer call
   (`public.gen_uuid_v7()`) is insufficient, confirmed live. Fix: a single,
   isolated, single-purpose bridge function per schema
   (`campaign.fn_new_uuid_v7()`, `voice.fn_new_uuid_v7()`), each the *only*
   function in its migration permitted to see `public` — every other
   function's `search_path` remains minimal (`campaign, organization,
   pg_catalog` / `voice, organization, pg_catalog` / `voice, pg_catalog`).
2. **Two genuine cross-tenant/cross-campaign defects, found by live
   adversarial testing during this pass, not by inspection alone.**
   `campaign.fn_enqueue_contact()` originally trusted its
   `p_organization_id` parameter without ever confirming `p_campaign_id`
   actually belonged to it — a live probe (Org A calling the function with
   Org B's `campaign_id`) succeeded and created a real cross-tenant
   `campaign_contacts` row before the fix. `campaign.fn_reserve_dispatch()`
   separately never confirmed the targeted `CampaignContact` actually
   belonged to the claimed `campaign_id` (only to the claimed
   `organization_id`) — a live probe with a mismatched same-tenant
   `(campaign_id, campaign_contact_id)` pair would have created a
   `call_jobs` row whose `campaign_id` disagreed with the contact it
   referenced. Both are now closed by an explicit ownership lookup/predicate
   before any write; re-tested live afterward and confirmed rejected
   (non-disclosing exception / `CONTACT_NOT_FOUND`, matching this codebase's
   established non-disclosure convention).
3. **A `#variable_conflict use_column` PL/pgSQL fix**, found and reproduced
   live: `voice.fn_claim_dispatch_for_provider_submission()`'s `RETURNS
   TABLE` output parameter `attempt_count` collided with
   `voice.call_dispatch_keys.attempt_count`, the exact column its own
   `UPDATE ... SET attempt_count = attempt_count + 1` needed to increment —
   PL/pgSQL raised "column reference is ambiguous" until this pragma was
   added.
4. **Row 099 (`099_5C1.sql`, Phase 5C.1) now also closes the provider-
   dispatch durability hole a second-pass adversarial review found in the
   first version of this file** (a genuine, distinct defect from Blocker #3
   above, not merely a restatement of it): the first version refused to
   ever re-invoke the telephony provider once a dispatch key was claimed,
   which meant a worker crash **between** committing the logical-call
   reservation and actually calling `TelephonyPort.place_call()` would
   **permanently lose the call** — the exact opposite failure mode from
   double-dialing. `voice.call_dispatch_keys` now carries a full
   provider-dispatch state machine (`RESERVED → CLAIMED → CONFIRMED |
   AMBIGUOUS | FAILED`, lease-based ownership, `attempt_count`,
   `provider_request_ref`/`provider_call_ref`, `last_error`), with four new
   functions (`fn_claim_dispatch_for_provider_submission()`,
   `fn_record_dispatch_confirmed()`, `fn_record_dispatch_ambiguous()`,
   `fn_record_dispatch_failed()`) giving a genuine claim/lease/outcome
   protocol instead of a single claim-then-never-retry flag. **AMBIGUOUS is
   a hard stop** — no function in this migration ever transitions it back
   to `CLAIMED` automatically; only a stale (lease-expired) `CLAIMED` row or
   an explicit `FAILED` row is re-claimable.

**Live validation performed in this pass (all genuinely executed, not
narrated — full transcripts and exact commands in
`docs/phase-06-api-design/6H-Campaign-APIs.md` §49):**

- Fresh-database `alembic upgrade head` (001 → 099): **PASS**, exit code 0.
- Incremental upgrade from an existing `097_5D5` database to `head`: **PASS**,
  exit code 0.
- `alembic heads`/`alembic current`: single head `099_5C1`, current matches
  head, linear history confirmed.
- `pg_proc`/`information_schema` inspection: all 9 new functions confirmed
  `SECURITY DEFINER` with the documented, minimal `search_path`; `EXECUTE`
  confirmed granted only to the intended roles and revoked from `PUBLIC` on
  every one.
- Genuine two-connection concurrency races (both orderings interleaved via
  real overlapping transactions, not simulated sequentially): duplicate
  `CampaignContact` enqueue (exactly one winner, zero duplicate rows);
  duplicate dispatch reservation for the same `CampaignContact` (exactly one
  `call_jobs` row); Pause-vs-in-flight-reservation (reservation already
  holding the lock completes; Pause's own `UPDATE` genuinely blocked ~1.5s
  waiting for it, then succeeded); Pause-already-committed-first (a fresh
  reservation attempt correctly refused, `CAMPAIGN_NOT_RUNNING`); duplicate
  Voice in-process dispatch with an identical key (exactly one
  `call_sessions` row, exactly one `call_dispatch_keys` row); duplicate
  provider-submission claim with an identical key (exactly one claimant).
- Crash-recovery proofs: a claimed-then-abandoned (simulated crash, never
  confirmed) dispatch, once its lease genuinely expired, was safely
  re-claimed and confirmed by a different worker — the call was **not**
  permanently lost; an `AMBIGUOUS` outcome was proven to permanently block
  every subsequent reclaim attempt regardless of lease state (no automatic
  retry); a `FAILED` outcome was proven safely re-claimable (the opposite
  of `AMBIGUOUS`, confirming the state machine's asymmetry is real, not
  just documented).
- Duplicate Celery-style task redelivery (the identical dispatch attempt
  submitted twice, sequentially): second delivery correctly refused
  (`CONTACT_NOT_DISPATCHABLE`), exactly one `call_jobs` row.
- Cross-tenant/cross-campaign probes (post-fix): all four rejected as
  designed.

**What remains an accepted, bounded, external-system limit, not closed by
either migration:** whether the *telephony provider itself* received and
acted on a single `TelephonyPort.place_call()` network call whose own
response leg was lost is not resolvable by any idempotency key on the
platform's own side alone — that residual sliver is bounded by 6D's
pre-existing provider-retry contract (3B §19) and, where the active provider
adapter supports it, a `provider_request_ref`-based reconciliation window
against inbound callbacks (a documented, disclosed dependency on the
provider-adapter layer, not assumed universally true of every provider).

**Reconciled totals after this amendment:** 99/99 `migrations/*.sql` files,
single linear chain, single head `099_5C1`, with matching
`alembic/versions/098_5E1.py`/`099_5C1.py` wrappers now present and
genuinely exercised (unlike the superseded pass, which had SQL files but no
Alembic wrappers and no live execution at all).

**Consumer:** `docs/phase-06-api-design/6H-Campaign-APIs.md` (Revision 3)
§9, §16–§18, §32, §46–§47, §49–§51.

---

## Phase 6G CRM Reconciliation, Follow-up (2026-08-28) — merge marker PII removal

Row 097 is a **new forward migration**, added after and on top of the
validated 96-row Phase 6G CRM Reconciliation baseline. No row 001-096 was
edited — `093_5D2.sql` in particular is untouched; its checksum in the
table above is unchanged from the entry that follows this section.

An independent whole-project review, performed after the Phase 6G CRM
Reconciliation above, found a real GDPR-erasure-boundary defect in
`093_5D2.sql`'s `crm.fn_merge_contacts()`: the merge-marker Activity it
records on the survivor copied the secondary Contact's `full_name` and
`phone_e164` directly into the Activity's JSONB `payload`. Because
`crm.activities` is append-only (`REVOKE UPDATE, DELETE`, `022_5D.sql`)
and is never touched by Contact GDPR erasure (erasure clears fields on
`crm.contacts` only — 5D §5.1, ADR-5D-007), this created a second,
erasure-proof copy of exactly the PII `DELETE /contacts/{id}` is supposed
to clear. A Contact merged and later the subject of a Data Subject
erasure request would have had their name and phone number survive,
unerasable, inside this one Activity row.

`097_5D5.sql` fixes this with a single `CREATE OR REPLACE FUNCTION
crm.fn_merge_contacts(...)`, identical to `093_5D2.sql`'s version in
every respect — guards (self/tenant/erased/already-merged), deterministic
lock ordering, lead-status ranking, tag/custom-field union and cap
enforcement, the four mutable-child repoints (`crm.deals`/`tasks`/
`notes`/`appointments`), the secondary's `merged_into_contact_id`/
`merged_at` assignment, `SECURITY DEFINER` hardening (`search_path`
including `public`, `REVOKE ALL FROM PUBLIC`, identical `EXECUTE` grants
to `app_api`/`app_worker`/`app_platform_admin`) — **except** the marker
Activity's `payload` now carries identifiers/provenance only: `event`,
`primary_contact_id` (newly added), `secondary_contact_id`, `merged_by`.
No Contact name, phone, email, address, custom-field value, or
qualification reason is written into this payload.

Live-validated (disposable local PostgreSQL 18, fresh-DB `001_5B ->
097_5D5` and existing-DB `096_5B2 -> 097_5D5`, both exit code 0, single
head `097_5D5`): a full merge regression pass — valid same-tenant merge;
all four mutable children still repointed; `crm.activities` and
`crm.lead_score_records` still physically unchanged (attached to the
secondary's id, untouched); the marker Activity is created; its payload's
key set is confirmed to be exactly `{event, merged_by,
primary_contact_id, secondary_contact_id}` via `jsonb_object_keys` —
`payload ? 'secondary_full_name'` and `payload ? 'secondary_phone_e164'`
both return `false`, and a direct text-search of the serialized payload
for the test fixture's actual name (`"Sensitive Secondary Name"`) and
phone digits confirms neither string appears anywhere in it; GDPR
erasure of the now-merged secondary still succeeds unobstructed
afterward, and the (already PII-free) marker payload is unaffected by
that erasure, confirming no Contact PII survives solely because a prior
merge copied it; cross-tenant merge still rejected; a genuine
two-connection concurrent merge race reproduces the identical pre-fix
outcome (one success, one real `MERGE_SECONDARY_ALREADY_MERGED`
exception).

**Reconciled totals after this amendment:** 97/97 `migrations/*.sql`
files, 97/97 `alembic/versions/*.py` files, single linear chain, single
head `097_5D5`.

**Consumer:** `docs/phase-06-api-design/6G-CRM-Leads-APIs.md` (Revision 3)
§10, §34, §36.

---

## Phase 6G CRM Reconciliation (2026-08-28) — merge lineage, event idempotency, score CAS, permission amendment

Four new **forward** migrations, added after and on top of the validated
92-row Phase 5L.2 baseline. No row 001-092 was edited. All four were
live-executed against a genuinely fresh, disposable local PostgreSQL 18
database (`crm_6g_validate`) — full chain `001_5B -> ... -> 096_5B2`,
exit code 0, single head `096_5B2` — and again against the same database
without dropping it (an "existing DB" incremental-apply check), also exit
code 0. Alembic itself (the Python package) was not available in the
validating environment; the equivalent chain-integrity checks it would
perform were instead run directly against `alembic/versions/*.py`: 96/96
files, no duplicate revision ids, exactly one root (`001_5B`, `None`),
exactly one head (`096_5B2`, confirmed as the only revision id that is
nobody's `down_revision`), and a 1:1 filename correspondence between
`migrations/*.sql` and `alembic/versions/*.py`.

This reconciliation was triggered by an independent review of
`docs/phase-06-api-design/6G-CRM-Leads-APIs.md`'s first pass, which found
three genuine defects rather than accepting them as documented
limitations:

1. **Row 093 (`093_5D2.sql`, Phase 5D.2) — Contact merge-lineage support.**
   6G's first pass represented a merged-away Contact via `deleted_at`
   (the GDPR-erasure tombstone), conflating two semantically distinct
   states. Adds `crm.contacts.merged_into_contact_id` / `merged_at`
   (both-or-neither, self-referential FK, no-self-merge CHECK), two guard
   triggers (`trg_contacts_merge_tenant_guard` rejects a cross-tenant
   merge destination; `trg_contacts_merge_immutable` rejects any attempt
   to re-point or clear an already-recorded merge lineage — together these
   make a merge cycle structurally impossible, proven live in a two-hop
   chain test), and `crm.fn_merge_contacts()` — the sole guarded write
   path, `SECURITY DEFINER` for centralized invariant enforcement (not
   privilege elevation — `app_api`/`app_worker` already hold every table
   grant this function uses). Re-points only the mutable child aggregates
   that already carry real `UPDATE` grants (`crm.deals`, `crm.tasks`,
   `crm.notes`, `crm.appointments`); `crm.activities` and
   `crm.lead_score_records` are deliberately left untouched and
   unrepointed — both remain `REVOKE UPDATE, DELETE` for `app_api`/
   `app_worker` exactly as `022_5D.sql`/`023_5D.sql` already set, and this
   migration does **not** restore that privilege. Live-validated: valid
   same-tenant merge (full field-merge, lead-status "further along"
   ranking, tag/custom-field union with cap enforcement, all four mutable
   children repointed, Activities/LeadScoreRecords correctly left in
   place, marker Activity recorded on the survivor); self-merge rejected;
   cross-tenant merge rejected (secondary not found under the caller's
   tenant — a non-disclosing failure mode); already-merged Contact
   rejected as either primary or secondary; GDPR-erased Contact rejected
   as either primary or secondary; a genuine two-connection concurrent
   duplicate-merge race (one connection succeeded, the other received a
   real `MERGE_SECONDARY_ALREADY_MERGED` exception — not simulated
   sequentially); a real multi-hop lineage chain (A merged into B, B
   later merged into C) with A's lineage pointer correctly left
   unrewritten; a direct-SQL bypass attempt against both new triggers,
   both rejected; and — critically — GDPR erasure of an **already-merged**
   Contact still succeeds unobstructed (the immutability trigger fires
   only on `merged_into_contact_id`/`merged_at`, never on the erasure
   field-set), confirming the two states remain genuinely independent.
   A first draft of this function omitted `public` from its `SET
   search_path`, which broke on live execution the same way
   `analytics.fn_claim_projection_slot` (068_5J.sql) previously did —
   `public.gen_uuid_v7()`'s own call to `public.gen_random_bytes()`
   (pgcrypto) does not resolve under a narrowed search_path inherited
   from the calling `SECURITY DEFINER` context. Fixed before this
   migration was ever left in a broken state, following
   `audit.fn_insert_audit_event`'s (072_5J.sql) already-established
   pattern exactly: `public` included in `search_path`, and the new row's
   id generated into a local variable and passed explicitly rather than
   relied on as a column default.

2. **Row 094 (`094_5D3.sql`, Phase 5D.3) — durable CRM event-consumer
   idempotency.** 6G's first pass protected against duplicate
   `call.ended`/`conversation.qualification_set`/
   `conversation.summarization_completed` delivery with a race-prone
   "`SELECT` for existing `call_ref`, then `INSERT`" application pattern.
   Adds `crm.event_consumer_dedup` (true `PRIMARY KEY (consumer_name,
   source_event_id)`, CRM-owned — not a reuse of
   `analytics.analytics_event_dedup`, distinct from
   `audit.domain_event_outbox`'s publisher-side queue) and
   `crm.fn_claim_event()`, an atomic claim-or-detect-duplicate primitive
   every CRM event subscriber calls once, in the same transaction as its
   side effect. Live-validated: a genuine two-connection concurrent claim
   race on the identical `(consumer_name, source_event_id)` (exactly one
   `TRUE`, one `FALSE`, exactly one persisted row); a claim inside a
   transaction that is then rolled back correctly leaves zero rows (the
   claim and the side effect commit atomically, by construction of the
   caller's transaction boundary); a retry after that rollback succeeds
   cleanly.

3. **Row 095 (`095_5D4.sql`, Phase 5D.4) — CAS-safe lead-score apply,
   fixing an accepted-as-risk race.** 6G's first pass accepted that an
   older, slow-to-arrive scoring computation could overwrite
   `contacts.lead_score`/`lead_temperature` with a stale value after a
   newer one had already applied. Adds `crm.fn_apply_lead_score()` —
   **no new column** was needed or added: the fix is a `Contact`-row
   lock (narrow, single-row, exactly the case the governing review
   explicitly permitted) combined with a `(computed_at, id)` recency
   check against the already-existing, still fully append-only
   `crm.lead_score_records` history. Live-validated: applying a newer
   computation first, then an older one, correctly leaves the newer
   value in place and returns `FALSE` for the stale attempt while both
   immutable history rows persist; a genuine two-connection concurrent
   race for the *same* Contact with different `computed_at` values
   correctly converges on the objectively newer value regardless of
   which transaction's `INSERT` or lock acquisition happened to complete
   first.

4. **Row 096 (`096_5B2.sql`, Phase 5B.2) — permission catalog amendment.**
   The only new permission this reconciliation adds:
   `crm_field:manage` (`OWNER`/`ADMIN` only), closing DEP-6G-10 (CRM
   custom-field-definition administration has tenant-wide schema impact
   and was previously mapped onto the `MEMBER`-eligible `contact:write`
   for lack of a dedicated scope). Every other 4C/5B terminology gap
   reviewed in this same pass (`contact:qualify`, `contact:score_override`,
   `contact:force_convert`, `crm:admin` for non-author note delete) was
   found *not* to cross the bar for a new permission — each is either not
   exposed at all, or already served by a conservative interim mapping —
   see `6G-CRM-Leads-APIs.md` SS5/SS39 for the full classification. Purely
   additive, `ON CONFLICT DO NOTHING`, following `007_5B.sql`'s own
   idempotent seeding pattern exactly; `007_5B.sql` itself is untouched.

**No broad privilege restoration occurred.** Explicitly re-verified live
after all four migrations: `app_api`/`app_worker` still hold only
`SELECT, INSERT` (never `UPDATE`/`DELETE`) on `crm.activities`,
`crm.lead_score_records`, and `crm.consent_records`; `crm.contact_suppressions`
still grants them only `SELECT, INSERT`; the `uq_sup_active` partial
unique index (085) still rejects a duplicate active suppression with a
real `unique_violation`; `crm.prevent_ai_note_body_mutation()` still
rejects an `AI_SUMMARY` note body edit. All five new `SECURITY DEFINER`
functions (`fn_merge_contacts`, `prevent_cross_tenant_merge`,
`prevent_remerge`, `fn_claim_event`, `fn_apply_lead_score`) carry an
explicit, non-empty `search_path` and `REVOKE ALL ... FROM PUBLIC` (PUBLIC
`EXECUTE` denial confirmed indirectly: `app_readonly`, never explicitly
granted `EXECUTE` on any of the three functions it should not be able to
call, shows `has_function_privilege = false` for all three — if `PUBLIC`
retained `EXECUTE`, an ungranted role would still show `true`); `EXECUTE`
is granted only to the specific roles that need each function
(`fn_merge_contacts`: `app_api`, `app_worker`, `app_platform_admin`;
`fn_claim_event`/`fn_apply_lead_score`: `app_worker`,
`app_platform_admin` only — these two are background-worker-only
primitives, never called from the request-time REST API).

**Reconciled totals after this amendment:** 96/96 `migrations/*.sql`
files, 96/96 `alembic/versions/*.py` files, single linear chain, single
head `096_5B2`.

**Consumer:** `docs/phase-06-api-design/6G-CRM-Leads-APIs.md` (Revision 2)
— DEP-6G-01 (BLOCKING) is now RESOLVED; DEP-6G-06 is RESOLVED via the
`5J-Analytics-Audit-Schema.md` governance amendment recorded there
(no SQL — `chk_ae_action_kind` remains length-only); DEP-6G-07 is
RESOLVED (`organization.organizations.currency`, `003_5B.sql`, was
already present and simply not located in the first pass); DEP-6G-10 is
RESOLVED by row 096 above.

---

## Phase 5L.2 amendment (2026-08-24) — final freeze review correction

Row 092 is a **new forward migration**, added after and on top of the
validated 91-row Phase 5L.1 baseline. No row 001-091 was edited. A final
independent freeze review found the reindex manifest predicate
(`fn_kb_reindex_begin`/`fn_kb_reindex_complete`, `088_5F8.sql`) too
broad — `d.status <> 'DELETED'` wrongly included `ARCHIVED` documents,
which 6F's retrieval policy excludes. Fixed by tightening both to
`d.status = 'READY'`. Live-executed (fresh-DB 001->092 and existing-DB
091->092, both exit code 0, single head `092_5F12`).

The effective-generation retrieval fix (the other Phase 5L.2 finding —
retrieval must select exactly one chunk generation per current document
version, not every generation `<= index_version`) required **no schema
change**: the existing `idx_dc_version_generation` index (`089_5F9.sql`)
already serves the corrected query efficiently (confirmed via `EXPLAIN
ANALYZE` — index-only scan, sub-millisecond). This is a documented
query-contract correction only (5F/6F amendments).

**Reconciled totals after this amendment:** 92/92 `migrations/*.sql`
files, 92/92 `alembic/versions/*.py` files, single linear Alembic chain,
single head `092_5F12`.

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
