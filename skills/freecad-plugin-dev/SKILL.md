---
name: freecad-plugin-dev
description: Develop, test, package, and publish FreeCAD 1.1 Python workbenches in the LuckyMian FreeCad_Plugins repository at F:\Codex\Freecad. Use for workbench commands, Qt panels, FreeCAD API integration, addon metadata, development linking, or plugin delivery in this repository; do not use for FreeCAD C++ modules, generic CAD modeling, or unrelated addons.
metadata:
  short-description: FreeCAD 1.1 plugin development and release
---

# FreeCAD plugin development

> **Skill changes must be pushed**: after editing this skill or any other skill under `%USERPROFILE%\.codex\skills`, run
> `powershell -NoProfile -File F:\Codex\Skill\MianSkill\sync.ps1`
> and confirm that `MianSkill` reached GitHub. Read `$skill-vault` for failure handling.

Work against the plugin collection at `F:\Codex\Freecad`, whose `origin` is `https://github.com/LuckyMian/FreeCad_Plugins.git`. The local baseline is FreeCAD 1.1.4 with Python 3.11.14. Inspect the current repository instead of assuming that a plugin or directory named below already exists.

## Route the task

- For repository layout, `package.xml`, workbench lifecycle, commands, Qt panels, preferences, or development linking, read [addon-development.md](references/addon-development.md).
- For validation, FreeCADCmd tests, GUI acceptance, branches, commits, or PR delivery, read [testing-and-release.md](references/testing-and-release.md).
- To start a plugin, copy [addon-template](assets/addon-template/) into `plugins/<addon-id>/` and replace every template identifier as described in the reference.

## Non-negotiable project rules

- Target FreeCAD 1.1.x only. Do not add compatibility branches for 0.21 or 1.0 unless the user explicitly changes the target.
- Each plugin is `plugins/<addon-id>/`; the plugin directory is the package root and contains `package.xml` plus `InitGui.py`. Use lowercase letters, digits, and hyphens for `<addon-id>`.
- Keep domain and geometry logic in plain Python modules where practical. Keep FreeCAD and Qt imports in the workbench, command, and panel layers so core logic can run outside FreeCAD.
- Develop only in `F:\Codex\Freecad`; never edit files under `C:\Program Files\FreeCAD 1.1`. Mount a plugin into the user Mod directory only through `scripts/dev_link.ps1` or an equivalent verified directory junction.
- Preserve uncommitted work and unrelated plugins. Do not rewrite the repository README or reorganize an existing plugin unless the task requires it.
- Run `scripts/validate_addon.py` before declaring a plugin change complete. A successful syntax check does not replace opening FreeCAD and exercising the workbench and command.

## Delivery workflow

1. Inspect `git status`, the target plugin's `package.xml`, and its workbench entry point before editing.
2. Create or update the plugin under `plugins/<addon-id>`. Reuse the package metadata conventions and command structure from the template.
3. Test core logic with system Python, then run the validator with FreeCADCmd. Complete the GUI checklist for any user-visible behavior.
4. When the request includes delivery, branch from the current `main`, commit only the scoped plugin or repository changes, push the branch, and report the GitHub compare URL. Never push plugin code directly to `main`.
5. If the user only asks to inspect, diagnose, or draft, do not commit or push.

Use commit prefixes `feat(<addon-id>): ...`, `fix(<addon-id>): ...`, `test(<addon-id>): ...`, `docs(<addon-id>): ...`, or `chore(<addon-id>): ...`.
