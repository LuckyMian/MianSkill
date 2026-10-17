import unittest

from __PYTHON_PACKAGE__ import core


class CoreTests(unittest.TestCase):
    def test_format_message(self):
        self.assertEqual(core.format_message("FreeCAD"), "Hello from __DISPLAY_NAME__, FreeCAD!")

    def test_empty_name_is_rejected(self):
        with self.assertRaises(ValueError):
            core.format_message("  ")


if __name__ == "__main__":
    unittest.main()
