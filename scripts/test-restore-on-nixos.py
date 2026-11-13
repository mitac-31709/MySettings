#!/usr/bin/env python3
"""Exercise restore-on-nixos.sh with a real, disposable local backup.

Requires restic, rclone, and jq on PATH. No Google or Bitwarden access is used.
"""

import json
import os
from pathlib import Path
import pty
import select
import shutil
import stat
import subprocess
import tempfile
import time
import unittest


SCRIPT = Path(__file__).resolve().with_name("restore-on-nixos.sh")
SUCCESS = "復元と検証が完了しました。"


def run_in_pty(command, *, cwd, env, steps, timeout=15):
    """Drive an interactive bash invocation through a real PTY."""
    master, slave = pty.openpty()
    proc = subprocess.Popen(
        command,
        cwd=cwd,
        env=env,
        stdin=slave,
        stdout=slave,
        stderr=slave,
        close_fds=True,
    )
    os.close(slave)
    output = bytearray()
    scan_pos = 0
    step_index = 0
    deadline = time.monotonic() + timeout
    try:
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                proc.kill()
                raise TimeoutError(
                    f"Timed out waiting at step {step_index}/{len(steps)}.\n"
                    f"Captured output:\n{output.decode(errors='replace')}"
                )
            ready, _, _ = select.select([master], [], [], min(0.2, remaining))
            if ready:
                try:
                    chunk = os.read(master, 4096)
                except OSError:
                    chunk = b""
                if chunk:
                    output.extend(chunk)
                elif proc.poll() is not None:
                    break
            elif proc.poll() is not None:
                # Drain any buffered bytes already emitted before exit.
                while True:
                    more, _, _ = select.select([master], [], [], 0.05)
                    if not more:
                        break
                    try:
                        chunk = os.read(master, 4096)
                    except OSError:
                        break
                    if not chunk:
                        break
                    output.extend(chunk)
                break

            while step_index < len(steps):
                expect, send = steps[step_index]
                needle = expect.encode()
                idx = output.find(needle, scan_pos)
                if idx != -1:
                    scan_pos = idx + len(needle)
                    os.write(master, (send + "\n").encode())
                    step_index += 1
                    time.sleep(0.02)
                else:
                    break
        rc = proc.wait(timeout=5)
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait(timeout=5)
        os.close(master)
    return rc, output.decode(errors="replace"), step_index


class RestoreIntegrationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        for tool in ("restic", "rclone", "jq"):
            if not shutil.which(tool):
                raise RuntimeError(f"Required test dependency is missing: {tool}")
        cls.restic = shutil.which("restic")
        cls.temporary = tempfile.TemporaryDirectory(prefix="restore-integration-")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.root = Path(cls.temporary.name)
        cls.repository = cls.root / "restic" / "mitac-home"
        cls.repository.parent.mkdir()
        cls.home = cls.root / "isolated-user"
        cls.home.mkdir()
        cls.config = cls.root / "rclone.conf"
        cls.config.write_text("[gdrive]\ntype = local\n", encoding="utf-8")
        cls.config.chmod(0o600)
        cls.environment = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith(("RESTIC_", "RCLONE_", "RBW_", "RESTORE_"))
        }
        cls.environment.update(
            HOME=str(cls.home),
            XDG_CACHE_HOME=str(cls.root / "cache"),
            RCLONE_CONFIG=str(cls.config),
            RESTIC_CACHE_DIR=str(cls.root / "restic-cache"),
            RESTIC_PASSWORD="disposable-local-fixture-password",
            RESTORE_NO_RBW="1",
            TZ="UTC",
        )
        cls.run_restic("init")

        old_source = cls.root / "old-home"
        old_source.mkdir()
        (old_source / "old-only.txt").write_text("old snapshot\n", encoding="utf-8")
        cls.old_id = cls.backup(
            "old-home", host="old-machine", time="2026-01-01 01:00:00"
        )

        cls.expected_files = {
            "home/mitac/Documents/hiragino-otf/test-font.otf": b"font fixture\x00\xff",
            "home/mitac/Documents/notes.txt": "復元するメモ\n".encode(),
            "home/mitac/.config/example.conf": b"setting = restored\n",
            "run/restic-backups-home/system/nm-connections/example": b"system fixture\n",
        }
        for name, contents in cls.expected_files.items():
            destination = cls.root / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(contents)
        cls.latest_id = cls.backup(
            "home/mitac",
            "run/restic-backups-home/system",
            host="new-machine",
            time="2026-01-02 01:00:00",
        )

    @classmethod
    def run_restic(cls, *arguments):
        result = subprocess.run(
            [cls.restic, "--repo", str(cls.repository), *arguments],
            cwd=cls.root,
            env=cls.environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )
        if result.returncode:
            raise RuntimeError(
                f"Fixture restic command failed: {arguments}\n"
                f"{result.stdout}\n{result.stderr}"
            )
        return result.stdout

    @classmethod
    def backup(cls, *paths, host, time):
        output = cls.run_restic(
            "backup", "--json", "--host", host, "--time", time, *paths
        )
        summaries = [json.loads(line) for line in output.splitlines()]
        return next(item["snapshot_id"] for item in summaries if "snapshot_id" in item)

    def setUp(self):
        self.case_directory = Path(tempfile.mkdtemp(dir=self.root, prefix="case-"))
        self.target = self.case_directory / "restored"

    def restore(self, *, environment=None):
        # The real script runs unchanged; only its machine/user prerequisite is
        # replaced so the local transport can be exercised on the test host.
        return subprocess.run(
            [
                "bash",
                "-c",
                'source "$1"; check_platform() { :; }; shift; main "$@"',
                "restore-integration",
                str(SCRIPT),
                str(self.target),
            ],
            cwd=self.root,
            env=environment or self.environment,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )

    def test_latest_snapshot_restores_all_bytes(self):
        result = self.restore()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(SUCCESS, result.stdout)
        self.assertEqual(
            (self.target / ".restored-snapshot-id").read_text().strip(),
            self.latest_id,
        )
        for name, contents in self.expected_files.items():
            with self.subTest(file=name):
                self.assertEqual((self.target / name).read_bytes(), contents)
        self.assertFalse((self.target / "old-home").exists())

    def test_existing_target_is_unchanged(self):
        self.target.mkdir()
        sentinel = self.target / "keep.txt"
        sentinel.write_bytes(b"existing user file\n")
        result = self.restore()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(sentinel.read_bytes(), b"existing user file\n")
        self.assertEqual(list(self.target.iterdir()), [sentinel])
        self.assertNotIn(SUCCESS, result.stdout)

    def test_wrong_password_does_not_create_target(self):
        environment = dict(self.environment, RESTIC_PASSWORD="incorrect-fixture-password")
        result = self.restore(environment=environment)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.target.exists())
        self.assertNotIn(SUCCESS, result.stdout)

    def test_non_tty_without_password_fails(self):
        environment = {
            key: value
            for key, value in self.environment.items()
            if key != "RESTIC_PASSWORD"
        }
        result = self.restore(environment=environment)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("RESTIC_PASSWORD", result.stderr)
        self.assertFalse(self.target.exists())
        self.assertNotIn(SUCCESS, result.stdout)

    def test_pty_password_prompt_retries_then_restores(self):
        environment = {
            key: value
            for key, value in self.environment.items()
            if key != "RESTIC_PASSWORD"
        }
        rc, output, consumed = run_in_pty(
            [
                "bash",
                "-c",
                'source "$1"; check_platform() { :; }; shift; main "$@"',
                "restore-pty-integration",
                str(SCRIPT),
                str(self.target),
            ],
            cwd=self.root,
            env=environment,
            steps=[
                ("restic 暗号化パスワードを入力してください", ""),
                ("パスワードは空にできません。", "wrong-password"),
                ("パスワードを再入力しますか？ [Y/n]", "y"),
                ("入力は非表示）:", "disposable-local-fixture-password"),
            ],
            timeout=60,
        )
        self.assertEqual(consumed, 4, output)
        self.assertEqual(rc, 0, output)
        self.assertIn(SUCCESS, output)
        self.assertEqual(
            (self.target / ".restored-snapshot-id").read_text().strip(),
            self.latest_id,
        )

    def test_default_in_place_restores_all_locations(self):
        restore_root = self.case_directory / "root"
        stage_parent = self.case_directory / "var-tmp"
        existing_home = restore_root / "home" / "mitac" / "MySettings"
        existing_home.mkdir(parents=True)
        (restore_root / "home" / "mitac" / "Documents").mkdir(parents=True)
        stale_file = existing_home / "README.md"
        stale_file.write_text("old checkout", encoding="utf-8")
        stage_parent.mkdir()

        sudo_log = self.case_directory / "sudo.log"
        shim_bin = self.case_directory / "bin"
        shim_bin.mkdir()
        sudo_shim = shim_bin / "sudo"
        sudo_shim.write_text(
            '#!/usr/bin/env bash\n'
            'printf "%s\\n" "$*" >> "$SUDO_LOG"\n'
            'if [[ ${1:-} == chown ]]; then\n'
            '  exit 0\n'
            'fi\n'
            'exec "$@"\n',
            encoding="utf-8",
        )
        sudo_shim.chmod(0o700)

        env = dict(
            self.environment,
            HOME=str(restore_root / "home" / "mitac"),
            PATH=f"{shim_bin}:{self.environment['PATH']}",
            RESTORE_ROOT=str(restore_root),
            RESTORE_STAGE_PARENT=str(stage_parent),
            SUDO_LOG=str(sudo_log),
        )
        result = subprocess.run(
            [
                "bash",
                "-c",
                'source "$1"; check_platform() { :; }; shift; main "$@"',
                "restore-integration-inplace",
                str(SCRIPT),
            ],
            cwd=self.root,
            env=env,
            stdin=subprocess.DEVNULL,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(SUCCESS, result.stdout)
        for name, contents in self.expected_files.items():
            if name.startswith("home/mitac/"):
                self.assertEqual((restore_root / name).read_bytes(), contents)
        nm_file = restore_root / "etc/NetworkManager/system-connections/example"
        self.assertEqual(nm_file.read_bytes(), b"system fixture\n")
        self.assertEqual(stat.S_IMODE(nm_file.stat().st_mode), 0o600)
        self.assertEqual(list(stage_parent.iterdir()), [])
        sudo_calls = sudo_log.read_text(encoding="utf-8")
        self.assertIn(f"chown -R root:root -- {restore_root}/etc/NetworkManager/system-connections", sudo_calls)

    def test_restore_failure_preserves_exit_status(self):
        # Keep real repository discovery/stats, but force an interrupted restore.
        # A successful marker must never be written after the restore fails.
        shim_directory = self.case_directory / "bin"
        shim_directory.mkdir()
        shim = shim_directory / "restic"
        shim.write_text(
            '#!/usr/bin/env bash\n'
            'if [[ ${1:-} == restore ]]; then\n'
            '  printf "fixture: restore interrupted\\n" >&2\n'
            '  exit 23\n'
            'fi\n'
            'exec "$FIXTURE_RESTIC" "$@"\n',
            encoding="utf-8",
        )
        shim.chmod(0o700)
        environment = dict(
            self.environment,
            PATH=f"{shim_directory}:{self.environment['PATH']}",
            FIXTURE_RESTIC=self.restic,
        )
        result = self.restore(environment=environment)
        self.assertEqual(result.returncode, 23, result.stdout + result.stderr)
        self.assertTrue(self.target.is_dir())
        self.assertFalse((self.target / ".restored-snapshot-id").exists())
        self.assertNotIn(SUCCESS, result.stdout)


class RestorePromptTest(unittest.TestCase):
    """Exercise interactive rbw/rclone/password setup without requiring real Google/Bitwarden/restic."""

    FAKE_HASH = "a" * 64

    @classmethod
    def setUpClass(cls):
        for tool in ("rclone", "jq", "bash"):
            if not shutil.which(tool):
                raise RuntimeError(f"Required test dependency is missing: {tool}")
        cls.real_rclone = shutil.which("rclone")

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="restore-prompt-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.rbw_state = self.root / "rbw-state"
        self.rbw_state.mkdir()
        self.rbw_log = self.root / "rbw.log"
        self.target = self.root / "target-restore"
        self.capture = self.root / "captured.txt"
        self.sudo_log = self.root / "sudo.log"
        self.stage_parent = self.root / "var-tmp"
        self.stage_parent.mkdir()
        self.install_shims()
        self.environment = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith(
                ("RESTIC_", "RCLONE_", "XDG_CONFIG_HOME", "RESTORE_", "RBW_")
            )
            and key not in ("DISPLAY", "WAYLAND_DISPLAY")
        }
        self.environment.update(
            HOME=str(self.home),
            PATH=f"{self.bin}:{os.environ['PATH']}",
            REAL_RCLONE=self.real_rclone,
            CAPTURE_FILE=str(self.capture),
            SUDO_LOG=str(self.sudo_log),
            RESTORE_STAGE_PARENT=str(self.stage_parent),
            RESTORE_NO_RBW="1",
            RBW_STATE_DIR=str(self.rbw_state),
            RBW_LOG=str(self.rbw_log),
            FAKE_HASH=self.FAKE_HASH,
        )

    def rbw_env(self, **extra):
        env = {k: v for k, v in self.environment.items() if k != "RESTORE_NO_RBW"}
        env.update(extra)
        return env

    def write_rbw_item(self, data, filename="item.json"):
        path = self.rbw_state / filename
        path.write_text(json.dumps(data), encoding="utf-8")
        return path

    def write_rbw_config(self, cfg):
        conf = self.rbw_state / "config.json"
        conf.write_text(json.dumps(cfg), encoding="utf-8")
        return conf

    def read_rbw_config(self):
        return json.loads((self.rbw_state / "config.json").read_text(encoding="utf-8"))

    def read_rbw_log(self):
        if not self.rbw_log.exists():
            return []
        return self.rbw_log.read_text(encoding="utf-8").splitlines()

    def install_shims(self):
        sudo_shim = self.bin / "sudo"
        sudo_shim.write_text(
            '#!/usr/bin/env bash\n'
            'set -euo pipefail\n'
            'printf "%s\\n" "$*" >> "$SUDO_LOG"\n'
            'if [[ ${1:-} == chown ]]; then\n'
            '  exit 0\n'
            'fi\n'
            'exec "$@"\n',
            encoding="utf-8",
        )
        sudo_shim.chmod(0o700)

        for pin_name in ("pinentry-qt", "pinentry-curses"):
            pin_shim = self.bin / pin_name
            pin_shim.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
            pin_shim.chmod(0o700)

        rbw_shim = self.bin / "rbw"
        rbw_shim.write_text(
            '#!/usr/bin/env bash\n'
            'set -euo pipefail\n'
            'state=${RBW_STATE_DIR:?}\n'
            'mkdir -p "$state"\n'
            'conf="${state}/config.json"\n'
            '[[ -f $conf ]] || printf "{}" > "$conf"\n'
            'log="${RBW_LOG:-$state/rbw.log}"\n'
            'printf "%s\\n" "$*" >> "$log"\n'
            'cmd=${1:-}\n'
            'shift || true\n'
            'case "$cmd" in\n'
            '  config)\n'
            '    sub=${1:-}\n'
            '    shift || true\n'
            '    case "$sub" in\n'
            '      show)\n'
            '        cat "$conf"\n'
            '        ;;\n'
            '      set)\n'
            '        key=${1:-}\n'
            '        val=${2:-}\n'
            '        tmp=$(mktemp "$state/config.XXXXXX")\n'
            '        jq --arg k "$key" --arg v "$val" \'.[$k] = $v\' "$conf" > "$tmp"\n'
            '        mv -f "$tmp" "$conf"\n'
            '        ;;\n'
            '      *)\n'
            '        exit 1\n'
            '        ;;\n'
            '    esac\n'
            '    ;;\n'
            '  stop-agent)\n'
            '    exit 0\n'
            '    ;;\n'
            '  unlocked)\n'
            '    [[ -f "$state/unlocked" ]]\n'
            '    ;;\n'
            '  register)\n'
            '    if [[ ${RBW_SHIM_REGISTER_FAIL:-0} == 1 ]]; then\n'
            '      exit 1\n'
            '    fi\n'
            '    touch "$state/registered"\n'
            '    ;;\n'
            '  login)\n'
            '    if [[ ${RBW_SHIM_NEED_REGISTER:-0} == 1 && ! -f "$state/registered" ]]; then\n'
            '      printf "rbw login: device registration required\\n" >&2\n'
            '      exit 1\n'
            '    fi\n'
            '    if [[ ${RBW_SHIM_LOGIN_FAIL:-0} == 1 ]]; then\n'
            '      printf "rbw login: failed\\n" >&2\n'
            '      exit 1\n'
            '    fi\n'
            '    ;;\n'
            '  unlock)\n'
            '    if [[ ${RBW_SHIM_UNLOCK_FAIL:-0} == 1 ]]; then\n'
            '      printf "rbw unlock: failed\\n" >&2\n'
            '      exit 1\n'
            '    fi\n'
            '    touch "$state/unlocked"\n'
            '    ;;\n'
            '  sync)\n'
            '    if [[ ${RBW_SHIM_SYNC_FAIL:-0} == 1 ]]; then\n'
            '      printf "rbw sync: simulated error\\n" >&2\n'
            '      exit 1\n'
            '    fi\n'
            '    if [[ -f "$state/first-sync-done" ]]; then\n'
            '      if [[ -n ${RBW_RESYNC_ITEM_FILE:-} && -f ${RBW_RESYNC_ITEM_FILE} ]]; then\n'
            '        cp -f "$RBW_RESYNC_ITEM_FILE" "$state/item.json"\n'
            '      fi\n'
            '    else\n'
            '      touch "$state/first-sync-done"\n'
            '    fi\n'
            '    ;;\n'
            '  get)\n'
            '    raw=0\n'
            '    if [[ ${1:-} == --raw ]]; then\n'
            '      raw=1\n'
            '      shift\n'
            '    fi\n'
            '    item=${1:-}\n'
            '    [[ -f "$state/unlocked" ]] || { printf "rbw get: vault is locked\\n" >&2; exit 1; }\n'
            '    expected_item=${RBW_EXPECTED_ITEM:-restic-home}\n'
            '    if [[ $item != "$expected_item" || ! -f "$state/item.json" ]]; then\n'
            '      printf "rbw get: no entry found for %s\\n" "$item" >&2\n'
            '      exit 1\n'
            '    fi\n'
            '    if (( raw == 1 )); then\n'
            '      cat "$state/item.json"\n'
            '    else\n'
            '      jq -r \'.data.password // empty\' "$state/item.json"\n'
            '    fi\n'
            '    ;;\n'
            '  *)\n'
            '    printf "unexpected rbw subcommand: %s\\n" "$cmd" >&2\n'
            '    exit 1\n'
            '    ;;\n'
            'esac\n',
            encoding="utf-8",
        )
        rbw_shim.chmod(0o700)

        rclone_shim = self.bin / "rclone"
        rclone_shim.write_text(
            '#!/usr/bin/env bash\n'
            'set -euo pipefail\n'
            'if [[ ${1:-} == about && ${2:-} == gdrive: ]]; then\n'
            '  if [[ -n ${SIMULATE_ABOUT_REQUIRE_TOKEN:-} ]]; then\n'
            '    rt=$(RCLONE_CONFIG="$RCLONE_CONFIG" "$REAL_RCLONE" config dump 2>/dev/null '
            '| jq -r ".gdrive.token // empty | fromjson? // {} | .refresh_token // empty")\n'
            '    if [[ $rt != "$SIMULATE_ABOUT_REQUIRE_TOKEN" ]]; then\n'
            '      printf "simulated invalid_grant for refresh_token=%s\\n" "$rt" >&2\n'
            '      exit 1\n'
            '    fi\n'
            '  fi\n'
            '  printf "Total: 100 GiB\\n"\n'
            '  exit 0\n'
            'fi\n'
            'if [[ ${1:-} == config && ${2:-} == reconnect && ${3:-} == gdrive: ]]; then\n'
            '  if [[ -n ${SIMULATE_OAUTH_TOKEN:-} ]]; then\n'
            '    cid=$(RCLONE_CONFIG="$RCLONE_CONFIG" "$REAL_RCLONE" config dump | jq -r ".gdrive.client_id")\n'
            '    csec=$(RCLONE_CONFIG="$RCLONE_CONFIG" "$REAL_RCLONE" config dump | jq -r ".gdrive.client_secret")\n'
            '    "$REAL_RCLONE" config create gdrive drive '
            'client_id "$cid" client_secret "$csec" scope drive '
            'token "$SIMULATE_OAUTH_TOKEN" config_refresh_token false config_is_local false >/dev/null\n'
            '    exit 0\n'
            '  fi\n'
            '  exit 1\n'
            'fi\n'
            'exec "$REAL_RCLONE" "$@"\n',
            encoding="utf-8",
        )
        rclone_shim.chmod(0o700)

        restic_shim = self.bin / "restic"
        restic_shim.write_text(
            '#!/usr/bin/env bash\n'
            'set -euo pipefail\n'
            'case "${1:-}" in\n'
            '  snapshots)\n'
            '    if [[ ${2:-} == --json && ${3:-} == latest ]]; then\n'
            '      expected="${EXPECTED_RESTIC_PASSWORD:-correct-pw}"\n'
            '      if [[ ${RESTIC_PASSWORD:-} != "$expected" ]]; then\n'
            '        printf "Fatal: wrong password or no key found\\n" >&2\n'
            '        exit 1\n'
            '      fi\n'
            '      printf "[{\\"id\\":\\"%s\\"}]\\n" "$FAKE_HASH"\n'
            '    fi\n'
            '    ;;\n'
            '  stats)\n'
            '    printf "{\\"total_size\\":1024}\\n"\n'
            '    ;;\n'
            '  restore)\n'
            '    if [[ ${SIMULATE_RESTORE_FAIL:-0} == 1 ]]; then\n'
            '      printf "simulated restore failure\\n" >&2\n'
            '      exit 23\n'
            '    fi\n'
            '    {\n'
            '      printf "REPO=%s\\n" "${RESTIC_REPOSITORY:-}"\n'
            '      printf "RCLONE_CONFIG=%s\\n" "${RCLONE_CONFIG:-}"\n'
            '      printf "PW_LEN=%s\\n" "${#RESTIC_PASSWORD}"\n'
            '      printf "PW=%s\\n" "${RESTIC_PASSWORD:-}"\n'
            '    } > "$CAPTURE_FILE"\n'
            '    if [[ -n ${FIXTURE_STAGE_TREE:-} ]]; then\n'
            '      cp -a -- "${FIXTURE_STAGE_TREE}/." "$4/"\n'
            '    else\n'
            '      mkdir -p "$4/home/mitac"\n'
            '    fi\n'
            '    ;;\n'
            'esac\n',
            encoding="utf-8",
        )
        restic_shim.chmod(0o700)

    def dump_gdrive(self, config_path):
        raw = subprocess.check_output(
            [self.real_rclone, "config", "dump"],
            env=dict(self.environment, RCLONE_CONFIG=str(config_path)),
            text=True,
        )
        return json.loads(raw)["gdrive"]

    def test_non_tty_missing_gdrive_fails_fast(self):
        result = subprocess.run(
            [
                "bash",
                "-c",
                'source "$1"; check_platform() { :; }; shift; main "$@"',
                "prompt-test",
                str(SCRIPT),
                str(self.target),
            ],
            cwd=self.root,
            env=self.environment,
            stdin=subprocess.DEVNULL,
            text=True,
            capture_output=True,
            timeout=15,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("リモート gdrive: が", result.stderr)
        self.assertIn("見つかりません", result.stderr)
        self.assertFalse((self.home / ".config" / "rclone" / "rclone.conf").exists())

    def test_pty_configures_gdrive_from_refresh_token_and_restores(self):
        env = dict(
            self.environment,
            EXPECTED_RESTIC_PASSWORD="secret pass with spaces",
            SIMULATE_ABOUT_REQUIRE_TOKEN="1//rt=hello",
        )
        rc, output, consumed = run_in_pty(
            [
                "bash",
                "-c",
                'source "$1"; check_platform() { :; }; shift; main "$@"',
                "prompt-test",
                str(SCRIPT),
                str(self.target),
            ],
            cwd=self.root,
            env=env,
            steps=[
                ("Google OAuth client_id:", "  cid=abc  "),
                ("Google OAuth client_secret:", "  csec=xyz  "),
                ("Google OAuth refresh_token", "  1//rt=hello  "),
                ("restic 暗号化パスワードを入力してください", "secret pass with spaces"),
            ],
        )
        self.assertEqual(consumed, 4, output)
        self.assertEqual(rc, 0, output)
        self.assertIn(SUCCESS, output)

        conf = self.home / ".config" / "rclone" / "rclone.conf"
        self.assertTrue(conf.is_file())
        self.assertEqual(stat.S_IMODE(conf.stat().st_mode), 0o600)

        gdrive = self.dump_gdrive(conf)
        self.assertEqual(gdrive["type"], "drive")
        self.assertEqual(gdrive["scope"], "drive")
        self.assertEqual(gdrive["client_id"], "cid=abc")
        self.assertEqual(gdrive["client_secret"], "csec=xyz")
        token = json.loads(gdrive["token"])
        self.assertEqual(token["refresh_token"], "1//rt=hello")
        self.assertEqual(token["access_token"], "x")
        self.assertEqual(token["token_type"], "Bearer")
        self.assertEqual(token["expiry"], "2000-01-01T00:00:00Z")

        captured = self.capture.read_text(encoding="utf-8")
        self.assertIn("REPO=rclone:gdrive:restic/mitac-home\n", captured)
        self.assertIn(f"RCLONE_CONFIG={conf}\n", captured)
        self.assertIn("PW=secret pass with spaces\n", captured)

    def test_pty_validates_token_json_and_normalizes_minimal_object(self):
        env = dict(
            self.environment,
            EXPECTED_RESTIC_PASSWORD="pw1",
            SIMULATE_ABOUT_REQUIRE_TOKEN="1//min-tok",
        )
        rc, output, consumed = run_in_pty(
            [
                "bash",
                "-c",
                'source "$1"; check_platform() { :; }; shift; main "$@"',
                "prompt-test",
                str(SCRIPT),
                str(self.target),
            ],
            cwd=self.root,
            env=env,
            steps=[
                ("Google OAuth client_id:", "cid-1"),
                ("Google OAuth client_secret:", "csec-1"),
                ("Google OAuth refresh_token", "{not-json"),
                ("token JSON の形式が不正です", "{}"),
                ("token JSON の形式が不正です", '{"refresh_token":"1//min-tok"}'),
                ("restic 暗号化パスワードを入力してください", "pw1"),
            ],
        )
        self.assertEqual(consumed, 6, output)
        self.assertEqual(rc, 0, output)
        self.assertIn(SUCCESS, output)

        conf = self.home / ".config" / "rclone" / "rclone.conf"
        token = json.loads(self.dump_gdrive(conf)["token"])
        self.assertEqual(token["refresh_token"], "1//min-tok")
        self.assertEqual(token["access_token"], "x")
        self.assertEqual(token["token_type"], "Bearer")

    def test_pty_probe_failure_reenter_keeps_existing_client_fields(self):
        conf = self.home / ".config" / "rclone" / "rclone.conf"
        conf.parent.mkdir(parents=True)
        conf.touch()
        conf.chmod(0o600)
        subprocess.run(
            [
                self.real_rclone,
                "config",
                "create",
                "gdrive",
                "drive",
                "client_id",
                "existing-client-id-123456",
                "client_secret",
                "existing-secret-789",
                "scope",
                "drive",
                "token",
                json.dumps(
                    {
                        "access_token": "x",
                        "token_type": "Bearer",
                        "refresh_token": "1//stale",
                        "expiry": "2000-01-01T00:00:00Z",
                    }
                ),
                "config_refresh_token",
                "false",
                "config_is_local",
                "false",
            ],
            env=dict(self.environment, RCLONE_CONFIG=str(conf)),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True,
        )
        env = dict(
            self.environment,
            EXPECTED_RESTIC_PASSWORD="pw2",
            SIMULATE_ABOUT_REQUIRE_TOKEN="1//fresh-rt",
        )
        rc, output, consumed = run_in_pty(
            [
                "bash",
                "-c",
                'source "$1"; check_platform() { :; }; shift; main "$@"',
                "prompt-test",
                str(SCRIPT),
                str(self.target),
            ],
            cwd=self.root,
            env=env,
            steps=[
                ("[b/r/o/t/q]:", "r"),
                ("[Enter で維持: existing-cli...]:", ""),
                ("[Enter で既存値を維持]:", ""),
                ("Google OAuth refresh_token", "1//fresh-rt"),
                ("restic 暗号化パスワードを入力してください", "pw2"),
            ],
        )
        self.assertEqual(consumed, 5, output)
        self.assertEqual(rc, 0, output)
        gdrive = self.dump_gdrive(conf)
        self.assertEqual(gdrive["client_id"], "existing-client-id-123456")
        self.assertEqual(gdrive["client_secret"], "existing-secret-789")
        self.assertEqual(json.loads(gdrive["token"])["refresh_token"], "1//fresh-rt")

    def test_pty_probe_failure_oauth_reconnect_recovers(self):
        conf = self.home / ".config" / "rclone" / "rclone.conf"
        conf.parent.mkdir(parents=True)
        conf.touch()
        conf.chmod(0o600)
        subprocess.run(
            [
                self.real_rclone,
                "config",
                "create",
                "gdrive",
                "drive",
                "client_id",
                "cid-keep",
                "client_secret",
                "csec-keep",
                "scope",
                "drive",
                "token",
                json.dumps(
                    {
                        "access_token": "x",
                        "token_type": "Bearer",
                        "refresh_token": "1//revoked",
                        "expiry": "2000-01-01T00:00:00Z",
                    }
                ),
                "config_refresh_token",
                "false",
                "config_is_local",
                "false",
            ],
            env=dict(self.environment, RCLONE_CONFIG=str(conf)),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True,
        )
        new_token = json.dumps(
            {
                "access_token": "new-acc",
                "token_type": "Bearer",
                "refresh_token": "1//reconnected",
                "expiry": "2031-01-01T00:00:00Z",
            }
        )
        env = dict(
            self.environment,
            EXPECTED_RESTIC_PASSWORD="pw-o",
            SIMULATE_ABOUT_REQUIRE_TOKEN="1//reconnected",
            SIMULATE_OAUTH_TOKEN=new_token,
        )
        rc, output, consumed = run_in_pty(
            [
                "bash",
                "-c",
                'source "$1"; check_platform() { :; }; shift; main "$@"',
                "prompt-test",
                str(SCRIPT),
                str(self.target),
            ],
            cwd=self.root,
            env=env,
            steps=[
                ("[b/r/o/t/q]:", "o"),
                ("restic 暗号化パスワードを入力してください", "pw-o"),
            ],
        )
        self.assertEqual(consumed, 2, output)
        self.assertEqual(rc, 0, output)
        gdrive = self.dump_gdrive(conf)
        self.assertEqual(gdrive["client_id"], "cid-keep")
        self.assertEqual(json.loads(gdrive["token"])["refresh_token"], "1//reconnected")

    def test_pty_accepts_full_token_json_verbatim(self):
        full_token = {
            "access_token": "ya29.existing-token",
            "token_type": "Bearer",
            "refresh_token": "1//full-tok",
            "expiry": "2026-05-01T12:00:00Z",
        }
        env = dict(
            self.environment,
            EXPECTED_RESTIC_PASSWORD="pw-full",
            SIMULATE_ABOUT_REQUIRE_TOKEN="1//full-tok",
        )
        rc, output, consumed = run_in_pty(
            [
                "bash",
                "-c",
                'source "$1"; check_platform() { :; }; shift; main "$@"',
                "prompt-test",
                str(SCRIPT),
                str(self.target),
            ],
            cwd=self.root,
            env=env,
            steps=[
                ("Google OAuth client_id:", "cid-full"),
                ("Google OAuth client_secret:", "csec-full"),
                ("Google OAuth refresh_token", json.dumps(full_token)),
                ("restic 暗号化パスワードを入力してください", "pw-full"),
            ],
        )
        self.assertEqual(consumed, 4, output)
        self.assertEqual(rc, 0, output)
        conf = self.home / ".config" / "rclone" / "rclone.conf"
        self.assertEqual(json.loads(self.dump_gdrive(conf)["token"]), full_token)

    def test_pty_blank_refresh_token_uses_interactive_oauth(self):
        oauth_token = json.dumps(
            {
                "access_token": "oauth-access",
                "token_type": "Bearer",
                "refresh_token": "1//oauth-rt",
                "expiry": "2030-01-01T00:00:00Z",
            }
        )
        env = dict(
            self.environment,
            EXPECTED_RESTIC_PASSWORD="pw3",
            SIMULATE_OAUTH_TOKEN=oauth_token,
            SIMULATE_ABOUT_REQUIRE_TOKEN="1//oauth-rt",
        )
        rc, output, consumed = run_in_pty(
            [
                "bash",
                "-c",
                'source "$1"; check_platform() { :; }; shift; main "$@"',
                "prompt-test",
                str(SCRIPT),
                str(self.target),
            ],
            cwd=self.root,
            env=env,
            steps=[
                ("Google OAuth client_id:", "cid-oauth"),
                ("Google OAuth client_secret:", "csec-oauth"),
                ("Google OAuth refresh_token", ""),
                ("restic 暗号化パスワードを入力してください", "pw3"),
            ],
        )
        self.assertEqual(consumed, 4, output)
        self.assertEqual(rc, 0, output)
        self.assertIn("gdrive: の対話式 OAuth 認証を開始します。", output)
        conf = self.home / ".config" / "rclone" / "rclone.conf"
        self.assertEqual(stat.S_IMODE(conf.stat().st_mode), 0o600)
        gdrive = self.dump_gdrive(conf)
        self.assertEqual(json.loads(gdrive["token"])["refresh_token"], "1//oauth-rt")

    def test_pty_legacy_rclone_conf_fallback_and_password_retry(self):
        legacy_conf = self.home / ".rclone.conf"
        legacy_conf.write_text("[gdrive]\ntype = local\n", encoding="utf-8")
        legacy_conf.chmod(0o600)
        env = dict(self.environment, EXPECTED_RESTIC_PASSWORD="right-password")
        rc, output, consumed = run_in_pty(
            [
                "bash",
                "-c",
                'source "$1"; check_platform() { :; }; shift; main "$@"',
                "prompt-test",
                str(SCRIPT),
                str(self.target),
            ],
            cwd=self.root,
            env=env,
            steps=[
                ("restic 暗号化パスワードを入力してください", "wrong-pw"),
                ("パスワードを再入力しますか？ [Y/n]", ""),
                ("入力は非表示）:", "right-password"),
            ],
        )
        self.assertEqual(consumed, 3, output)
        self.assertEqual(rc, 0, output)
        self.assertNotIn("Google OAuth client_id", output)
        self.assertIn(f"RCLONE_CONFIG={legacy_conf}\n", self.capture.read_text(encoding="utf-8"))

    def make_writable_tree(self, root_path):
        if not root_path.exists():
            return
        for dirpath, _, filenames in os.walk(root_path, topdown=True):
            os.chmod(dirpath, 0o700)
            for fname in filenames:
                fpath = Path(dirpath) / fname
                if not fpath.is_symlink():
                    os.chmod(fpath, 0o600)

    def test_pty_in_place_restores_all_locations_and_preserves_new_rclone(self):
        restore_root = self.root / "restore-root"
        target_home = restore_root / "home" / "mitac"
        (target_home / "MySettings").mkdir(parents=True)
        (target_home / "MySettings" / "existing.txt").write_text(
            "stale checkout\n", encoding="utf-8"
        )
        (target_home / "unbacked-local-keep.txt").write_text(
            "keep unbacked\n", encoding="utf-8"
        )
        outside_dir = self.root / "outside-nix-store"
        outside_dir.mkdir()
        (outside_dir / "store-file.txt").write_text("from store\n", encoding="utf-8")
        (target_home / "hm-dir-link").symlink_to(outside_dir)
        (target_home / "dir-becomes-file").mkdir()
        (target_home / "dir-becomes-file" / "nested.txt").write_text(
            "old dir\n", encoding="utf-8"
        )
        ro_target = target_home / "ro_existing"
        ro_target.mkdir()
        (ro_target / "item").write_text("old secret\n", encoding="utf-8")
        (ro_target / "item").chmod(0o400)
        ro_target.chmod(0o500)

        nm_dest = restore_root / "etc" / "NetworkManager" / "system-connections"
        nm_dest.mkdir(parents=True)
        (nm_dest / "current.nmconnection").write_text("current wifi\n", encoding="utf-8")

        fixture = self.root / "fixture-stage"
        self.addCleanup(self.make_writable_tree, restore_root)
        self.addCleanup(self.make_writable_tree, fixture)
        (fixture / "home" / "mitac" / "MySettings").mkdir(parents=True)
        (fixture / "home" / "mitac" / "MySettings" / "existing.txt").write_text(
            "restored checkout\n", encoding="utf-8"
        )
        (fixture / "home" / "mitac" / "hm-dir-link").mkdir(parents=True)
        (fixture / "home" / "mitac" / "hm-dir-link" / "real.txt").write_text(
            "inside restored dir\n", encoding="utf-8"
        )
        (fixture / "home" / "mitac" / "dir-becomes-file").write_text(
            "now a file\n", encoding="utf-8"
        )
        ro_src = fixture / "home" / "mitac" / "ro_existing"
        ro_src.mkdir(parents=True)
        (ro_src / "item").write_text("new secret\n", encoding="utf-8")
        (ro_src / "item").chmod(0o400)
        ro_src.chmod(0o500)
        (fixture / "home" / "mitac" / "Documents" / "hiragino-otf").mkdir(parents=True)
        (fixture / "home" / "mitac" / "Documents" / "hiragino-otf" / "Hiragino.otf").write_bytes(
            b"OTF\x00data"
        )
        (fixture / "home" / "mitac" / ".config" / "rclone").mkdir(parents=True)
        (fixture / "home" / "mitac" / ".config" / "rclone" / "rclone.conf").write_text(
            "[gdrive]\ntype = drive\n# stale snapshot config\n", encoding="utf-8"
        )

        sys_src = fixture / "run" / "restic-backups-home" / "system"
        (sys_src / "nm-connections").mkdir(parents=True)
        (sys_src / "nm-connections" / "home-wifi.nmconnection").write_text(
            "[connection]\nid=home\n", encoding="utf-8"
        )
        (sys_src / "bluetooth" / "AA:BB").mkdir(parents=True)
        (sys_src / "bluetooth" / "AA:BB" / "info").write_text(
            "[General]\nName=Headphones\n", encoding="utf-8"
        )
        (sys_src / "cloudflare-warp").mkdir(parents=True)
        (sys_src / "tailscale").mkdir(parents=True)
        (sys_src / "tailscale" / "tailscaled.state").write_text(
            "ts-state\n", encoding="utf-8"
        )

        env = dict(
            self.environment,
            HOME=str(target_home),
            RESTORE_ROOT=str(restore_root),
            FIXTURE_STAGE_TREE=str(fixture),
            EXPECTED_RESTIC_PASSWORD="pw-inplace",
            SIMULATE_ABOUT_REQUIRE_TOKEN="1//fresh-inplace-rt",
        )
        rc, output, consumed = run_in_pty(
            [
                "bash",
                "-c",
                'source "$1"; check_platform() { :; }; shift; main "$@"',
                "prompt-inplace",
                str(SCRIPT),
            ],
            cwd=self.root,
            env=env,
            steps=[
                ("Google OAuth client_id:", "cid-inplace"),
                ("Google OAuth client_secret:", "csec-inplace"),
                ("Google OAuth refresh_token", "1//fresh-inplace-rt"),
                ("restic 暗号化パスワードを入力してください", "pw-inplace"),
            ],
        )
        self.assertEqual(consumed, 4, output)
        self.assertEqual(rc, 0, output)
        self.assertIn(SUCCESS, output)
        self.assertIn("--impure", output)

        self.assertEqual(
            (target_home / "MySettings" / "existing.txt").read_text(encoding="utf-8"),
            "restored checkout\n",
        )
        self.assertEqual(
            (target_home / "unbacked-local-keep.txt").read_text(encoding="utf-8"),
            "keep unbacked\n",
        )
        self.assertFalse((target_home / "hm-dir-link").is_symlink())
        self.assertEqual(
            (target_home / "hm-dir-link" / "real.txt").read_text(encoding="utf-8"),
            "inside restored dir\n",
        )
        self.assertEqual(
            (outside_dir / "store-file.txt").read_text(encoding="utf-8"),
            "from store\n",
        )
        self.assertTrue((target_home / "dir-becomes-file").is_file())
        self.assertEqual(
            (target_home / "dir-becomes-file").read_text(encoding="utf-8"),
            "now a file\n",
        )
        self.assertEqual(
            (target_home / "ro_existing" / "item").read_text(encoding="utf-8"),
            "new secret\n",
        )
        self.assertEqual(stat.S_IMODE((target_home / "ro_existing" / "item").stat().st_mode), 0o400)
        self.assertEqual(stat.S_IMODE((target_home / "ro_existing").stat().st_mode), 0o500)
        self.assertEqual(
            (target_home / "Documents" / "hiragino-otf" / "Hiragino.otf").read_bytes(),
            b"OTF\x00data",
        )

        rclone_conf = target_home / ".config" / "rclone" / "rclone.conf"
        self.assertEqual(stat.S_IMODE(rclone_conf.stat().st_mode), 0o600)
        gdrive = self.dump_gdrive(rclone_conf)
        self.assertEqual(gdrive["client_id"], "cid-inplace")
        self.assertEqual(json.loads(gdrive["token"])["refresh_token"], "1//fresh-inplace-rt")

        self.assertEqual(
            (nm_dest / "home-wifi.nmconnection").read_text(encoding="utf-8"),
            "[connection]\nid=home\n",
        )
        self.assertEqual(stat.S_IMODE((nm_dest / "home-wifi.nmconnection").stat().st_mode), 0o600)
        self.assertEqual(
            (nm_dest / "current.nmconnection").read_text(encoding="utf-8"),
            "current wifi\n",
        )
        self.assertEqual(
            (restore_root / "var/lib/bluetooth/AA:BB/info").read_text(encoding="utf-8"),
            "[General]\nName=Headphones\n",
        )
        self.assertEqual(
            (restore_root / "var/lib/tailscale/tailscaled.state").read_text(encoding="utf-8"),
            "ts-state\n",
        )
        self.assertFalse((restore_root / "var/lib/cloudflare-warp").exists())

        sudo_calls = self.sudo_log.read_text(encoding="utf-8")
        self.assertIn(f"chown -R root:root -- {nm_dest}", sudo_calls)
        self.assertIn(f"chown -R root:root -- {restore_root}/var/lib/bluetooth", sudo_calls)
        self.assertIn(f"chown -R root:root -- {restore_root}/var/lib/tailscale", sudo_calls)
        self.assertNotIn("cloudflare-warp", sudo_calls)
        self.assertEqual(list(self.stage_parent.iterdir()), [])

    def test_pty_oauth_reconnect_in_place_preserves_reconnected_rclone(self):
        restore_root = self.root / "restore-root"
        target_home = restore_root / "home" / "mitac"
        conf = target_home / ".config" / "rclone" / "rclone.conf"
        conf.parent.mkdir(parents=True)
        conf.touch()
        conf.chmod(0o600)
        subprocess.run(
            [
                self.real_rclone,
                "config",
                "create",
                "gdrive",
                "drive",
                "client_id",
                "cid-keep",
                "client_secret",
                "csec-keep",
                "scope",
                "drive",
                "token",
                json.dumps(
                    {
                        "access_token": "x",
                        "token_type": "Bearer",
                        "refresh_token": "1//revoked",
                        "expiry": "2000-01-01T00:00:00Z",
                    }
                ),
                "config_refresh_token",
                "false",
                "config_is_local",
                "false",
            ],
            env=dict(self.environment, RCLONE_CONFIG=str(conf)),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True,
        )

        fixture = self.root / "fixture-stage"
        (fixture / "home" / "mitac" / ".config" / "rclone").mkdir(parents=True)
        (fixture / "home" / "mitac" / ".config" / "rclone" / "rclone.conf").write_text(
            "[gdrive]\ntype = drive\nclient_id = old-snap\n", encoding="utf-8"
        )

        new_token = json.dumps(
            {
                "access_token": "new-acc",
                "token_type": "Bearer",
                "refresh_token": "1//reconnected-inplace",
                "expiry": "2031-01-01T00:00:00Z",
            }
        )
        env = dict(
            self.environment,
            HOME=str(target_home),
            RESTORE_ROOT=str(restore_root),
            FIXTURE_STAGE_TREE=str(fixture),
            EXPECTED_RESTIC_PASSWORD="pw-rec",
            SIMULATE_ABOUT_REQUIRE_TOKEN="1//reconnected-inplace",
            SIMULATE_OAUTH_TOKEN=new_token,
        )
        rc, output, consumed = run_in_pty(
            [
                "bash",
                "-c",
                'source "$1"; check_platform() { :; }; shift; main "$@"',
                "prompt-reconnect-inplace",
                str(SCRIPT),
            ],
            cwd=self.root,
            env=env,
            steps=[
                ("[b/r/o/t/q]:", "o"),
                ("restic 暗号化パスワードを入力してください", "pw-rec"),
            ],
        )
        self.assertEqual(consumed, 2, output)
        self.assertEqual(rc, 0, output)
        gdrive = self.dump_gdrive(conf)
        self.assertEqual(gdrive["client_id"], "cid-keep")
        self.assertEqual(json.loads(gdrive["token"])["refresh_token"], "1//reconnected-inplace")

    def test_in_place_overwrites_rclone_conf_when_existing_remote_reused(self):
        restore_root = self.root / "restore-root"
        target_home = restore_root / "home" / "mitac"
        conf = target_home / ".config" / "rclone" / "rclone.conf"
        conf.parent.mkdir(parents=True)
        conf.write_text("[gdrive]\ntype = local\n", encoding="utf-8")
        conf.chmod(0o600)

        fixture = self.root / "fixture-stage"
        (fixture / "home" / "mitac" / ".config" / "rclone").mkdir(parents=True)
        snapshot_conf = "[gdrive]\ntype = drive\nclient_id = from-snapshot\n"
        (fixture / "home" / "mitac" / ".config" / "rclone" / "rclone.conf").write_text(
            snapshot_conf, encoding="utf-8"
        )

        env = dict(
            self.environment,
            HOME=str(target_home),
            RESTORE_ROOT=str(restore_root),
            FIXTURE_STAGE_TREE=str(fixture),
            RESTIC_PASSWORD="correct-pw",
        )
        result = subprocess.run(
            [
                "bash",
                "-c",
                'source "$1"; check_platform() { :; }; shift; main "$@"',
                "prompt-overwrite-rclone",
                str(SCRIPT),
            ],
            cwd=self.root,
            env=env,
            stdin=subprocess.DEVNULL,
            text=True,
            capture_output=True,
            timeout=15,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(conf.read_text(encoding="utf-8"), snapshot_conf)

    def test_in_place_failure_leaves_original_locations_and_stage_intact(self):
        restore_root = self.root / "restore-root"
        target_home = restore_root / "home" / "mitac"
        conf = target_home / ".config" / "rclone" / "rclone.conf"
        conf.parent.mkdir(parents=True)
        conf.write_text("[gdrive]\ntype = local\n", encoding="utf-8")
        conf.chmod(0o600)
        keep_file = target_home / "MySettings" / "keep.txt"
        keep_file.parent.mkdir(parents=True)
        keep_file.write_text("local state\n", encoding="utf-8")

        env = dict(
            self.environment,
            HOME=str(target_home),
            RESTORE_ROOT=str(restore_root),
            RESTIC_PASSWORD="correct-pw",
            SIMULATE_RESTORE_FAIL="1",
        )
        result = subprocess.run(
            [
                "bash",
                "-c",
                'source "$1"; check_platform() { :; }; shift; main "$@"',
                "prompt-fail-inplace",
                str(SCRIPT),
            ],
            cwd=self.root,
            env=env,
            stdin=subprocess.DEVNULL,
            text=True,
            capture_output=True,
            timeout=15,
        )
        self.assertEqual(result.returncode, 23, result.stdout + result.stderr)
        self.assertEqual(keep_file.read_text(encoding="utf-8"), "local state\n")
        self.assertFalse(self.sudo_log.exists())
        staged_dirs = list(self.stage_parent.iterdir())
        self.assertEqual(len(staged_dirs), 1)
        self.assertTrue(staged_dirs[0].name.startswith("restore-mitac-"))

    def test_pty_rbw_auto_config_gui_custom_fields_verbatim_password_spaces(self):
        self.write_rbw_item(
            {
                "data": {"password": "  pw with leading and trailing spaces  "},
                "fields": [
                    {"name": "Client ID", "value": "  cid-from-field  "},
                    {"name": "client-secret", "value": " csec-from-field "},
                    {"name": "Refresh Token", "value": "1//field-rt"},
                ],
                "notes": (
                    "client_id: ignored-note-cid\n"
                    "client_secret: ignored-note-csec\n"
                    "refresh_token: 1//ignored-note-rt\n"
                ),
            }
        )
        env = self.rbw_env(
            DISPLAY=":0",
            EXPECTED_RESTIC_PASSWORD="  pw with leading and trailing spaces  ",
            SIMULATE_ABOUT_REQUIRE_TOKEN="1//field-rt",
        )
        rc, output, consumed = run_in_pty(
            [
                "bash",
                "-c",
                'source "$1"; check_platform() { :; }; shift; main "$@"',
                "rbw-gui-custom",
                str(SCRIPT),
                str(self.target),
            ],
            cwd=self.root,
            env=env,
            steps=[
                ("Bitwarden (rbw) から項目 'restic-home' の設定・鍵を自動取得しますか？ [Y/n]", ""),
                ("Bitwarden メールアドレス [Enter で mitac31709@gmail.com]:", ""),
            ],
        )
        self.assertEqual(consumed, 2, output)
        self.assertEqual(rc, 0, output)
        self.assertIn(SUCCESS, output)
        self.assertNotIn("Google OAuth client_id", output)
        self.assertNotIn("入力は非表示", output)

        rbw_cfg = self.read_rbw_config()
        self.assertEqual(rbw_cfg["email"], "mitac31709@gmail.com")
        self.assertEqual(rbw_cfg["base_url"], "https://api.bitwarden.eu")
        self.assertEqual(rbw_cfg["identity_url"], "https://identity.bitwarden.eu")
        self.assertEqual(rbw_cfg["ui_url"], "https://vault.bitwarden.eu")
        self.assertEqual(rbw_cfg["notifications_url"], "https://notifications.bitwarden.eu")
        self.assertEqual(rbw_cfg["pinentry"], str(self.bin / "pinentry-qt"))

        log = self.read_rbw_log()
        self.assertIn("stop-agent", log)
        self.assertIn("login", log)
        self.assertIn("unlock", log)
        self.assertIn("sync", log)
        self.assertIn("get --raw restic-home", log)

        conf = self.home / ".config" / "rclone" / "rclone.conf"
        self.assertEqual(stat.S_IMODE(conf.stat().st_mode), 0o600)
        gdrive = self.dump_gdrive(conf)
        self.assertEqual(gdrive["client_id"], "cid-from-field")
        self.assertEqual(gdrive["client_secret"], "csec-from-field")
        self.assertEqual(json.loads(gdrive["token"])["refresh_token"], "1//field-rt")
        self.assertIn(
            "PW=  pw with leading and trailing spaces  \n",
            self.capture.read_text(encoding="utf-8"),
        )

    def test_pty_rbw_headless_pinentry_curses_notes_crlf_and_custom_item(self):
        self.write_rbw_item(
            {
                "data": {"password": "pw-notes-crlf"},
                "fields": [{"name": "refresh_token", "value": "(未設定)"}],
                "notes": (
                    "client_id: \"cid-from-notes\"\r\n"
                    "  client_secret = 'csec-from-notes'\r\n"
                    "refresh_token: (not set)\r\n"
                    "token: <replace me>\r\n"
                    "- token: {\"refresh_token\":\"1//notes-tok\"}\r\n"
                ),
            }
        )
        env = self.rbw_env(
            RBW_ITEM="alt-backup-item",
            RBW_EXPECTED_ITEM="alt-backup-item",
            EXPECTED_RESTIC_PASSWORD="pw-notes-crlf",
            SIMULATE_ABOUT_REQUIRE_TOKEN="1//notes-tok",
        )
        rc, output, consumed = run_in_pty(
            [
                "bash",
                "-c",
                'source "$1"; check_platform() { :; }; shift; main "$@"',
                "rbw-headless-notes",
                str(SCRIPT),
                str(self.target),
            ],
            cwd=self.root,
            env=env,
            steps=[
                ("Bitwarden (rbw) から項目 'alt-backup-item' の設定・鍵を自動取得しますか？ [Y/n]", "y"),
                ("Bitwarden メールアドレス [Enter で mitac31709@gmail.com]:", "custom@example.org"),
            ],
        )
        self.assertEqual(consumed, 2, output)
        self.assertEqual(rc, 0, output)
        self.assertIn(SUCCESS, output)

        rbw_cfg = self.read_rbw_config()
        self.assertEqual(rbw_cfg["email"], "custom@example.org")
        self.assertEqual(rbw_cfg["pinentry"], str(self.bin / "pinentry-curses"))

        conf = self.home / ".config" / "rclone" / "rclone.conf"
        gdrive = self.dump_gdrive(conf)
        self.assertEqual(gdrive["client_id"], "cid-from-notes")
        self.assertEqual(gdrive["client_secret"], "csec-from-notes")
        self.assertEqual(json.loads(gdrive["token"])["refresh_token"], "1//notes-tok")

    def test_non_tty_preunlocked_rbw_restores_without_prompts(self):
        self.write_rbw_config(
            {
                "email": "mitac31709@gmail.com",
                "base_url": "https://api.bitwarden.eu",
                "pinentry": str(self.bin / "pinentry-curses"),
            }
        )
        (self.rbw_state / "unlocked").touch()
        self.write_rbw_item(
            {
                "data": {"password": "pw-preunlocked"},
                "notes": (
                    "  client_id: cid-pre\n"
                    "  client_secret: csec-pre\n"
                    "  refresh_token: 1//pre-rt\n"
                ),
            }
        )
        env = self.rbw_env(
            EXPECTED_RESTIC_PASSWORD="pw-preunlocked",
            SIMULATE_ABOUT_REQUIRE_TOKEN="1//pre-rt",
        )
        result = subprocess.run(
            [
                "bash",
                "-c",
                'source "$1"; check_platform() { :; }; shift; main "$@"',
                "rbw-nontty-unlocked",
                str(SCRIPT),
                str(self.target),
            ],
            cwd=self.root,
            env=env,
            stdin=subprocess.DEVNULL,
            text=True,
            capture_output=True,
            timeout=15,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(SUCCESS, result.stdout)
        self.assertIn("Bitwarden (restic-home) から gdrive: を自動設定しました。", result.stderr)

    def test_pty_readonly_hm_rbw_config_skips_config_set(self):
        store_cfg = self.root / "store-rbw-config.json"
        hm_cfg = {
            "email": "mitac31709@gmail.com",
            "base_url": "https://api.bitwarden.eu",
            "identity_url": "https://identity.bitwarden.eu",
            "ui_url": "https://vault.bitwarden.eu",
            "notifications_url": "https://notifications.bitwarden.eu",
            "pinentry": str(self.bin / "pinentry-qt"),
        }
        store_cfg.write_text(json.dumps(hm_cfg), encoding="utf-8")
        store_cfg.chmod(0o444)
        self.addCleanup(store_cfg.chmod, 0o600)
        hm_link = self.home / ".config" / "rbw" / "config.json"
        hm_link.parent.mkdir(parents=True)
        hm_link.symlink_to(store_cfg)

        self.write_rbw_config(hm_cfg)
        self.write_rbw_item(
            {
                "data": {"password": "pw-hm"},
                "notes": (
                    "client_id: cid-hm\n"
                    "client_secret: csec-hm\n"
                    "refresh_token: 1//hm-rt\n"
                ),
            }
        )
        env = self.rbw_env(
            DISPLAY=":0",
            EXPECTED_RESTIC_PASSWORD="pw-hm",
            SIMULATE_ABOUT_REQUIRE_TOKEN="1//hm-rt",
        )
        rc, output, consumed = run_in_pty(
            [
                "bash",
                "-c",
                'source "$1"; check_platform() { :; }; shift; main "$@"',
                "rbw-hm-ro",
                str(SCRIPT),
                str(self.target),
            ],
            cwd=self.root,
            env=env,
            steps=[
                ("Bitwarden (rbw) から項目 'restic-home' の設定・鍵を自動取得しますか？ [Y/n]", ""),
            ],
        )
        self.assertEqual(consumed, 1, output)
        self.assertEqual(rc, 0, output)
        self.assertIn(SUCCESS, output)
        log = self.read_rbw_log()
        self.assertFalse(any(line.startswith("config set ") for line in log), log)

    def test_pty_rbw_partial_item_prefills_and_oauth_reconnect(self):
        self.write_rbw_config(
            {
                "email": "mitac31709@gmail.com",
                "base_url": "https://api.bitwarden.eu",
                "pinentry": str(self.bin / "pinentry-qt"),
            }
        )
        self.write_rbw_item(
            {
                "data": {"password": "pw-partial"},
                "notes": (
                    "  client_id: cid-partial-123456\n"
                    "  client_secret: csec-partial\n"
                    "  refresh_token: (未設定)\n"
                ),
            }
        )
        oauth_token = json.dumps(
            {
                "access_token": "oauth-acc",
                "token_type": "Bearer",
                "refresh_token": "1//partial-reconnected",
                "expiry": "2031-01-01T00:00:00Z",
            }
        )
        env = self.rbw_env(
            DISPLAY=":0",
            EXPECTED_RESTIC_PASSWORD="pw-partial",
            SIMULATE_OAUTH_TOKEN=oauth_token,
            SIMULATE_ABOUT_REQUIRE_TOKEN="1//partial-reconnected",
        )
        rc, output, consumed = run_in_pty(
            [
                "bash",
                "-c",
                'source "$1"; check_platform() { :; }; shift; main "$@"',
                "rbw-partial",
                str(SCRIPT),
                str(self.target),
            ],
            cwd=self.root,
            env=env,
            steps=[
                ("Bitwarden (rbw) から項目 'restic-home' の設定・鍵を自動取得しますか？ [Y/n]", ""),
                ("[Enter で維持: cid-partial-...]:", ""),
                ("[Enter で既存値を維持]:", ""),
                ("Google OAuth refresh_token", ""),
            ],
        )
        self.assertEqual(consumed, 4, output)
        self.assertEqual(rc, 0, output)
        self.assertIn(SUCCESS, output)
        self.assertNotIn("入力は非表示", output)
        conf = self.home / ".config" / "rclone" / "rclone.conf"
        gdrive = self.dump_gdrive(conf)
        self.assertEqual(gdrive["client_id"], "cid-partial-123456")
        self.assertEqual(gdrive["client_secret"], "csec-partial")
        self.assertEqual(json.loads(gdrive["token"])["refresh_token"], "1//partial-reconnected")

    def test_pty_rbw_login_failure_recovers_via_register(self):
        self.write_rbw_config(
            {
                "email": "mitac31709@gmail.com",
                "base_url": "https://api.bitwarden.eu",
                "pinentry": str(self.bin / "pinentry-qt"),
            }
        )
        self.write_rbw_item(
            {
                "data": {"password": "pw-reg"},
                "notes": (
                    "client_id: cid-reg\n"
                    "client_secret: csec-reg\n"
                    "refresh_token: 1//reg-rt\n"
                ),
            }
        )
        env = self.rbw_env(
            DISPLAY=":0",
            RBW_SHIM_NEED_REGISTER="1",
            EXPECTED_RESTIC_PASSWORD="pw-reg",
            SIMULATE_ABOUT_REQUIRE_TOKEN="1//reg-rt",
        )
        rc, output, consumed = run_in_pty(
            [
                "bash",
                "-c",
                'source "$1"; check_platform() { :; }; shift; main "$@"',
                "rbw-register-recover",
                str(SCRIPT),
                str(self.target),
            ],
            cwd=self.root,
            env=env,
            steps=[
                ("Bitwarden (rbw) から項目 'restic-home' の設定・鍵を自動取得しますか？ [Y/n]", ""),
                ("[r/l/m/q]:", "r"),
            ],
        )
        self.assertEqual(consumed, 2, output)
        self.assertEqual(rc, 0, output)
        self.assertIn(SUCCESS, output)
        self.assertIn("register", self.read_rbw_log())

    def test_pty_rbw_probe_failure_resync_in_place_preserves_new_rclone(self):
        restore_root = self.root / "restore-root"
        target_home = restore_root / "home" / "mitac"
        conf = target_home / ".config" / "rclone" / "rclone.conf"
        conf.parent.mkdir(parents=True)
        conf.touch()
        conf.chmod(0o600)
        subprocess.run(
            [
                self.real_rclone,
                "config",
                "create",
                "gdrive",
                "drive",
                "client_id",
                "cid-stale",
                "client_secret",
                "csec-stale",
                "scope",
                "drive",
                "token",
                json.dumps(
                    {
                        "access_token": "x",
                        "token_type": "Bearer",
                        "refresh_token": "1//stale-rt",
                        "expiry": "2000-01-01T00:00:00Z",
                    }
                ),
                "config_refresh_token",
                "false",
                "config_is_local",
                "false",
            ],
            env=dict(self.environment, RCLONE_CONFIG=str(conf)),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True,
        )

        self.write_rbw_config(
            {
                "email": "mitac31709@gmail.com",
                "base_url": "https://api.bitwarden.eu",
                "pinentry": str(self.bin / "pinentry-qt"),
            }
        )
        self.write_rbw_item(
            {
                "data": {"password": "pw-before-sync"},
                "notes": (
                    "client_id: cid-stale\n"
                    "client_secret: csec-stale\n"
                    "refresh_token: 1//stale-rt\n"
                ),
            }
        )
        resync_item = self.write_rbw_item(
            {
                "data": {"password": "pw-after-sync"},
                "notes": (
                    "client_id: cid-resynced\n"
                    "client_secret: csec-resynced\n"
                    "refresh_token: 1//resynced-rt\n"
                ),
            },
            filename="item-resync.json",
        )
        # Simulate user previously unlocked agent before updating Bitwarden on another device.
        (self.rbw_state / "unlocked").touch()
        (self.rbw_state / "first-sync-done").touch()

        fixture = self.root / "fixture-stage"
        (fixture / "home" / "mitac" / ".config" / "rclone").mkdir(parents=True)
        (fixture / "home" / "mitac" / ".config" / "rclone" / "rclone.conf").write_text(
            "[gdrive]\ntype = drive\nclient_id = stale-from-snapshot\n", encoding="utf-8"
        )

        env = self.rbw_env(
            HOME=str(target_home),
            RESTORE_ROOT=str(restore_root),
            FIXTURE_STAGE_TREE=str(fixture),
            DISPLAY=":0",
            RBW_RESYNC_ITEM_FILE=str(resync_item),
            EXPECTED_RESTIC_PASSWORD="pw-after-sync",
            SIMULATE_ABOUT_REQUIRE_TOKEN="1//resynced-rt",
        )
        rc, output, consumed = run_in_pty(
            [
                "bash",
                "-c",
                'source "$1"; check_platform() { :; }; shift; main "$@"',
                "rbw-resync-inplace",
                str(SCRIPT),
            ],
            cwd=self.root,
            env=env,
            steps=[
                ("[b/r/o/t/q]:", "b"),
            ],
        )
        self.assertEqual(consumed, 1, output)
        self.assertEqual(rc, 0, output)
        self.assertIn(SUCCESS, output)
        gdrive = self.dump_gdrive(conf)
        self.assertEqual(gdrive["client_id"], "cid-resynced")
        self.assertEqual(gdrive["client_secret"], "csec-resynced")
        self.assertEqual(json.loads(gdrive["token"])["refresh_token"], "1//resynced-rt")

    def test_pty_rbw_wrong_password_resync_recovers(self):
        self.write_rbw_config(
            {
                "email": "mitac31709@gmail.com",
                "base_url": "https://api.bitwarden.eu",
                "pinentry": str(self.bin / "pinentry-qt"),
            }
        )
        self.write_rbw_item(
            {
                "data": {"password": "old-wrong-password"},
                "notes": (
                    "client_id: cid-pw\n"
                    "client_secret: csec-pw\n"
                    "refresh_token: 1//pw-rt\n"
                ),
            }
        )
        resync_item = self.write_rbw_item(
            {
                "data": {"password": "updated-right-password"},
                "notes": (
                    "client_id: cid-pw\n"
                    "client_secret: csec-pw\n"
                    "refresh_token: 1//pw-rt\n"
                ),
            },
            filename="item-pw-resync.json",
        )
        env = self.rbw_env(
            DISPLAY=":0",
            RBW_RESYNC_ITEM_FILE=str(resync_item),
            EXPECTED_RESTIC_PASSWORD="updated-right-password",
            SIMULATE_ABOUT_REQUIRE_TOKEN="1//pw-rt",
        )
        rc, output, consumed = run_in_pty(
            [
                "bash",
                "-c",
                'source "$1"; check_platform() { :; }; shift; main "$@"',
                "rbw-pw-resync",
                str(SCRIPT),
                str(self.target),
            ],
            cwd=self.root,
            env=env,
            steps=[
                ("Bitwarden (rbw) から項目 'restic-home' の設定・鍵を自動取得しますか？ [Y/n]", ""),
                ("[b/m/q]:", "b"),
            ],
        )
        self.assertEqual(consumed, 2, output)
        self.assertEqual(rc, 0, output)
        self.assertIn(SUCCESS, output)
        self.assertIn("PW=updated-right-password\n", self.capture.read_text(encoding="utf-8"))

    def test_pty_rbw_empty_password_manual_fallback(self):
        self.write_rbw_config(
            {
                "email": "mitac31709@gmail.com",
                "base_url": "https://api.bitwarden.eu",
                "pinentry": str(self.bin / "pinentry-qt"),
            }
        )
        self.write_rbw_item(
            {
                "data": {"password": ""},
                "notes": (
                    "client_id: cid-epw\n"
                    "client_secret: csec-epw\n"
                    "refresh_token: 1//epw-rt\n"
                ),
            }
        )
        env = self.rbw_env(
            DISPLAY=":0",
            EXPECTED_RESTIC_PASSWORD="manual-fallback-password",
            SIMULATE_ABOUT_REQUIRE_TOKEN="1//epw-rt",
        )
        rc, output, consumed = run_in_pty(
            [
                "bash",
                "-c",
                'source "$1"; check_platform() { :; }; shift; main "$@"',
                "rbw-empty-pw-manual",
                str(SCRIPT),
                str(self.target),
            ],
            cwd=self.root,
            env=env,
            steps=[
                ("Bitwarden (rbw) から項目 'restic-home' の設定・鍵を自動取得しますか？ [Y/n]", ""),
                ("[b/m/q]:", "m"),
                ("restic 暗号化パスワードを入力してください", "manual-fallback-password"),
            ],
        )
        self.assertEqual(consumed, 3, output)
        self.assertEqual(rc, 0, output)
        self.assertIn(SUCCESS, output)
        self.assertIn(
            "PW=manual-fallback-password\n", self.capture.read_text(encoding="utf-8")
        )

    def test_pty_declining_rbw_falls_back_to_manual_without_reprompt(self):
        env = self.rbw_env(
            EXPECTED_RESTIC_PASSWORD="declined-manual-pw",
            SIMULATE_ABOUT_REQUIRE_TOKEN="1//declined-rt",
        )
        rc, output, consumed = run_in_pty(
            [
                "bash",
                "-c",
                'source "$1"; check_platform() { :; }; shift; main "$@"',
                "rbw-decline",
                str(SCRIPT),
                str(self.target),
            ],
            cwd=self.root,
            env=env,
            steps=[
                ("Bitwarden (rbw) から項目 'restic-home' の設定・鍵を自動取得しますか？ [Y/n]", "n"),
                ("Google OAuth client_id:", "cid-manual"),
                ("Google OAuth client_secret:", "csec-manual"),
                ("Google OAuth refresh_token", "1//declined-rt"),
                ("restic 暗号化パスワードを入力してください", "declined-manual-pw"),
            ],
        )
        self.assertEqual(consumed, 5, output)
        self.assertEqual(rc, 0, output)
        self.assertIn(SUCCESS, output)
        self.assertEqual(output.count("自動取得しますか？"), 1, output)
        log = self.read_rbw_log()
        self.assertNotIn("login", log)
        self.assertNotIn("unlock", log)

    def test_pty_missing_rbw_on_non_nix_host_falls_back_to_manual(self):
        (self.bin / "rbw").unlink()
        clean_dirs = [
            d
            for d in os.environ["PATH"].split(os.pathsep)
            if d and not (Path(d) / "rbw").exists() and not (Path(d) / "nix").exists()
        ]
        env = self.rbw_env(
            PATH=f"{self.bin}:{os.pathsep.join(clean_dirs)}",
            EXPECTED_RESTIC_PASSWORD="no-rbw-manual-pw",
            SIMULATE_ABOUT_REQUIRE_TOKEN="1//no-rbw-rt",
        )
        rc, output, consumed = run_in_pty(
            [
                "bash",
                "-c",
                'source "$1"; check_platform() { :; }; shift; main "$@"',
                "no-rbw-fallback",
                str(SCRIPT),
                str(self.target),
            ],
            cwd=self.root,
            env=env,
            steps=[
                ("Google OAuth client_id:", "cid-norbw"),
                ("Google OAuth client_secret:", "csec-norbw"),
                ("Google OAuth refresh_token", "1//no-rbw-rt"),
                ("restic 暗号化パスワードを入力してください", "no-rbw-manual-pw"),
            ],
        )
        self.assertEqual(consumed, 4, output)
        self.assertEqual(rc, 0, output)
        self.assertIn(SUCCESS, output)
        self.assertNotIn("Bitwarden (rbw) から項目", output)


if __name__ == "__main__":
    unittest.main()
