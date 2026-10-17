import FreeCAD as App
import FreeCADGui as Gui
from PySide import QtWidgets

from . import core


class HelloCommand:
    def GetResources(self):
        return {
            "Pixmap": "template.svg",
            "MenuText": "Hello FreeCAD",
            "ToolTip": "Show a message from __DISPLAY_NAME__.",
        }

    def IsActive(self):
        return App.ActiveDocument is not None

    def Activated(self):
        message = core.format_message("FreeCAD")
        QtWidgets.QMessageBox.information(
            Gui.getMainWindow(),
            "__DISPLAY_NAME__",
            message,
        )


def register():
    Gui.addCommand("__COMMAND_ID__", HelloCommand())
