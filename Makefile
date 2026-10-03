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
export ANSIBLE_VAULT_PASSWORD_FILE := $(HOME)/.config/projects/openwrt-builder-wrapper/ansible_vault_password
# HOST names the variant to operate on (its inventory host / host_vars dir).
# VAULT_FILE is the operator vault (edited by `vault-edit`); MANAGED_VAULT_FILE
# is the role-generated shared vault. `vault-view` shows both (missing skipped).
HOST              ?= ib-main
VAULT_FILE        ?= inventory/host_vars/$(HOST)/vault.yml
MANAGED_VAULT_FILE ?= inventory/group_vars/builder/vault_managed.yml

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
KEYCHAIN_URL     := https://github.com/danielrobbins/keychain/releases/download/$(KEYCHAIN_VERSION)/keychain-$(KEYCHAIN_VERSION).pyz
KEYCHAIN_BIN     ?= $(HOME)/.local/bin/keychain
KEYCHAIN_CACHE   ?= $(HOME)/.cache/openwrt-builder-wrapper
KEYCHAIN_ASSET   := $(KEYCHAIN_CACHE)/keychain-$(KEYCHAIN_VERSION).pyz
# Start (or reuse) the Keychain agent in the CURRENT shell; --eval prints the
# SSH_AUTH_SOCK / SSH_AGENT_PID exports on stdout (banner goes to stderr).
KEYCHAIN_AGENT   := eval "$$($(KEYCHAIN_BIN) agent start --eval --quiet 2>/dev/null)"

export ANSIBLE_CONFIG := ansible.cfg

# Interpreter that runs ansible-playbook: the community.docker modules need the
# `docker` Python SDK importable by the target's interpreter (asserted by the
# role preflight on the build host). Resolve the mise tool path first.
ANSIBLE_PYTHON ?= $(shell \
	p=$$(command -v ansible-playbook 2>/dev/null); \
	if command -v mise >/dev/null 2>&1; then m=$$(mise which ansible-playbook 2>/dev/null); [ -n "$$m" ] && p=$$m; fi; \
	if [ -n "$$p" ]; then f=$$(readlink -f "$$p" 2>/dev/null); \
	  if [ -f "$$f" ] && head -c 2 "$$f" | grep -q '#!'; then head -1 "$$f" | sed -n 's|^#! *||; s| .*||p'; fi; fi)

# Public interface (documented by `make help`).
.PHONY: help install agent-setup vault-init host-init vault-edit vault-view \
        host-bootstrap lint info build deploy
# Internal helpers (not listed in help; not part of the public interface).
.PHONY: ensure-toolchain ensure-sshpass ensure-keychain ensure-collections \
        ensure-passlib keychain-fetch keychain-verify run-playbook \
        agent-load agent-check

help: ## Show targets and overridable variables
	@printf '\nUsage: make <target> [VAR=value ...]\n'
	@awk 'BEGIN {FS = ":.*?## "} \
		/^[a-zA-Z0-9_-]+:.*?## / { printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2 }' \
		$(MAKEFILE_LIST)
	@printf '\n\033[1mVariables (override on the command line)\033[0m\n'
	@printf '  \033[36m%-25s\033[0m %s\n' \
		'HOST'              'variant to operate on (inventory host / host_vars name, default: ib-main)' \
		'VAULT_FILE'        'operator vault path (edited by vault-edit; shown by vault-view)' \
		'MANAGED_VAULT_FILE' 'shared managed vault path (shown by vault-view)' \
		'EXTRA'             'extra Ansible args, e.g. -e openwrt_modules_adjust=["statistics"]'
	@printf '\n'

# ==============================================================================
# Dependencies: `install` is the ONLY dependency entry point
# ==============================================================================
# Every other target depends on `install` (directly, or through `run-playbook`),
# which ensures the toolchain, collections, sshpass, passlib and Keychain in one
# place. The `ensure-*` helpers below are internal and fail loudly.

install: ensure-toolchain ensure-sshpass ensure-keychain ensure-collections ensure-passlib ## Install the control-node toolchain, collections, sshpass, passlib, Keychain

agent-setup: install ## Append Keychain agent startup to ~/.bashrc (idempotent)
	@set -e; \
	rc="$$HOME/.bashrc"; \
	begin="# >>> openwrt-builder-wrapper keychain >>>"; \
	end="# <<< openwrt-builder-wrapper keychain <<<"; \
	touch "$$rc"; \
	if grep -qF "$$begin" "$$rc"; then \
		echo "agent-setup: block already present in $$rc"; exit 0; \
	fi; \
	{ \
		echo ""; \
		echo "$$begin"; \
		echo 'if command -v keychain >/dev/null 2>&1; then'; \
		echo '  eval "$$(keychain agent start --eval --quiet 2>/dev/null)"'; \
		echo 'fi'; \
		echo "$$end"; \
	} >> "$$rc"; \
	echo "agent-setup: appended Keychain block to $$rc (run: source $$rc)"

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

host-init: vault-init ## Scaffold inventory + host_vars/<HOST> from the example (vault encrypted)
	@test -n "$(HOST)" || { echo "ERROR: HOST is required, e.g. make host-init HOST=ib-main"; exit 1; }
	@[ -e $(INV) ] || { cp $(INV).example $(INV); echo "created $(INV)"; }
	@install -d -m 0700 inventory/host_vars/$(HOST)
	@[ -e inventory/host_vars/$(HOST)/main.yml ] || cp inventory/host_vars/example/main.yml inventory/host_vars/$(HOST)/main.yml
	@[ -e inventory/host_vars/$(HOST)/vault.yml ] || cp inventory/host_vars/example/vault.yml.example inventory/host_vars/$(HOST)/vault.yml
	@if ! grep -q 'ANSIBLE_VAULT' inventory/host_vars/$(HOST)/vault.yml; then \
		echo "encrypting inventory/host_vars/$(HOST)/vault.yml"; \
		ansible-vault encrypt inventory/host_vars/$(HOST)/vault.yml; \
	fi
	@chmod 0600 inventory/host_vars/$(HOST)/vault.yml
	@echo "scaffolded inventory/host_vars/$(HOST)/ (edit main.yml; make vault-edit HOST=$(HOST) for vault.yml)"

vault-edit: vault-init ## Edit a host vault (vi; encrypts a plaintext vault first) (HOST=<name> or VAULT_FILE=<path>)
	@test -f $(VAULT_FILE) || { echo "No such vault file: $(VAULT_FILE)" >&2; exit 1; }
	@if grep -q 'ANSIBLE_VAULT' $(VAULT_FILE); then :; else \
		echo "Encrypting plaintext $(VAULT_FILE) before editing..."; \
		ansible-vault encrypt $(VAULT_FILE); \
	fi
	ansible-vault edit $(VAULT_FILE)

vault-view: vault-init ## View the host vault + shared managed vault (HOST=<name>)
	@for p in $$(printf '%s\n' "$(VAULT_FILE)" "$(MANAGED_VAULT_FILE)" | awk '!seen[$$0]++'); do \
		printf '\n\033[1m== %s ==\033[0m\n' "$$p"; \
		if [ ! -f "$$p" ]; then echo "(missing)"; continue; fi; \
		if grep -q 'ANSIBLE_VAULT' "$$p"; then \
			ansible-vault view "$$p" 2>/dev/null \
				|| { printf '%s\n' "$(VAULT_PASSWORD_HINT)" >&2; exit 1; }; \
		else cat "$$p"; fi; \
	done

host-bootstrap: ## Probe/provision the build host (ansible account, keys, sudo)
	@test -f $(INV) || { \
		echo "ERROR: $(INV) not found — copy $(INV).example and fill it in."; exit 1; }
	@$(MAKE) --no-print-directory run-playbook PLAYBOOK=playbooks/bootstrap.yml

lint: install vault-init ## Syntax check + ansible-lint
	@for p in playbooks/*.yml; do \
		$(ANS_PLAY) --syntax-check -i $(INV) "$$p" || exit 1; \
	done
	@if command -v ansible-lint >/dev/null 2>&1; then \
		ansible-lint -c .ansible-lint .; \
	else \
		echo "WARN: ansible-lint not installed, skipped"; \
	fi

info: ## Query ImageBuilder image/profile info (no build)
	@test -f $(INV) || { \
		echo "ERROR: $(INV) not found — copy $(INV).example and fill it in."; exit 1; }
	@$(MAKE) --no-print-directory run-playbook PLAYBOOK=playbooks/info.yml

build: ## Build a customized OpenWrt firmware image (run host-bootstrap first)
	@test -f $(INV) || { \
		echo "ERROR: $(INV) not found — copy $(INV).example and fill it in."; exit 1; }
	@$(MAKE) --no-print-directory run-playbook PLAYBOOK=playbooks/build.yml

deploy: host-bootstrap build ## One-click: bootstrap the build host, then build every variant

# ==============================================================================
# Internal helpers (not part of the public interface)
# ==============================================================================

# (internal) Start/reuse the Keychain ssh-agent and load the vault keys. Only
# used as an explicit convenience; `run-playbook` performs the same fallback
# automatically when OpenSSH refuses a key file's permissions.
agent-load: install vault-init
	@$(KEYCHAIN_AGENT); \
	$(ANS_PLAY) playbooks/ssh_agent_load.yml

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
	if [ -f "$(KEYCHAIN_ASSET)" ]; then exit 0; fi; \
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
keychain-verify: keychain-fetch
	@set -e; \
	printf '%s  %s\n' "$(KEYCHAIN_SHA256)" "$(KEYCHAIN_ASSET)" | sha256sum -c - >/dev/null \
		|| { echo "ERROR: keychain asset checksum mismatch: $(KEYCHAIN_ASSET)" >&2; \
		     echo "  Remove it and re-run, or download it manually from $(KEYCHAIN_URL)." >&2; \
		     exit 1; }; \
	echo "keychain pin OK: v$(KEYCHAIN_VERSION)"

# (internal) Ensure the pinned Keychain is installed (used only as a fallback).
ensure-keychain: keychain-verify
	@set -e; \
	if [ -f "$(KEYCHAIN_BIN)" ] \
	   && printf '%s  %s\n' "$(KEYCHAIN_SHA256)" "$(KEYCHAIN_BIN)" | sha256sum -c - >/dev/null 2>&1; then \
		echo "keychain: v$(KEYCHAIN_VERSION) ($(KEYCHAIN_BIN))"; \
	else \
		mkdir -p "$$(dirname "$(KEYCHAIN_BIN)")"; \
		install -m 0755 "$(KEYCHAIN_ASSET)" "$(KEYCHAIN_BIN)"; \
		echo "keychain installed: $(KEYCHAIN_BIN) (v$(KEYCHAIN_VERSION))"; \
	fi

# (internal) Run a playbook. Keychain is a FALLBACK: when OpenSSH refuses a
# private key because its file permissions cannot be fixed (e.g. 0777 on the WSL
# /mnt/c mount), start the Keychain agent and load the vault keys in THIS shell,
# then retry once. Correctly permissioned keys (and password auth) connect
# directly, with no agent.
run-playbook: install vault-init
	@set -o pipefail; \
	log=$$(mktemp); trap 'rm -f "$$log"' EXIT; \
	$(ANS_PLAY) -i $(INV) $(PLAYBOOK) $(EXTRA) 2>&1 | tee "$$log"; \
	rc=$${PIPESTATUS[0]}; \
	if [ $$rc -eq 0 ]; then exit 0; fi; \
	if grep -qiE 'UNPROTECTED PRIVATE KEY FILE|are too open|bad permissions|Permissions [0-9]+ for' "$$log"; then \
		echo "NOTE: SSH refused a private key due to file permissions — starting Keychain and retrying once..."; \
		$(KEYCHAIN_AGENT); \
		$(ANS_PLAY) playbooks/ssh_agent_load.yml; \
		$(ANS_PLAY) -i $(INV) $(PLAYBOOK) $(EXTRA); \
	else \
		exit $$rc; \
	fi
