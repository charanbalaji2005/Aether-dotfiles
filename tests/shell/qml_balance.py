#!/usr/bin/env python3
"""Print "<open-braces> <close-braces> <open-parens> <close-parens>" for a
QML/JS file, counted on code only: string literals, template strings and
comments are removed first (a "(" inside a string is not structure)."""
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
text = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', text)
text = re.sub(r"'(?:\\.|[^'\\\n])*'", "''", text)
text = re.sub(r"`[^`]*`", "``", text)
text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
text = re.sub(r"//[^\n]*", "", text)
print(text.count("{"), text.count("}"), text.count("("), text.count(")"))
