SHELL := /bin/bash
.DEFAULT_GOAL := help

ANS_PLAY := ansible-playbook
INV      := inventory/hosts.yml

EXTRA ?=

export ANSIBLE_VAULT_PASSWORD_FILE := $(HOME)/.config/projects/openwrt-image-builder-iac/ansible_vault_password
HOST              ?= openwrt-ib-prod-1

HOST_IP           ?=

$(foreach v,HOST HOST_IP,$(if $(filter environment,$(origin $(v))),$(warning $(v) is inherited from the environment; pass $(v)=... explicitly if unintended)))

QUIET ?=
say = $(if $(QUIET),:,echo)

REFRESH ?=
KNOWN_HOSTS ?= $(HOME)/.ssh/known_hosts

VAULT_PASSWORD_HINT := ERROR: Ansible Vault cannot decrypt this file - the password in $(ANSIBLE_VAULT_PASSWORD_FILE) is missing or incorrect. Restore the original password, or re-encrypt the vault file with the current one.

SSHPASS_BIN ?= $(HOME)/.local/bin/sshpass

KEYCHAIN_PIN     := $(CURDIR)/keychain.pin
KEYCHAIN_VERSION := $(shell awk '!/^#/ && NF {print $$1; exit}' $(KEYCHAIN_PIN))
KEYCHAIN_SHA256  := $(shell awk '!/^#/ && NF {print $$2; exit}' $(KEYCHAIN_PIN) | sed 's/^sha256://')
KEYCHAIN_URL     ?= https://github.com/danielrobbins/keychain/releases/download/$(KEYCHAIN_VERSION)/keychain-$(KEYCHAIN_VERSION).pyz
KEYCHAIN_BIN     ?= $(HOME)/.local/bin/keychain
KEYCHAIN_CACHE   ?= $(HOME)/.cache/openwrt-image-builder-iac
KEYCHAIN_ASSET   := $(KEYCHAIN_CACHE)/keychain-$(KEYCHAIN_VERSION).pyz
KEYCHAIN_AGENT   := eval "$$($(KEYCHAIN_BIN) agent start --eval --quiet 2>/dev/null)"

export ANSIBLE_CONFIG := ansible.cfg

SSH_AGENT_ENV   ?= $(HOME)/.cache/iac/ssh-agent.env
SSH_AGENT_RUN   ?= $(CURDIR)/scripts/run-with-ssh-agent.sh
SSH_AGENT_KEY_VARS ?= host_iac_ssh_privkey_file host_admin_ssh_privkey_file host_root_ssh_privkey_file
export SSH_AGENT_ENV
export SSH_AGENT_KEYCHAIN_BIN  := $(KEYCHAIN_BIN)
export SSH_AGENT_ANS_PLAY      := $(ANS_PLAY)
export SSH_AGENT_INVENTORY     := $(INV)
export SSH_AGENT_LOAD_PLAYBOOK := playbooks/ssh_agent_load.yml

SSH_AGENT_PROBE := ansible-inventory -i $(INV) --list 2>/dev/null | SSH_AGENT_KEY_VARS="$(SSH_AGENT_KEY_VARS)" python3 -c "import json,os,sys; names=os.environ['SSH_AGENT_KEY_VARS'].split(); vs=json.load(sys.stdin).get('_meta',{}).get('hostvars',{}); ks={os.path.expanduser(h.get(v)) for h in vs.values() for v in names if h.get(v)}; sys.exit(0 if any(os.path.isfile(k) and (os.stat(k).st_mode & 0o077) for k in ks) else 1)"

define SSH_AGENT_PREPARE
	@set -e; \
	mkdir -p "$$(dirname "$(SSH_AGENT_ENV)")"; \
	rm -f "$(SSH_AGENT_ENV)"; \
	if [ -n "$${SSH_AUTH_SOCK:-}" ] && ssh-add -l >/dev/null 2>&1; then \
		$(say) "ssh-agent: reusing loaded agent"; \
		echo "export SSH_AUTH_SOCK='$$SSH_AUTH_SOCK'" > "$(SSH_AGENT_ENV)"; exit 0; \
	fi; \
	if [ "$(SSH_AGENT_FORCE)" != "1" ] && ! $(SSH_AGENT_PROBE); then \
		$(say) "ssh-agent: not needed (keys usable or password auth)"; exit 0; \
	fi; \
	$(say) "ssh-agent: starting Keychain and loading keys"; \
	eval "$$($(KEYCHAIN_BIN) agent start --eval --quiet 2>/dev/null)"; \
	echo "export SSH_AUTH_SOCK='$$SSH_AUTH_SOCK'" > "$(SSH_AGENT_ENV)"; \
	$(ANS_PLAY) -i $(INV) $(SSH_AGENT_LOAD_PLAYBOOK)
endef

ANSIBLE_PYTHON ?= $(shell \
	p=$$(command -v ansible-playbook 2>/dev/null); \
	if command -v mise >/dev/null 2>&1; then m=$$(mise which ansible-playbook 2>/dev/null); [ -n "$$m" ] && p=$$m; fi; \
	if [ -n "$$p" ]; then f=$$(readlink -f "$$p" 2>/dev/null); \
	  if [ -f "$$f" ] && head -c 2 "$$f" | grep -q '#!'; then head -1 "$$f" | sed -n 's|^#! *||; s| .*||p'; fi; fi)

.PHONY: help install vault-init host-init vault-edit vault-edit-group vault-view \
        host-bootstrap info build deploy
.PHONY: ensure-toolchain ensure-sshpass ensure-keychain ensure-ansible-collections \
        ensure-passlib keychain-fetch verify-keychain-pin run-playbook \
        agent-needed agent-fallback agent-ensure agent-load agent-check \
        vault-edit-file lint

help: ## Show this help
	@printf '\nUsage: make <target> [VAR=value ...]\n\n'
	@awk 'BEGIN {FS = ":.*?## "} \
		/^[a-zA-Z0-9_-]+:.*?## / { if ($$1 == "help") { hd = $$2; next } \
			printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2 } \
		END { printf "  \033[36m%-25s\033[0m %s\n", "help", hd }' \
		$(MAKEFILE_LIST)
	@printf '\n'

install: ensure-toolchain ensure-sshpass ensure-keychain ensure-ansible-collections ensure-passlib ## Install the pinned toolchain, collections, and control-node dependencies

host-init: vault-init ## Scaffold inventory + host_vars/<HOST> from the examples (comment-free); HOST default openwrt-ib-prod-1, HOST_IP default CHANGE_ME_HOST_IP, FORCE=1 replaces an existing entry
	@[ -e $(INV) ] || { python3 $(CURDIR)/scripts/render_clean_template.py $(INV).example $(INV); echo "created $(INV) (comments stripped)"; }
	@[ -e inventory/group_vars/builders/main.yml ] || { python3 $(CURDIR)/scripts/render_clean_template.py inventory/group_vars/builders/main.yml.example inventory/group_vars/builders/main.yml; echo "created inventory/group_vars/builders/main.yml (comments stripped)"; }
	@install -d -m 0700 inventory/host_vars/$(HOST)
	@[ -e inventory/host_vars/$(HOST)/main.yml ] || python3 $(CURDIR)/scripts/render_clean_template.py --strip-blank-lines inventory/host_vars/example/main.yml inventory/host_vars/$(HOST)/main.yml
	@[ -e inventory/host_vars/$(HOST)/vault.yml ] || python3 $(CURDIR)/scripts/render_clean_template.py --strip-blank-lines inventory/host_vars/example/vault.yml.example inventory/host_vars/$(HOST)/vault.yml
	@if ! grep -q 'ANSIBLE_VAULT' inventory/host_vars/$(HOST)/vault.yml; then \
		echo "encrypting inventory/host_vars/$(HOST)/vault.yml"; \
		ansible-vault encrypt inventory/host_vars/$(HOST)/vault.yml; \
	fi
	@chmod 0600 inventory/host_vars/$(HOST)/vault.yml
	@python3 $(CURDIR)/scripts/ensure_inventory_host.py $(INV) "$(HOST)" --group builders --ansible-host "$(HOST_IP)" $(if $(FORCE),--force)
	@echo "scaffolded inventory/host_vars/$(HOST)/ (machine registered under the builders group; edit build_variants[] in main.yml)"
	@echo "next: make vault-edit HOST=$(HOST)"

host-bootstrap: hostkey-init ## Create the iac automation account (bootstrap.yml; EXTRA=<extra -e vars>; REFRESH=1 refreshes host keys first)
	@test -f $(INV) || { \
		echo "ERROR: $(INV) not found — copy $(INV).example and fill it in."; exit 1; }
	@$(MAKE) --no-print-directory run-playbook PLAYBOOK=playbooks/bootstrap.yml

vault-init: ## One-time: generate the vault password (idempotent)
	@mkdir -p $(dir $(ANSIBLE_VAULT_PASSWORD_FILE))
	@if [ ! -s $(ANSIBLE_VAULT_PASSWORD_FILE) ]; then \
		openssl rand -base64 32 > $(ANSIBLE_VAULT_PASSWORD_FILE); \
		chmod 600 $(ANSIBLE_VAULT_PASSWORD_FILE); \
		echo "vault password generated: $(ANSIBLE_VAULT_PASSWORD_FILE) (BACK IT UP in a password manager)"; \
	fi
	@test "$$(wc -c < $(ANSIBLE_VAULT_PASSWORD_FILE))" -ge 44 || { echo "ERROR: vault password too weak"; exit 1; }
	@f=""; \
	for c in $$(find inventory -type f -name 'vault*.yml' 2>/dev/null); do \
		if head -c 16 "$$c" | grep -q 'ANSIBLE_VAULT'; then f="$$c"; break; fi; \
	done; \
	if [ -n "$$f" ] && command -v ansible-vault >/dev/null 2>&1; then \
		ansible-vault view "$$f" >/dev/null 2>&1 \
			|| { printf '%s\n' "$(VAULT_PASSWORD_HINT)" >&2; exit 1; }; \
	fi

vault-edit: vault-init ## Edit a machine's vault, plaintext auto-encrypted first (keys re-sorted; HOST=<name>)
	@$(MAKE) --no-print-directory vault-edit-file VAULT_EDIT_FILE=inventory/host_vars/$(HOST)/vault.yml

vault-edit-group: vault-init ## Edit the shared builder connection vault (plaintext auto-encrypted first; keys re-sorted)
	@$(MAKE) --no-print-directory vault-edit-file VAULT_EDIT_FILE=inventory/group_vars/builders/vault.yml

vault-edit-file:
	@test -f $(VAULT_EDIT_FILE) || { echo "No such vault file: $(VAULT_EDIT_FILE)" >&2; exit 1; }
	@if grep -q 'ANSIBLE_VAULT' $(VAULT_EDIT_FILE); then :; else \
		echo "Encrypting plaintext $(VAULT_EDIT_FILE) before editing..."; \
		ansible-vault encrypt $(VAULT_EDIT_FILE) >/dev/null; \
	fi
	@set -e; \
	edit_rc=0; ansible-vault edit $(VAULT_EDIT_FILE) || edit_rc=$$?; \
	if [ $$edit_rc -eq 0 ]; then \
		b=$$(mktemp); a=$$(mktemp); rc=0; \
		trap 'rm -f "$$b" "$$a"' EXIT; \
		ansible-vault view $(VAULT_EDIT_FILE) > "$$b" || rc=1; \
		if [ $$rc -eq 0 ]; then cp "$$b" "$$a" || rc=1; fi; \
		if [ $$rc -eq 0 ]; then keys=$$(python3 $(CURDIR)/scripts/sort_vault_keys.py "$$a") || rc=1; fi; \
		if [ $$rc -ne 0 ]; then \
			echo "ERROR: could not normalise the key order of $(VAULT_EDIT_FILE); it is unchanged (as edited)" >&2; \
		elif ! cmp -s "$$b" "$$a"; then \
			ansible-vault encrypt --output $(VAULT_EDIT_FILE) "$$a" >/dev/null || rc=1; \
		fi; \
		if [ $$rc -ne 0 ]; then exit $$rc; fi; \
		echo "Encryption successful! (Total keys: $$keys)"; \
	fi; \
	exit $$edit_rc

vault-view: vault-init ## View every variant's vault + the shared connection vault (read-only)
	@test -f $(INV) || { echo "ERROR: $(INV) not found — copy $(INV).example and fill it in." >&2; exit 1; }
	@hosts="$$(ansible-inventory -i $(INV) --graph builders | awk '/\|\-\-/{sub(/^.*\|\-\- */, ""); print}')"; \
	files=""; \
	for h in $$hosts; do \
		files="$$files inventory/host_vars/$$h/vault.yml"; \
	done; \
	if [ -f inventory/group_vars/builders/vault.yml ]; then \
		files="$$files inventory/group_vars/builders/vault.yml"; \
	fi; \
	seen=""; \
	for p in $$files; do \
		case "$$seen" in *"|$$p|"*) continue;; esac; \
		seen="$$seen|$$p|"; \
		printf '\n\033[1m== %s ==\033[0m\n' "$$p"; \
		if [ ! -f "$$p" ]; then echo "(missing)"; continue; fi; \
		if grep -q 'ANSIBLE_VAULT' "$$p"; then \
			ansible-vault view "$$p" 2>/dev/null \
				|| { printf '%s\n' "$(VAULT_PASSWORD_HINT)" >&2; exit 1; }; \
		else cat "$$p"; fi; \
	done

lint: install vault-init validate-knobs
	@for p in playbooks/*.yml; do \
		$(ANS_PLAY) --syntax-check -i $(INV) "$$p" || exit 1; \
	done
	@if command -v ansible-lint >/dev/null 2>&1; then \
		ansible-lint -c .ansible-lint .; \
	else \
		echo "WARN: ansible-lint not installed, skipped"; \
	fi
	@python3 scripts/audit_example_knobs.py
	python3 scripts/check_host_keys.py

.PHONY: hostkey-init
hostkey-init: vault-init ## Refresh every managed host's SSH host key in known_hosts (FORCE=1 replaces a changed key)
	@set -e; \
	nh="$(KNOWN_HOSTS)"; mkdir -p "$$(dirname "$$nh")"; tmp=$$(mktemp); targets=$$(mktemp); tsv=$$(mktemp); pub=$$(mktemp); failures=0; \
	trap 'rm -f "$$tmp" "$$targets" "$$tsv" "$$pub"' EXIT; \
	if [ -f "$$nh" ]; then cp "$$nh" "$$tmp"; else : > "$$tmp"; fi; \
	$(ANS_PLAY) -i $(INV) playbooks/host_keys.yml -e host_keys_out="$$targets" >/dev/null; \
	python3 -c 'import json,sys; [print("{}\t{}\t{}".format(t["name"],t["host"],t["port"])) for t in json.load(open(sys.argv[1]))]' "$$targets" > "$$tsv"; \
	mv "$$tsv" "$$targets"; \
	test -s "$$targets" || { echo "ERROR: no hosts resolved from the inventory."; exit 1; }; \
	while IFS=$$'\t' read -r name host port; do \
		[ -n "$$name" ] || continue; \
		echo "host key: $$name ($$host:$$port)"; \
		if ! keys="$$(ssh-keyscan -T 5 -p "$$port" "$$host" 2>/dev/null)" || [ -z "$$keys" ]; then \
			echo "ERROR: ssh-keyscan returned no host key for $$host:$$port; entry left unchanged" >&2; failures=1; continue; \
		fi; \
		if [ "$$port" = "22" ]; then key="$$host"; else key="[$$host]:$$port"; fi; \
		old=$$(ssh-keygen -F "$$key" -f "$$tmp" 2>/dev/null | awk '!/^#/ && NF {print $$2" "$$3}' | sort); \
		new=$$(printf '%s\n' "$$keys" | awk '{print $$2" "$$3}' | sort); \
	printf '%s\n' "$$keys" | awk '{print $$2" "$$3}' > "$$pub"; \
	ssh-keygen -lf "$$pub" 2>/dev/null | sed 's/^/  fingerprint: /' >&2 || true; \
		if [ -n "$$old" ] && [ -n "$$(comm -23 <(printf '%s\n' "$$old") <(printf '%s\n' "$$new"))" ] && [ "$(FORCE)" != "1" ]; then \
			echo "ERROR: host key changed for $$key; verify the fingerprint, then re-run with FORCE=1" >&2; failures=1; continue; \
		fi; \
		ssh-keygen -R "$$key" -f "$$tmp" >/dev/null 2>&1 || true; \
		printf '%s\n' "$$keys" >> "$$tmp"; \
	done < "$$targets"; \
	chmod 600 "$$tmp"; mv "$$tmp" "$$nh"; \
	[ "$$failures" -eq 0 ] || { echo "some host keys were not refreshed; known_hosts updated for the rest" >&2; exit 1; }; \
	echo "host keys refreshed in $$nh"


info: ## Query ImageBuilder image/profile info (no build; EXTRA=<extra -e vars>)
	@test -f $(INV) || { \
		echo "ERROR: $(INV) not found — copy $(INV).example and fill it in."; exit 1; }
	@log=$$(mktemp); spin=""; \
	trap 'rm -f "$$log"; [ -n "$$spin" ] && kill "$$spin" 2>/dev/null' EXIT INT TERM; \
	if [ -t 2 ]; then \
		( frames='|/-'; i=0; while :; do printf '\r%s Querying ImageBuilder info' "$${frames:$$i:1}" >&2; i=$$(( (i+1) % 3 )); sleep 0.15; done ) & \
		spin=$$!; \
	else \
		printf 'Querying ImageBuilder info\n' >&2; \
	fi; \
	QUIET=1 \
	ANSIBLE_STDOUT_CALLBACK=info_format \
	ANSIBLE_CALLBACK_PLUGINS=$(CURDIR)/callback_plugins \
	ANSIBLE_CALLBACKS_ENABLED=info_silent \
	$(MAKE) --no-print-directory run-playbook PLAYBOOK=playbooks/info.yml >"$$log" 2>&1; \
	rc=$$?; \
	if [ -n "$$spin" ]; then kill "$$spin" 2>/dev/null; wait "$$spin" 2>/dev/null; printf '\r\033[K' >&2; fi; \
	cat "$$log"; \
	exit $$rc

build: validate-knobs ## Build a customized OpenWrt firmware image, run host-bootstrap first (EXTRA=<extra -e vars>)
	@test -f $(INV) || { \
		echo "ERROR: $(INV) not found — copy $(INV).example and fill it in."; exit 1; }
	@$(MAKE) --no-print-directory run-playbook PLAYBOOK=playbooks/build.yml

deploy: host-bootstrap build ## One-click: bootstrap the build host, then build every variant (EXTRA=<extra -e vars>; REFRESH=1 refreshes host keys first)

agent-needed: vault-init
	@$(SSH_AGENT_PROBE)

agent-fallback: ensure-keychain
	$(SSH_AGENT_PREPARE)

agent-ensure: ensure-keychain
	$(SSH_AGENT_PREPARE)
agent-ensure: SSH_AGENT_FORCE := 1

agent-load: install vault-init
	@$(KEYCHAIN_AGENT); \
	$(ANS_PLAY) -i $(INV) $(SSH_AGENT_LOAD_PLAYBOOK)

agent-check: install vault-init
	@$(KEYCHAIN_AGENT); \
	if ssh-add -l >/dev/null 2>&1; then \
		echo "ssh-agent: identities loaded"; \
	else \
		echo "ERROR: the Keychain ssh-agent has no identities loaded."; \
		echo "Load the connection keys with: make agent-load"; \
		exit 1; \
	fi

ensure-toolchain:
	@command -v python3 >/dev/null 2>&1 || { \
		echo "ERROR: python3 not found on the control node."; exit 1; }
	@python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 8) else 1)' \
		|| { echo "ERROR: python3 >= 3.8 required; found $$(python3 --version 2>&1)."; exit 1; }
	@command -v openssl >/dev/null 2>&1 \
		|| { echo "ERROR: openssl is required (secret generation). Install it."; exit 1; }
	@$(say) "toolchain: python3 $$(python3 --version 2>&1 | awk '{print $$2}'), openssl $$(openssl version | awk '{print $$2}')"

ensure-sshpass:
	@set -e; \
	if command -v sshpass >/dev/null 2>&1 || [ -x "$(SSHPASS_BIN)" ]; then \
		$(say) "sshpass: present"; exit 0; \
	fi; \
	if sudo -n true >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then \
		$(say) "sshpass: installing via sudo apt-get..."; \
		if sudo -n apt-get install -y sshpass; then exit 0; fi; \
		$(say) "sshpass: sudo install failed — trying a rootless install..."; \
	fi; \
	$(say) "sshpass: installing rootless into $(dir $(SSHPASS_BIN))..."; \
	if ! command -v apt-get >/dev/null 2>&1 || ! command -v dpkg-deb >/dev/null 2>&1; then \
		echo "ERROR: cannot auto-install sshpass (apt-get/dpkg-deb not found)." >&2; \
		echo "  Install sshpass manually, or use key-only bootstrap credentials" >&2; \
		echo "  (host_<id>_ssh_privkey_file)." >&2; \
		exit 1; \
	fi; \
	tmp=$$(mktemp -d); trap 'rm -rf "$$tmp"' EXIT; cd "$$tmp"; \
	apt-get download sshpass >/dev/null 2>&1 || { \
		echo "ERROR: failed to download the sshpass package." >&2; \
		echo "  Install sshpass manually, or use key-only bootstrap credentials." >&2; \
		exit 1; }; \
	dpkg-deb -x sshpass_*.deb root; \
	mkdir -p "$(dir $(SSHPASS_BIN))"; \
	install -m 0755 root/usr/bin/sshpass "$(SSHPASS_BIN)"; \
	$(say) "sshpass installed: $(SSHPASS_BIN)"

ensure-passlib:
	@set -e; \
	py="$(ANSIBLE_PYTHON)"; [ -n "$$py" ] || py=$$(command -v python3); \
	if "$$py" -c 'import passlib' >/dev/null 2>&1; then \
		$(say) "passlib: present ($$py)"; exit 0; \
	fi; \
	if "$$py" -m pip install --quiet passlib >/dev/null 2>&1; then \
		$(say) "passlib: installed with pip ($$py)"; exit 0; \
	fi; \
	$(say) "passlib: pip unavailable for $$py — using the rootless deb fallback..."; \
	if ! command -v apt-get >/dev/null 2>&1 || ! command -v dpkg-deb >/dev/null 2>&1; then \
		echo "ERROR: cannot auto-install passlib (apt-get/dpkg-deb not found)." >&2; \
		echo "  Install python3-passlib with pip or your package manager." >&2; \
		exit 1; \
	fi; \
	dest=$$("$$py" -c "import sys,site; print(site.getsitepackages()[0] if sys.prefix != sys.base_prefix else site.getusersitepackages())"); \
	tmp=$$(mktemp -d); trap 'rm -rf "$$tmp"' EXIT; cd "$$tmp"; \
	apt-get download python3-passlib >/dev/null 2>&1 || { \
		echo "ERROR: failed to download the python3-passlib package." >&2; \
		echo "  Install python3-passlib with pip or your package manager." >&2; \
		exit 1; }; \
	dpkg-deb -x python3-passlib_*.deb root; \
	mkdir -p "$$dest"; \
	cp -a root/usr/lib/python3/dist-packages/passlib "$$dest/"; \
	$(say) "passlib installed: $$dest/passlib"

ensure-ansible-collections:
	@ansible-galaxy collection install -r requirements.yml $(if $(QUIET),1>/dev/null,)

keychain-fetch:
	@set -e; \
	mkdir -p "$(KEYCHAIN_CACHE)"; \
	if [ -f "$(KEYCHAIN_ASSET)" ] \
	   && printf '%s  %s\n' "$(KEYCHAIN_SHA256)" "$(KEYCHAIN_ASSET)" | sha256sum -c - >/dev/null 2>&1; then \
		exit 0; \
	fi; \
	$(say) "downloading keychain $(KEYCHAIN_VERSION)..."; \
	if ! curl -fsSL -o "$(KEYCHAIN_ASSET).tmp" "$(KEYCHAIN_URL)"; then \
		rm -f "$(KEYCHAIN_ASSET).tmp"; \
		echo "ERROR: failed to download keychain v$(KEYCHAIN_VERSION)." >&2; \
		echo "  Download it manually from:" >&2; \
		echo "    $(KEYCHAIN_URL)" >&2; \
		echo "  save it to $(KEYCHAIN_ASSET) and re-run." >&2; \
		exit 1; \
	fi; \
	mv "$(KEYCHAIN_ASSET).tmp" "$(KEYCHAIN_ASSET)"

verify-keychain-pin: keychain-fetch
	@set -e; \
	printf '%s  %s\n' "$(KEYCHAIN_SHA256)" "$(KEYCHAIN_ASSET)" | sha256sum -c - >/dev/null \
		|| { echo "ERROR: keychain asset checksum mismatch: $(KEYCHAIN_ASSET)" >&2; \
		     echo "  Remove it and re-run, or download it manually from $(KEYCHAIN_URL)." >&2; \
		     exit 1; }; \
	$(say) "keychain pin OK: v$(KEYCHAIN_VERSION)"

ensure-keychain: verify-keychain-pin
	@set -e; \
	if [ -f "$(KEYCHAIN_BIN)" ] \
	   && printf '%s  %s\n' "$(KEYCHAIN_SHA256)" "$(KEYCHAIN_BIN)" | sha256sum -c - >/dev/null 2>&1; then \
		$(say) "keychain:  present (v$(KEYCHAIN_VERSION), $(KEYCHAIN_BIN))"; \
	else \
		mkdir -p "$$(dirname "$(KEYCHAIN_BIN)")"; \
		install -m 0755 "$(KEYCHAIN_ASSET)" "$(KEYCHAIN_BIN)"; \
		$(say) "keychain installed: $(KEYCHAIN_BIN) (v$(KEYCHAIN_VERSION))"; \
	fi

run-playbook: install vault-init agent-fallback
	@$(SSH_AGENT_RUN) $(ANS_PLAY) -i $(INV) $(PLAYBOOK) $(EXTRA)

.PHONY: validate-knobs
validate-knobs: vault-init
	@if [ -f $(INV) ]; then $(ANS_PLAY) -i $(INV) playbooks/validate_knobs.yml; else echo "validate-knobs: $(INV) missing, skipped"; fi
