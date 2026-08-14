# Evidence-Driven Synchronization Commit Index

Generated: 2026-08-14

This index covers the startup boundary
`9668770830acdeaae87278502b3e04f66101a89b` (exclusive) through the
pre-closure head `75548e6f95e0b1b58f07abd43793600320d192e5` (inclusive).
The terminal SYNC-000A documentation commit is reported by SHA in the final
handoff because it creates this index.

The chronological list is a direct Git-history readback. Full SHAs make every
implementation, repair, validation, and closure slice independently
addressable. Mainline integration commits are separated because they are not
migration slices.

## ID-Tagged Migration And Validation Commits (496)

```text
94d5ef2667316f5f28310381baa9a5057f0fda0e	docs(sync): establish SYNC-000 migration baseline
695f7403adf475da45e0774f327004a32d4d81ab	refactor(sync): migrate SYNC-001 remote AX scan
d267c491b8a3ea09aa9c1da4c5412ade52f11255	refactor(sync): migrate SYNC-002 app launch readiness
de5f77851958c4f861bdc531fe7582ec5fd4216c	refactor(sync): migrate SYNC-003 transient repair readiness
8b593e8eece12e6c5ab12af2ee511515536d6c57	refactor(sync): migrate SYNC-004 AX window evidence delivery
dfc3389fc37075717fafb2142581d037e3dc01a7	refactor(sync): migrate SYNC-005 Chrome focus readback
96daf6f85514547c5450a3e3e69945464c9f9869	refactor(sync): migrate SYNC-006 activation convergence
d9bf79aae7da1db90b645ffe4ff4c80ef6f222bc	refactor(sync): migrate SYNC-009 runtime log observation
6b7a6d295a606428ff13d45b2c491d027f0298a6	refactor(sync): migrate SYNC-010 diagnostic session deadline
d18d1b5c48a44b772481ff771c2a125105756dfe	refactor(sync): migrate SYNC-012 permission observation
e7b209a2a1a23b298f113fdb489f951a7bf59e9a	refactor(sync): migrate SYNC-011 home permission observation
cf6318ec68db4cef1bb58c105d2aeb642eebdf38	refactor(sync): migrate SYNC-013 home initial readiness
fa8ef7e014a7cfe0ccfe846c2634764402cd9ff1	refactor(sync): migrate SYNC-040 home summary updates
113f9bdf07fe166d6d74f66fe39c77e1a1aa78e2	refactor(sync): migrate SYNC-041 home detail updates
d30626ea9c48e88564f5640d6d70e7fe7fc7a7cd	refactor(sync): migrate SYNC-014 status item activation
76827b26f68878cc8c61ea9cc1f337ca9d8a89e0	refactor(sync): migrate SYNC-015 search scheduling
aa62c7deef87d1ed805dee239581c33ec6009aa1	refactor(sync): migrate SYNC-016 hotkey registration status
7abc326547bc11c5e0de9cd9d446a1261d2b3ab3	refactor(sync): migrate SYNC-017 modifier release observation
44b0802a477b12351df5de7ad70fe24a06c60f73	refactor(sync): migrate SYNC-018 hotkey input identity
a0b746b004333a304b8b328ffa2519e5aa35a040	refactor(sync): migrate SYNC-019 initial panel visibility
206afdffa78e3bc1e193033fe03e1f06b69be0e3	refactor(sync): migrate SYNC-020 panel visibility recovery
b7a1b2263598dfbd5f18797501dfdc0f4e0eb549	test(sync): correct SYNC-020 cancellation pressure oracle
17a0e8552fe31a64db60586cdb012a59c348c1a1	refactor(sync): migrate SYNC-021 active Space transition
29645db31b29a4efab45d7543e2f3b13f69e5a83	refactor(sync): migrate SYNC-022 terminate interruption protection
6c3f3810a6a4090018b7587904417f10a4a55754	refactor(sync): migrate SYNC-023 delayed window-layer entry
f5bb3c29601866705ecf6b34afce29ef58976565	refactor(sync): migrate SYNC-024A terminate press completion
845d353574cb99c384cee9eae543747d5bdfb7f8	refactor(sync): migrate SYNC-024B initial preview reveal
5a3e470c7e7d6cbd8bc6eb5788d657dfe0b7f203	refactor(sync): classify SYNC-024C app removal animation
a0096673a73927dd02b1959f80b016f965f4a247	refactor(sync): classify SYNC-024D home press animation
0e682598d51861495185b6bf2fdeed038504d4c7	refactor(sync): classify SYNC-024E settings navigation animation
b95e5998e8701c9ef6a84bb5e089c47165e1ae27	refactor(sync): classify SYNC-025 presentation diagnostic sampling
e934fd2a5abc61bb0fdbd8d745e6d5993884ccf9	refactor(sync): migrate SYNC-026A fullscreen transition chain
8c5554912551fe1b5f5edea0e4e85c0ad4e29a78	refactor(sync): migrate SYNC-026B desktop refocus
ea0b73d19ea0c1d725938a3c97d44648c6100d61	refactor(sync): publish SYNC-026C1 projection acknowledgement
4d3a6222de4c38034625f5a62ca4efc23fb67375	refactor(sync): migrate SYNC-026C2 AX suppression
44cb4dc3b9676cbb9444b9041017757912dff570	refactor(sync): retain SYNC-027A termination fault policy
80254968b03675f233928159d55e03c80e98e2d1	refactor(sync): migrate SYNC-027B window close fault
9a8363f9f6e78704aeecf644d5e2f16a8e907563	refactor(sync): migrate SYNC-028A fixture readiness
025ef62938cc3b930b520722e66a7a6a929eba76	refactor(sync): migrate SYNC-028B1 workflow readiness
397ab8c3f3d70537ff3619754d04181d2a38acba	refactor(sync): migrate SYNC-028B2 desktop anchor
8092758e0e0fca7eb0d9a6345f504b9c50b900db	refactor(sync): migrate SYNC-034A exact window oracle
1c4dae662a0a9179b8edde21fb9ce8adc34e4385	refactor(sync): migrate SYNC-029 initial UI readiness
65a74c1b672aa62fc4a0ed7ca4ec1c7bc7eaa4fd	refactor(sync): migrate SYNC-030A preview latency
e6ee592e35033f64b478b0a740e370e992e7a9ab	refactor(sync): migrate SYNC-030B occlusion staleness
3b4668a26ae3ab89f957b6a66aa5f6a07848269e	refactor(sync): migrate SYNC-031 tab stress
83dc6d6adba43da1f3d4c5bf8ce7aa9c57718ed2	test(sync): migrate SYNC-032A app visibility reload
65ef5cb4561d8a88a2a6fe0d07aee8a29b0d124d	test(sync): migrate SYNC-032B1 workspace delivery
06f26034464bc2529b920c2a33a70aaea12cbcbc	refactor(sync): migrate SYNC-032B2 hotkey delivery
a8469a684c5e7f504f598e78d9aeb3f00905674f	test(sync): migrate SYNC-032C termination search refresh
6c308e8c5fbc809283e341883725d59cce243378	refactor(sync): migrate SYNC-032H launch bootstrap
3857a8576ac7cb805654f60a72113cc3fc74334f	test(sync): migrate SYNC-032D1 preview publication
be645c87c6972aa72c609a0ba9b01a64fabccec2	test(sync): migrate SYNC-032D2 preview reveal
454c63574e270eba9a2b8b7cccfd40748fc71a27	test(sync): migrate SYNC-032E1 search scroll publication
6f00bc18461643a8ccb023d0c71de66c506c4def	test(sync): migrate SYNC-032E2 initial search presentation
cf4890e2c57d4024add168e91698899e1f4adc4d	test(sync): migrate SYNC-032F terminate feedback entry
a88bdde79a5e1be066282f4827d5bf1a04d8f3cc	test(sync): migrate SYNC-032G1 delayed entry deadline
171cee6eceed016b72233d84e6c31e7ec94dbe0f	test(sync): migrate SYNC-032G2 manual entry evidence
4322115416ad1099b542f964b570cebc010b82eb	test(sync): migrate SYNC-033C notification publication
a70b527363f21a3810b7db0ee410dbd3fc96ce07	test(sync): migrate SYNC-033D AX background resolution
c76b13c9c24f515fe7be223cfbdb835d38bc54c5	test(sync): migrate SYNC-033E AX collection pressure
b07c75cb7f2adf6b70df3b543d46a621f5fa62f2	test(sync): migrate SYNC-033A hosted Logs controls
3d09a602ed242809944ba4439e2e726af0c82a4c	test(sync): migrate SYNC-033B1 system theme readback
c87d1483fad7505e70375e4beb771de17157e4ea	test(sync): migrate SYNC-033B2 Settings presentation evidence
413038061ae0e6eaa8808405e4dc75676bfa8b4e	test(sync): migrate SYNC-033B3 permission readback
74afd40ea55345a74f70918606af9a44d1bb6a85	test(sync): migrate SYNC-034B frontmost activation
9838f69b36a5fa812878ec6446126590f659e490	test(sync): migrate SYNC-034C app order observation
f53afd3aa00fa895dbcef98ede4d626a8cbc9c16	test(sync): migrate SYNC-034D process termination
9e84dbe7675f0d9c070c3b074ecbe9c58c779dbf	test(sync): migrate SYNC-035A switcher dismissal
442de518dff8a35b4fa9318b39d365ee53a34cbf	test(sync): migrate SYNC-034E status observation
483ff018f5f877b62ab82e5ec05adc23aabe0b57	test(sync): migrate SYNC-034F takeover marker
65bbc1e7ad96c9a5f45e4bcccf2c4b2eb57b99cc	test(sync): migrate SYNC-034G hittable queries
1c1656ba686b56f831c3265ac6fc1b0d0478d703	test(sync): migrate SYNC-034H element values
c6be9c9c9aee8708481976cd6a450b8ef1abbee9	test(sync): migrate SYNC-034I serial readbacks
ed81aabb1c3e38159797d11f6922cce1cbe0ce6e	test(sync): migrate SYNC-034J Home projection
f5d9dbb8369635a7742187bd347213d8b0991d51	test(sync): migrate SYNC-034K Switcher titles
b5e3302588a9d56ad12b49edae0c90029ae1cd10	test(sync): migrate SYNC-034L Switcher cards
e2a81f52783595306a552b890401bb4633b45cc2	test(sync): migrate SYNC-034M Logs projection
336c50afdee2345ff79c94e552b23332e392881e	test(sync): migrate SYNC-034N runtime log observation
881cca7be035f367bf8f72cae23bf32d37c70ed1	test(sync): migrate SYNC-035B settings commit
57681626afe97e17005bb1ad598af8a6c746a742	test(sync): remove SYNC-034O obsolete focus wait
44d7063f062bca398ed3ddde59d0d25be905d42f	test(sync): remove SYNC-034P obsolete absence wait
01c3786f6fe9d15b859fc79645d3bf599aeaa1d2	test(sync): migrate SYNC-034Q workflow window activation
16382e8be956c752351807640891e015ef2bc37f	test(sync): migrate SYNC-034R dropdown scrolling
ac3bb50fd4dec7265ae355edb90ccdaa8c328778	test(sync): migrate SYNC-034S scrolling visibility
4ea39c42683aea779b3866a6a0f1d38a3d758075	test(sync): migrate SYNC-034T Home app selection
d3d8d55a04eb5a856a574c9d144ffdef1a9b936a	test(sync): remove SYNC-034U obsolete topmost wait
6e1441a8ae82106ab56b2dc107fce9a462b7b0aa	test(sync): migrate SYNC-034V exact CG window wait
3eeaea6bea7288a46ea2eea8f6b25e354a5207d6	test(sync): migrate SYNC-034W frontmost Space window
911cfa9216aaba12962002526849977d22a3eab1	test(sync): remove SYNC-034X obsolete active-Space wait
8ef8de839b7bb59f9c2509caa3fed372449948f6	test(sync): migrate SYNC-034Y active-Space window
9f9fec8f7c1e39327a473c0dd195da9d4bc00ad4	test(sync): migrate SYNC-034Z Space window collection
dfbb8bba780b32e5abd308c514b79c900aeb980a	test(sync): migrate SYNC-034AA Settings luminance
4925d6e27aa5a57b3df2a91318ad8ca6f9ad4375	test(sync): migrate SYNC-034AB switcher diagnostics
0b350c14f5e12d5532ead279e58540a4e2f906b1	test(sync): migrate SYNC-034AC pointer diagnostics
c3d1b4e8c155b7fcc35837c54321b4e9b04417e9	test(sync): migrate SYNC-034AD runtime diagnostics
2fea9b3fedbae46f434bcba663692f7c6d02db90	test(sync): migrate SYNC-034AE Search index diagnostics
28c46cff506942c8d05fcdf437be1a455e0cb2f1	test(sync): migrate SYNC-034AF Search result projection
0b75dba39115a011e2e55cfa47aa78c6a57ff20b	test(sync): migrate SYNC-034AG Search selection
967d337c804fedaee359ce7173ffabc7f4c37be7	test(sync): migrate SYNC-034AH app projection
9f8755d9c25b027a4b3f82b0ced0fc2ec00f270e	test(sync): migrate SYNC-034AI selected window title
4c0ab8757b3bf2658f8d56cb971db28cc84b671e	test(sync): migrate SYNC-034AJ preview projection
87dee36e054510aa17762686d115cbbeb5c6e9b1	test(sync): migrate SYNC-034AK selected app preview
42359d455771c2f431f160b5e4d32f7ce5b8ef06	test(sync): stabilize SYNC-017 modifier event oracle
0581ea0c9b03755618432586df7f8d2d86c94e6a	fix(sync): require SYNC-029A initial search activation
af8e2a1c9e059b9e8f243bfac22f36ececacb249	test(sync): migrate SYNC-034AL preview transition
b0779983c5d3f23fd2fcd768c7e36f2f8e271a72	refactor(sync): repair SYNC-028B1R readiness readback
50d03b593325b4b228398dd92b5b3a999e3e2664	fix(sync): route SYNC-028B1T prepared fixtures
e0d97dc99475dc2288a239b0e739ee0d255a49be	fix(sync): refresh SYNC-028B1R2 readiness readback on events
7012591c013dc502895c0ad3351fdc90a43f029e	fix(sync): preserve SYNC-028B1F fullscreen plan
a7641d1e72703a74b033ebf2eb1fa76f6fd5e31d	fix(sync): repair SYNC-026C2R AX readback
e953f440b5dffbe2fb6e87a1fb74328b3ffbdec5	test(sync): migrate SYNC-028B1M metadata readiness
f587450390b6011e6ed4aad93c216aaeee21afdd	test(sync): migrate SYNC-035C window selection
1662e140a539e248a1fa039dbb9b2aebc88bae6c	test(sync): validate SYNC-034T Home app selection
a7ccda2421058bcbc5405a0fae829af5dbe385bf	test(sync): validate SYNC-034V exact CG window wait
f8f63b37a1ffaf48e45c78c2d518bac3cb4b8442	test(sync): validate SYNC-034W frontmost Space window
244d71f5c465490d0725b3c386daab6456eaf738	test(sync): validate SYNC-034Y active-Space window
2bb010b8e414f98f45a08434c9cd0737492deda6	test(sync): validate SYNC-034Z Space window collection
93bf9e241e08c111be04f01c5b7350ae8d90d62f	test(sync): validate SYNC-034AA Settings luminance
0ba2634726de6556cff65a2459966805c7f1977a	test(sync): validate SYNC-034AB switcher diagnostics
adbd5f0650fceec4444e3f99ec1f9ccb7f28e2f5	test(sync): migrate SYNC-034AM process termination
9bcdcabd4e9af401ea891f0bc1d14c0ec5927fde	test(sync): migrate SYNC-034AN pointer presentation
96bd1542d8ea5b5fb5036342682c04ddcfc3a49a	test(sync): validate SYNC-034AC pointer diagnostics
981c2af7248143aab22a2180491939cf1564fc37	test(sync): validate SYNC-034AD runtime diagnostics
35b37bcfc9cecf04e35d43cca0d1d5746045bcc7	test(sync): validate SYNC-034AE Search index diagnostics
8ebeac22603dfe43c8eea7ebdec460c326e482db	test(sync): validate SYNC-034AF Search result projection
1e1e1c60374f3336bf3510b5d3d9ad5e7d7dcf88	test(sync): validate SYNC-034AG Search selection
edeffe3c773e7760117ff33b0b4115a41aa2af76	test(sync): migrate SYNC-035D fixture refocus
873af908939a612dba065f6357eea5bf976a5e83	test(sync): migrate SYNC-034AO trigger completion
b3f6aff07c64f7291b5fa00f1ac3bc9dc15ced85	test(sync): validate SYNC-034AH app projection
f2853b1cc2d88368a7771a43982d7b6c50a3e01b	test(sync): validate SYNC-034AI selected window title
a9cef9dd21be0a964ed22e80aefab62f39152281	test(sync): validate SYNC-034AJ preview projection
e21556a76f18b689b1a4f4c834ce947133a78403	test(sync): validate SYNC-034AK selected app preview
23aa6b540017350a2a28381afc14e477967b1193	refactor(sync): migrate SYNC-035E Search input readiness
0383536b6f3964ed0d32140e905846d0798c5405	test(sync): migrate SYNC-035F window selection
9b3f2738e26d525ad90260f261686e2b1217ce9a	test(sync): migrate SYNC-034AP fixture termination
a52e5e7bf9dff745a750d2ad7ab84f3bdae4260d	test(sync): migrate SYNC-035G Search selection wrap
40dbe442ab21ff81a515ea62b1fa77294437f65d	refactor(sync): migrate SYNC-035H Search result completion
bd3564cb5024b7fa69eb00799145d53af89e5241	test(sync): migrate SYNC-034AQ Home app value
6b63588a945da5c785cc153ea0ca4a102da3a807	test(sync): migrate SYNC-034AR Home window order
f62fa5288b309e07e1533135d175217d3f6bbc01	test(sync): migrate SYNC-034AS fixture process exit
6ee6db40b4b1403668739d771293254021ed4be2	test(sync): migrate SYNC-034AT Switcher summary
f919e8152bea1ecaf6d4e52f7555d692cf59e11d	test(sync): migrate SYNC-034AU in-app readiness
1e27acbce9840ce3067ee53e9ac9548afb08ef61	test(sync): migrate SYNC-034AV fixture cleanup
321569f0868a690347ba1fe215ccf113b1b88fee	test(sync): migrate SYNC-035I provisional hidden state
bb6b16213c484783d1cf1a5baa5a6442ac8004f6	test(sync): migrate SYNC-034AW Edge app selection
4f954069d6b3bca58fbeb1025140b2cbf526bb9e	test(sync): migrate SYNC-034AX Edge window cards
c53ef2a5a233eb76c8d9bd63c99c26743f03da39	test(sync): migrate SYNC-034AY Edge Search results
a756ca219a5cf8763fa26c0cdbdf1e417736f75a	test(sync): migrate SYNC-034AZ multi-app selection
0c700c183c2abe91b09f8e3e9d46420053f67903	test(sync): migrate SYNC-034BA keyboard selection
0dd8c4a8d03a3751f87348872e46a382931f7f82	test(sync): migrate SYNC-034BB preview exit
457ab9fbdaf55767626b84e4308f2ae8cab8bd7f	test(sync): migrate SYNC-034BC initial presentation
bfd54538131228e9b172277b85cfe6637d6abf51	test(sync): migrate SYNC-034BD preview exit
3b0180137fd4b242dae32da53f2bed3631eb60a1	test(sync): migrate SYNC-034BE preview entry
476e431013e5a39f7bee6bb8efcc51b3312f8748	test(sync): migrate SYNC-034BF search activation
78d9efaf2e044c2ffe62ea67cd95c65165af71af	refactor(sync): migrate SYNC-035J home initial projection
f430fc67ccd49378c13fcf6c4c8a4225b46b6fe1	refactor(sync): migrate SYNC-035K stationary pointer gate
1c0d3d65f7bda18ce7cba71b44a655e3c4ec9f5d	refactor(sync): migrate SYNC-038A release process exit
b3122466393409d71aca76e73a1af9743ddec98e	refactor(sync): migrate SYNC-038B uninstaller process exit
eb1bbc1921670bbdec8d84ef2ab4845f61a76eb1	refactor(sync): migrate SYNC-037A tab stress process exit
d30d4a3d340767ee1adb0204d32ede6d731d7beb	refactor(sync): migrate SYNC-037B search pressure process exit
dc4b9d55304716b12ee16af8890b8b27443b3ec7	refactor(sync): migrate SYNC-037C topology pressure process exit
0634b5203e20b1e3a3e17ae74e595b57514a8165	refactor(sync): migrate SYNC-037D topology application cleanup
f1bf64cf5e2e88e982d7009343f54fe13154fdd3	refactor(sync): close SYNC-037D1 application process exit
de94837b0b705587d14b954db09eafb6b9cbe21b	refactor(sync): migrate SYNC-037E target exit completion
b7e84cd7e5f3b3076a46e9ea4837b57a68bcda88	refactor(sync): migrate SYNC-037F target launch readiness
1678fe6c541491c53bbb27b2c83dd6999dbbf510	test(sync): migrate SYNC-036A UI support watchdogs
92ca82236fc4cb8d4465b156d4902fa09ad59d6c	test(sync): migrate SYNC-036B runtime log watchdogs
dc274a33d989d427402229adb99bda17f4a1b3bb	test(sync): migrate SYNC-036C pending termination oracle
a7864bb5693acf311e89b782e6b405640800af1f	test(sync): migrate SYNC-036D termination layout oracle
25f1f229765eee03f9f2399795869f3f1de73d46	test(sync): migrate SYNC-036E keyboard readiness watchdog
75f1a3252e957ef3e0f6ae34f5a12325da3e1e6d	test(sync): migrate SYNC-036F main queue watchdog
1e6be861ac5d738039c9cf3f2f3a1ae8a0eac856	test(sync): migrate SYNC-036G maintenance watchdogs
9545e798c0488d6e6d99d499c632803911f6d00b	test(sync): migrate SYNC-036H preview event watchdogs
4b3cf8067c7a5d0930054460f0f196f93f9a04d9	test(sync): migrate SYNC-036I focus recovery watchdogs
2cb7e5a0d454e6de12c96d86d1ddfc287054ac86	test(sync): migrate SYNC-036J workspace lifecycle watchdog
ca570d52194e5ec5f2056eb0cd1a76a5e7998491	test(sync): migrate SYNC-036K app launch maintenance watchdogs
bab94459cb4399426be515a42ffb21de444cfc80	test(sync): migrate SYNC-036L initial Search presentation watchdog
57e82b98242a3e04c45f5d46b0c1d9f004f8931e	test(sync): migrate SYNC-036M committed Search publication watchdog
19d5560b7277edcb7d62da6293527155c745ed49	test(sync): migrate SYNC-036N projection main-thread delivery watchdog
28c4d4b50c17b17909e3682790682917974d2cff	test(sync): migrate SYNC-036O Search scroll publication watchdog
6815a9ed568ef91d6b1b8a6965ab2bce03e4e145	test(sync): migrate SYNC-036P Search computation watchdog
497bd5b3f6efdd8eb9eaacc5344e709407b674a9	test(sync): migrate SYNC-036Q termination Search refresh oracle
0c3fd1b38d3b3133ae46da931c959f20c0986fc8	test(sync): migrate SYNC-036R Home maintenance watchdog
5278ea007ace11176b3b31d476af7448de51ad0a	test(sync): migrate SYNC-036S Home detail evidence watchdog
70544028b4a9cd714eda8071b57a82ac8d5f9f46	test(sync): migrate SYNC-036T Home summary evidence watchdog
988fb5414bea1810c9ce71ae16cf15ba9eeb7b7a	test(sync): migrate SYNC-036U Home permission lifecycle watchdogs
853df0ee7f288f95b4a2b083249c2cfeafc980b8	test(sync): migrate SYNC-036V hotkey evidence watchdog
8c497381daf3dfcf4c2924f3723ad87a71d0c093	test(sync): migrate SYNC-036W AppDelegate hotkey watchdog
ef92b3a00d56d3c1f9b35892f9f633d5b2b7c602	test(sync): migrate SYNC-036X Search coverage repair watchdog
bd04f3df0c68e6ca22df745b3a784e22007a287a	test(sync): migrate SYNC-036Y AppDelegate bootstrap watchdog
da27f7be3fdc6f53c13b837287c2651caa68d0c8	test(sync): migrate SYNC-036Z termination refresh oracle
eac6cfbe53d102935422c4359dec4e8b24517127	test(sync): migrate SYNC-036AA preview publication watchdogs
f175ae4d432c1296ca8bc135459109ef317c4fbe	test(sync): migrate SYNC-036AB preview batch start watchdog
7a87196cbb33f6223b7e60505243b3ad87272eaf	test(sync): migrate SYNC-036AC initial preview reveal watchdog
4db05a9a84e225bc46e63c34cfbe5f046b9858db	test(sync): migrate SYNC-036AD termination layout oracle
9c1a793bf697074feca3d27434ee6d460442615d	test(sync): migrate SYNC-036AE occlusion cleanup watchdog
67c365edf2511204088a43bd96290fe75bd79ba8	test(sync): migrate SYNC-036AF app visibility watchdogs
d851e1ac3bcdaed91b93956ff78db74b32120fff	test(sync): migrate SYNC-036AG preview latency watchdogs
96019e0415947d1739ab255676c8f3f8d1f3f131	test(sync): migrate SYNC-036AH remote AX scan watchdogs
e1b7f66c043ad9090f80c7856ed4219d70591d5f	test(sync): migrate SYNC-036AI termination feedback oracle
8d23286015b22d236ff73d8bbffc9bfc9c0da5bb	refactor(sync): migrate SYNC-036AJ app window operation evidence
bd27debcaee8822728aa5a3e6327fa3b646d00f3	test(sync): migrate SYNC-036AK readiness aggregate readbacks
6673d485d23aa892a2b08b1261852bb9440d4b81	test(sync): migrate SYNC-036AL RuntimeLog readiness watchdog
df4fbf953c924f1847fe406516eb9fb005e08081	test(sync): migrate SYNC-036AM termination watchdog override
17e2f9a07cf4bf523be00c0921fee3a29da4904a	test(sync): migrate SYNC-036AN Home selection budget
65e9496863b18616245ed6d9f0319d7e48ff2b70	test(sync): migrate SYNC-036AO Logs projection watchdogs
f456aee744d8c9448eb7146592e0a917ca833d7a	test(sync): migrate SYNC-036AP Launch at Login watchdog
97c9f294f8b43bb4f00e191c749308fc38631b08	refactor(sync): migrate SYNC-036AQ search confirmation evidence
dc1d91f37a1349a3efdd77a8005cbaee9f0e609c	test(sync): migrate SYNC-036AR tab stress policy
930f32e55c0bcb1e8ecdb845a25fc59f6b596864	test(sync): migrate SYNC-036AS Home postlaunch watchdogs
e694637639f67b2d9c6a6195dd5d33e2b9f75577	test(sync): migrate SYNC-036AT AX suppression termination evidence
55fe5e25f459e92ccb8b32e7d183600e439228bb	test(sync): migrate SYNC-036AU AX suppression readiness watchdog
fbdaa7219d903c9abd8007d0dbf4c0f38d344e19	test(sync): migrate SYNC-036AV AX suppression watchdog
e24f0b17751fc48195ddae05dcf17677f2d90f48	test(sync): migrate SYNC-036AW Search wrap transitions
14062289e7430da373a4c5a373b7a536e934b425	test(sync): migrate SYNC-036AX Search diagnostics publication
8291807572001aa3522afe8b480791eef9acd370	test(sync): migrate SYNC-036AY Search result hittability
9dd6ea0071618f59cfad0f26cc4125b85754f7bf	test(sync): migrate SYNC-036AZ Home activation navigation
e87a575b7c6498065c5f6d3accf219ac693c007d	test(sync): migrate SYNC-036BA Home activation App row
8d28d07ed21a2f8e3e86fee1e0765cfcea7124f9	test(sync): migrate SYNC-036BB Home window projection
2f4d6cd9f51543d3d71ccaa1cf00061037fce177	test(sync): migrate SYNC-036BC Home exact window activation
4f1c5500b1e1e806b79202340406df9c3bba752a	test(sync): migrate SYNC-036BD committed Search window publication
459eb4bb736683e05b1e391b5197a1656c891408	test(sync): migrate SYNC-036BE Search input readiness
1ba92c4bbfc29d80a6d9753a566aa6f18f9c735c	test(sync): migrate SYNC-036BF mock App foreground readiness
d1534a7d13711b3e7bdeb55367a4a48d730cd218	test(sync): migrate SYNC-036BG fixture foreground readiness
36448a674b4731124651ceee18c70312d0a35d85	test(sync): migrate SYNC-036BH configured fixture content
88c09c7185c5055120fcb3a7949bfef8be81200e	test(sync): migrate SYNC-036BI Home permission foreground readiness
e1ec99fea05dee283c477dc68cbd896011301cfd	test(sync): migrate SYNC-036BJ Home navigation evidence
5c4593eb58265249b7695105e35bca1eae369dce	test(sync): migrate SYNC-036BK Home projection evidence
4920d7d2f1cc69853d1e26f72c7b7f590977d67b	test(sync): migrate SYNC-036BL Home initial foreground readiness
b2cb951623cda3ddd5b8db6cdec27d6f58e73460	test(sync): migrate SYNC-036BM Home initial navigation evidence
44da451687b05d9004c93f2f89e0a9c048082376	test(sync): migrate SYNC-036BN Home initial row evidence
6143d6925a3baadfc402ef1f6aba09e885216e57	test(sync): migrate SYNC-036BO Home applied row evidence
e94ddf5ee4225820e8cb5a01830007b14feb1ed0	test(sync): migrate SYNC-036BP Home permission foreground readiness
4c9f6062680ef296dfeeac1ea83688c8723dee66	test(sync): migrate SYNC-036BQ Home permission navigation evidence
f358bafc01328df05e61717043899d6bc6660683	test(sync): migrate SYNC-036BR Home permission projection evidence
3e6b857f21e0f70741b8749522e681b23094397e	test(sync): migrate SYNC-036BS Home permission transition evidence
7be7564c0a8e02a3a4db95246fcba00c2c9adbae	test(sync): name SYNC-036BT runtime log evidence watchdog
7429c010eee2e5f59b7776e420b1c13de7832653	test(sync): migrate SYNC-036BU Settings navigation evidence
542ebdc198eb2339cead4f00d026e145ab01dbfb	test(sync): migrate SYNC-036BV English Search evidence
1a54d0147e5dc09e9cd9dccb148c95cf6c14d70c	refactor(sync): migrate SYNC-036BW Search trigger evidence
ef0afd67fe4d7b99e1fa61b79c18e7af15e4eb3b	test(sync): migrate SYNC-036BX Settings permission evidence
7af4b9351c983e0af50cc16a661e026186a6aac1	test(sync): migrate SYNC-036BY permission transition evidence
53372ea0309fc5e74eb0fb0e79aa12274fd033ec	test(sync): migrate SYNC-036BZ takeover status evidence
f0d0d8ade06895e83ab2747c091edffc0c661ac8	test(sync): migrate SYNC-036CA takeover log evidence
d14f30d4784b52939552768073ece63758c66cda	test(sync): migrate SYNC-036CB trigger log evidence
0e7e6c549815ab98f1c40ae66ed9f188e7a8e9f9	test(sync): migrate SYNC-036CC graceful exit evidence
77275291c3f7ab24ab1eec8c70eff4aa3f76005c	test(sync): migrate SYNC-036CD fallback cleanup evidence
d42e56aba3c329e55fa5456f531880171cb1ebdc	test(sync): migrate SYNC-036CE defaults reset exit evidence
0c1c6272a7548067f91d9b98464cf4ad845d1319	test(sync): migrate SYNC-036CF fixture mode evidence
8514fc58c68a604241eede1b2f9c0f65af5d8b1e	test(sync): migrate SYNC-036CG permission evidence
678702d1b7c08f01816ee87f00afa5d0a9437cd0	test(sync): migrate SYNC-036CH search scope evidence
8740bb701de69323305c3c79b5e3dd6943be9417	test(sync): migrate SYNC-036CI window close evidence
5d3eb5211ad089ce686377a1ce718b7fd9599cc4	test(sync): migrate SYNC-036CJ window reopen evidence
557d6a6da37b7aa28671bb03a537a41c87339540	test(sync): migrate SYNC-036CK activation policy evidence
7e0a46aed1af07f81f38c84abe6943e45bc0d04b	test(sync): migrate SYNC-036CL status menu quit evidence
663c3a998a62f5216ebc4579f0bb277efcaa501d	test(sync): migrate SYNC-036CM granted permission evidence
bff3ba34437a3ad811b7cf7796bd0ff48652c7df	test(sync): migrate SYNC-036CN reminder persistence evidence
685af5fd2724e9f0e3b40ae1895dc5b587caf305	test(sync): migrate SYNC-036CO permission dismiss evidence
c9d94a130bb645203bcf8c837761a5408e4234ca	test(sync): migrate SYNC-036CP dismiss persistence evidence
aa0962733fb4050d1db75c47cc24608b45ff00f5	test(sync): migrate SYNC-036CQ log level projection evidence
99dc15500ef02ca7c8377fba55e2b7dbdd1379c8	test(sync): migrate SYNC-036CR diagnostic session evidence
2398f7b37a233bb7b5c860f86783dc586ec00e45	test(sync): migrate SYNC-036CS logs clear projection evidence
0f17da1afd0787d673efe90b228d1c4d58aa2075	test(sync): migrate SYNC-036CT logs clear relaunch evidence
41d4f22db1054e0ae42073cd80b0f2a38e0f21f7	test(sync): migrate SYNC-036CU seeded logs readiness evidence
95ae0feab605f9b0835a831d61038ad8193cb731	test(sync): migrate SYNC-036CV runtime log delivery evidence
878798864b298144c6ce50fbd31e3627e7a3bf14	test(sync): migrate SYNC-036CW live update clear evidence
8164b08403e0fe6d7bc535f11a3cfe744ac45be1	test(sync): migrate SYNC-036CX initial logs evidence
fcdc1965eae8eb6223f1b1511829c33166bb6578	test(sync): migrate SYNC-036CY logs action readiness
12e5caaa7c7b0bb070f38452b52efaa41228c4ef	test(sync): migrate SYNC-036CZ sidebar tab projections
2cf9bc1fcdd622054305bf1fe9d50f14983edef0	test(sync): migrate SYNC-036DA shared logs navigation
4df8552562e322043e9522f3657a0920324aeec2	test(sync): migrate SYNC-036DB English logs evidence
a626180a0fd60f546d18b36d2b4cb930a3358ef6	test(sync): migrate SYNC-036DC shared settings navigation
cbc3191646cd89ec1c594de4fcc67c31590df3fc	test(sync): migrate SYNC-036DD Settings content evidence
310cacbfa5566d931b53108bc5237a3b073b979c	test(sync): migrate SYNC-036DE Settings permission projection
a594e01970b5cb977bbf846120b5f9e93bfba668	test(sync): migrate SYNC-036DF English permission actions
2e7f00a1db666f0e8e0ad0850326737f8aca14ff	test(sync): migrate SYNC-036DG App Visibility page
9d25ff31e805d47c0b7c1f064108068b6c6a5c31	refactor(sync): migrate SYNC-036DH App Visibility inventory
b5a76711432132d5b539d03ef03adccbecfaa2a6	refactor(sync): migrate SYNC-036DI App Visibility query
9a6838eecba5efe35a654069d5ca1c564d374494	refactor(sync): migrate SYNC-036DJ App Visibility filter
dee5ed5551fc800abefe3f0f411d488e5f13c548	refactor(sync): migrate SYNC-036DK App Visibility detail
bf9103f57a95914214bf89f3c83de6182295f6d4	refactor(sync): migrate SYNC-036DL Switcher app projection
08dcf5facf29c30977354aab36c03ea63b62c80e	refactor(sync): migrate SYNC-036DM disabled Search launch
d2666acb5a42d776ec9c23b923b4d9386f84323b	refactor(sync): migrate SYNC-036DN committed Search rows
d95de213f7308f5443065998a0e73d68cd1a799c	refactor(sync): migrate SYNC-036DO user-path Switcher projection
3be0d877ed27f57dc9b9936b7356b5c3369ece01	test(sync): migrate SYNC-036DP user-path foreground readiness
b26836b0fcffce9c9913b32fe2e6238624560245	test(sync): migrate SYNC-036DQ permission foreground readiness
6b27f3cb9ab1b8accba4a42bc14f9b82b8e6f76f	test(sync): migrate SYNC-036DR Search toggle projection
591e431e346f6e4e583837e119f051ec05ba9284	test(sync): migrate SYNC-036DS App Visibility Back projection
e8a66231ddcc665a955c14dfddf7d8c61ae0eb10	test(sync): migrate SYNC-036DT hidden-App Search foreground readiness
88b43daaa29450874192dfddaf8a5dbf3d7cbd10	test(sync): migrate SYNC-036DU hidden-App empty Search projection
53a0105d74cea7af4dfe319401ad17f6f7bf7cc9	test(sync): migrate SYNC-036DV current-App Settings projection
12742aed4189f94d131a2e658e4bb004d2f1b4b7	test(sync): migrate SYNC-036DW Settings Appearance projection
7c1d3f07b9d2a995d777a96fa11c0a82a5b154fd	test(sync): migrate SYNC-036DX Settings English projection
183905aaca99c2114c8257af3b22d799cf1ea2fd	test(sync): migrate SYNC-036DY initial Appearance projection
b0244b9c8fe749041b1637991c6d4d4f129df4b4	test(sync): migrate SYNC-036DZ theme luminance watchdog
f7874cbe1a8f8c2ca894f24ca9793c6c6db329ef	test(sync): migrate SYNC-036EA Window Behavior projection
bbd35172291b08918aabae6c4321ae9b9f3d1e24	test(sync): migrate SYNC-036EB initial Switcher presentation
fe0a708a36d5ac7f9703b68fe54fb671022abb80	test(sync): migrate SYNC-036EC hide-minimized Settings readiness
17a97aeffcf740db3d395e69c7dc2bab0a0192fa	test(sync): migrate SYNC-036ED filtered Switcher projection
1ad52853b411f4f614264982e2c559107e99ea33	test(sync): migrate SYNC-036EE localized permission readiness
38bde325308135df7a54db8b2faa48c9820ff540	test(sync): migrate SYNC-036EF main hotkey readiness
fdb1a960956d48bf87128e829b9fd5c5e8562e1d	test(sync): migrate SYNC-036EG quit target readiness
680c35a8ab1e5db5b68f96f1ec0e048b6bd82152	test(sync): migrate SYNC-036EH in-app hotkey readiness
dcba6a642512fa259903a9f438da394bc0a25347	test(sync): migrate SYNC-036EI quit completion watchdog
5ae73bd92a698d7b8227f661408fea5a5b45c124	test(sync): migrate SYNC-036EJ selected row disappearance
2f4b524347017dcb12b53a1e6360000815aaee86	test(sync): migrate SYNC-036EK dropdown option identity
bcade6749852634fffa962efb04abb7b700c0228	test(sync): migrate SYNC-036EL settings control readiness
404c1cde202cee5dbc44b61d01984aef1d021f1e	test(sync): migrate SYNC-036EM language control readiness
e3631f1b6ed41e17d58c593f09bdc5a78ebd1693	test(sync): migrate SYNC-036EN disabled controls projection
ca37694202d78f843842066691a19c9f15202653	test(sync): migrate SYNC-036EO English Search projection
5810f78a62074dbfe923a7c4a2b024c218610aa6	test(sync): migrate SYNC-036EP English foreground readiness
ace441b2a617cc5f7543ad2172041e5bd20a3a5e	test(sync): migrate SYNC-036EQ fixture permission foreground readiness
c923f870dc81edd5e2cc31b8e2e669c1c42845db	test(sync): migrate SYNC-036ER fixture permission Home readiness
4ebff6d35de853a4005c2b554acaab456a4fef9c	test(sync): migrate SYNC-036ES System MRU app order
e69e7be40b38c175ee3951b2f7c05792dd995720	test(sync): migrate SYNC-036ET System MRU bootstrap logs
676d849e7158eabacdc4ae70d326b4e6ecf884e3	test(sync): migrate SYNC-036EU System MRU termination
37e36195748edb967809522ee3c2db612f027bec	test(sync): migrate SYNC-036EV System MRU relaunch readiness
cba4e3ae921c4b539e65d0636714b36caf853f33	test(sync): migrate SYNC-036EW System MRU fixture activation
faef2824fc9efbe5011b9fc0ad758102856c50c1	test(sync): migrate SYNC-036EX noisy preview projection
f91d202f4a1f8eab76bd09a81baca57eaed2ebef	test(sync): migrate SYNC-036EY noisy switcher dismissal
7935877f090707be0e0b55b3675c20df86653fc9	test(sync): migrate SYNC-036EZ noisy exact-window activation
aaad98560b5cc1dbeece59a04c2dd569a9b29220	test(sync): migrate SYNC-036FA noisy reconciliation evidence
78a3a18cbc0a73c586630eb3d7f9708da17e1324	test(sync): migrate SYNC-036FB noisy pre-confirm evidence
a86781a81c616101ec6dc1a1f7bbe2aec894325b	test(sync): migrate SYNC-036FC initial Option+Tab topology
dc1e16b4baf3caab0699e40383a74ee084e43b71	test(sync): migrate SYNC-036FD initial window-state topology
14072825be017c020eb952dfde6acb46eba02f61	test(sync): migrate SYNC-036FE confirmed window activation
8b9a0a0b7a692cb2af079db9d3396e5c763135ab	test(sync): migrate SYNC-036FF confirmation dismissal
40d63dac75da16758696f1c5b015885b4a2419ea	test(sync): migrate SYNC-036FG relaunch window topology
0e1e483cf5a325c12150f6918d6189d2459fc110	test(sync): migrate SYNC-036FH initial Window Search topology
f00bf8deaf854cef366bc8c62f36a28321c4ab09	test(sync): migrate SYNC-036FI initial Search presentation topology
b6724d6f0e7a3c3dcbebf74f9dd0b3cbcba04f7f	test(sync): migrate SYNC-036FJ Search confirmation activation
da6c5c493fab101c90419c0b93a087addddd2ece	test(sync): migrate SYNC-036FK Search input dismissal
0e1aa6a089998c1b15128ccb4ed1871fe8e16b2b	test(sync): migrate SYNC-036FL Search relaunch window topology
281b7986f1ca3dc7595936ffb4928a088d0a2f7c	test(sync): migrate SYNC-036FM Search diagnostics publication
3bb221c52bbf24aa38f339aa208e0167822f1507	test(sync): migrate SYNC-036FN Search committed projection
81a63c190c09c0822e2a6c18b67e843ac142952b	test(sync): migrate SYNC-036FO Search query projection
17aa04ef5054160ae4038cbb38335a1a8b488350	test(sync): migrate SYNC-036FP Search result selection
6d3ad246b216fc80f55f8b09dd0b47d4b9e42e90	test(sync): migrate SYNC-036FQ app selection
8fe513ddd7720d495b5ad716c00f46d06b8afd24	test(sync): migrate SYNC-036FR window-cycle entry
9b3120f5a900e88aa730267916fe5c1941a930a2	test(sync): migrate SYNC-036FS app projection
7e24951da6142b0e88aa50e4ed4f00c2133810a1	test(sync): migrate SYNC-036FT preview projection
1664ac5ad9aa461fb76588f4f8767dc2c957ccc6	test(sync): migrate SYNC-036FU diagnostics publication
c012346a226f395d7b4a7ed2a7242c1bfdeb54c1	test(sync): migrate SYNC-036FV space-backed dismissal
37a310165f91e4b7bb9b899f3ddf43ca03910bc6	test(sync): migrate SYNC-036FW single-window advance
b6426e1cd6ae1b78f2c898298def961273246331	test(sync): migrate SYNC-036FX provisional projection
7eccd9ad8f3092b984a640ea140ace966a83a4f8	test(sync): migrate SYNC-036FY space-backed projection
50631c9210df9ae0facf5042b4dee115b318014c	test(sync): migrate SYNC-036FZ selected window source
846f2b37d2174cba3482b47bb5bed11d63185e4f	test(sync): migrate SYNC-036GA window request publication
2e3b86d0eac5304115a6f8a8d07131e8f8fbbee7	test(sync): migrate SYNC-036GB CG activation route
3fab28efcfb0496a46a5b92c8430a688f3eff9fd	test(sync): migrate SYNC-036GC CG readback mismatch
4e7853f82909413b2c5a99a2dd03bd259c2b3569	test(sync): migrate SYNC-036GD recovery failure evidence
2b0169b2d5b53200bd51681ada185a8ad47c8404	test(sync): migrate SYNC-036GE interaction foreground readiness
23a9bdf8a5b143dd222e1e99ca1465491635509d	test(sync): migrate SYNC-036GF Home navigation
d21d66f397bcfa362e06476defd8bc822c28cf3f	test(sync): migrate SYNC-036GG atomic Home order
bac659e0f451054cf893d214a3219487505acba1	test(sync): migrate SYNC-036GH Switcher order
ce63ca645258e927171f4593b8e20db1a12b7e64	test(sync): migrate SYNC-036GI ControlTab diagnostics
6556d3dbb114d4691368eda16a9f5f76b19aff95	test(sync): migrate SYNC-036GJ selected preview evidence
15cc562038dbc5b07196a2ed7b53c9771e89b9ca	test(sync): migrate SYNC-036GK window card projection
e3788d0838ef6ec55ed05e722d0f2871217391b8	test(sync): migrate SYNC-036GL runtime log watchdog
645e374ffacf8084a3b936c0cd2d67e1918cdb33	test(sync): migrate SYNC-036GM presentation dismissal
c5e91921d259c363c99544ec7dad24800823b748	test(sync): migrate SYNC-036GN App click dismissal
145136014495f3c88437dd5f1320802dcbd1c018	test(sync): migrate SYNC-036GO window click dismissal
05829a5c9cd752077eef5bb7449444499776684c	test(sync): migrate SYNC-036GP Search click dismissal
c7b10b6b62b9db8f36c4223a4efb4819728da3c6	test(sync): migrate SYNC-036GQ Search foreground readiness
bd504f312b1ef319935ce3f7523551b621ca54ac	test(sync): migrate SYNC-036GR fixture Search result
8f4140be604f4b3276cc6cf40169a196cce72906	test(sync): migrate SYNC-036GS Search header readiness
892d42ff406c7ef3d06d12887b6db13201908eb2	test(sync): migrate SYNC-036GT Search header projection
116b141b38f991db256720ad8b566e755bae5164	test(sync): migrate SYNC-036GU mock Search projection
a9d049804906ff8230ac09343d4c25b5efe4f41c	test(sync): migrate SYNC-036GV pointer foreground readiness
bd42377e19e3bbadb6f4ffa2a03bc5c2b4ca6598	test(sync): migrate SYNC-036GW Option Tab App rows
c3e2a07df2f303b8b445e9bb49b58033f800b877	test(sync): migrate SYNC-036GX Option Tab selection
18177af066e2fa68ccc062fd9b729bc469ed1fec	refactor(sync): extract SYNC-036GY watchdog policy
b3a49d3fee1abc1f48d4bb353f698a2c894aabb2	test(sync): migrate SYNC-036GZ Control Tab windows
a655ddbb1b2149273f26e03a6bf8a3d2285d92f8	test(sync): migrate SYNC-036HA Control Tab selection
7dbcce4a080b41017ab4ca85ef71e66bccd875ae	test(sync): migrate SYNC-036HB Search selection
43f6dfb2f6618a49195832b24d78e26540431401	test(sync): migrate SYNC-036HC Search results
49e526dc511cf7418d6a5cafbb79507d15b40a8a	test(sync): migrate SYNC-036HD foreground readiness
4d497121329fc985cf2ade58dec6a53666921e91	test(sync): migrate SYNC-036HE stale row
f374b3d278fe0c369b31dc08b61f9c388a6b5af3	test(sync): migrate SYNC-036HF recovery logs
fc5c7ea57d83821d46329dc438fb1e31595ea4ff	test(sync): migrate SYNC-036HG nested Apps
7c96b0e47c573ae6fd9a337b74a1e49628cc461c	test(sync): migrate SYNC-036HH nested windows
18840f2cb3c71929731661d0cbee94c9e843a1d2	test(sync): migrate SYNC-036HI nested hotkey log
ca00308b874ac8d413e92b5fff5639d0aa645260	test(sync): migrate SYNC-036HJ pagination App readiness
0a1814314e51fcda2f0d641348708b68c17c21f6	test(sync): migrate SYNC-036HK pagination Window readiness
a3620a9cbf62cbb97bc96caf3de50ad078e168fb	test(sync): migrate SYNC-036HL pagination page-control readiness
c6e469fe14643c967228decfeeb06202c985d688	test(sync): migrate SYNC-036HM pagination page projection
f367c0ad0001c1695e610b382e44d1ba378d0e13	test(sync): classify SYNC-036HN Home Logs readiness
2f8ef458d1ae5103abb4f8dc9fe2cb665663c900	test(sync): classify SYNC-036HO status activation
0e67cbd5b6ca7530eaa05d13aa2eb2aea2e08d91	test(sync): classify SYNC-036HP Home trigger readiness
7f0bbb4152399e23eae30fd191fae0e0e56c9036	test(sync): migrate SYNC-036HQ Home tab projection
56ed469f103b4028239ec504ab8e487314b00a36	test(sync): migrate SYNC-036HR live Home directory
5874a0851942bc848091c8004ee1ed238ebc7576	test(sync): migrate SYNC-036HS Home Overview projection
80c18958c101a8c4adb749de3b9ab1fe75530ee9	test(sync): migrate SYNC-036HT hidden Home row projection
a014f108f5acdccdfb7146499294444acf5d8c31	test(sync): migrate SYNC-036HU nested topology rows
4333f23f095a0d1204b55d0c5eb7c460b4c179b2	test(sync): migrate SYNC-036HV nested topology windows
0c6bb74e45e8b517aa020892b977e86acac499b2	test(sync): migrate SYNC-036HW nested App projection
4a71137e92f461eb414bfc99691708305e93c3c1	test(sync): migrate SYNC-036HX Home App publication
e4dccac3d9399529f9a82c6aa6b3340fdf515704	fix(sync): migrate SYNC-036HX1 signing identity
200732a08ad74e12590269fbdbe6d4bb6cd01eae	test(sync): migrate SYNC-036HY Home window publication
bcbad9a60e95cf23dd80a401eb5a57f21cf278bb	test(sync): classify SYNC-036HZ Home window activation
f3c5d9dec12abfd43519722d3a600e87058718c5	test(sync): migrate SYNC-036IA FlowTab foreground activation
2511741f7be0d7a903d849d463366bd3a0cb7dc8	test(sync): migrate SYNC-036IB Home return navigation
5e6b70b8f4ac53a39f37d3293d080dd5317b92ec	test(sync): migrate SYNC-036IC Home recency projection
aa99f68d5e8f135bc3913cc05560cf286ce089eb	test(sync): migrate SYNC-036ID permission Settings trigger
935fa6ba7f4d546f1ecf935b557a3485a599931d	test(sync): migrate SYNC-036IE permission toggle projection
3f9129a0ca70e45e0f7a841c4632c24971cc3e91	test(sync): migrate SYNC-036IF permission controls baseline
a00a1477dd1d378acc3df4174b71d0e7cbcc6370	test(sync): migrate SYNC-036IG permission Dismiss trigger
571f0b76a4762f04225fd77348207be941b18012	test(sync): migrate SYNC-036IH fixture foreground readiness
957659321c2c6855a513d6550d94e7bc961923bc	test(sync): migrate SYNC-036II Edge fixture foreground readiness
b40b1f322bd686869aec2fa35fba8d04e8cabc38	test(sync): migrate SYNC-036IJ standard fixture foreground readiness
8f77276471a5a710871e6a877e4ac5e20b3621cb	test(sync): refine SYNC-036IH1 foreground evidence readback
82ad28fff67b5d68ff010b883a0c2737f4abf2b3	test(sync): migrate SYNC-036IK quit fixture foreground readiness
583820424908238d58cf7a5115f66007da77e221	test(sync): migrate SYNC-036IL lifecycle foreground readiness
843ae91567fb7489332def253fa9780cd437a583	test(sync): migrate SYNC-036IM mutation foreground readiness
b2dc664e36cad46e37f5a6ad4c24e51575b345ff	refactor(sync): migrate SYNC-036IM1 window-set evidence
338f12dbf9e52dc4799d341dd864b9682c218deb	test(sync): migrate SYNC-036IN post-fixture foreground
28f1aa0d1c2ce775a85e8b0c6c4f86a6659e9bba	refactor(sync): migrate SYNC-036IP workspace lifecycle handoff
f3e38b728d879857d0940edac50652d58fd6291e	test(sync): migrate SYNC-036IO lifecycle foreground readiness
6be69d66bef12bd2b099089f18165c825af80545	test(sync): migrate SYNC-036IQ exact lifecycle launch evidence
196f825230906abfc1eb1f39d21fb78868863f20	test(sync): migrate SYNC-036IR exact lifecycle termination evidence
6185b11adf1ed946eaeb63f77ff6ea1b758ff732	test(sync): migrate SYNC-036IS lifecycle fixture exit watchdog
ae12a695a29346e8ef5647f53d6cfe5284f53383	test(sync): migrate SYNC-036IT lifecycle Home projection
c4939059c0aa042a9b9020f1889db6d78c94c026	test(sync): migrate SYNC-036IU window-close scheduling
d04cb5d6da8ed3482bcb2d468c6e6b520f0e19c2	test(sync): migrate SYNC-036IV window-close application
0aec81ac5f7dbc5be1c03ab9eed278d5e57c272a	test(sync): migrate SYNC-036IW initial Home projection
f385e0e7586ba1f0029135a7cd4c98a1775833cf	test(sync): migrate SYNC-036IX closed-window disappearance
d807a056acca240eef3fb57ff5a4a17ea6ba9b1e	test(sync): migrate SYNC-036IY final Home projection
1d1ae0ceabb64ea1c6053ed062387e0567653822	test(sync): migrate SYNC-036IZ initial three-window projection
e4fdb138c08252bf157ffbefad4c3b870440731a	test(sync): migrate SYNC-036JA standard fixture App projection
ceea908177cf38b151d67788ec2560c6b2d231ea	test(sync): migrate SYNC-036JB quit App removal
acf25ba7733708f420ae16f4badd8fd2d9c73483	test(sync): migrate SYNC-036JC quit App readiness
8b5bf6a39f6f46cfd2a43f2a612f603c86794cf6	test(sync): migrate SYNC-036JD workflow App readiness
1cbcf31bba6a19689e81887bd9d18f41c8cbad7c	test(sync): migrate SYNC-036JE window-card readback
e6263c424e583fadeda41f809858fb1b80f5e652	test(sync): migrate SYNC-036JF explicit window close
96a51f86f622d5b020e0b55c2f947949abe3c169	test(sync): migrate SYNC-036JG foreground readiness
b248317596df7e899808c01786ad3812e37c4461	test(sync): migrate SYNC-036JH initial App projection
0fd37d56865cd724de1cb3f8c4d84bee99b164e1	test(sync): migrate SYNC-036JI App selection evidence
ba0f0516f5ec639cbe89d85c3d7bf369f9e1e1e7	test(sync): migrate SYNC-036JJ exact window-cycle entry
f82bf92eb154e8d15dfabe34415e8034f8db4598	test(sync): migrate SYNC-036JK initial window projection
10064921899a6ec06c7cd361cfd28304c561279e	test(sync): migrate SYNC-036JL runtime reconciliation
8f2afdcfd70b20409e9b5fd8e4380c85a1b53910	test(sync): migrate SYNC-036JM selected-window close
a4927fc143b404be0b476f5361df454f3cc550ea	test(sync): migrate SYNC-036JN foreground readiness
2a74d83870ca1332653230e5cee2ab88b3ad322a	test(sync): migrate SYNC-036JO initial App projection
ed283001df0c81d8acfed261d4dc6ce23c71ad76	test(sync): migrate SYNC-036JP App selection evidence
21842b1a60092f5fea9d3c5149d357c6799d1593	test(sync): migrate SYNC-036JQ exact window-cycle entry
8e63f4a0c63ca42a9240d16415f9d941214d8d0f	test(sync): migrate SYNC-036JR initial Window projection
971cda06d27df0f3e3072929adc99703a202a98a	test(sync): migrate SYNC-036JS post-close Window projection
97d711ecb99247eea6e3a881e47a5febf40d2de3	test(sync): migrate SYNC-036JT exact retained Window state
f6ec55747c8c3d0211a144aa49904f695725a8c0	test(sync): migrate SYNC-036JU exact runtime reconciliation
8f6a1d9f34b8b6d9325110cb30949bffc5106e6c	test(sync): close SYNC-001 signed pressure validation
92b894dd8b7655d55922a7ff76894847c2a96182	test(sync): close SYNC-002 signed lifecycle pressure
23fce632d4e5ce34c8dec9933fcaa9b737cfb28e	fix(sync): repair SYNC-026C1R projection scope
e6334a71732df75c69f5bcd0824e9485e60f7f0e	fix(sync): repair SYNC-006R1 focus evidence priority
4f67f84abd4ff500fae6d4e6d41dd935ea502b2d	test(sync): close SYNC-003 signed topology pressure
6b3f67694abd4eeea601ff51945e0500f50a40dc	fix(sync): repair SYNC-019R1 slow panel visibility
ad953072c88de319e7b914c63f663287ee929c9f	test(sync): close SYNC-020 signed recovery pressure
a0f1650826407514359e0d9aa64faedb734ec34d	fix(sync): repair SYNC-023R1 manual window readiness
f44e1011a6c3330436cba2cb1d8da5cf1133ed5b	test(sync): close SYNC-021 signed Space pressure
9063d8f1ecb4fdeefb6cfcb9166afe4cc5b76e4c	test(sync): close SYNC-041 signed Home detail pressure
cff75e602bb4ea07d4b6e7093dcfadbb74000622	docs(sync): inventory SYNC-036JV remaining UI watchdogs
73da680bd33af3c8e0b6d63338789ead48a83abf	refactor(sync): migrate SYNC-036JV quit request publication
4de5816cfe4669bdb85ca86a3cb722ac8534c4fb	refactor(sync): migrate SYNC-036JW scheduled termination evidence
1c6231391c3b6f0876051611f8a249f5b7c88af5	refactor(sync): migrate SYNC-036JX exact applied termination evidence
973f7024c661293d74b381f81af28b717c1b8aab	refactor(sync): migrate SYNC-036JY exact fixture process exit
2a1c55ac9b38167b754a22f1b326f5bcff8e83f6	refactor(sync): migrate SYNC-036JZ exact projection refresh evidence
c38a1840f7c1b1a848dae31b207d02e84a8d2d10	refactor(sync): migrate SYNC-036KA exact window-cycle transition
c2ec68c836b51c63f3fdac009523779ad0f5380f	refactor(sync): migrate SYNC-036KB exact Edge App projection
6b058164ec4a5dc48ea13fa7e268490c9d710450	refactor(sync): migrate SYNC-036KE focused public-state evidence
4d32cce8bab479924a0c1b6d3bf71544fdb006d0	refactor(sync): migrate SYNC-036KC Edge App selection
72998c9294e28fd26bdfa7946c499658e3912686	test(sync): migrate SYNC-036KD Edge card watchdog
d99f13e9a2506ec2fd92c5a9992da797ad4913e7	test(sync): migrate SYNC-036KF minimized AX propagation
03d98e506084a6f60b21a90be8390d3e42993f22	test(sync): migrate SYNC-036KG Edge Search watchdog
d7d86b80f460f1394622aeadba8c21ffb6f9876e	test(sync): migrate SYNC-036KH Edge activation watchdog
5eec5ca0c9a158da02faceb3d724bffb5c7acc0f	test(sync): migrate SYNC-036KI atomic Home rows
2251e2883469cf142f50c9b089684999302b3bec	test(sync): migrate SYNC-036KJ Home App inventory
e0d1bc71f066a17bdb321d967374a97c0264bd0e	test(sync): migrate SYNC-036KK exact Home windows
3ccb7bac6ca1ee3ac85f79c5ebc1674c4e5c1ac0	test(sync): migrate SYNC-036KL exact Switcher Apps
4c8d622f5026c1b077bf5b272f5f28930ee5749d	test(sync): migrate SYNC-036KM selected App preview
01480cfda127f731fde870d947ca18ecac459bae	test(sync): migrate SYNC-036KN card identity watchdog
e2e708a5e91665b97cb4033b3719c151325ff385	test(sync): migrate SYNC-036KO explicit window close
c4a1644b9f8b3a35ec6b7bd22abcae530930d508	test(sync): migrate SYNC-036KP exact AX reconciliation
b3601de6db932133304ba15d22c48908a1c482a5	test(sync): migrate SYNC-036KQ fullscreen explicit close
b24f62b85ae84995c32863223d661fb61f518130	test(sync): migrate SYNC-036KR fullscreen AX reconciliation
4824bb55cdc4d6e27aa8a305450c508e40f560dc	test(sync): migrate SYNC-036KS committed Window Search
824c3d30eeb331ef73b8a22833d4145ef91c3ad5	test(sync): migrate SYNC-036KT exact Window Search confirmation
350fe14bf80483022014136f6eb9a599cc677cd6	test(sync): migrate SYNC-036KU committed App Search
76fe2389c50b61c1947adb3663bd5b57ebda9493	test(sync): migrate SYNC-036KV exact App Search activation
20c8ad6739e50733421e18aa8fc483469b76741e	test(sync): migrate SYNC-036KW In-App topology readiness
55059a7839be6ec831137f66b78a00a9f8521d5b	test(sync): migrate SYNC-036KX atomic In-App panel projection
6146691d5d0c5796a69a326e984244a3084bb8fe	refactor(sync): migrate SYNC-036KY In-App command application
d77d890f1b5340e59799d3f74324118376ff2b5c	test(sync): migrate SYNC-036KZ atomic In-App confirmation
66da1ae575a95d48f4df8f4f1b84334e10d186ac	refactor(sync): migrate SYNC-036LA filtered artifact evidence
f5f1db5be0267941c1f180cdbd1be42627cbadf4	test(sync): migrate SYNC-036LB exact Window-layer evidence
10eafe522ce4f839f6c71bee906baaf97c63330b	test(sync): migrate SYNC-036LC exact window request
54d2511ca8973bdb6745a1d24ef7a1a8e62df347	test(sync): migrate SYNC-036LD verified-focus evidence
75548e6f95e0b1b58f07abd43793600320d192e5	test(sync): migrate SYNC-036LE diagnostics watchdog
```

## Mainline Integration Commits (6)

```text
f0633f834dee27646b031b0611e7451a7fb65ecc	fix(release): harden distribution security boundaries
7ba0b60aceb96816d8ddd7688b42fc8863ede546	Merge branch 'main' into evidence-driven-sync-migration
c706e6352dddae1589d4d1cb8eed9ed26fdbcdb2	docs: make English README the default
18d887ceac0e2afe88e960a6e1b20bfe9077de2b	Merge branch 'main' into evidence-driven-sync-migration
5fa48a48217024225637bf831a70595ac6870dcf	docs: center README headers
a9c2f99c206f443afb7da88d5cbba3933092ab3c	Merge branch 'main' into evidence-driven-sync-migration
```
