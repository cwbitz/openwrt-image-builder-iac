SHELL := /bin/bash
.DEFAULT_GOAL := help

ANS_PLAY := ansible-playbook
INV      := inventory/hosts.yml

# Extra Ansible args appended to every playbook invocation, e.g.
#   make build EXTRA='-e openwrt_modules_adjust=["statistics"]'
EXTRA ?=

# Vault password file (kept OUTSIDE the repo). The canonical `ansible.cfg` sets
# `vault_password_file` to the same path, so a raw ansible-vault/ansible-* from
# the project root auto-loads it. ansible-core 2.19 hard-fails when the file is
# missing, so the ansible-running targets depend on `vault-init` (which
# generates it), and CI generates a throwaway one before lint/syntax-check.
# Ansible Vault password file (outside the repo), exported under Ansible's own
# env-var name so every ansible-* invocation picks it up.
export ANSIBLE_VAULT_PASSWORD_FILE := $(HOME)/.config/projects/openwrt-image-builder-iac/ansible_vault_password
# VARIANT names the variant to operate on (its inventory host / host_vars dir).
# `vault-edit` edits that variant's vault; `vault-edit-group` edits the shared
# builder connection vault; `vault-view` auto-iterates every variant vault plus
# the shared connection vault.
VARIANT           ?= ib-main

# Refresh SSH host keys before connecting (HOST_KEY=1). Useful after the build
# host is rebuilt: its new host key would otherwise fail the "host key changed"
# check. hostkey-init scans every inventory host and (re)writes its key into
# the control node's known_hosts. deploy/host-bootstrap call it when set.
HOST_KEY ?=
# known_hosts file to write (control node). Defaults to OpenSSH's user file.
KNOWN_HOSTS ?= $(HOME)/.ssh/known_hosts

# Unified operator hint, printed only when a vault command cannot decrypt a
# file (the vault password is missing or does not match).
VAULT_PASSWORD_HINT := ERROR: Ansible Vault cannot decrypt this file - the password in $(ANSIBLE_VAULT_PASSWORD_FILE) is missing or incorrect. Restore the original password, or re-encrypt the vault file with the current one.

# sshpass is a control-node prerequisite (`make host-bootstrap` password SSH).
# When passwordless sudo is unavailable, fall back to a rootless install into
# ~/.local/bin. Ensured by the internal `ensure-sshpass` target (called by
# `install`); a failure is fatal.
SSHPASS_BIN ?= $(HOME)/.local/bin/sshpass

# Keychain 3 (pinned, single zipapp) is a FALLBACK ssh-agent: `install` ensures
# it can be installed, but it is only started when OpenSSH refuses a private
# key whose file permissions cannot be fixed (e.g. on the WSL /mnt/c mount).
# Loading via stdin (`ssh-add - < key`) reads the key content directly and skips
# the permission check. The asset URL is a fixed constant; a failed download is
# fatal (fetch the asset manually and re-run).
KEYCHAIN_PIN     := $(CURDIR)/keychain.pin
KEYCHAIN_VERSION := $(shell awk '!/^#/ && NF {print $$1; exit}' $(KEYCHAIN_PIN))
KEYCHAIN_SHA256  := $(shell awk '!/^#/ && NF {print $$2; exit}' $(KEYCHAIN_PIN) | sed 's/^sha256://')
KEYCHAIN_URL     ?= https://github.com/danielrobbins/keychain/releases/download/$(KEYCHAIN_VERSION)/keychain-$(KEYCHAIN_VERSION).pyz
KEYCHAIN_BIN     ?= $(HOME)/.local/bin/keychain
KEYCHAIN_CACHE   ?= $(HOME)/.cache/openwrt-image-builder-iac
KEYCHAIN_ASSET   := $(KEYCHAIN_CACHE)/keychain-$(KEYCHAIN_VERSION).pyz
# Start (or reuse) the Keychain agent in the CURRENT shell; --eval prints the
# SSH_AUTH_SOCK / SSH_AGENT_PID exports on stdout (banner goes to stderr).
KEYCHAIN_AGENT   := eval "$$($(KEYCHAIN_BIN) agent start --eval --quiet 2>/dev/null)"

export ANSIBLE_CONFIG := ansible.cfg

# ------------------------------------------------ shared ssh-agent runner ----
# Identical across the 5 IaC projects: the generic scripts/run-with-ssh-agent.sh
# is driven by the SSH_AGENT_* environment variables, so only the per-project
# values below differ (the private-key hostvar names, and the inventory/playbook
# paths already defined above). The agent is prepared proactively only when a
# configured key has permissions OpenSSH would refuse (e.g. WSL /mnt/c), and the
# runner retries once on a refused-key failure as a safety net.
SSH_AGENT_ENV   ?= $(HOME)/.cache/iac/ssh-agent.env
SSH_AGENT_RUN   ?= $(CURDIR)/scripts/run-with-ssh-agent.sh
# Per-project fork: hostvars holding the control-node private-key paths.
SSH_AGENT_KEY_VARS ?= vault_host_ansible_ssh_privkey_file vault_host_admin_ssh_privkey_file vault_host_root_ssh_privkey_file
export SSH_AGENT_ENV
export SSH_AGENT_KEYCHAIN_BIN  := $(KEYCHAIN_BIN)
export SSH_AGENT_ANS_PLAY      := $(ANS_PLAY)
export SSH_AGENT_INVENTORY     := $(INV)
export SSH_AGENT_LOAD_PLAYBOOK := playbooks/ssh_agent_load.yml

# (shared) Probe: exit 0 when a configured private key has unsafe permissions
# (group/other bits set, e.g. 0777), i.e. OpenSSH would refuse it.
SSH_AGENT_PROBE := ansible-inventory -i $(INV) --list 2>/dev/null | SSH_AGENT_KEY_VARS="$(SSH_AGENT_KEY_VARS)" python3 -c "import json,os,sys; names=os.environ['SSH_AGENT_KEY_VARS'].split(); vs=json.load(sys.stdin).get('_meta',{}).get('hostvars',{}); ks={os.path.expanduser(h.get(v)) for h in vs.values() for v in names if h.get(v)}; sys.exit(0 if any(os.path.isfile(k) and (os.stat(k).st_mode & 0o077) for k in ks) else 1)"

# (shared) Canned recipe: prepare the Keychain ssh-agent. Reuse a loaded agent;
# otherwise start Keychain and load the configured keys. SSH_AGENT_FORCE=1 skips
# the permission probe. Writes SSH_AGENT_ENV for the runner to source.
define SSH_AGENT_PREPARE
	@set -e; \
	mkdir -p "$$(dirname "$(SSH_AGENT_ENV)")"; \
	rm -f "$(SSH_AGENT_ENV)"; \
	if [ -n "$${SSH_AUTH_SOCK:-}" ] && ssh-add -l >/dev/null 2>&1; then \
		echo "ssh-agent: reusing loaded agent"; \
		echo "export SSH_AUTH_SOCK='$$SSH_AUTH_SOCK'" > "$(SSH_AGENT_ENV)"; exit 0; \
	fi; \
	if [ "$(SSH_AGENT_FORCE)" != "1" ] && ! $(SSH_AGENT_PROBE); then \
		echo "ssh-agent: not needed (keys usable or password auth)"; exit 0; \
	fi; \
	echo "ssh-agent: starting Keychain and loading keys"; \
	eval "$$($(KEYCHAIN_BIN) agent start --eval --quiet 2>/dev/null)"; \
	echo "export SSH_AUTH_SOCK='$$SSH_AUTH_SOCK'" > "$(SSH_AGENT_ENV)"; \
	$(ANS_PLAY) -i $(INV) $(SSH_AGENT_LOAD_PLAYBOOK)
endef

# Interpreter that runs ansible-playbook: the community.docker modules need the
# `docker` Python SDK importable by the target's interpreter (asserted by the
# role preflight on the build host). Resolve the mise tool path first.
ANSIBLE_PYTHON ?= $(shell \
	p=$$(command -v ansible-playbook 2>/dev/null); \
	if command -v mise >/dev/null 2>&1; then m=$$(mise which ansible-playbook 2>/dev/null); [ -n "$$m" ] && p=$$m; fi; \
	if [ -n "$$p" ]; then f=$$(readlink -f "$$p" 2>/dev/null); \
	  if [ -f "$$f" ] && head -c 2 "$$f" | grep -q '#!'; then head -1 "$$f" | sed -n 's|^#! *||; s| .*||p'; fi; fi)

# Public interface (documented by `make help`).
.PHONY: help install vault-init host-init vault-edit vault-edit-group vault-view \
        host-bootstrap info build deploy
# Internal helpers (not listed in help; not part of the public interface).
.PHONY: ensure-toolchain ensure-sshpass ensure-keychain ensure-collections \
        ensure-passlib keychain-fetch verify-keychain-pin run-playbook \
        agent-needed agent-fallback agent-ensure agent-load agent-check \
        vault-edit-file lint hostkey-init

help: ## Show this help
	@printf '\nUsage: make <target> [VAR=value ...]\n\n'
	@awk 'BEGIN {FS = ":.*?## "} \
		/^[a-zA-Z0-9_-]+:.*?## / { if ($$1 == "help") { hd = $$2; next } \
			printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2 } \
		END { printf "  \033[36m%-25s\033[0m %s\n", "help", hd }' \
		$(MAKEFILE_LIST)
	@printf '\n'

# ==============================================================================
# Dependencies: `install` is the ONLY dependency entry point
# ==============================================================================
# Every other target depends on `install` (directly, or through `run-playbook`),
# which ensures the toolchain, collections, sshpass, passlib and Keychain in one
# place. The `ensure-*` helpers below are internal and fail loudly.

install: ensure-toolchain ensure-sshpass ensure-keychain ensure-collections ensure-passlib ## Install the pinned toolchain, collections, and control-node dependencies

host-init: vault-init ## Scaffold group_vars + host_vars/<VARIANT> from the examples (vault encrypted; VARIANT=<name>)
	@test -n "$(VARIANT)" || { echo "ERROR: VARIANT is required, e.g. make host-init VARIANT=ib-main"; exit 1; }
	@[ -e $(INV) ] || { cp $(INV).example $(INV); echo "created $(INV)"; }
	@[ -e inventory/group_vars/builder/main.yml ] || { cp inventory/group_vars/builder/main.yml.example inventory/group_vars/builder/main.yml; echo "created inventory/group_vars/builder/main.yml"; }
	@install -d -m 0700 inventory/host_vars/$(VARIANT)
	@[ -e inventory/host_vars/$(VARIANT)/main.yml ] || cp inventory/host_vars/variant.example/main.yml inventory/host_vars/$(VARIANT)/main.yml
	@[ -e inventory/host_vars/$(VARIANT)/vault.yml ] || cp inventory/host_vars/variant.example/vault.yml.example inventory/host_vars/$(VARIANT)/vault.yml
	@if ! grep -q 'ANSIBLE_VAULT' inventory/host_vars/$(VARIANT)/vault.yml; then \
		echo "encrypting inventory/host_vars/$(VARIANT)/vault.yml"; \
		ansible-vault encrypt inventory/host_vars/$(VARIANT)/vault.yml; \
	fi
	@chmod 0600 inventory/host_vars/$(VARIANT)/vault.yml
	@echo "scaffolded inventory/host_vars/$(VARIANT)/ (edit main.yml; make vault-edit VARIANT=$(VARIANT) for vault.yml)"

host-bootstrap: ## Create the ansible service account (bootstrap.yml; EXTRA=<extra -e vars>; HOST_KEY=1 refreshes host keys first)
	@test -f $(INV) || { \
		echo "ERROR: $(INV) not found — copy $(INV).example and fill it in."; exit 1; }
	@if [ -n "$(HOST_KEY)" ]; then $(MAKE) --no-print-directory hostkey-init; fi
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

vault-edit: vault-init ## Edit a variant's vault, plaintext auto-encrypted first (VARIANT=<name>)
	@$(MAKE) --no-print-directory vault-edit-file VAULT_EDIT_FILE=inventory/host_vars/$(VARIANT)/vault.yml

vault-edit-group: vault-init ## Edit the shared builder connection vault (plaintext auto-encrypted first)
	@$(MAKE) --no-print-directory vault-edit-file VAULT_EDIT_FILE=inventory/group_vars/builder/vault.yml

# (internal) Encrypt a plaintext vault in place, then edit it.
vault-edit-file:
	@test -f $(VAULT_EDIT_FILE) || { echo "No such vault file: $(VAULT_EDIT_FILE)" >&2; exit 1; }
	@if grep -q 'ANSIBLE_VAULT' $(VAULT_EDIT_FILE); then :; else \
		echo "Encrypting plaintext $(VAULT_EDIT_FILE) before editing..."; \
		ansible-vault encrypt $(VAULT_EDIT_FILE); \
	fi
	ansible-vault edit $(VAULT_EDIT_FILE)

vault-view: vault-init ## View every pseudo-host vault + the shared connection vault (read-only)
	@test -f $(INV) || { echo "ERROR: $(INV) not found — copy $(INV).example and fill it in." >&2; exit 1; }
	@hosts="$$(ansible-inventory -i $(INV) --graph builder | awk '/\|\-\-/{sub(/^.*\|\-\- */, ""); print}')"; \
	files=""; \
	for h in $$hosts; do \
		files="$$files inventory/host_vars/$$h/vault.yml"; \
	done; \
	if [ -f inventory/group_vars/builder/vault.yml ]; then \
		files="$$files inventory/group_vars/builder/vault.yml"; \
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

# (internal) Syntax check + ansible-lint (invoked by CI).
lint: install vault-init
	@for p in playbooks/*.yml; do \
		$(ANS_PLAY) --syntax-check -i $(INV) "$$p" || exit 1; \
	done
	@if command -v ansible-lint >/dev/null 2>&1; then \
		ansible-lint -c .ansible-lint .; \
	else \
		echo "WARN: ansible-lint not installed, skipped"; \
	fi

# (internal) Scan every inventory host and (re)write its SSH host key into the
# control node's known_hosts (removing any stale entry first). Invoked by
# deploy/host-bootstrap when HOST_KEY=1, and usable standalone.
hostkey-init: vault-init
	@set -e; \
	nh="$(KNOWN_HOSTS)"; mkdir -p "$$(dirname "$$nh")"; tmp=$$(mktemp); \
	$(ANS_PLAY) -i $(INV) playbooks/host_keys.yml -e host_keys_out="$$tmp" >/dev/null; \
	mapfile -t lines < <(python3 -c "import json; [print(f\"{t['name']}\t{t['host']}\t{t['port']}\") for t in json.load(open('$$tmp'))]"); \
	rm -f "$$tmp"; \
	if [ "$${#lines[@]}" -eq 0 ]; then echo "ERROR: no hosts resolved from the inventory."; exit 1; fi; \
	for line in "$${lines[@]}"; do \
		name=$$(printf '%s' "$$line" | cut -f1); host=$$(printf '%s' "$$line" | cut -f2); port=$$(printf '%s' "$$line" | cut -f3); \
		echo "host key: $$name ($$host:$$port)"; \
		ssh-keygen -R "$$host" -f "$$nh" >/dev/null 2>&1 || true; \
		if [ "$$port" != "22" ]; then ssh-keygen -R "[$$host]:$$port" -f "$$nh" >/dev/null 2>&1 || true; fi; \
		ssh-keyscan -T 5 -p "$$port" -t rsa,ecdsa,ed25519 "$$host" >> "$$nh" 2>/dev/null || { echo "ERROR: ssh-keyscan failed for $$host:$$port"; exit 1; }; \
	done; \
	echo "host keys refreshed in $$nh"

info: ## Query ImageBuilder image/profile info (no build; EXTRA=<extra -e vars>)
	@test -f $(INV) || { \
		echo "ERROR: $(INV) not found — copy $(INV).example and fill it in."; exit 1; }
	@$(MAKE) --no-print-directory run-playbook PLAYBOOK=playbooks/info.yml

build: ## Build a customized OpenWrt firmware image, run host-bootstrap first (EXTRA=<extra -e vars>)
	@test -f $(INV) || { \
		echo "ERROR: $(INV) not found — copy $(INV).example and fill it in."; exit 1; }
	@$(MAKE) --no-print-directory run-playbook PLAYBOOK=playbooks/build.yml

deploy: host-bootstrap build ## One-click: bootstrap the build host, then build every variant (EXTRA=<extra -e vars>; HOST_KEY=1 refreshes host keys first)
	@if [ -n "$(HOST_KEY)" ]; then $(MAKE) --no-print-directory hostkey-init; fi

# ==============================================================================
# Internal helpers (not part of the public interface)
# ==============================================================================

# (internal) Diagnostic probe: exit 0 when a configured private key would be
# refused by OpenSSH. Shared across the 5 projects.
agent-needed: vault-init
	@$(SSH_AGENT_PROBE)

# (internal) Prepare the Keychain ssh-agent, probe-gated (Ansible targets).
agent-fallback: ensure-keychain
	$(SSH_AGENT_PREPARE)

# (internal) Prepare the Keychain ssh-agent unconditionally. Unused by this
# Ansible-only project, kept so the block is identical across the 5 projects.
agent-ensure: ensure-keychain
	$(SSH_AGENT_PREPARE)
agent-ensure: SSH_AGENT_FORCE := 1

# (internal) Start/reuse the Keychain ssh-agent and load the vault keys. Only
# used as an explicit convenience; `run-playbook` prepares the agent on demand.
agent-load: install vault-init
	@$(KEYCHAIN_AGENT); \
	$(ANS_PLAY) -i $(INV) $(SSH_AGENT_LOAD_PLAYBOOK)

# (internal) Diagnostic: ensure the Keychain is installed and the agent has
# identities loaded. `run-playbook` already starts it on demand.
agent-check: install vault-init
	@$(KEYCHAIN_AGENT); \
	if ssh-add -l >/dev/null 2>&1; then \
		echo "ssh-agent: identities loaded"; \
	else \
		echo "ERROR: the Keychain ssh-agent has no identities loaded."; \
		echo "Load the connection keys with: make agent-load"; \
		exit 1; \
	fi

# (internal) Ensure the control-node toolchain: python >= 3.8 + openssl.
ensure-toolchain:
	@command -v python3 >/dev/null 2>&1 || { \
		echo "ERROR: python3 not found on the control node."; exit 1; }
	@python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 8) else 1)' \
		|| { echo "ERROR: python3 >= 3.8 required; found $$(python3 --version 2>&1)."; exit 1; }
	@command -v openssl >/dev/null 2>&1 \
		|| { echo "ERROR: openssl is required (secret generation). Install it."; exit 1; }
	@echo "toolchain: python3 $$(python3 --version 2>&1 | awk '{print $$2}'), openssl $$(openssl version | awk '{print $$2}')"

# (internal) Ensure sshpass: passwordless apt-get when available, otherwise a
# rootless install into ~/.local/bin. A failure is fatal (install it manually or
# use key-only bootstrap credentials).
ensure-sshpass:
	@set -e; \
	if command -v sshpass >/dev/null 2>&1 || [ -x "$(SSHPASS_BIN)" ]; then \
		echo "sshpass: present"; exit 0; \
	fi; \
	if sudo -n true >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then \
		echo "sshpass: installing via sudo apt-get..."; \
		if sudo -n apt-get install -y sshpass; then exit 0; fi; \
		echo "sshpass: sudo install failed — trying a rootless install..."; \
	fi; \
	echo "sshpass: installing rootless into $(dir $(SSHPASS_BIN))..."; \
	if ! command -v apt-get >/dev/null 2>&1 || ! command -v dpkg-deb >/dev/null 2>&1; then \
		echo "ERROR: cannot auto-install sshpass (apt-get/dpkg-deb not found)." >&2; \
		echo "  Install sshpass manually, or use key-only bootstrap credentials" >&2; \
		echo "  (vault_host_<id>_ssh_privkey_file)." >&2; \
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
	echo "sshpass installed: $(SSHPASS_BIN)"

# (internal) Ensure passlib (password_hash for the automation user): the target
# interpreter already has it, else pip, else a rootless deb fallback. Fatal.
ensure-passlib:
	@set -e; \
	py="$(ANSIBLE_PYTHON)"; [ -n "$$py" ] || py=$$(command -v python3); \
	if "$$py" -c 'import passlib' >/dev/null 2>&1; then \
		echo "passlib: present ($$py)"; exit 0; \
	fi; \
	if "$$py" -m pip install --quiet passlib >/dev/null 2>&1; then \
		echo "passlib: installed with pip ($$py)"; exit 0; \
	fi; \
	echo "passlib: pip unavailable for $$py — using the rootless deb fallback..."; \
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
	echo "passlib installed: $$dest/passlib"

# (internal) Ensure the required Ansible collections are installed.
ensure-collections:
	@cols="$$(ansible-galaxy collection list 2>/dev/null)"; \
	if printf '%s\n' "$$cols" | grep -qE '^community\.docker[[:space:]]'; then \
		echo "ansible collections: present"; \
	else \
		echo "ansible collections: missing — installing"; \
		ansible-galaxy collection install -r requirements.yml -p collections; \
	fi

# (internal) Download the pinned Keychain asset into the cache. A failed
# download is fatal: fetch the asset manually and re-run.
keychain-fetch:
	@set -e; \
	mkdir -p "$(KEYCHAIN_CACHE)"; \
	if [ -f "$(KEYCHAIN_ASSET)" ] \
	   && printf '%s  %s\n' "$(KEYCHAIN_SHA256)" "$(KEYCHAIN_ASSET)" | sha256sum -c - >/dev/null 2>&1; then \
		exit 0; \
	fi; \
	echo "downloading keychain $(KEYCHAIN_VERSION)..."; \
	if ! curl -fsSL -o "$(KEYCHAIN_ASSET).tmp" "$(KEYCHAIN_URL)"; then \
		rm -f "$(KEYCHAIN_ASSET).tmp"; \
		echo "ERROR: failed to download keychain v$(KEYCHAIN_VERSION)." >&2; \
		echo "  Download it manually from:" >&2; \
		echo "    $(KEYCHAIN_URL)" >&2; \
		echo "  save it to $(KEYCHAIN_ASSET) and re-run." >&2; \
		exit 1; \
	fi; \
	mv "$(KEYCHAIN_ASSET).tmp" "$(KEYCHAIN_ASSET)"

# (internal) Verify the cached Keychain asset against the pin.
verify-keychain-pin: keychain-fetch
	@set -e; \
	printf '%s  %s\n' "$(KEYCHAIN_SHA256)" "$(KEYCHAIN_ASSET)" | sha256sum -c - >/dev/null \
		|| { echo "ERROR: keychain asset checksum mismatch: $(KEYCHAIN_ASSET)" >&2; \
		     echo "  Remove it and re-run, or download it manually from $(KEYCHAIN_URL)." >&2; \
		     exit 1; }; \
	echo "keychain pin OK: v$(KEYCHAIN_VERSION)"

# (internal) Ensure the pinned Keychain is installed (used only as a fallback).
ensure-keychain: verify-keychain-pin
	@set -e; \
	if [ -f "$(KEYCHAIN_BIN)" ] \
	   && printf '%s  %s\n' "$(KEYCHAIN_SHA256)" "$(KEYCHAIN_BIN)" | sha256sum -c - >/dev/null 2>&1; then \
		echo "keychain:  present (v$(KEYCHAIN_VERSION), $(KEYCHAIN_BIN))"; \
	else \
		mkdir -p "$$(dirname "$(KEYCHAIN_BIN)")"; \
		install -m 0755 "$(KEYCHAIN_ASSET)" "$(KEYCHAIN_BIN)"; \
		echo "keychain installed: $(KEYCHAIN_BIN) (v$(KEYCHAIN_VERSION))"; \
	fi

# (internal) Run a playbook through the shared ssh-agent runner: the agent is
# prepared (probe-gated) first, and the runner retries once if OpenSSH refuses a
# private key (e.g. 0777 on the WSL /mnt/c mount). Correctly permissioned keys
# (and password auth) connect directly, with no agent.
run-playbook: install vault-init agent-fallback
	@$(SSH_AGENT_RUN) $(ANS_PLAY) -i $(INV) $(PLAYBOOK) $(EXTRA)
