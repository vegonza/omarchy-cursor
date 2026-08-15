import importlib.util
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "cursor_projects.py"
SPEC = importlib.util.spec_from_file_location("cursor_projects", MODULE_PATH)
assert SPEC and SPEC.loader
cursor_projects = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(cursor_projects)


class CursorProjectsTest(unittest.TestCase):
    def test_local_remote_workspace_and_deduplication(self):
        with tempfile.TemporaryDirectory() as temporary_dir:
            home = Path(temporary_dir)
            local_project = home / "work/pan"
            local_project.mkdir(parents=True)
            workspace = home / "work/pan.code-workspace"
            workspace.write_text("{}", encoding="utf-8")
            missing = home / "work/missing"
            ssh_authority = json.dumps({"hostName": "clover-apps"}).encode().hex()
            ssh_uri = (
                f"vscode-remote://ssh-remote%2B{ssh_authority}"
                "/home/ubuntu/clover"
            )

            payload = {
                "entries": [
                    {"folderUri": local_project.as_uri()},
                    {"folderUri": local_project.as_uri()},
                    {"folderUri": missing.as_uri()},
                    {
                        "workspace": {"configPath": workspace.as_uri()},
                        "label": "Pan workspace",
                    },
                    {"folderUri": ssh_uri},
                    {"fileUri": (local_project / "README.md").as_uri()},
                ]
            }

            projects = cursor_projects.projects_from_payload(payload, home=home)

            self.assertEqual(3, len(projects))
            self.assertEqual("pan", projects[0]["name"])
            self.assertEqual("~/work/pan", projects[0]["detail"])
            self.assertEqual("Workspace", projects[1]["projectType"])
            self.assertEqual("SSH", projects[2]["projectType"])
            self.assertEqual(
                "clover-apps · /home/ubuntu/clover", projects[2]["detail"]
            )
            self.assertTrue(projects[2]["remote"])

    def test_reads_the_cursor_database_read_only(self):
        with tempfile.TemporaryDirectory() as temporary_dir:
            root = Path(temporary_dir)
            project = root / "project"
            project.mkdir()
            database = root / "state.vscdb"
            with sqlite3.connect(database) as connection:
                connection.execute("CREATE TABLE ItemTable (key TEXT, value TEXT)")
                connection.execute(
                    "INSERT INTO ItemTable VALUES (?, ?)",
                    (
                        cursor_projects.RECENT_PROJECTS_KEY,
                        json.dumps({"entries": [{"folderUri": project.as_uri()}]}),
                    ),
                )

            projects = cursor_projects.read_recent_projects(database)

            self.assertEqual(str(project), projects[0]["target"])
            self.assertFalse(projects[0]["remote"])

    def test_rejects_an_unexpected_payload_shape(self):
        with self.assertRaises(cursor_projects.ProjectReadError):
            cursor_projects.projects_from_payload([])

    def test_tolerates_non_object_ssh_authority_metadata(self):
        encoded_authority = json.dumps([]).encode().hex()
        uri = f"vscode-remote://ssh-remote%2B{encoded_authority}/srv/project"

        projects = cursor_projects.projects_from_payload(
            {"entries": [{"folderUri": uri}]}
        )

        self.assertEqual("SSH", projects[0]["projectType"])
        self.assertEqual("remote · /srv/project", projects[0]["detail"])


if __name__ == "__main__":
    unittest.main()
