from pathlib import Path

import FreeCADGui as Gui
import __PYTHON_PACKAGE__ as addon_package


ICON_DIR = str(Path(addon_package.__file__).resolve().parents[1] / "resources" / "icons")
Gui.addIconPath(ICON_DIR)


class TemplateWorkbench(Gui.Workbench):
    MenuText = "__DISPLAY_NAME__"
    ToolTip = "__DESCRIPTION__"
    Icon = "template.svg"

    def Initialize(self):
        from __PYTHON_PACKAGE__ import commands

        commands.register()
        self.appendToolbar("__DISPLAY_NAME__", ["__COMMAND_ID__"])
        self.appendMenu("__DISPLAY_NAME__", ["__COMMAND_ID__"])

    def Activated(self):
        pass

    def Deactivated(self):
        pass

    def GetClassName(self):
        return "Gui::PythonWorkbench"


Gui.addWorkbench(TemplateWorkbench())
