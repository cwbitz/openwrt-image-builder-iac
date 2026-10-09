# Minimal stdout callback for the `make info` run. Prints one
# `host: <msg>` line per tagged debug result (see
# roles/imagebuilder/tasks/info.yml) and for failures, with no task
# banners, `ok: [...] => {...}` blocks or PLAY RECAP. Selected via
# ANSIBLE_STDOUT_CALLBACK only by the `info` target.
from __future__ import annotations

from ansible.plugins.callback import CallbackBase

INFO_TAG = "imagebuilder_info"


def _format(result):
    msg = result.result.get("msg", "")
    if isinstance(msg, (list, tuple)):
        return "\n".join(str(line) for line in msg)
    return str(msg)


class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = "stdout"
    CALLBACK_NAME = "info_format"

    def _show(self, result, label=""):
        self._display.display(f"{result.host.get_name()}: {label}{_format(result)}")

    def v2_runner_on_ok(self, result):
        if INFO_TAG in result.task.tags:
            host = result.host.get_name()
            self._display.display(f"\n{'=' * 20} {host} {'=' * 20}\n{_format(result)}")

    def v2_runner_on_failed(self, result, ignore_errors=False):
        self._show(result, label="FAILED: ")

    def v2_runner_on_unreachable(self, result):
        self._show(result, label="UNREACHABLE: ")

    def v2_runner_on_skipped(self, result):
        pass
