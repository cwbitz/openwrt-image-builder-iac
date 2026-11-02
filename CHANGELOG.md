# Changelog

## 0.1.0 (2026-11-02)


### ⚠ BREAKING CHANGES

* **accounts:** existing inventories, vaults and operator configs that use the `builder` group or the `ansible` account must be renamed (`builders`, `vault_host_iac_password`, `host_iac_ssh_*`) before the next run.
* **secrets:** existing inventories must move the account name and key path knobs from the vault into the group configuration; the vault keeps the passwords.
* every operator key in host_vars/<machine>/main.yml and group_vars/builder/main.yml is renamed; existing inventories must be migrated (openwrt_variants -> build_variants, openwrt_image -> imagebuilder_image, openwrt_profile -> target_profile, openwrt_fetch_artifacts -> fetch_artifacts, openwrt_modules_* -> modules_*, openwrt_extra_packages -> extra_packages, openwrt_root_password/pppoe_password -> root_password/pppoe_password).
* model each build machine as an inventory host with per-machine variants
* **make:** VARIANT rename, drop VAULT_FILE, internalize lint, unify help
* **inventory:** define the builder address once; make main.yml local-only
* **vault:** merge generated secrets into vault.yml, drop the managed vault
* **make:** unify HOST and internalize agent helpers
* **make:** make clean, make vault-encrypt, the public check-* targets and the public keychain-* helpers are gone; make install is the only dependency entry point and Keychain is used only as a fallback.
* the Ansible root moved from ansible/ to the repository root, and several Make targets were renamed.
* **connect:** host vaults must now set vault_host_<user>_ssh_private_key_file; without it key login falls back to the SSH agent or password.
* **users:** the `ansible` automation account default changes from 1001:1001 to 6000:6000. The role migrates an existing account (group, uid, gid, home ownership), but files owned by the old numeric uid elsewhere keep that owner and should be re-chowned if they matter.
* the run.sh/build.sh CLI and the modules/ directory are removed. Configuration now lives in ansible/inventory/host_vars/<host>/ (main.yml + vault.yml) and is driven by Ansible via the Makefile.

### Features

* add ekko prefer mihomo config ([63eef4b](https://github.com/cwbitz/openwrt-image-builder-iac/commit/63eef4ba7d44eced9ded12b90f17fee65d6e5b76))
* add Linux desktop support ([8c5bf68](https://github.com/cwbitz/openwrt-image-builder-iac/commit/8c5bf68dca8212c0cdfb8ef418a878db7b9df8c1))
* add mihomo default config and as-default module ([a8646c4](https://github.com/cwbitz/openwrt-image-builder-iac/commit/a8646c4dc791b1e363f7fbc0cfec4f3f66ccd5ed))
* add OpenWrt-mihomo module ([244d677](https://github.com/cwbitz/openwrt-image-builder-iac/commit/244d677d3a7ff612283f087f9a9cc0a5506fc9d2))
* add Windows support ([7115d56](https://github.com/cwbitz/openwrt-image-builder-iac/commit/7115d5621666f20e4552cecb96e74323de91bfb5))
* **bootstrap:** make the admin account opt-in ([e36b697](https://github.com/cwbitz/openwrt-image-builder-iac/commit/e36b6977639310a68a8ff6c9b58912236ee2908c))
* **bootstrap:** make the human admin account opt-in with a generated password ([3c9f371](https://github.com/cwbitz/openwrt-image-builder-iac/commit/3c9f3711bc15c3ec6e47dfbf719db4e0a2568548))
* **bootstrap:** support Docker Hub registry mirrors ([72631f3](https://github.com/cwbitz/openwrt-image-builder-iac/commit/72631f337c46749652a765d0bd814afaf84346c0))
* **build:** add lan to default modules ([c657893](https://github.com/cwbitz/openwrt-image-builder-iac/commit/c657893535bf85ff3f866f8d5c0557274d54d5b5))
* bypass China IPs, oveture DNS ([b8ec95b](https://github.com/cwbitz/openwrt-image-builder-iac/commit/b8ec95b71060faedaecb9422e960265ba9685afb))
* **cli:** add help option and restructure script functions ([287a366](https://github.com/cwbitz/openwrt-image-builder-iac/commit/287a3669909a7c1d8ee1e44145c92cb0acf2ca64))
* **connect:** require an explicit SSH private key path ([dfeb764](https://github.com/cwbitz/openwrt-image-builder-iac/commit/dfeb7649c862e134bfc80dcac52208e0ffcde657))
* **core:** support environment variable fallback and document precedence ([7022fb7](https://github.com/cwbitz/openwrt-image-builder-iac/commit/7022fb74accf77a25ade3a7d48756a8fa7e8768d))
* **daed:** geodb use MetaCubeX ([d5139f8](https://github.com/cwbitz/openwrt-image-builder-iac/commit/d5139f87fccf79c890c357178d7b7011bd61a26c))
* download subscribe file for first boot for mihomo ([859ea0e](https://github.com/cwbitz/openwrt-image-builder-iac/commit/859ea0ec4220b28e3ef726e1546882d77334cdf7))
* first version of package app ([0959525](https://github.com/cwbitz/openwrt-image-builder-iac/commit/095952541777d62f4b9545f4f9aa9844297b1697))
* flatten Ansible layout and add multi-variant firmware builds ([79f7ad7](https://github.com/cwbitz/openwrt-image-builder-iac/commit/79f7ad7cfd89d1873b69e59bf53cd95870ecf911))
* **gui:** add i18n support ([54a0eb4](https://github.com/cwbitz/openwrt-image-builder-iac/commit/54a0eb46f592b013cd2c0e6cbd639f623ee8f828))
* **gui:** add repo to config ([97962b1](https://github.com/cwbitz/openwrt-image-builder-iac/commit/97962b10c23c01fa2ec4e42e43355d9544518149))
* **gui:** add show detail of module ([9e07208](https://github.com/cwbitz/openwrt-image-builder-iac/commit/9e072088b520b348c94453f15b4a434dbfff1228))
* **gui:** clear and copy log ([849874d](https://github.com/cwbitz/openwrt-image-builder-iac/commit/849874d19e2f6621b9631898f0fe5c38b118512a))
* **gui:** docker status check ([1a4eac7](https://github.com/cwbitz/openwrt-image-builder-iac/commit/1a4eac74fd9886ef5a03bbbd40ec6fd27b2edbb6))
* **gui:** fake build ([1cca6c5](https://github.com/cwbitz/openwrt-image-builder-iac/commit/1cca6c53c80ac4cb511a7dccbd34af47be0b21e7))
* **gui:** firmware build is working properly ([1a2ec74](https://github.com/cwbitz/openwrt-image-builder-iac/commit/1a2ec7449cc7c8b48973f4de9305d5093927107e))
* **gui:** init ([19ea46a](https://github.com/cwbitz/openwrt-image-builder-iac/commit/19ea46a8509bcf9597fa135c8c069a01238d6c81))
* **gui:** move building status to right top ([ccd5a2c](https://github.com/cwbitz/openwrt-image-builder-iac/commit/ccd5a2c0693bd29435d194f7fc086fd269de470a))
* **gui:** only show module source when have user_modules ([afb0577](https://github.com/cwbitz/openwrt-image-builder-iac/commit/afb05772ff39b4e7e37569756d94178de75f74dd))
* **gui:** open dialog when click path input ([35eabab](https://github.com/cwbitz/openwrt-image-builder-iac/commit/35eababa9780eebd67653cb45b07d8f6435dc42c))
* **gui:** refine docker status show ([48e8910](https://github.com/cwbitz/openwrt-image-builder-iac/commit/48e89101654e93748be4199c3a5d1cbd71a1da65))
* **gui:** simplify image tag selection ([e5733b8](https://github.com/cwbitz/openwrt-image-builder-iac/commit/e5733b891ac6f965c66e207aac8b91e7c059218b))
* **gui:** support advance config, fixed config restore ([484979f](https://github.com/cwbitz/openwrt-image-builder-iac/commit/484979f4288e7164ab17e877b9d2483791c1101e))
* **gui:** support set rootfsPartSize ([4068745](https://github.com/cwbitz/openwrt-image-builder-iac/commit/4068745bd426e4498cc815e31f4b496a66af30b3))
* **gui:** support theme ([7d63ef2](https://github.com/cwbitz/openwrt-image-builder-iac/commit/7d63ef208ab07d64717f7e5188d4882477cb920e))
* **gui:** support user_modules path set ([fb36405](https://github.com/cwbitz/openwrt-image-builder-iac/commit/fb36405d8bc48a202c0dec2da51c447c67a101a0))
* **lint:** audit the operator templates against the role knobs ([f17d2ad](https://github.com/cwbitz/openwrt-image-builder-iac/commit/f17d2adf98c05cba52c2bd44609dd42e6f57ab91))
* **lint:** reject real identifiers in tracked files ([ab33bd1](https://github.com/cwbitz/openwrt-image-builder-iac/commit/ab33bd13c6927ecc58d9e81c7e691fcaa8201613))
* **lint:** require active operator knobs in the example templates ([562ad13](https://github.com/cwbitz/openwrt-image-builder-iac/commit/562ad13c5f278feb71524a659850b7b889c369de))
* **make:** add one-click deploy target ([a9b5478](https://github.com/cwbitz/openwrt-image-builder-iac/commit/a9b5478b89d52f565741f50b74bd813685c2c8c3))
* **make:** default host-init to the placeholder build machine ([c59e6e7](https://github.com/cwbitz/openwrt-image-builder-iac/commit/c59e6e71c5cfad7dbb8392f01d8a1d6d70bceb84))
* **make:** expose hostkey-init and rename HOST_KEY to REFRESH ([fccd6a6](https://github.com/cwbitz/openwrt-image-builder-iac/commit/fccd6a61169040393641ba2a0728d8bc90fae8c3))
* **make:** optionally refresh SSH host keys before connecting ([c23d8f8](https://github.com/cwbitz/openwrt-image-builder-iac/commit/c23d8f8bf8331ac58f4b78f2b4c8d3eab1b490a8))
* **make:** re-sort vault keys alphabetically after editing ([5c823bb](https://github.com/cwbitz/openwrt-image-builder-iac/commit/5c823bbe24a3277a48747662de4da60bfcf2f4a6))
* **make:** scaffold host-init comment-free and register the variant ([b7200fc](https://github.com/cwbitz/openwrt-image-builder-iac/commit/b7200fccdb826015b713181a0183d441d794c8ca))
* **make:** show one clean info block per variant ([2898243](https://github.com/cwbitz/openwrt-image-builder-iac/commit/2898243bd4806ca367f974fbc9c72269d1c5df71))
* model each build machine as an inventory host with per-machine variants ([b75f61c](https://github.com/cwbitz/openwrt-image-builder-iac/commit/b75f61c2049f986b796bd32904435d8b0d9d8133))
* more mihomo config ([08366b7](https://github.com/cwbitz/openwrt-image-builder-iac/commit/08366b7574002f501c4f7c33f0ab6ce79de69375))
* **openclash:** add more ip to openclash_custom_fallback_filter.yaml ([aabd912](https://github.com/cwbitz/openwrt-image-builder-iac/commit/aabd9128d8704afe8b1bcf88e9499d886701a9ba))
* **openclash:** add more ip to openclash_custom_fallback_filter.yaml ([cd2806b](https://github.com/cwbitz/openwrt-image-builder-iac/commit/cd2806be2388dc308a88cb571037a66bdbbd6046))
* **openclash:** enable dns fallback_filter by default to against DNS pollution ([a1d20ad](https://github.com/cwbitz/openwrt-image-builder-iac/commit/a1d20adf9c1dc493a3165af2bc1d3d926e3e35c7))
* **openclash:** enable_respect_rules ([33a8bc4](https://github.com/cwbitz/openwrt-image-builder-iac/commit/33a8bc48a499b65be06861dde2f8eb0087894df9))
* **openclash:** set default to redir-host explicit and add geo update config ([11c8dd1](https://github.com/cwbitz/openwrt-image-builder-iac/commit/11c8dd132db7f85849f088676bdba3db1b56e325))
* **rename:** rename BW_LAN_IP to BW_MAIN_LAN_IP and document env config ([12709f8](https://github.com/cwbitz/openwrt-image-builder-iac/commit/12709f8488bd0ef512bfa071d40a9ce676d538cc))
* rewrite as an Ansible IaC project ([b8c38ec](https://github.com/cwbitz/openwrt-image-builder-iac/commit/b8c38ec8ac925b7e1ac7d06643f65d670cbef80f))
* **secrets:** resolve firmware secrets from the vault by variant name ([0316cf6](https://github.com/cwbitz/openwrt-image-builder-iac/commit/0316cf6a31b6458c4eb2383e69a7f0d312d54c2d))
* split mirror configuration into setup and build phases ([2acec94](https://github.com/cwbitz/openwrt-image-builder-iac/commit/2acec94a66ec4ca154dc18730ef074021c91f933))
* **sshd:** add opt-in key-only SSH hardening for the build machine ([6737bdd](https://github.com/cwbitz/openwrt-image-builder-iac/commit/6737bddeb82be001e8dbc6837fadc80ea8817985))
* support 24.10 ([e979e3f](https://github.com/cwbitz/openwrt-image-builder-iac/commit/e979e3fceef768b2ca9d38a89fe503b601f3832b))
* support default module set ([192adbb](https://github.com/cwbitz/openwrt-image-builder-iac/commit/192adbbc00a0fa8b8ce326bc80de2bab3daf2f87))
* support dynamic packages define ([2acaa1b](https://github.com/cwbitz/openwrt-image-builder-iac/commit/2acaa1b997ebf40e7bc4a2b729d07bebc34116a0))
* support ENABLE_MODULES ([69dd2f5](https://github.com/cwbitz/openwrt-image-builder-iac/commit/69dd2f509491589d7554263ad12a84981d25144c))
* support global env set ([4f6991b](https://github.com/cwbitz/openwrt-image-builder-iac/commit/4f6991bdd2dcc476b7bca6f169f3dd4a81a9310d))
* support OpenWrt forks ([b6aec86](https://github.com/cwbitz/openwrt-image-builder-iac/commit/b6aec869f2a3df64125878ecb3aa0f27fd35fdfa))
* support read system env ([1c1cc7c](https://github.com/cwbitz/openwrt-image-builder-iac/commit/1c1cc7c1e7c8bdc661148644fc206c89edd1a5ec))
* throw error when file name conflict to avoid unexpected behavior ([225f7a1](https://github.com/cwbitz/openwrt-image-builder-iac/commit/225f7a17d20af8beb95e59be9f3c38f84b4cf544))
* use DoH for mainland DNS ([2294b1e](https://github.com/cwbitz/openwrt-image-builder-iac/commit/2294b1e238e9a8e916f38694d5b7a43d106a2672))
* use new dist arch ([96630d5](https://github.com/cwbitz/openwrt-image-builder-iac/commit/96630d5f0d591f33276399a01181f8873f045a33))
* use package source instead of download ipks ([eeb60da](https://github.com/cwbitz/openwrt-image-builder-iac/commit/eeb60dafc0da8ab7b68acbcd2478e91b29f63593))
* **users:** assign the ansible account the 6000:6000 service-account uid/gid ([e78772f](https://github.com/cwbitz/openwrt-image-builder-iac/commit/e78772f5fef05eba784e1014d5654e76d802684c))
* **validation:** assert the ansible-core range and validate operator knobs ([0fd967e](https://github.com/cwbitz/openwrt-image-builder-iac/commit/0fd967e336b4f8565796a61614554131544291fe))
* 支持 nikki ([2d54ff5](https://github.com/cwbitz/openwrt-image-builder-iac/commit/2d54ff599d0b6b6558487bd66c62925eaf182c4f))
* 更新 mixin.yml ([c3a9c97](https://github.com/cwbitz/openwrt-image-builder-iac/commit/c3a9c977c6a1193fa64ea1c49a04867b461adb18))


### Bug Fixes

* .env not write to module directory ([4898671](https://github.com/cwbitz/openwrt-image-builder-iac/commit/48986717fdd34e2608d0c8a3c203b38ef1807393))
* **ansible:** cache facts in memory to keep them fresh ([a955d94](https://github.com/cwbitz/openwrt-image-builder-iac/commit/a955d94d57802e6bb0c776c77de2bcfeee183c44))
* **bootstrap:** keep probe secrets out of -vvv and apply generated admin passwords ([8aca00c](https://github.com/cwbitz/openwrt-image-builder-iac/commit/8aca00cd64fb20a128e873ce596d76daf5480adf))
* **bootstrap:** keep the service account in the docker group ([b1efffd](https://github.com/cwbitz/openwrt-image-builder-iac/commit/b1efffd3bb49f2ca6901973025f67d9602a1e735))
* **bootstrap:** prove escalation in the SSH probe and install sudo ([c033270](https://github.com/cwbitz/openwrt-image-builder-iac/commit/c033270b69851256a46baf6852b1f0357923e547))
* **bootstrap:** reuse probed identity password for become ([5b59321](https://github.com/cwbitz/openwrt-image-builder-iac/commit/5b5932110d3f345148ce67baecb0f0c2a0491557))
* **bootstrap:** verify password-sudo escalation ([77e8fa7](https://github.com/cwbitz/openwrt-image-builder-iac/commit/77e8fa70983648678f947a26b710f4ec80ff2b32))
* catch docker compose error code ([3930f9b](https://github.com/cwbitz/openwrt-image-builder-iac/commit/3930f9bf5d511944c58778fa3bde37ceee742d98))
* ci ([6339cf9](https://github.com/cwbitz/openwrt-image-builder-iac/commit/6339cf90ab542c02e1b3088f8e505ee5c0848bcd))
* **connect:** use shell expansion for probe credentials ([df9b6ac](https://github.com/cwbitz/openwrt-image-builder-iac/commit/df9b6ac34d2dfdee28e1af7962934f2c615c1ba9))
* **deps:** auto-install sshpass before host-bootstrap ([b050e51](https://github.com/cwbitz/openwrt-image-builder-iac/commit/b050e5172b86247dcacc9c1e61083a024e0fdfa4))
* exit when .env not exist ([a671e8f](https://github.com/cwbitz/openwrt-image-builder-iac/commit/a671e8f99402f8c831e36673442b7aeb832aa993))
* fakeip mode when use qq login like service ([b56e61a](https://github.com/cwbitz/openwrt-image-builder-iac/commit/b56e61ace3924fde33ecc5cbefa49250e00768fa))
* **gitignore:** stop dimming the committed example folder ([9a0e26c](https://github.com/cwbitz/openwrt-image-builder-iac/commit/9a0e26cd7d9abafc53fc195281dd98f8057c76f9))
* **gui:** can not open url ([213d80b](https://github.com/cwbitz/openwrt-image-builder-iac/commit/213d80bd6c41cbba4932b4e07efe7dd4aecd6fff))
* **gui:** clear config not work ([a28dec3](https://github.com/cwbitz/openwrt-image-builder-iac/commit/a28dec3c933180507743ec577f0f880791e1a76f))
* **gui:** dev mode use wrong path ([27fa9d4](https://github.com/cwbitz/openwrt-image-builder-iac/commit/27fa9d4023ce3c8b6d4dba2c650d04c1a0c9092b))
* **gui:** docker not found ([1d7c491](https://github.com/cwbitz/openwrt-image-builder-iac/commit/1d7c4910f788c44a6b91cbc0203665c9171a768b))
* **gui:** ENABLE_MODULES not work well ([74c4f88](https://github.com/cwbitz/openwrt-image-builder-iac/commit/74c4f888f5ae039c4152379234540e692e4d2a68))
* **gui:** home card not have same height ([ab3ecb7](https://github.com/cwbitz/openwrt-image-builder-iac/commit/ab3ecb781626a552892d96cd9af06ccb82082df5))
* **gui:** incorrect module path ([9bc98bb](https://github.com/cwbitz/openwrt-image-builder-iac/commit/9bc98bb6e9bfaa8e7309126dcd4176c54b248d81))
* **gui:** multiple info icon when config select ([31c2b8a](https://github.com/cwbitz/openwrt-image-builder-iac/commit/31c2b8a21b1eb695567a38f3ec623cfec79fcc21))
* **gui:** old file not override when luanch ([bdf3186](https://github.com/cwbitz/openwrt-image-builder-iac/commit/bdf31868af94e4e685b731421c099fb000c77f20))
* **gui:** output directory now working properly ([1476d22](https://github.com/cwbitz/openwrt-image-builder-iac/commit/1476d2262007f718fe7c6832c3c988d323ded860))
* **gui:** output directory select not work ([5af76f6](https://github.com/cwbitz/openwrt-image-builder-iac/commit/5af76f6ed46ca862aefecff85ac67a16b7dc71f8))
* **gui:** remove useless function ([05ab1ac](https://github.com/cwbitz/openwrt-image-builder-iac/commit/05ab1acd8cc4372381e0a5dbf29a89ecd883e5b8))
* **gui:** rootfsPartSize not reset when reset config ([4e15653](https://github.com/cwbitz/openwrt-image-builder-iac/commit/4e1565322f470b47de4713ac2dfef6e6a83ec536))
* **gui:** support config persistence ([ac9c878](https://github.com/cwbitz/openwrt-image-builder-iac/commit/ac9c8784c7fea0d3f6fa35fe7f35797182e2c0b9))
* **gui:** ts error ([6d5245c](https://github.com/cwbitz/openwrt-image-builder-iac/commit/6d5245ce3e609beb5b2b5f8b6c487378ecdb6559))
* **gui:** type error ([c1a6cc4](https://github.com/cwbitz/openwrt-image-builder-iac/commit/c1a6cc43f67a7672676203b2acc031ad9eba4b38))
* **gui:** use wrong run.sh ([568ebb8](https://github.com/cwbitz/openwrt-image-builder-iac/commit/568ebb87ddaddf4222a18dae671278bad94d7d76))
* **gui:** wrong mode detect ([8a2021b](https://github.com/cwbitz/openwrt-image-builder-iac/commit/8a2021b21896eaeec61b2a7760df1904a8be9a9f))
* **helpers:** keep control-node tasks unprivileged under become ([c0ed2ed](https://github.com/cwbitz/openwrt-image-builder-iac/commit/c0ed2edb851263a69e5db0f9c39f95cc8f8e69d8))
* **helpers:** track the vault read/write task files ([a26b62c](https://github.com/cwbitz/openwrt-image-builder-iac/commit/a26b62ccff0eca2a703589dec9f369472edfe12b))
* **hostkeys:** enforce SSH verification and refresh known_hosts atomically ([e91b3a3](https://github.com/cwbitz/openwrt-image-builder-iac/commit/e91b3a323ecee10d64bde2399a378f20da993b67))
* https://github.com/EkkoG/OpenWrt/issues/8 ([6f5ae19](https://github.com/cwbitz/openwrt-image-builder-iac/commit/6f5ae19174f824ed20be0063a11c22cf0c97ca57))
* **imagebuilder:** always fetch artifacts and clean the builder scratch ([93c4145](https://github.com/cwbitz/openwrt-image-builder-iac/commit/93c41454aa43085c21c51e308bac283718a5bbfb))
* **imagebuilder:** pin container nofile ulimit for fakeroot ([77cdc42](https://github.com/cwbitz/openwrt-image-builder-iac/commit/77cdc427795cc90ee2a18746239d00c75c6fa988))
* **imagebuilder:** reject the example ImageBuilder tag placeholder ([b87ba37](https://github.com/cwbitz/openwrt-image-builder-iac/commit/b87ba37f45446dfd6b2f7cdeaa7583a461995c6c))
* lan and pppoe file conflict ([5010bbc](https://github.com/cwbitz/openwrt-image-builder-iac/commit/5010bbc2460e4310edcd3dcaffb28e4f7fe2757e))
* log container not auto scroll to bottom ([b4c6b69](https://github.com/cwbitz/openwrt-image-builder-iac/commit/b4c6b69733fd4725511d3d56ab226c8960341536))
* **make:** skip knob validation when the inventory is absent ([7e54671](https://github.com/cwbitz/openwrt-image-builder-iac/commit/7e54671405964fc1fc9209ea4c9e5b1e2d3291f6))
* **make:** strip blank lines from the scaffolded vault ([3e1d384](https://github.com/cwbitz/openwrt-image-builder-iac/commit/3e1d384250ddbc5c1af3aeb41ef03dffaf5ea0d1))
* **mirror:** include the OpenWrt prefix in the default mirror ([1501d1c](https://github.com/cwbitz/openwrt-image-builder-iac/commit/1501d1c94f87de4253b1a58162758c2f8814f7a1))
* missing var in ib module ([5b0c084](https://github.com/cwbitz/openwrt-image-builder-iac/commit/5b0c084c71031dac1e69fcf6e210eae637cd0710))
* **overlay:** fail when root-password has no vaulted password ([6a674b7](https://github.com/cwbitz/openwrt-image-builder-iac/commit/6a674b7d51497a256c862098f7d954c03d44cbb0))
* **overlay:** keep rendered overlay content out of the logs ([1fd2a97](https://github.com/cwbitz/openwrt-image-builder-iac/commit/1fd2a9747a748b2df4b0e5ff7c7c9d7564354bb9))
* PARTSIZE ([47226f1](https://github.com/cwbitz/openwrt-image-builder-iac/commit/47226f14cb65b266b25f7b18457791919b901349))
* passwall feed version ([7522792](https://github.com/cwbitz/openwrt-image-builder-iac/commit/752279260662468cd3a596857c293fa634748146))
* **preflight:** fail fast when the builders group is empty ([b21abc9](https://github.com/cwbitz/openwrt-image-builder-iac/commit/b21abc94b1dcd16081a5e925eb876b185f92d734))
* **preflight:** keep control-node plays unprivileged ([2a8ade8](https://github.com/cwbitz/openwrt-image-builder-iac/commit/2a8ade8e76fdbcf32ae56e8025b04cc423393582))
* **preflight:** reject placeholder management addresses in build and info ([6ff4453](https://github.com/cwbitz/openwrt-image-builder-iac/commit/6ff44532aca9e922db81310673df93ddabe402d7))
* **release:** seed manifest with 0.1.0 ([db5cc40](https://github.com/cwbitz/openwrt-image-builder-iac/commit/db5cc404e229abc797afe7c2b4b795072f4fdd4e))
* remove moduel with - not work well ([92aa8e0](https://github.com/cwbitz/openwrt-image-builder-iac/commit/92aa8e02f651ef9ce79f49f48c0d858356ce3737))
* run container as root and restore artifact ownership ([775eb7d](https://github.com/cwbitz/openwrt-image-builder-iac/commit/775eb7dc2b903409bcc4bfd92a0ed8996e935761))
* **run.sh:** use docker cmd to clean container ([add0633](https://github.com/cwbitz/openwrt-image-builder-iac/commit/add0633051aed65a838f6fdfbf668b365d8da1d0))
* **run:** fix output directory permissions and ownership handling ([5e33729](https://github.com/cwbitz/openwrt-image-builder-iac/commit/5e3372939878bdd675cfcff91cf8cf7d9ed06452))
* **run:** prevent unbound variable errors during env forwarding ([e2d38dd](https://github.com/cwbitz/openwrt-image-builder-iac/commit/e2d38ddc27cae82e18c2031d6621cf41c25b8512))
* **run:** use imagebuilder service for docker compose exit code ([6868700](https://github.com/cwbitz/openwrt-image-builder-iac/commit/6868700904e744b0d1ba262bf7e9c43db906142a))
* set workspace TMPDIR to prevent out-of-space errors ([0d706a1](https://github.com/cwbitz/openwrt-image-builder-iac/commit/0d706a1129dd2e21d034331fea5f533c7f67e833))
* **sshd:** escalate the hardening play ([a1fa1c5](https://github.com/cwbitz/openwrt-image-builder-iac/commit/a1fa1c579fef87636d14054cb5b2baede036397e))
* typo ([49dd01d](https://github.com/cwbitz/openwrt-image-builder-iac/commit/49dd01d5f774dde8ac7ac192e101b67541110db1))
* use dhcpv4 disabled setting instead of deprecated ignore flag ([a80f1e7](https://github.com/cwbitz/openwrt-image-builder-iac/commit/a80f1e73cf2fe8515610a03c9d1dfe425664ed4d))
* **validation:** honor EXTRA overrides and bound rootfs_partsize ([060887c](https://github.com/cwbitz/openwrt-image-builder-iac/commit/060887c8ca557c642c9febd12f87d730faaac59a))
* **vault:** invoke the pinned ansible-vault binary ([9056619](https://github.com/cwbitz/openwrt-image-builder-iac/commit/9056619947ea7a4e86bc75df97415b10abd7b672))
* **vault:** treat null secret values as empty strings ([4263e0b](https://github.com/cwbitz/openwrt-image-builder-iac/commit/4263e0b5c3ecba5c5fd120acacb9411fd53faa1a))
* wrong feed path ([9fb7698](https://github.com/cwbitz/openwrt-image-builder-iac/commit/9fb769886461fdd4e75e3ebe22303f1b4d8ea9e2))


### Code Refactoring

* **accounts:** rename the automation identity to iac and the builders group ([8b6d73b](https://github.com/cwbitz/openwrt-image-builder-iac/commit/8b6d73bda28a245dd97865bc506eff99197291b3))
* drop the redundant prefixes from the operator knobs ([2438e29](https://github.com/cwbitz/openwrt-image-builder-iac/commit/2438e29080bc00b15f7150fc3a77853ebb513c64))
* **inventory:** define the builder address once; make main.yml local-only ([1bfea3a](https://github.com/cwbitz/openwrt-image-builder-iac/commit/1bfea3a3ca4bb7ed30aaefeee40c78efcb92f06e))
* **make:** make install the sole dependency entry and Keychain a fallback ([0a5c671](https://github.com/cwbitz/openwrt-image-builder-iac/commit/0a5c6710fa8d4633a354298e23ede357d5b71202))
* **make:** unify HOST and internalize agent helpers ([4b5de61](https://github.com/cwbitz/openwrt-image-builder-iac/commit/4b5de6171d6518bc7176ce833fbcc50f67d479ea))
* **make:** VARIANT rename, drop VAULT_FILE, internalize lint, unify help ([ab72113](https://github.com/cwbitz/openwrt-image-builder-iac/commit/ab72113ff1bac54812f8af060b242201f689a964))
* **secrets:** keep non-secret connection identity knobs out of the vault ([0acd5c2](https://github.com/cwbitz/openwrt-image-builder-iac/commit/0acd5c2d3d71fd54236fa95e96d8cd2b7aae653e))
* **vault:** merge generated secrets into vault.yml, drop the managed vault ([7d78953](https://github.com/cwbitz/openwrt-image-builder-iac/commit/7d78953bf03113b14668f6ae67628bc9dd23be0c))

## Changelog

All notable changes to this project are documented in this file. It is managed
by [release-please](https://github.com/googleapis/release-please): version bumps
and entries arrive through a release PR, which is merged only after the required
CI checks pass. Do not edit this file by hand.

The first release is bootstrapped as **v0.1.0** (via `initial-version` in
`release-please-config.json` + the empty `.release-please-manifest.json`); its
entry is generated from the Conventional Commits history when the first release
PR is opened.
