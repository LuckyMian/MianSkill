# FreeCAD 1.1 addon development

## Environment

| Item | Value |
| --- | --- |
| Repository | `F:\Codex\Freecad` |
| Remote | `https://github.com/LuckyMian/FreeCad_Plugins.git` |
| FreeCAD | 1.1.4, revision 20260928 |
| FreeCAD executable | `C:\Program Files\FreeCAD 1.1\bin\FreeCAD.exe` |
| Headless executable | `C:\Program Files\FreeCAD 1.1\bin\FreeCADCmd.exe` |
| FreeCAD Python | 3.11.14 |
| User Mod directory | `%APPDATA%\FreeCAD\v1-1\Mod` |
| User macro directory | `%APPDATA%\FreeCAD\v1-1\Macro` |

The user Mod directory may not exist until the first addon is mounted. Create it when needed; do not add files to the FreeCAD installation directory.

## Repository layout

```text
FreeCad_Plugins/
├─ README.md
└─ plugins/
   ├─ first-plugin/
   │  ├─ package.xml
   │  ├─ Init.py
   │  ├─ InitGui.py
   │  ├─ <python_package>/
   │  │  ├─ __init__.py
   │  │  ├─ commands.py
   │  │  └─ core.py
   │  ├─ resources/
   │  └─ tests/
   └─ second-plugin/
      └─ package.xml
```

The repository is a collection. Each direct child of `plugins/` is an independent package root; do not put a shared `package.xml` at the repository root. Plugin folders may share repository tooling only when the dependency is explicit and tested.

## Package metadata

FreeCAD 1.1 reads `package.xml` from the package root. Keep the metadata namespace and the repository URL consistent with this project:

```xml
<package format="1" xmlns="https://wiki.freecad.org/Package_Metadata">
    <name>My Tool</name>
    <description>Short user-facing description.</description>
    <version>0.1.0</version>
    <date>2026-10-17</date>
    <maintainer email="maintainer@example.com">Maintainer Name</maintainer>
    <license>LGPL-2.1-or-later</license>
    <url type="repository" branch="main">https://github.com/LuckyMian/FreeCad_Plugins</url>
    <content>
        <workbench>
            <name>MyToolWorkbench</name>
            <subdirectory>./</subdirectory>
        </workbench>
    </content>
</package>
```

Update `<version>` and `<date>` when publishing a user-visible release. Confirm the license with the user before publishing a new plugin; the template uses FreeCAD's common LGPL-2.1-or-later value only as a starting point.

## Workbench and commands

- `InitGui.py` is loaded only with the graphical application. Define a `FreeCADGui.Workbench` subclass, register commands, and call `FreeCADGui.addWorkbench(...)`.
- `Init.py` is optional and runs in both GUI and console contexts. Keep it side-effect free except for lightweight setup that must occur in both modes.
- Put commands and core logic in a uniquely named Python package under the plugin root. Do not put generic `core.py` or `commands.py` modules directly on the shared FreeCAD module path.
- Register command objects once and give each command an ID prefixed with the plugin name to avoid collisions.
- Put Qt imports in the GUI-facing modules. Do not import `FreeCADGui`, `PySide`, or Qt from `core.py` or other pure-Python test modules.
- Load icons from the plugin's own `resources/icons` directory with `FreeCADGui.addIconPath(...)`; never depend on an icon existing in another workbench.
- Prefer `FreeCAD.ParamGet("User parameter:BaseApp/Preferences/Mod/<PluginId>")` for settings and give preferences stable names.
- Guard commands that require a document with `IsActive`; do not crash when no document is open.
- GUI commands that mutate a document should use transactions and preserve undo/redo behavior.

## Starting from the template

1. Copy the contents of `assets/addon-template/` to `plugins/<addon-id>/`.
2. Rename the `__PYTHON_PACKAGE__` directory to a unique lowercase identifier such as `my_tool`, then replace `__ADDON_ID__`, `__PYTHON_PACKAGE__`, `__PACKAGE_NAME__`, `__WORKBENCH_NAME__`, `__COMMAND_ID__`, `__DISPLAY_NAME__`, `__DESCRIPTION__`, `__MAINTAINER__`, `__MAINTAINER_EMAIL__`, `__RELEASE_DATE__`, and `__LICENSE__`.
3. Rename `TemplateWorkbench` and `Template_Hello` consistently in `InitGui.py` and the package's `commands.py`.
4. Keep the pure-Python example in the package's `core.py` and its test until real domain logic replaces it.
5. Run the validator and the GUI checklist before committing.

## Development mounting

Use the helper from the skill:

```powershell
powershell -NoProfile -File C:\Users\Administrator\.codex\skills\freecad-plugin-dev\scripts\dev_link.ps1 `
  -PluginRoot F:\Codex\Freecad\plugins\<addon-id> `
  -AddonId <addon-id>
```

Preview first with `-DryRun`. The helper creates a directory junction at `%APPDATA%\FreeCAD\v1-1\Mod\<addon-id>`. It refuses to replace a real directory and only removes a junction that points back to the same plugin. Remove a development link with `-Remove`; removing the junction does not delete the source plugin.

After Python changes, close and reopen FreeCAD when the workbench lifecycle is involved. A GUI reload may leave stale modules, Qt classes, or registered commands; a clean restart is the reliable acceptance test.

## Common failure modes

- Importing `FreeCADGui` from a pure-Python test process fails or behaves differently; test core logic with system Python and GUI integration with FreeCAD.
- Importing a module by a generic name such as `commands` can collide across addons. Keep package-relative imports within the plugin or use a uniquely named module.
- A missing or malformed `package.xml`, an absent `InitGui.py`, or a workbench whose `<subdirectory>` does not contain the entry point prevents AddonManager or FreeCAD from loading the plugin.
- Editing a plugin copied into Program Files is overwritten by upgrades and may require administrator rights. Edit the repository and mount it through the user Mod directory.
