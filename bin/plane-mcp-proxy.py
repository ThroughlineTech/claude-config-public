#!/usr/bin/env python3
"""
Plane MCP filter proxy for VS Code Copilot.

Wraps `uvx plane-mcp-server stdio` and intercepts tools/list responses,
filtering the tool list to only the 17 tools used by ticket workflow
commands. Reduces tool count from 109 → 17, preventing context truncation
in Copilot agents with small token budgets (e.g. Haiku 4.5 at 0.3x).

Usage: configured as the mcp.json command by install.sh. Not invoked directly.
"""
import json
import os
import subprocess
import sys
import threading

ALLOWED = {
    "create_project",
    "create_work_item",
    "create_work_item_comment",
    "create_work_item_link",
    "create_work_item_relation",
    "get_me",
    "list_labels",
    "list_projects",
    "list_states",
    "list_work_item_activities",
    "list_work_item_comments",
    "list_work_item_links",
    "list_work_item_relations",
    "list_work_items",
    "retrieve_work_item",
    "retrieve_work_item_by_identifier",
    "update_work_item",
}

proc = subprocess.Popen(
    ["uvx", "plane-mcp-server", "stdio"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=sys.stderr,
    env=os.environ,
)


def _pipe_stdin():
    try:
        for line in sys.stdin.buffer:
            proc.stdin.write(line)
            proc.stdin.flush()
    except Exception:
        pass
    finally:
        try:
            proc.stdin.close()
        except Exception:
            pass


threading.Thread(target=_pipe_stdin, daemon=True).start()

for raw in proc.stdout:
    line = raw.decode("utf-8", errors="replace").rstrip("\n")
    try:
        msg = json.loads(line)
        if isinstance(msg.get("result"), dict) and "tools" in msg["result"]:
            msg["result"]["tools"] = [
                t for t in msg["result"]["tools"] if t.get("name") in ALLOWED
            ]
            line = json.dumps(msg)
    except (json.JSONDecodeError, Exception):
        pass
    sys.stdout.write(line + "\n")
    sys.stdout.flush()

sys.exit(proc.wait())
