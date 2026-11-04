# Testing and release

## Fast checks

Run validation from the repository:

```powershell
py -3 -X utf8 C:\Users\Administrator\.codex\skills\freecad-plugin-dev\scripts\validate_addon.py `
  F:\Codex\Freecad\plugins\<addon-id>
```

The validator exits with status 0 only when metadata, workbench entry point, Python syntax, and the FreeCADCmd smoke check pass. Use `--freecad-cmd` when FreeCAD is installed somewhere other than the default. Use `--skip-freecad` only for a quick metadata/syntax pass; it is not a release check.

Run pure-Python tests from the plugin directory:

```powershell
py -3 -m unittest discover -s tests -v
```

The template's tests must not import `FreeCAD`, `FreeCADGui`, `PySide`, or `shiboken`.

## FreeCADCmd smoke test

The validator starts the installed FreeCAD Python and imports the root `core` module or the plugin's single top-level Python package when one exists. For a manual check:

```powershell
& 'C:\Program Files\FreeCAD 1.1\bin\FreeCADCmd.exe' -c `
  "import sys; sys.path.insert(0, r'F:\Codex\Freecad\plugins\<addon-id>'); from <python_package> import core; print(core.format_message('FreeCAD'))"
```

Exercise geometry or document APIs with a temporary document, then close it without saving. Do not leave test documents or backup files in the user's open documents.

`FreeCADCmd.exe script.py` executes the file with `__name__` set to the **file stem**, not `"__main__"`. Call the test entry point unconditionally, or check `if __name__ in ("__main__", Path(__file__).stem)`. A script that only has `if __name__ == "__main__": main()` will silently do nothing under FreeCADCmd.

Add a save/reload smoke check for every new `FeaturePython` object:

1. create the object and force `doc.recompute()`;
2. `doc.saveAs(temp_file)`, close, reopen;
3. `doc.getObject(...)`, call `recompute()`, and assert the shape/children still exist;
4. change one parameter and assert it rebuilds.

The reload pass catches missing `__setstate__` initialization and broken cross-object references.

## GUI automation

For repeatable GUI acceptance without a human, start `FreeCAD.exe` with a Python script and drive it with `QTimer`:

```powershell
& 'C:\Program Files\FreeCAD 1.1\bin\FreeCAD.exe' "F:\path\to\gui_smoke.py"
```

At the end of the script schedule `Gui.getMainWindow().close()`; use `QTimer.singleShot(3000, run)` so the main window and workbench are initialized before creating objects. Save a screenshot with `Gui.activeDocument().activeView().saveImage(path, width, height, "Current")`.

For a command with a modal dialog:

- `Gui.runCommand(...)` invoked from a `QTimer` callback can return before the command actually runs; do not treat that as success.
- A deterministic alternative is to instantiate the command object and call `command.Activated()` directly, then use a second `QTimer` to find the **visible** dialog and accept it.
- Filter top-level widgets with `widget.isVisible()`; stale, closed dialogs stay in `QApplication.topLevelWidgets()` and can be mistaken for the current dialog.
- After the command returns, assert the object count and inspect the child shapes.

Do not print `⌀` or `Ø` to FreeCADCmd on a Chinese Windows console: the GBK codec cannot encode them and the script can abort. Use `Φ` (U+03A6) or plain `D12`, and write UTF-8 logs to files when symbols are needed. Chinese summary strings printed to the console may look mojibake; that is a console-encoding artifact, not necessarily a data error.

## GUI acceptance checklist

1. Mount the plugin with `dev_link.ps1` and start `FreeCAD.exe`.
2. Confirm that the workbench appears and that selecting it does not raise an exception.
3. Open or create a document, run each new command, and verify the intended result, undo, and redo.
4. Close and reopen FreeCAD, then repeat the workbench and command check to catch import-order and registration problems.
5. Test the no-document state and confirm document-dependent commands are disabled rather than crashing.
6. For panels, confirm close/reopen behavior, selection changes, save/reload, and resizing.
7. Remove the development link with `-Remove` when finished if the plugin should not remain installed.

## Git delivery

Inspect the branch and scope before committing:

```powershell
git status --short --branch
git diff --check
git diff --stat
```

Create a branch from `main`; never push plugin code directly to `main`:

```powershell
git switch -c feat/<addon-id>-<topic>
git add plugins/<addon-id>
git commit -m "feat(<addon-id>): <summary>"
git push -u origin feat/<addon-id>-<topic>
```

Use `fix`, `test`, `docs`, or `chore` instead of `feat` when that better describes the change. If the branch already exists, do not reset it or force-push over unknown work; inspect it and choose a new branch name when needed.

`gh` is not installed on this machine. After the push, report this compare URL for PR creation:

```text
https://github.com/LuckyMian/FreeCad_Plugins/compare/main...<branch>?expand=1
```

Confirm the pushed commit with `git ls-remote --heads origin <branch>` or the GitHub compare page. A local commit is not delivery.

## Release criteria

- `package.xml` version and date are intentional, and the repository URL is `https://github.com/LuckyMian/FreeCad_Plugins`.
- The validator passes without `--skip-freecad`.
- Pure-Python tests pass, and the GUI checklist passes for all changed user-visible behavior.
- The diff contains no unrelated plugins, generated caches, virtual environments, or test documents.
- The feature branch is pushed and the PR targets `main`.
