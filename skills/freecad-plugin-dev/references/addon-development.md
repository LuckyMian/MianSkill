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
- Do not use `__file__` at the top of `InitGui.py`: FreeCAD 1.1 executes this file through `RunInitGuiPy`, where `__file__` may be undefined. Import the plugin package and resolve the icon directory from `Path(package.__file__)` instead (the template does this).

## Parametric objects and display

For a shape-bearing parametric object, a plain `App::FeaturePython` with a `Part::PropertyPartShape` does **not** necessarily display in the 3D view. `Part::FeaturePython` can also get a Part view provider that does not rebuild its representation from a Python `execute()`.

The reliable pattern used by the optical-axis plugin is a small object graph:

```text
App::Part (container)
├─ App::FeaturePython  controller  (parameters only, no Shape)
├─ Part::Feature       printable body
└─ Part::Feature       optional rods / second body
```

- The controller's `execute()` rebuilds the child `Part::Feature.Shape` values.
- `Part::Feature` children use FreeCAD's standard Part view provider; display, selection, colors, and export work normally.
- Do not assign a plain Python object to a `Part::Feature`'s `ViewObject.Proxy`; keep the default provider unless you implement a proper `PartGui` view provider.
- Apply per-object display colors on the child features (`ShapeColor`, `LineColor`), not on the controller.

## Cross-scope references

An `App::PropertyLink` from an object in one `App::Part` to an object in another part can log:

```text
Link(s) to object(s) ... go out of the allowed scope ...
```

For a lightweight cross-module reference, store the target object's **name** in an `App::PropertyString` and resolve it in `execute()` with `Document.getObject(name)`. This is also stable across save/reload and avoids link-scope warnings. It does not create a dependency, so call `touch()` on the dependent object when the base changes if it must rebuild immediately.

## Persistence

FreeCAD does not always call a `FeaturePython` proxy's `__init__` when restoring a document; it may only call `__setstate__`. Any transient attribute used by `execute()`/`onChanged()` must be initialized there:

```python
def __getstate__(self):
    return None

def __setstate__(self, state):
    self._building = False
```

Otherwise saved documents can raise `AttributeError` on the first recompute. Add a save/reload smoke test for every new parametric object.

## Fillet, chamfer, and boolean order

Edge operations are order-sensitive. For a plate with holes and a window/pocket, this order was reliable:

1. extrude the outer profile;
2. fillet the outer vertical corners;
3. cut the through-holes;
4. chamfer the hole edges;
5. cut the window/pocket;
6. fillet the window's vertical corners;
7. chamfer the outer perimeter;
8. add outer-face caps.

Select outer-perimeter edges from the two large faces' `OuterWire`, not by face area (a pocket floor is also a large face). Wrap each `makeFillet`/`makeChamfer` in `try/except` and log a warning; an extreme parameter should not destroy the feature. If a blind pocket is added to a mirrored/paired part, parameterize which local face is the **outside**; simply copying the same solid can close the wrong side.

**Every printable model needs chamfers** (non-negotiable project rule). Expose at least an outer-edge chamfer and a hole/bore-mouth chamfer (default roughly 0.5–1.0 mm), include them in the model's parameter object and dialog, and apply them even to models that are "just a plate". For a new part, chamfer each simple solid before fusing it into the assembly: a plain box/prism accepts a chamfer on all edges, while a fused L-shape, U-slot, or thin-wall sleeve is much more likely to fail. Chamfering before the fuse also keeps the visible outer edges clean and avoids selecting edges on complex boolean results. Do not leave a model with raw sharp outer corners because "it prints anyway".

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
- `NameError: name '__file__' is not defined` in `InitGui.py`: use the imported package's `__file__`, not the entry file's.
- A shape-bearing `App::FeaturePython` is invisible: use the controller + `Part::Feature` child pattern or a proper PartGui view provider.
- `AttributeError` on the first recompute after reload: initialize proxy state in `__setstate__`.
- `Link ... go out of the allowed scope`: replace cross-`App::Part` `PropertyLink` with an object-name `PropertyString`.
- Editing a plugin copied into Program Files is overwritten by upgrades and may require administrator rights. Edit the repository and mount it through the user Mod directory.
