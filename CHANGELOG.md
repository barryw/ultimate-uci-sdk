# Changelog
All notable changes to this project will be documented in this file. See [conventional commits](https://www.conventionalcommits.org/) for commit guidelines.

- - -
## [v0.6.1](https://github.com/barryw/ultimate-uci-sdk/compare/cf11c808d8e64258d5c7bfdec94c54e9343f155a..v0.6.1) - 2026-09-03
#### Documentation
- (**boing**) open capture in raw player - ([b63e317](https://github.com/barryw/ultimate-uci-sdk/commit/b63e317260126cfb9c986652d0b9f1012c8e3ef6)) - Barry Walker
- (**boing**) add linked demo capture - ([cf11c80](https://github.com/barryw/ultimate-uci-sdk/commit/cf11c808d8e64258d5c7bfdec94c54e9343f155a)) - Barry Walker

- - -

## [v0.6.0](https://github.com/barryw/ultimate-uci-sdk/compare/26c22daa54d35eee66524d49049bf5addffa3e9b..v0.6.0) - 2026-09-03
#### Features
- (**audio**) ultimate_audio_load_wav, a WAV file into the REU and a voice - ([d0da050](https://github.com/barryw/ultimate-uci-sdk/commit/d0da05072529ef283b96f25457e3d21a6cac07d2)) - Barry Walker, Claude Fable 5.1
- (**bindings**) audio_load_wav for C and the blob, in an extension table at +$300 - ([a22c328](https://github.com/barryw/ultimate-uci-sdk/commit/a22c328a58349e2b0d67d8ad94053b88a1668654)) - Barry Walker, Claude Fable 5.1
- (**bindings**) BLOB_* jump table and parameter block offsets, generated - ([4cae868](https://github.com/barryw/ultimate-uci-sdk/commit/4cae868ee20b7f29f42631617615df9fa31794e0)) - Barry Walker, Claude Fable 5.1
- (**demo**) ship self-contained Boing demo - ([c90cfea](https://github.com/barryw/ultimate-uci-sdk/commit/c90cfeaedffe073a304f688898e1207e979359d5)) - Barry Walker
#### Bug Fixes
- (**abi**) a byte result in A leaves the flags set from A - ([5770367](https://github.com/barryw/ultimate-uci-sdk/commit/577036719bffe377f098e7d65bd2e61f47be8c0f)) - Barry Walker, Claude Fable 5.1
- (**audio**) configure settles after the stop and after the writes - ([e2be280](https://github.com/barryw/ultimate-uci-sdk/commit/e2be280b09f927dbefece2419a69317fd741cb6d)) - Barry Walker, Claude Fable 5.1
#### Documentation
- (**asm**) audio_load_wav also clobbers ult_arg2 and ult_attrib - ([9760298](https://github.com/barryw/ultimate-uci-sdk/commit/97602984d5ee93ca815c39d2659e6769266c3a0a)) - Barry Walker, Claude Fable 5.1
- (**plan**) Task 5 commits only what passes - ([c8ac6ae](https://github.com/barryw/ultimate-uci-sdk/commit/c8ac6ae9cdeff9d309409071e70e71fb4d4b2277)) - Barry Walker, Claude Fable 5.1
- (**plan**) implementation plan for the four SDK fixes from the Boing demo - ([33ed5ba](https://github.com/barryw/ultimate-uci-sdk/commit/33ed5ba4944904f3c4534caa621aa5a1c970a2ce)) - Barry Walker, Claude Fable 5.1
- (**spec**) the WAV loader takes 8-bit files too, and Boing ships its recording - ([87b9584](https://github.com/barryw/ultimate-uci-sdk/commit/87b9584cc65bdebea957e5271b725de4e0f81836)) - Barry Walker, Claude Fable 5.1
- (**spec**) four fixes, not three - ([ab9277f](https://github.com/barryw/ultimate-uci-sdk/commit/ab9277ff84ae578eeafec25ffe41bcab0f4d3bba)) - Barry Walker, Claude Fable 5.1
- (**spec**) ultimate_audio_load_wav, and Boing loads its sample from a file - ([5448a37](https://github.com/barryw/ultimate-uci-sdk/commit/5448a37cdef62eeb6de03beeda53a81740990056)) - Barry Walker, Claude Fable 5.1
- (**spec**) SDK fixes from the Boing demo, and a generic sprite multiplexer - ([26c22da](https://github.com/barryw/ultimate-uci-sdk/commit/26c22daa54d35eee66524d49049bf5addffa3e9b)) - Barry Walker, Claude Fable 5.1
#### Tests
- (**blob**) pin the two closed jump tables' full ranges again - ([2874b5f](https://github.com/barryw/ultimate-uci-sdk/commit/2874b5f36f4e4290ff4da3de423dbd4b91a5622c)) - Barry Walker, Claude Fable 5.1
- (**wav**) the sign pass in the simulator, and six doc corrections - ([cb7dfc7](https://github.com/barryw/ultimate-uci-sdk/commit/cb7dfc746605e85a79001a9512f3375b6e073a1a)) - Barry Walker, Claude Fable 5.1
- (**wav**) fixtures for ultimate_audio_load_wav, and UA_RATE_CLOCK - ([799acbd](https://github.com/barryw/ultimate-uci-sdk/commit/799acbd284182dd0312ca1885e07523a36f8bd13)) - Barry Walker, Claude Fable 5.1
#### Refactoring
- (**vsprites**) generated BLOB_* offsets, no cmp #0 - ([18dab01](https://github.com/barryw/ultimate-uci-sdk/commit/18dab01687ddf971f4741a91067f7c540fd9157d)) - Barry Walker, Claude Fable 5.1
#### Miscellaneous
- track the KickAssembler sources the blanket *.asm rule hid - ([49c5e3c](https://github.com/barryw/ultimate-uci-sdk/commit/49c5e3cb5dc162a98d464e8a363d091513a221d5)) - Barry Walker, Claude Fable 5.1
- baseline of two sessions' uncommitted work - ([2625b93](https://github.com/barryw/ultimate-uci-sdk/commit/2625b9337a83d337ebd1681f9244566a4b5fa995)) - Barry Walker, Claude Fable 5.1

- - -

## [v0.5.0](https://github.com/barryw/ultimate-uci-sdk/compare/ee9a66d194cd87c0a9563ef843dac00f63857261..v0.5.0) - 2026-08-28
#### Features
- (**protocol**) constants for the commands the firmware has and the SDK lacked - ([ee9a66d](https://github.com/barryw/ultimate-uci-sdk/commit/ee9a66d194cd87c0a9563ef843dac00f63857261)) - Christian Gleissner
- (**sdk**) the rest of the Ultimate DOS, disk, clock, machine and HTTP commands - ([5f09883](https://github.com/barryw/ultimate-uci-sdk/commit/5f09883ac84f29e9b7578f11389839872d9766d6)) - Christian Gleissner
#### Bug Fixes
- (**cc65**) a 256-byte status decoded as an empty one - ([d74d09e](https://github.com/barryw/ultimate-uci-sdk/commit/d74d09efebf53ef0b8ffe90b92cdcd35e01d5f8b)) - Christian Gleissner
- (**control**) read a drive information reply that includes the IEC slots - ([5eaa889](https://github.com/barryw/ultimate-uci-sdk/commit/5eaa889b97220af0fd921ed09aba6b62afa8bca6)) - Christian Gleissner
- (**release**) package the blob at the base address it is actually built for - ([b02773c](https://github.com/barryw/ultimate-uci-sdk/commit/b02773c0851e6805393fda85334292887383352f)) - Christian Gleissner
#### Performance
- (**core**) count a block's bytes locally instead of through the request block - ([397bfca](https://github.com/barryw/ultimate-uci-sdk/commit/397bfca6baea9c8ef16dbfa6bbe034513640048c)) - Christian Gleissner
#### Documentation
- (**blob**) correct the $7000 placement claim, and stop printing a stale size - ([4ed2b58](https://github.com/barryw/ultimate-uci-sdk/commit/4ed2b5801577eb367e48d37991ce845d23632205)) - Christian Gleissner
- (**examples**) an assembly program for the two structured replies - ([d9134a3](https://github.com/barryw/ultimate-uci-sdk/commit/d9134a3faf825b68e6c74a707ff9df840152a19a)) - Christian Gleissner
- (**guide**) rebuild the committed PDF from the current sources - ([3e36de9](https://github.com/barryw/ultimate-uci-sdk/commit/3e36de9e9e6a31bae83445e09884ba3c028312ab)) - Christian Gleissner
- (**guide**) rebuild the committed PDF from the current sources - ([7eb5f24](https://github.com/barryw/ultimate-uci-sdk/commit/7eb5f24ec102534b72ba0490057b73a2c5bdecfe)) - Christian Gleissner
- (**guide**) correct ten wrong statements, and document the new command set - ([43490d2](https://github.com/barryw/ultimate-uci-sdk/commit/43490d264c4006c8a6897acafdb0ecbd9be3b402)) - Christian Gleissner
- (**handover**) say that section 1 is a dated snapshot - ([b8fa2cb](https://github.com/barryw/ultimate-uci-sdk/commit/b8fa2cbb8a54c44d7ab77d76a9bc1105faa8194a)) - Christian Gleissner
- (**protocol**) mark NET_CMD_SET_INTERFACE as reserved, not implemented - ([ec3571e](https://github.com/barryw/ultimate-uci-sdk/commit/ec3571e8a236400a69b79a7bdbfafda3a39c1df3)) - Christian Gleissner
- (**tests**) say what blob-relocated.suite actually compares - ([ee44808](https://github.com/barryw/ultimate-uci-sdk/commit/ee448087ec26d7274953f4c0cc65a02f4965fcb5)) - Christian Gleissner
- correct the figures that had drifted, and record three reply layouts - ([37af579](https://github.com/barryw/ultimate-uci-sdk/commit/37af57908dc08a871fb92404eaa7100e899643e4)) - Christian Gleissner

- - -

## [v0.4.0](https://github.com/barryw/ultimate-uci-sdk/compare/9da60803bb258d70b18c8f15f49844737349b414..v0.4.0) - 2026-08-22
#### Features
- (**sid**) smooth six-voice visualizer - ([9da6080](https://github.com/barryw/ultimate-uci-sdk/commit/9da60803bb258d70b18c8f15f49844737349b414)) - Barry Walker

- - -

## [v0.3.0](https://github.com/barryw/ultimate-uci-sdk/compare/aa94e49d9edd70c11888d080decfa1e84bc0e0d6..v0.3.0) - 2026-08-21
#### Features
- (**sid**) add discovery and visualizer - ([aa94e49](https://github.com/barryw/ultimate-uci-sdk/commit/aa94e49d9edd70c11888d080decfa1e84bc0e0d6)) - Barry Walker
#### CI/CD
- build demo through release target - ([8936e24](https://github.com/barryw/ultimate-uci-sdk/commit/8936e24132c134aa4fccdf8e4fe62ec26e25269d)) - Barry Walker

- - -

## [v0.2.0](https://github.com/barryw/ultimate-uci-sdk/compare/40b6e9aaa2f05353800e019ec4ac64db1e88695a..v0.2.0) - 2026-08-21
#### Features
- (**release**) embed SDK version - ([40b6e9a](https://github.com/barryw/ultimate-uci-sdk/commit/40b6e9aaa2f05353800e019ec4ac64db1e88695a)) - Barry Walker

- - -

## [v0.1.1](https://github.com/barryw/ultimate-uci-sdk/compare/ddd2d9437412812f5dda1b346b12b648edf3a25e..v0.1.1) - 2026-08-21
#### CI/CD
- publish release tags - ([fef423e](https://github.com/barryw/ultimate-uci-sdk/commit/fef423e1121e1827f6761eeb2d5873397d65c6fb)) - Barry Walker
- fail release on guide errors - ([ddd2d94](https://github.com/barryw/ultimate-uci-sdk/commit/ddd2d9437412812f5dda1b346b12b648edf3a25e)) - Barry Walker
#### Miscellaneous
- (**version**) v0.1.0 [skip ci] - ([5c2ad43](https://github.com/barryw/ultimate-uci-sdk/commit/5c2ad4342631e49a3b570966f37d8c895c4ae122)) - Woodpecker CI

- - -

## [v0.1.0](https://github.com/barryw/ultimate-uci-sdk/compare/0e6f06fc739def3d7e63178fc4ea5171bb223b48..v0.1.0) - 2026-08-21
#### Features
- UREU - the BASIC half of ultimate_reu_size - ([2b0aef0](https://github.com/barryw/ultimate-uci-sdk/commit/2b0aef04721b57ea4c677368a37486488be6e8a5)) - Barry Walker, Claude Opus 5 (1M context)
- ultimate_reu_size - how much expansion is actually there - ([94b80ff](https://github.com/barryw/ultimate-uci-sdk/commit/94b80ffd692f991653d5b3862cb3d90c263f36e8)) - Barry Walker, Claude Opus 5 (1M context)
- http.s, and the status that was never a status code - ([36c9326](https://github.com/barryw/ultimate-uci-sdk/commit/36c93264898d5592a39856851ecd1e5a151dad26)) - Barry Walker, Claude Opus 5 (1M context)
- net.s - sockets, and the four things the protocol document does not say - ([14289f5](https://github.com/barryw/ultimate-uci-sdk/commit/14289f5b68c293ea7b4d90362193bd8b4508840e)) - Barry Walker, Claude Opus 5 (1M context)
- the DOS, file and REU services reach the blob's jump table - ([81b6876](https://github.com/barryw/ultimate-uci-sdk/commit/81b687642a6bfddebc4d57ac89c6facabd9ea841)) - Barry Walker, Claude Opus 5 (1M context)
- the six BASIC keywords, and Phase 3's promise kept - ([0bf1332](https://github.com/barryw/ultimate-uci-sdk/commit/0bf13320fe748bfc3e6e943960b630ec1c20b476)) - Barry Walker, Claude Opus 5 (1M context)
- reu.s - both directions, and both halves of the service - ([862f86e](https://github.com/barryw/ultimate-uci-sdk/commit/862f86e864ea56310e099d8bff8bd338b7eaae46)) - Barry Walker, Claude Opus 5 (1M context)
- file.s - load, bload and save, with the fast path - ([96a20ea](https://github.com/barryw/ultimate-uci-sdk/commit/96a20ea6039db6406e52d79e5d2e77fe3211f248)) - Barry Walker, Claude Opus 5 (1M context)
- dos.s, and the block-at-a-time transport it needed - ([7c415db](https://github.com/barryw/ultimate-uci-sdk/commit/7c415dbe08f7665b12c35f02b30ebe924fb02b36)) - Barry Walker, Claude Opus 5 (1M context)
- turbo, in assembly, C, BASIC and the blob - ([ac68ccc](https://github.com/barryw/ultimate-uci-sdk/commit/ac68ccc5dbad5cbfbc1e645aaa6520086ab24abe)) - Barry Walker, Claude Opus 5 (1M context)
- wrap the palette commands as a service - ([ce1652e](https://github.com/barryw/ultimate-uci-sdk/commit/ce1652ed0735b7c9c51b2cdf1dc322c16f70819e)) - Barry Walker, Claude Opus 5 (1M context)
- measure a UCI round trip against the raster - ([2329871](https://github.com/barryw/ultimate-uci-sdk/commit/232987141fdda81e6c6d5af66730ac7b4fee15c2)) - Barry Walker, Claude Opus 5 (1M context)
- generate the Ultimate 64 turbo register constants - ([1db275b](https://github.com/barryw/ultimate-uci-sdk/commit/1db275bbcb44385aba516b8697b2ddacc52af085)) - Barry Walker, Claude Opus 5 (1M context)
- argument shapes drive the wedge, and the cartridge build - ([82eabe8](https://github.com/barryw/ultimate-uci-sdk/commit/82eabe8d90f716988b0a131f3482a74607ecfcd7)) - Barry Walker, Claude Opus 5 (1M context)
- the wedge's tokens now run - UCI, the observers, UW() and UL() - ([eb7a8ad](https://github.com/barryw/ultimate-uci-sdk/commit/eb7a8ad73b1a0ca51cbfe8864a344d766b5a0eeb)) - Barry Walker, Claude Opus 5 (1M context)
- the BASIC wedge tokenises and lists its own keywords - ([8ecafaf](https://github.com/barryw/ultimate-uci-sdk/commit/8ecafaff93b66a2a3222a55b6ba9e70c492834c3)) - Barry Walker, Claude Opus 5 (1M context)
- model CRUNCH and generate the wedge's keyword table - ([ff9c941](https://github.com/barryw/ultimate-uci-sdk/commit/ff9c9413423a5fc3558fade7165b35191cf86e4a)) - Barry Walker, Claude Opus 5 (1M context)
- generate the wedge's runtime argument table from ARGS - ([9f3540e](https://github.com/barryw/ultimate-uci-sdk/commit/9f3540e5c160a34831db23c84c0c69a4972972e4)) - Barry Walker, Claude Opus 5 (1M context)
- make the UCI argument shapes structured data - ([6b06e5b](https://github.com/barryw/ultimate-uci-sdk/commit/6b06e5bbaf9d9e807087875e2a1fcfa5b59b7420)) - Barry Walker, Claude Opus 5 (1M context)
- extract a reusable Ultimate settings guard for tests - ([494aec1](https://github.com/barryw/ultimate-uci-sdk/commit/494aec1003865549c408e82ffe523f2215437fb4)) - Barry Walker, Claude Opus 5 (1M context)
- emit protocol constants for KickAssembler and ACME - ([5c35b88](https://github.com/barryw/ultimate-uci-sdk/commit/5c35b88171b6132a3dc4472b50928ac1e0a0aee2)) - Barry Walker
- relocate the blob at runtime, and prove the table is complete - ([435c376](https://github.com/barryw/ultimate-uci-sdk/commit/435c3767e78ae89788beaa351fed88ada8ff49a1)) - Barry Walker, Claude Opus 5 (1M context)
- generate the blob's relocation table by diffing two builds - ([46b6442](https://github.com/barryw/ultimate-uci-sdk/commit/46b6442dafe60ca6fc430433f7cc53b15a614e8d)) - Barry Walker
- page-aligned parameter block in the blob - ([d10d2b0](https://github.com/barryw/ultimate-uci-sdk/commit/d10d2b0effa930ea6329a8a89821c5c202a56430)) - Barry Walker
- build the SDK as a standalone blob with a jump table - ([c0c33d9](https://github.com/barryw/ultimate-uci-sdk/commit/c0c33d9ef054362c5ff9ef71cf710153ad70e921)) - Barry Walker
#### Bug Fixes
- build on the cc65 that CI actually has - ([8b08846](https://github.com/barryw/ultimate-uci-sdk/commit/8b08846c143e67a8b8b4fdfebbe9dc647aa56fbb)) - Barry Walker, Claude Opus 5 (1M context)
- the hardware test must not assume a peer, and must not be the slow one - ([3e109a9](https://github.com/barryw/ultimate-uci-sdk/commit/3e109a98c3b537377fefe2559892b58de012615e)) - Barry Walker, Claude Opus 5 (1M context)
- a filesystem error arrives in words, not in a code - ([9770fbe](https://github.com/barryw/ultimate-uci-sdk/commit/9770fbe343ca6e35cd66e0b294aa47983bdf330b)) - Barry Walker, Claude Opus 5 (1M context)
- the cc65 side was printing graphics glyphs too - ([a01282e](https://github.com/barryw/ultimate-uci-sdk/commit/a01282e1e3ff64c4422c2dde16b8f2c3c209f97a)) - Barry Walker, Claude Opus 5 (1M context)
- make the BASIC wedge work on real hardware - ([19450ae](https://github.com/barryw/ultimate-uci-sdk/commit/19450aefccecf1eb937d26966fdaedeecfb1b239)) - Barry Walker, Claude Opus 5 (1M context)
- append missing blob exports, harden two vacuous timeout/init tests, and cover two more generated bindings in CI - ([3e2bd71](https://github.com/barryw/ultimate-uci-sdk/commit/3e2bd71a7bb55b1147b455770f03009c5d7c92bb)) - Barry Walker, Claude Opus 5 (1M context)
- prove relocation completeness by comparing against a ground-truth $8000 build - ([7f80f95](https://github.com/barryw/ultimate-uci-sdk/commit/7f80f95d74dd347c0791681c2bf51b2b413f9473)) - Barry Walker, Claude Opus 5 (1M context)
- place uci_req through UCI_VARS like everything else - ([9d19be9](https://github.com/barryw/ultimate-uci-sdk/commit/9d19be9e05e8779ec4dc3d712e9fca6f1d44c284)) - Barry Walker
- place ult_probe_target in the shared variable block - ([78ed75d](https://github.com/barryw/ultimate-uci-sdk/commit/78ed75d82f3f14f62b95785a94bd454f0df1f752)) - Barry Walker
#### Documentation
- (**guide**) rebuild SDK reference - ([079239c](https://github.com/barryw/ultimate-uci-sdk/commit/079239caec9e1f973ec933ca0be1f72e6f7a53d9)) - Barry Walker
- a programmer's reference guide, in the shape of a Commodore manual - ([85c1354](https://github.com/barryw/ultimate-uci-sdk/commit/85c135403f3e580fb5537d11e52ee82acf7f4003)) - Barry Walker, Claude Opus 5 (1M context)
- measure every figure again, and fix the nine that had drifted - ([4dd019a](https://github.com/barryw/ultimate-uci-sdk/commit/4dd019a438fd480faa1cfdd97c955500fa40a6a8)) - Barry Walker, Claude Opus 5 (1M context)
- hand over the cleanup pass - ([bdff6e0](https://github.com/barryw/ultimate-uci-sdk/commit/bdff6e0c2d0653dcb06379070c7cb31e0eb6e837)) - Barry Walker, Claude Opus 5 (1M context)
- Phase 3 is done, and what it found out on the way - ([dde1362](https://github.com/barryw/ultimate-uci-sdk/commit/dde13622bd1f5b18187f839f98c8807242c53b51)) - Barry Walker, Claude Opus 5 (1M context)
- hand over Phase 3 in progress - ([71b42f4](https://github.com/barryw/ultimate-uci-sdk/commit/71b42f4810506ca40eb65bbf7d6cd68539ab1075)) - Barry Walker, Claude Opus 5 (1M context)
- hand over the loose ends, the turbo question and the boing ball - ([e414acc](https://github.com/barryw/ultimate-uci-sdk/commit/e414acc7e96d7468a4794c4bd955e066a73c2a99)) - Barry Walker, Claude Opus 5 (1M context)
- correct the hardware-run line after re-running the matrix - ([d53814c](https://github.com/barryw/ultimate-uci-sdk/commit/d53814cf6dc8a9685f64a4a58603d5fe27f41b00)) - Barry Walker, Claude Opus 5 (1M context)
- record #794 as intended behaviour, not a firmware bug - ([074d90c](https://github.com/barryw/ultimate-uci-sdk/commit/074d90cd6deeb322b887897b06703ced8f84a347)) - Barry Walker, Claude Opus 5 (1M context)
- record the settings guard in the handover - ([a5db3c6](https://github.com/barryw/ultimate-uci-sdk/commit/a5db3c60e9d4e86b2f5698256f61115d3edaac32)) - Barry Walker, Claude Opus 5 (1M context)
- rewrite the handover for the state after phase 1 - ([3fa11dc](https://github.com/barryw/ultimate-uci-sdk/commit/3fa11dcd8e8669c740072bdb62c3aad7c2f2315c)) - Barry Walker, Claude Opus 5 (1M context)
- correct the emulator test count - ([5bd03d1](https://github.com/barryw/ultimate-uci-sdk/commit/5bd03d10e11e96401a822bcffc11b8f2750cec12)) - Barry Walker, Claude Opus 5 (1M context)
- document the blob, its jump table and its parameter block - ([1b873b8](https://github.com/barryw/ultimate-uci-sdk/commit/1b873b86f8321a4ecd13e0d8d5ec8dc87f68e4a8)) - Barry Walker
- the control register's DMA bits are freeze, not a fast path - ([cfdda41](https://github.com/barryw/ultimate-uci-sdk/commit/cfdda41a1ad80b1159f36ea003823f0f2346535a)) - Barry Walker
#### Tests
- the socket round trip, proved on hardware - ([230f35a](https://github.com/barryw/ultimate-uci-sdk/commit/230f35abe03bcff340f63ee38860da4b9ccbe8fa)) - Barry Walker, Claude Opus 5 (1M context)
- a keyword that dispatches to nothing fails the build - ([f723485](https://github.com/barryw/ultimate-uci-sdk/commit/f7234852cbca3d7e3eddb95a86419b372364d1a2)) - Barry Walker, Claude Opus 5 (1M context)
- the write half runs on hardware, on the RAM disk - ([c16f38a](https://github.com/barryw/ultimate-uci-sdk/commit/c16f38a4d73027f467f7f1c83e6eed6d15753377)) - Barry Walker, Claude Opus 5 (1M context)
- run the same hardware checks from the cartridge - ([a5ef5b5](https://github.com/barryw/ultimate-uci-sdk/commit/a5ef5b582dbbb78a1f084063c881ac3671590a37)) - Barry Walker, Claude Opus 5 (1M context)
- cover the wedge's LIST lookup, which the last commit only claimed - ([3ca2aa9](https://github.com/barryw/ultimate-uci-sdk/commit/3ca2aa92dbcfa0f2941b75d7f29c3475010175e0)) - Barry Walker, Claude Opus 5 (1M context)
- drive the blob through its jump table with no symbols - ([bbee7b7](https://github.com/barryw/ultimate-uci-sdk/commit/bbee7b78d7a6f3f9d732ae861c176ceb953939e4)) - Barry Walker
#### CI/CD
- trigger initial release - ([1b746b5](https://github.com/barryw/ultimate-uci-sdk/commit/1b746b59584202bf3d2f6e9333b6ceb56b04fecb)) - Barry Walker
- automate SDK releases - ([81ddca5](https://github.com/barryw/ultimate-uci-sdk/commit/81ddca55583f8c9eefc77e45ee964815c8dcd164)) - Barry Walker
#### Refactoring
- the SDK moves to $A000, under BASIC ROM - ([33ebb01](https://github.com/barryw/ultimate-uci-sdk/commit/33ebb01f33180aa8ea00e97ebe1b4b4ec544296e)) - Barry Walker, Claude Opus 5 (1M context)
- split ultimate_strerror into its own module - ([7ff83aa](https://github.com/barryw/ultimate-uci-sdk/commit/7ff83aa96fbed42b80de06477ac437c158dc5a2e)) - Barry Walker
#### Miscellaneous
- a cleanup pass - current docs, one real bug, and 71 bytes back - ([922ba4f](https://github.com/barryw/ultimate-uci-sdk/commit/922ba4f83662f530316b3b2d8484fea6ddc657a2)) - Barry Walker, Claude Opus 5 (1M context)

- - -

Changelog generated by [cocogitto](https://github.com/cocogitto/cocogitto).
