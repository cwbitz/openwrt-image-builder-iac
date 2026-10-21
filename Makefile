SHELL := /bin/bash
.DEFAULT_GOAL := help

ANS_PLAY := ansible-playbook
INV      := inventory/hosts.yml

# Extra Ansible args appended to every playbook invocation, e.g.
#   make build EXTRA='-e modules_adjust=["statistics"]'
EXTRA ?=

# Ansible Vault password file, kept OUTSIDE the repo and exported under Ansible's
# own env-var name so every ansible-* invocation picks it up. ansible-core 2.19
# hard-fails when it is missing, so the ansible-running targets depend on
# `vault-init` (which generates it) and CI generates a throwaway one.
export ANSIBLE_VAULT_PASSWORD_FILE := $(HOME)/.config/projects/openwrt-image-builder-iac/ansible_vault_password
# HOST names the build machine (its inventory host / host_vars dir). `host-init`
# scaffolds it; `vault-edit` edits its vault; `vault-edit-group` edits the shared
# builder connection vault; `vault-view` iterates every machine vault plus the
# shared connection vault.
HOST              ?= openwrt-ib-prod-1

# Management address for the builder host, written once as the `builder` group
# variable (all variants share it). It is set only when the variable is unset or
# still a placeholder; an omitted value leaves an existing address untouched, and
# a disagreeing value is refused (FORCE_IP=1 is the deliberate override).
HOST_IP           ?=

# Operator knobs for the scaffolding target. They are command-line inputs: a
# value inherited from the environment is called out, because make lets an
# environment variable win over the file default silently.
$(foreach v,HOST HOST_IP,$(if $(filter environment,$(origin $(v))),$(warning $(v) is inherited from the environment; pass $(v)=... explicitly if unintended)))

# QUIET=1 silences the internal dependency helpers (ensure-* / keychain-* /
# ssh-agent) so a target's own output is not buried under their chatter. Set only
# by the `info` target.
QUIET ?=
# `$(say) "text"` echoes normally, or is a no-op when QUIET is set.
say = $(if $(QUIET),:,echo)

# Refresh SSH host keys before connecting (REFRESH=1). Useful after the build
# host is rebuilt: its new host key would otherwise fail the "host key changed"
# check. hostkey-init scans every inventory host and (re)writes its key into
# the control node's known_hosts. deploy/host-bootstrap call it when set.
REFRESH ?=
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
# it can be installed, but it starts only when OpenSSH refuses a private key
# whose file permissions cannot be fixed (e.g. the WSL /mnt/c mount). The asset
# URL is a fixed constant; a failed download is fatal (fetch it manually).
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
# The generic scripts/run-with-ssh-agent.sh is driven by the SSH_AGENT_*
# environment variables below. The agent is prepared only when a configured key
# has permissions OpenSSH would refuse (e.g. WSL /mnt/c), and the runner retries
# once on a refused-key failure.
SSH_AGENT_ENV   ?= $(HOME)/.cache/iac/ssh-agent.env
SSH_AGENT_RUN   ?= $(CURDIR)/scripts/run-with-ssh-agent.sh
# Hostvars holding the control-node private-key paths.
SSH_AGENT_KEY_VARS ?= host_ansible_ssh_privkey_file host_admin_ssh_privkey_file host_root_ssh_privkey_file
export SSH_AGENT_ENV
export SSH_AGENT_KEYCHAIN_BIN  := $(KEYCHAIN_BIN)
export SSH_AGENT_ANS_PLAY      := $(ANS_PLAY)
export SSH_AGENT_INVENTORY     := $(INV)
export SSH_AGENT_LOAD_PLAYBOOK := playbooks/ssh_agent_load.yml

# Probe: exit 0 when a configured private key has unsafe permissions
# (group/other bits set, e.g. 0777), i.e. OpenSSH would refuse it.
SSH_AGENT_PROBE := ansible-inventory -i $(INV) --list 2>/dev/null | SSH_AGENT_KEY_VARS="$(SSH_AGENT_KEY_VARS)" python3 -c "import json,os,sys; names=os.environ['SSH_AGENT_KEY_VARS'].split(); vs=json.load(sys.stdin).get('_meta',{}).get('hostvars',{}); ks={os.path.expanduser(h.get(v)) for h in vs.values() for v in names if h.get(v)}; sys.exit(0 if any(os.path.isfile(k) and (os.stat(k).st_mode & 0o077) for k in ks) else 1)"

# Canned recipe: prepare the Keychain ssh-agent. Reuse a loaded agent;
# otherwise start Keychain and load the configured keys. SSH_AGENT_FORCE=1 skips
# the permission probe. Writes SSH_AGENT_ENV for the runner to source.
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

# ==============================================================================
# Dependencies: `install` is the ONLY dependency entry point
# ==============================================================================
# Every other target depends on `install` (directly, or through `run-playbook`),
# which ensures the toolchain, collections, sshpass, passlib and Keychain in one
# place. The `ensure-*` helpers below are internal and fail loudly.

install: ensure-toolchain ensure-sshpass ensure-keychain ensure-ansible-collections ensure-passlib ## Install the pinned toolchain, collections, and control-node dependencies

host-init: vault-init ## Scaffold inventory + host_vars/<HOST> from the examples (comment-free); HOST default openwrt-ib-prod-1, HOST_IP default CHANGE_ME_HOST_IP
	@[ -e $(INV) ] || { python3 $(CURDIR)/scripts/render_clean_template.py $(INV).example $(INV); echo "created $(INV) (comments stripped)"; }
	@[ -e inventory/group_vars/builder/main.yml ] || { python3 $(CURDIR)/scripts/render_clean_template.py inventory/group_vars/builder/main.yml.example inventory/group_vars/builder/main.yml; echo "created inventory/group_vars/builder/main.yml (comments stripped)"; }
	@install -d -m 0700 inventory/host_vars/$(HOST)
	@[ -e inventory/host_vars/$(HOST)/main.yml ] || python3 $(CURDIR)/scripts/render_clean_template.py inventory/host_vars/example/main.yml inventory/host_vars/$(HOST)/main.yml
	@[ -e inventory/host_vars/$(HOST)/vault.yml ] || python3 $(CURDIR)/scripts/render_clean_template.py inventory/host_vars/example/vault.yml.example inventory/host_vars/$(HOST)/vault.yml
	@if ! grep -q 'ANSIBLE_VAULT' inventory/host_vars/$(HOST)/vault.yml; then \
		echo "encrypting inventory/host_vars/$(HOST)/vault.yml"; \
		ansible-vault encrypt inventory/host_vars/$(HOST)/vault.yml; \
	fi
	@chmod 0600 inventory/host_vars/$(HOST)/vault.yml
	@python3 $(CURDIR)/scripts/ensure_inventory_host.py $(INV) "$(HOST)" --group builder --ansible-host "$(HOST_IP)" $(if $(FORCE_IP),--force)
	@echo "scaffolded inventory/host_vars/$(HOST)/ (machine registered under the builder group; edit build_variants[] in main.yml)"
	@echo "next: make vault-edit HOST=$(HOST)"

host-bootstrap: ## Create the ansible service account (bootstrap.yml; EXTRA=<extra -e vars>; REFRESH=1 refreshes host keys first)
	@test -f $(INV) || { \
		echo "ERROR: $(INV) not found — copy $(INV).example and fill it in."; exit 1; }
	@if [ -n "$(REFRESH)" ]; then $(MAKE) --no-print-directory hostkey-init; fi
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
	@$(MAKE) --no-print-directory vault-edit-file VAULT_EDIT_FILE=inventory/group_vars/builder/vault.yml

# (internal) Encrypt a plaintext vault in place, edit it, then re-sort its
# top-level keys alphabetically. Key order carries no meaning, but one
# deterministic layout keeps every rewrite reviewable; the sort is a
# comment-preserving line permutation and leaves the file untouched when it
# cannot verify the round-trip.
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
lint: install vault-init validate-knobs
	@for p in playbooks/*.yml; do \
		$(ANS_PLAY) --syntax-check -i $(INV) "$$p" || exit 1; \
	done
	@if command -v ansible-lint >/dev/null 2>&1; then \
		ansible-lint -c .ansible-lint .; \
	else \
		echo "WARN: ansible-lint not installed, skipped"; \
	fi
	# The operator templates are what `host-init` scaffolds: audit them against
	# the knobs the roles read (stdlib-only, so a plain python3 runs it).
	@python3 scripts/audit_example_knobs.py

# Refresh every managed host's SSH host key in the control node's known_hosts
# (removing any stale entry first). Also run automatically when REFRESH=1 is set
# on deploy / host-bootstrap.
.PHONY: hostkey-init
hostkey-init: vault-init ## Refresh every managed host's SSH host key in known_hosts
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
	@if [ -n "$(REFRESH)" ]; then $(MAKE) --no-print-directory hostkey-init; fi

# ==============================================================================
# Internal helpers (not part of the public interface)
# ==============================================================================

# (internal) Diagnostic probe: exit 0 when a configured private key would be
# refused by OpenSSH.
agent-needed: vault-init
	@$(SSH_AGENT_PROBE)

# (internal) Prepare the Keychain ssh-agent, probe-gated (Ansible targets).
agent-fallback: ensure-keychain
	$(SSH_AGENT_PREPARE)

# (internal) Prepare the Keychain ssh-agent unconditionally (the
# SSH_AGENT_FORCE=1 variant of the recipe above).
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
	@$(say) "toolchain: python3 $$(python3 --version 2>&1 | awk '{print $$2}'), openssl $$(openssl version | awk '{print $$2}')"

# (internal) Ensure sshpass: passwordless apt-get when available, otherwise a
# rootless install into ~/.local/bin. A failure is fatal (install it manually or
# use key-only bootstrap credentials).
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

# (internal) Ensure passlib (password_hash for the automation user): the target
# interpreter already has it, else pip, else a rootless deb fallback. Fatal.
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

# (internal) Install/refresh the pinned Ansible collections into the
# project-local `collections/` dir (selected by ansible.cfg's `collections_path`,
# which REPLACES the global ~/.ansible/collections). ansible-galaxy is
# idempotent and version-aware: it no-ops when the pinned versions are present,
# and installs/upgrades to the exact requirements.yml pins otherwise.
ensure-ansible-collections:
	@ansible-galaxy collection install -r requirements.yml $(if $(QUIET),1>/dev/null,)

# (internal) Download the pinned Keychain asset into the cache. A failed
# download is fatal: fetch the asset manually and re-run.
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

# (internal) Verify the cached Keychain asset against the pin.
verify-keychain-pin: keychain-fetch
	@set -e; \
	printf '%s  %s\n' "$(KEYCHAIN_SHA256)" "$(KEYCHAIN_ASSET)" | sha256sum -c - >/dev/null \
		|| { echo "ERROR: keychain asset checksum mismatch: $(KEYCHAIN_ASSET)" >&2; \
		     echo "  Remove it and re-run, or download it manually from $(KEYCHAIN_URL)." >&2; \
		     exit 1; }; \
	$(say) "keychain pin OK: v$(KEYCHAIN_VERSION)"

# (internal) Ensure the pinned Keychain is installed (used only as a fallback).
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

# (internal) Run a playbook through the shared ssh-agent runner: the agent is
# prepared (probe-gated) first, and the runner retries once if OpenSSH refuses a
# private key (e.g. 0777 on the WSL /mnt/c mount). Correctly permissioned keys
# (and password auth) connect directly, with no agent.
run-playbook: install vault-init agent-fallback
	@$(SSH_AGENT_RUN) $(ANS_PLAY) -i $(INV) $(PLAYBOOK) $(EXTRA)

.PHONY: validate-knobs
validate-knobs: vault-init
	@test -f $(INV) || { echo "validate-knobs: $(INV) missing, skipped"; exit 0; }
	$(ANS_PLAY) -i $(INV) playbooks/validate_knobs.yml
