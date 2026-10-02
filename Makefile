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
ANSIBLE_VAULT_PASSWORD := $(HOME)/.config/projects/openwrt-builder-wrapper/ansible_vault_password
# Per-variant vault: override with VARIANT=<name> or VAULT_FILE=<path>.
# (The shared connection vault lives in group_vars/builder/; target it with
# VAULT_FILE=inventory/group_vars/builder/vault.yml.)
VARIANT    ?= ib-main
VAULT_FILE ?= inventory/host_vars/$(VARIANT)/vault.yml

# sshpass is a control-node prerequisite (`make host-bootstrap` password SSH).
# When passwordless sudo is unavailable, fall back to a rootless install into
# ~/.local/bin.
SSHPASS_BIN ?= $(HOME)/.local/bin/sshpass

# Keychain 3 (pinned, single zipapp) provides a long-running ssh-agent so
# private keys whose permissions cannot be fixed (e.g. on the WSL /mnt/c mount)
# can still be loaded via stdin (`ssh-add - < key`), which reads the key content
# directly and skips the permission check.
KEYCHAIN_PIN     := $(CURDIR)/keychain.pin
KEYCHAIN_VERSION := $(shell awk '!/^#/ && NF {print $$1; exit}' $(KEYCHAIN_PIN))
KEYCHAIN_SHA256  := $(shell awk '!/^#/ && NF {print $$2; exit}' $(KEYCHAIN_PIN) | sed 's/^sha256://')
KEYCHAIN_URL     ?= https://github.com/danielrobbins/keychain/releases/download/$(KEYCHAIN_VERSION)/keychain-$(KEYCHAIN_VERSION).pyz
KEYCHAIN_BIN     ?= $(HOME)/.local/bin/keychain
KEYCHAIN_CACHE   ?= $(HOME)/.cache/openwrt-builder-wrapper
KEYCHAIN_ASSET   := $(KEYCHAIN_CACHE)/keychain-$(KEYCHAIN_VERSION).pyz
KEYCHAIN_PYZ     ?=
# Start (or reuse) the Keychain agent in the CURRENT shell; --eval prints the
# SSH_AUTH_SOCK / SSH_AGENT_PID exports on stdout (banner goes to stderr).
KEYCHAIN_AGENT   := eval "$$($(KEYCHAIN_BIN) agent start --eval --quiet 2>/dev/null)"

export ANSIBLE_CONFIG := ansible.cfg

# Interpreter that runs ansible-playbook: the community.docker modules need the
# `docker` Python SDK importable by it. Resolve the mise tool path first.
ANSIBLE_PYTHON ?= $(shell \
	p=$$(command -v ansible-playbook 2>/dev/null); \
	if command -v mise >/dev/null 2>&1; then m=$$(mise which ansible-playbook 2>/dev/null); [ -n "$$m" ] && p=$$m; fi; \
	if [ -n "$$p" ]; then f=$$(readlink -f "$$p" 2>/dev/null); \
	  if [ -f "$$f" ] && head -c 2 "$$f" | grep -q '#!'; then head -1 "$$f" | sed -n 's|^#! *||; s| .*||p'; fi; fi)

.PHONY: help check-deps check-collections install-sshpass-local \
        install-passlib-local install lint host-init host-bootstrap build info \
        vault-init vault-encrypt vault-edit vault-view \
        keychain-fetch keychain-verify keychain-check agent-setup \
        agent-load agent-check clean

##@ General

help: ## Show grouped targets and overridable variables
	@printf '\nUsage: make <target> [VAR=value ...]\n'
	@awk 'BEGIN {FS = ":.*?## "} \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5); next } \
		/^[a-zA-Z0-9_-]+:.*?## / { printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2 }' \
		$(MAKEFILE_LIST)
	@printf '\n\033[1mVariables (override on the command line)\033[0m\n'
	@printf '  \033[36m%-25s\033[0m %s\n' \
		'HOST'        'variant to scaffold with host-init (e.g. HOST=ib-main)' \
		'VARIANT'     'variant whose vault vault-* operates on (default: ib-main)' \
		'VAULT_FILE'  'explicit vault path for vault-* (overrides VARIANT)' \
		'EXTRA'       'extra Ansible args, e.g. -e openwrt_modules_adjust=["statistics"]' \
		'KEYCHAIN_PYZ'   'path to a local Keychain asset (offline install, skips download)' \
		'KEYCHAIN_BIN'   'Keychain install path (default: ~/.local/bin/keychain)' \
		'KEYCHAIN_CACHE' 'Keychain download cache (default: ~/.cache/openwrt-builder-wrapper)' \
		'KEYCHAIN_URL'   'Keychain download URL override' \
		'SSHPASS_BIN' 'rootless sshpass install path (default: ~/.local/bin/sshpass)'
	@printf '\n'

##@ Vault

vault-init: ## One-time: generate vault password (idempotent)
	@mkdir -p $(dir $(ANSIBLE_VAULT_PASSWORD))
	@if [ ! -s $(ANSIBLE_VAULT_PASSWORD) ]; then \
		openssl rand -base64 32 > $(ANSIBLE_VAULT_PASSWORD); \
		chmod 600 $(ANSIBLE_VAULT_PASSWORD); \
		echo "vault password generated: $(ANSIBLE_VAULT_PASSWORD) (BACK IT UP in a password manager)"; \
	else \
		echo "vault password exists: $(ANSIBLE_VAULT_PASSWORD)"; \
	fi
	@test "$$(wc -c < $(ANSIBLE_VAULT_PASSWORD))" -ge 44 || { echo "ERROR: vault password too weak"; exit 1; }

vault-encrypt: ## Encrypt a plaintext host vault in place (VARIANT=<name> or VAULT_FILE=<path>)
	@test -s $(ANSIBLE_VAULT_PASSWORD) || { echo "ERROR: run 'make vault-init' first"; exit 1; }
	@test -f $(VAULT_FILE) || { echo "ERROR: $(VAULT_FILE) not found"; exit 1; }
	ansible-vault encrypt $(VAULT_FILE)

vault-edit: ## Edit a host vault (vi; encrypts a plaintext vault first) (VARIANT=<name> or VAULT_FILE=<path>)
	@test -s $(ANSIBLE_VAULT_PASSWORD) || { echo "ERROR: run 'make vault-init' first"; exit 1; }
	@test -f $(VAULT_FILE) || { echo "ERROR: $(VAULT_FILE) not found"; exit 1; }
	@if ! head -c 16 $(VAULT_FILE) | grep -q '$$ANSIBLE_VAULT'; then \
		echo "vault is plaintext — encrypting $(VAULT_FILE) first"; \
		ansible-vault encrypt $(VAULT_FILE); \
	fi
	ansible-vault edit $(VAULT_FILE)

vault-view: ## View a host vault (read-only) (VARIANT=<name> or VAULT_FILE=<path>)
	@test -s $(ANSIBLE_VAULT_PASSWORD) || { echo "ERROR: run 'make vault-init' first"; exit 1; }
	ansible-vault view $(VAULT_FILE)

##@ Setup

# Ensure control-node prerequisites (python3 + openssl + sshpass + passlib + docker SDK). Internal.
check-deps:
	@command -v python3 >/dev/null 2>&1 || { \
		echo "ERROR: python3 not found on the control node."; exit 1; }
	@python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 8) else 1)' \
		|| { echo "ERROR: python3 >= 3.8 required; found $$(python3 --version 2>&1)."; exit 1; }
	@if command -v openssl >/dev/null 2>&1; then \
		echo "openssl: $$(command -v openssl)"; \
	else \
		echo "ERROR: openssl is required (secret generation). Install it."; exit 1; \
	fi
	@if command -v sshpass >/dev/null 2>&1; then \
		echo "sshpass: $$(command -v sshpass)"; \
	elif [ -x "$(SSHPASS_BIN)" ]; then \
		echo "sshpass: $(SSHPASS_BIN)"; \
	elif sudo -n true >/dev/null 2>&1; then \
		echo "sshpass not found — installing via sudo apt-get..."; \
		sudo -n apt-get install -y sshpass; \
	else \
		echo "sshpass not found and no passwordless sudo — installing rootless to ~/.local..."; \
		$(MAKE) install-sshpass-local; \
	fi
	@py="$(ANSIBLE_PYTHON)"; [ -n "$$py" ] || py=$$(command -v python3); \
	if "$$py" -c 'import passlib' >/dev/null 2>&1; then \
		echo "passlib: present ($$py)"; \
	elif "$$py" -m pip install --quiet passlib >/dev/null 2>&1; then \
		echo "passlib: installed with pip ($$py)"; \
	else \
		echo "passlib: pip unavailable for $$py — using rootless deb fallback..."; \
		$(MAKE) install-passlib-local PY="$$py"; \
	fi
	@py="$(ANSIBLE_PYTHON)"; [ -n "$$py" ] || py=$$(command -v python3); \
	if "$$py" -c 'import docker' >/dev/null 2>&1; then \
		echo "docker python SDK: present ($$py)"; \
	elif "$$py" -m pip install --quiet docker >/dev/null 2>&1; then \
		echo "docker python SDK: installed with pip ($$py)"; \
	else \
		echo "NOTE: the 'docker' Python SDK is only needed when the build host is"; \
		echo "  the control node (localhost). Install it on the BUILD HOST if not."; \
	fi

# Install sshpass into ~/.local without root. Internal.
install-sshpass-local:
	@set -e; \
	if ! command -v apt-get >/dev/null 2>&1 || ! command -v dpkg-deb >/dev/null 2>&1; then \
		echo "ERROR: cannot auto-install sshpass (apt-get/dpkg-deb not found on the control node)." >&2; \
		echo "  Install sshpass manually, or use key-only bootstrap credentials (vault_host_ansible_ssh_pubkey_file / _ssh_privkey_file)." >&2; \
		exit 1; \
	fi; \
	tmp=$$(mktemp -d); \
	trap 'rm -rf "$$tmp"' EXIT; \
	cd "$$tmp"; \
	apt-get download sshpass >/dev/null 2>&1; \
	dpkg-deb -x sshpass_*.deb root; \
	mkdir -p "$(dir $(SSHPASS_BIN))"; \
	install -m 0755 root/usr/bin/sshpass "$(SSHPASS_BIN)"; \
	echo "sshpass installed: $(SSHPASS_BIN)"

# Install python3-passlib without root (into PY, else python3). Internal.
install-passlib-local:
	@set -e; \
	py="$(PY)"; [ -n "$$py" ] || py=python3; \
	dest=$$("$$py" -c "import sys,site; print(site.getsitepackages()[0] if sys.prefix != sys.base_prefix else site.getusersitepackages())"); \
	tmp=$$(mktemp -d); \
	trap 'rm -rf "$$tmp"' EXIT; \
	cd "$$tmp"; \
	apt-get download python3-passlib >/dev/null 2>&1; \
	dpkg-deb -x python3-passlib_*.deb root; \
	mkdir -p "$$dest"; \
	cp -a root/usr/lib/python3/dist-packages/passlib "$$dest/"; \
	echo "passlib installed: $$dest/passlib"

# Ensure required Ansible collections are installed (only if missing). Internal.
check-collections:
	@cols="$$(ansible-galaxy collection list 2>/dev/null)"; \
	if printf '%s\n' "$$cols" | grep -qE '^community\.docker[[:space:]]'; then \
		echo "ansible collections: present"; \
	else \
		echo "ansible collections: missing — installing"; \
		ansible-galaxy collection install -r requirements.yml -p collections; \
	fi

install: check-deps check-collections ## Install control-node prerequisites + collections

##@ Keychain (SSH agent)

# Download the pinned Keychain asset into the cache. Internal.
keychain-fetch:
	@set -e; \
	mkdir -p "$(KEYCHAIN_CACHE)"; \
	if [ -n "$(KEYCHAIN_PYZ)" ] || [ -f "$(KEYCHAIN_ASSET)" ]; then exit 0; fi; \
	echo "downloading keychain $(KEYCHAIN_VERSION)..."; \
	curl -fsSL -o "$(KEYCHAIN_ASSET).tmp" "$(KEYCHAIN_URL)"; \
	mv "$(KEYCHAIN_ASSET).tmp" "$(KEYCHAIN_ASSET)"

keychain-verify: keychain-fetch ## Verify the pinned Keychain asset SHA256 (no install)
	@set -e; \
	src="$(if $(KEYCHAIN_PYZ),$(KEYCHAIN_PYZ),$(KEYCHAIN_ASSET))"; \
	printf '%s  %s\n' "$(KEYCHAIN_SHA256)" "$$src" | sha256sum -c -; \
	echo "keychain pin OK: v$(KEYCHAIN_VERSION)"

keychain-check: keychain-fetch ## Ensure Keychain 3 (pinned) is installed (auto-download + SHA256)
	@set -e; \
	if [ -f "$(KEYCHAIN_BIN)" ] \
	   && printf '%s  %s\n' "$(KEYCHAIN_SHA256)" "$(KEYCHAIN_BIN)" | sha256sum -c - >/dev/null 2>&1; then \
		echo "keychain: v$(KEYCHAIN_VERSION) ($(KEYCHAIN_BIN))"; exit 0; \
	fi; \
	src="$(if $(KEYCHAIN_PYZ),$(KEYCHAIN_PYZ),$(KEYCHAIN_ASSET))"; \
	printf '%s  %s\n' "$(KEYCHAIN_SHA256)" "$$src" | sha256sum -c -; \
	mkdir -p "$$(dirname "$(KEYCHAIN_BIN)")"; \
	install -m 0755 "$$src" "$(KEYCHAIN_BIN)"; \
	echo "keychain installed: $(KEYCHAIN_BIN) (v$(KEYCHAIN_VERSION))"

agent-setup: keychain-check ## Append Keychain agent startup to ~/.bashrc (idempotent)
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

agent-load: vault-init keychain-check ## Load the vault connection keys into the Keychain ssh-agent
	@$(KEYCHAIN_AGENT); \
	ansible-playbook playbooks/ssh_agent_load.yml

agent-check: keychain-check ## Ensure the Keychain agent has identities loaded
	@$(KEYCHAIN_AGENT); \
	if ssh-add -l >/dev/null 2>&1; then \
		echo "ssh-agent: identities loaded"; \
	else \
		echo "ERROR: the Keychain ssh-agent has no identities loaded."; \
		echo "Load the connection keys with: make agent-load"; \
		exit 1; \
	fi

##@ Quality

lint: install vault-init ## Syntax check + ansible-lint
	@for p in playbooks/*.yml; do \
		$(ANS_PLAY) --syntax-check -i $(INV) "$$p" || exit 1; \
	done
	@if command -v ansible-lint >/dev/null 2>&1; then \
		ansible-lint -c .ansible-lint .; \
	else \
		echo "WARN: ansible-lint not installed, skipped"; \
	fi

##@ Host & Build

host-init: ## Scaffold inventory + host_vars/<HOST> from the example (HOST=<name>)
	@test -n "$(HOST)" || { echo "ERROR: HOST is required, e.g. make host-init HOST=ib-main"; exit 1; }
	@test -f $(INV) || { cp $(INV).example $(INV); echo "created $(INV)"; }
	@mkdir -p inventory/host_vars/$(HOST)
	@cp -n inventory/host_vars/example/main.yml inventory/host_vars/$(HOST)/main.yml || true
	@cp -n inventory/host_vars/example/vault.yml.example inventory/host_vars/$(HOST)/vault.yml || true
	@echo "scaffolded inventory/host_vars/$(HOST)/ (edit main.yml + vault.yml, then: make vault-edit VARIANT=$(HOST))"

host-bootstrap: check-deps check-collections vault-init agent-load ## Probe/provision the build host (ansible account, keys, sudo)
	@test -f $(INV) || { \
		echo "ERROR: $(INV) not found — copy $(INV).example and fill it in."; exit 1; }
	@$(KEYCHAIN_AGENT); \
	$(ANS_PLAY) -i $(INV) playbooks/bootstrap.yml $(EXTRA)

build: check-collections vault-init agent-load ## Build a customized OpenWrt firmware image (ImageBuilder container; run host-bootstrap first)
	@test -f $(INV) || { \
		echo "ERROR: $(INV) not found — copy $(INV).example and fill it in."; exit 1; }
	@$(KEYCHAIN_AGENT); \
	$(ANS_PLAY) -i $(INV) playbooks/build.yml $(EXTRA)

info: check-collections vault-init agent-load ## Query ImageBuilder image/profile info (no build)
	@test -f $(INV) || { \
		echo "ERROR: $(INV) not found — copy $(INV).example and fill it in."; exit 1; }
	@$(KEYCHAIN_AGENT); \
	$(ANS_PLAY) -i $(INV) playbooks/info.yml $(EXTRA)

##@ Housekeeping

clean: ## Remove caches and collections (does NOT touch fetched artifacts)
	rm -rf .cache collections .ansible
