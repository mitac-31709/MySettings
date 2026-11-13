#!/usr/bin/env python3
"""Exercise restore-on-nixos.sh with a real, disposable local backup.

Requires restic, rclone, and jq on PATH. No Google or Bitwarden access is used.
"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().with_name("restore-on-nixos.sh")
SUCCESS = "Restore and verification completed."


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
            if not key.startswith(("RESTIC_", "RCLONE_"))
        }
        cls.environment.update(
            HOME=str(cls.home),
            XDG_CACHE_HOME=str(cls.root / "cache"),
            RCLONE_CONFIG=str(cls.config),
            RESTIC_CACHE_DIR=str(cls.root / "restic-cache"),
            RESTIC_PASSWORD="disposable-local-fixture-password",
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


if __name__ == "__main__":
    unittest.main()
