import FreeCAD as App


def _log(message):
    App.Console.PrintLog(f"__DISPLAY_NAME__: {message}\n")


_log("application initialization loaded")
