"""Points Homebrew libraries at their copies under <root>/brew. Usage: relocate.py <root> <homebrew prefix>"""
import os
import re
import subprocess
import sys

root, prefix = sys.argv[1], sys.argv[2]
brew = os.path.join(root, "brew")
pattern = re.compile(r"^%s/(?:opt/([^/]+)|Cellar/([^/]+)/[^/]+)/(.+)$" % re.escape(prefix))


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


for folder, _, names in os.walk(root):
    for name in names:
        path = os.path.join(folder, name)
        if os.path.islink(path):
            continue
        with open(path, "rb") as file:
            if file.read(4) != b"\xcf\xfa\xed\xfe":
                continue
        changes = []
        own = run("otool", "-D", path).splitlines()[1:]
        if own and own[0].startswith(prefix):
            changes += ["-id", "@rpath/" + os.path.basename(own[0])]
        for line in run("otool", "-L", path).splitlines()[1:]:
            library = line.strip().split(" (")[0]
            found = pattern.match(library)
            if found:
                target = os.path.join(brew, found.group(1) or found.group(2), found.group(3))
                changes += ["-change", library, "@loader_path/" + os.path.relpath(target, folder)]
        if changes:
            os.chmod(path, 0o755)
            run("install_name_tool", *changes, path)
            run("codesign", "--force", "--sign", "-", path)
        left = [line for line in run("otool", "-L", path).splitlines()[1:] if prefix in line]
        assert not left, (path, left)
