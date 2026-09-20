SHELL := /bin/bash
.DEFAULT_GOAL := help

ANS_DIR  := ansible
ANS_PLAY := ansible-playbook
INV      := $(ANS_DIR)/inventory/hosts.yml

# Extra Ansible vars appended to every playbook invocation, e.g.
#   make build ANS_EXTRA='-e openwrt_modules_adjust=["statistics"]'
ANS_EXTRA ?=

# Vault password file (kept OUTSIDE the repo, like the state/secrets). Exported
# only when it exists: ansible-core fails when a configured vault password file
# is missing, which would break lint/CI on a fresh clone.
ANSIBLE_VAULT_PASSWORD := $(HOME)/.config/projects/openwrt-builder-wrapper/ansible_vault_password
# Host-scoped vault (single build host): override with HOST=<name> or FILE=<path>.
ANS_HOST   ?= openwrt-ib-prod-1
VAULT_FILE ?= $(ANS_DIR)/inventory/host_vars/$(ANS_HOST)/vault.yml

# sshpass is a control-node prerequisite (connection probe). When passwordless
# sudo is unavailable, fall back to a rootless install into ~/.local/bin.
SSHPASS_BIN ?= $(HOME)/.local/bin/sshpass

export ANSIBLE_CONFIG := $(ANS_DIR)/ansible.cfg
ifneq ($(wildcard $(ANSIBLE_VAULT_PASSWORD)),)
export ANSIBLE_VAULT_PASSWORD_FILE := $(ANSIBLE_VAULT_PASSWORD)
endif

# Interpreter that runs ansible-playbook: the community.docker modules need the
# `docker` Python SDK importable by it. Resolve the mise tool path first.
ANSIBLE_PYTHON ?= $(shell \
	p=$$(command -v ansible-playbook 2>/dev/null); \
	if command -v mise >/dev/null 2>&1; then m=$$(mise which ansible-playbook 2>/dev/null); [ -n "$$m" ] && p=$$m; fi; \
	if [ -n "$$p" ]; then f=$$(readlink -f "$$p" 2>/dev/null); \
	  if [ -f "$$f" ] && head -c 2 "$$f" | grep -q '#!'; then head -1 "$$f" | sed -n 's|^#! *||; s| .*||p'; fi; fi)

.PHONY: help check-deps check-ansible-collections install-sshpass-local \
        install-passlib-local ans-deps ans-lint build info \
        ans-vault-init ans-vault-encrypt ans-vault-edit ans-vault-view clean

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

# -------------------------------------------------------------- Ansible ----

check-deps: ## Ensure control-node prerequisites (python3 + openssl + sshpass + passlib + docker SDK)
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

install-sshpass-local: ## (internal) install sshpass into ~/.local without root
	@set -e; \
	tmp=$$(mktemp -d); \
	trap 'rm -rf "$$tmp"' EXIT; \
	cd "$$tmp"; \
	apt-get download sshpass >/dev/null 2>&1; \
	dpkg-deb -x sshpass_*.deb root; \
	mkdir -p "$(dir $(SSHPASS_BIN))"; \
	install -m 0755 root/usr/bin/sshpass "$(SSHPASS_BIN)"; \
	echo "sshpass installed: $(SSHPASS_BIN)"

install-passlib-local: ## (internal) install python3-passlib without root (into PY, else python3)
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

check-ansible-collections: ## Ensure required Ansible collections are installed (only if missing)
	@cols="$$(ansible-galaxy collection list 2>/dev/null)"; \
	if printf '%s\n' "$$cols" | grep -qE '^community\.docker[[:space:]]'; then \
		echo "ansible collections: present"; \
	else \
		echo "ansible collections: missing — installing"; \
		ansible-galaxy collection install -r $(ANS_DIR)/requirements.yml -p $(ANS_DIR)/collections; \
	fi

ans-deps: check-deps check-ansible-collections ## Install control-node prerequisites + collections

ans-lint: ans-deps ## Syntax check + ansible-lint
	@for p in $(ANS_DIR)/playbooks/*.yml; do \
		$(ANS_PLAY) --syntax-check -i $(INV) "$$p" || exit 1; \
	done
	@if command -v ansible-lint >/dev/null 2>&1; then \
		ansible-lint -c $(ANS_DIR)/.ansible-lint $(ANS_DIR); \
	else \
		echo "WARN: ansible-lint not installed, skipped"; \
	fi

build: check-ansible-collections ## Build a customized OpenWrt firmware image (ImageBuilder container)
	@test -f $(INV) || { \
		echo "ERROR: $(INV) not found — copy $(INV).example and fill it in."; exit 1; }
	$(ANS_PLAY) -i $(INV) $(ANS_DIR)/playbooks/build.yml $(ANS_EXTRA)

info: check-ansible-collections ## Query ImageBuilder image/profile info (no build)
	@test -f $(INV) || { \
		echo "ERROR: $(INV) not found — copy $(INV).example and fill it in."; exit 1; }
	$(ANS_PLAY) -i $(INV) $(ANS_DIR)/playbooks/info.yml $(ANS_EXTRA)

# ------------------------------------------------------------- Vault ----

ans-vault-init: ## One-time: generate vault password (idempotent)
	@mkdir -p $(dir $(ANSIBLE_VAULT_PASSWORD))
	@if [ ! -s $(ANSIBLE_VAULT_PASSWORD) ]; then \
		openssl rand -base64 32 > $(ANSIBLE_VAULT_PASSWORD); \
		chmod 600 $(ANSIBLE_VAULT_PASSWORD); \
		echo "vault password generated: $(ANSIBLE_VAULT_PASSWORD) (BACK IT UP in a password manager)"; \
	else \
		echo "vault password exists: $(ANSIBLE_VAULT_PASSWORD)"; \
	fi
	@test "$$(wc -c < $(ANSIBLE_VAULT_PASSWORD))" -ge 44 || { echo "ERROR: vault password too weak"; exit 1; }

ans-vault-encrypt: ## Encrypt a plaintext host vault in place; HOST=<name> or FILE=<path>
	@test -s $(ANSIBLE_VAULT_PASSWORD) || { echo "ERROR: run 'make ans-vault-init' first"; exit 1; }
	@test -f $(VAULT_FILE) || { echo "ERROR: $(VAULT_FILE) not found"; exit 1; }
	ANSIBLE_VAULT_PASSWORD_FILE=$(ANSIBLE_VAULT_PASSWORD) ansible-vault encrypt $(VAULT_FILE)

ans-vault-edit: ## Edit a host vault (vi); HOST=<name> or FILE=<path> (encrypts a plaintext vault first)
	@test -s $(ANSIBLE_VAULT_PASSWORD) || { echo "ERROR: run 'make ans-vault-init' first"; exit 1; }
	@test -f $(VAULT_FILE) || { echo "ERROR: $(VAULT_FILE) not found"; exit 1; }
	@if ! head -c 16 $(VAULT_FILE) | grep -q '$$ANSIBLE_VAULT'; then \
		echo "vault is plaintext — encrypting $(VAULT_FILE) first"; \
		ANSIBLE_VAULT_PASSWORD_FILE=$(ANSIBLE_VAULT_PASSWORD) ansible-vault encrypt $(VAULT_FILE); \
	fi
	ANSIBLE_VAULT_PASSWORD_FILE=$(ANSIBLE_VAULT_PASSWORD) ansible-vault edit $(VAULT_FILE)

ans-vault-view: ## View a host vault (read-only); HOST=<name> or FILE=<path>
	@test -s $(ANSIBLE_VAULT_PASSWORD) || { echo "ERROR: run 'make ans-vault-init' first"; exit 1; }
	ANSIBLE_VAULT_PASSWORD_FILE=$(ANSIBLE_VAULT_PASSWORD) ansible-vault view $(VAULT_FILE)

# ------------------------------------------------------------ Pipeline ----

clean: ## Remove caches and collections (does NOT touch fetched artifacts)
	rm -rf $(ANS_DIR)/.cache $(ANS_DIR)/collections $(ANS_DIR)/.ansible
