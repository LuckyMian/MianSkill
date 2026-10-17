def format_message(name: str) -> str:
    """Return the template greeting without depending on FreeCAD or Qt."""
    if not name.strip():
        raise ValueError("name must not be empty")
    return f"Hello from __DISPLAY_NAME__, {name}!"
