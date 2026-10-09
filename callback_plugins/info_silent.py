# No-op enabled callback used only to displace `callbacks_enabled`
# (ansible.posix.profile_tasks) for the `info` run: it keeps
# ANSIBLE_CALLBACKS_ENABLED valid while emitting nothing. Selected via
# ANSIBLE_CALLBACKS_ENABLED only by the `info` target.
from __future__ import annotations

from ansible.plugins.callback import CallbackBase


class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = "aggregate"
    CALLBACK_NAME = "info_silent"
    CALLBACK_NEEDS_ENABLED = True
