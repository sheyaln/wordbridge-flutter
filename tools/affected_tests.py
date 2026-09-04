#!/usr/bin/env python3
"""Which test files can reach the code that changed.

A test is selected when the transitive closure of what it imports contains a
file that changed. Nothing is inferred from a filename: `symbol_view.dart` is
covered by `board_render_test.dart`, whose name says neither, and a rule that
matched names would have missed it.

Prints one test path per line. Prints nothing and exits 2 when the change is
one whose blast radius this cannot reason about — a pubspec, the workflow, a
tool, the analysis options — which the caller must read as "run everything".

    python3 tools/affected_tests.py <changed file> [...]
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "app")
LIB = os.path.join(APP, "lib")
TEST = os.path.join(APP, "test")

# A change to any of these moves ground the graph is standing on, so the graph
# is not asked about it.
WHOLE_SUITE = (
    "app/pubspec.yaml",
    "app/pubspec.lock",
    "app/analysis_options.yaml",
    ".github/workflows/",
    "tools/",
    # Not Dart, so no import reaches them and the graph would select nothing
    # at all. The symbol manifest decides what every board draws, and a
    # selector that answered "no tests" for a change to it would be worse than
    # having no selector.
    "app/assets/",
    "app/ios/",
    "app/android/",
)

IMPORT = re.compile(r"""^\s*(?:import|export|part)\s+['"]([^'"]+)['"]""", re.M)


def dart_files(root):
    for base, _, names in os.walk(root):
        for name in names:
            if name.endswith(".dart"):
                yield os.path.join(base, name)


def resolve(importing, target):
    """A package: or relative import as a repo-relative path, or None."""
    if target.startswith("package:wordbridge/"):
        return os.path.relpath(
            os.path.join(LIB, target[len("package:wordbridge/"):]), ROOT
        )
    if target.startswith(("dart:", "package:")):
        return None
    return os.path.relpath(
        os.path.normpath(os.path.join(os.path.dirname(importing), target)), ROOT
    )


def edges(paths):
    graph = {}
    for path in paths:
        with open(path, encoding="utf-8") as f:
            source = f.read()
        key = os.path.relpath(path, ROOT)
        graph[key] = {
            r
            for r in (resolve(path, t) for t in IMPORT.findall(source))
            if r is not None
        }
    return graph


def closure(start, graph):
    seen, stack = set(), [start]
    while stack:
        node = stack.pop()
        for dep in graph.get(node, ()):
            if dep not in seen:
                seen.add(dep)
                stack.append(dep)
    return seen


def main(argv):
    changed = {c.strip() for c in argv if c.strip()}
    if not changed:
        return 2
    if any(c.startswith(WHOLE_SUITE) for c in changed):
        return 2

    # A generated file is not in the tree, so a change that would regenerate it
    # has to be treated as reaching whatever the source of it reaches.
    graph = edges(list(dart_files(LIB)) + list(dart_files(TEST)))

    selected = set()
    for test in sorted(os.path.relpath(p, ROOT) for p in dart_files(TEST)):
        # A test that changed runs whatever else it touches.
        if test in changed or closure(test, graph) & changed:
            selected.add(test)

    for test in sorted(selected):
        print(test)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
