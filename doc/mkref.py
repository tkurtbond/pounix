#!/usr/bin/env python3
"""The reference for an Oberon-2 module, in Markdown, from its source.

Usage: mkref.py Module.Mod > Module.md

Takes what a user of the module sees: the module's comment, then each
exported constant, type, variable and procedure, as declared, with the
comment just above it. Unexported names, record fields and ["C"]
procedures are left out. A comment of one line standing alone between
blank lines, as "(* Errors *)", heads a section of procedures; dashes
around it, as in "(* --- Config --- *)", are dropped, and a comment
whose first line is such a heading, "(* --- Connection info ---", has
the section's introduction in its other lines. The module
comment's paragraphs beginning "Phase" are the project's history, not
the interface, and are left out.

Copied from polibtls's doc/mkref.py, written for its sources and
posockets', which keep to that layout; not a general Oberon parser.
"""

import re
import sys
import textwrap

EXPORTED_NAME = re.compile(r"\b[A-Za-z][A-Za-z0-9]*[*-]")
EXPORTED_PROC = re.compile(r"^PROCEDURE\s+(\([^)]*\)\s*)?([A-Za-z][A-Za-z0-9]*)\*")
SECTION = re.compile(r"^(CONST|TYPE|VAR)\s*$")
LONG_HEADING = re.compile(r"^\(\* --- ([^*()]+?) ---$")
HEADING = re.compile(r"^\(\* (?:--- )?([^*()-][^*()]*?)(?: ---)? \*\)$")


def comment_text(lines):
    """The prose of a comment's lines, delimiters removed, dedented."""
    text = "\n".join(lines).strip()
    text = re.sub(r"^\(\*\s?", "", text)
    text = re.sub(r"\s*\*\)$", "", text)
    first, _, rest = text.partition("\n")
    return (first.strip() + "\n" + textwrap.dedent(rest)).strip()


def paragraphs(text):
    return [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]


def reflow(paragraph):
    """A paragraph as Markdown: indented lines (examples) as code."""
    lines = paragraph.split("\n")
    if lines[0].startswith("- "):
        return paragraph
    if all(l.startswith("  ") or not l.strip() for l in lines[1:]) and \
            len(lines) > 1 and lines[0].endswith(":"):
        return lines[0] + "\n\n```\n" + textwrap.dedent("\n".join(lines[1:])) + "\n```"
    if all(l.startswith("  ") for l in lines):
        return "```\n" + textwrap.dedent(paragraph) + "\n```"
    return " ".join(l.strip() for l in lines)


def prose(text):
    return "\n\n".join(reflow(p) for p in paragraphs(text))


def module_comment(lines):
    """The comment after the MODULE line, and the index after it."""
    i = 1
    while not lines[i].strip():
        i += 1
    if not lines[i].lstrip().startswith("(*"):
        return "", i
    start = i
    while "*)" not in lines[i]:
        i += 1
    return comment_text(lines[start:i + 1]), i + 1


def comment_block_before(lines, i):
    """The comment block ending on the line just above lines[i], if any."""
    j = i - 1
    if j < 0 or not lines[j].rstrip().endswith("*)"):
        return None
    k = j
    while "(*" not in lines[k]:
        k -= 1
    return comment_text(lines[k:j + 1])


def declarations(lines, start):
    """Groups of exported CONST, TYPE and VAR declarations: (kind,
    comment, code lines), in order."""
    groups = []
    kind = None
    comment = []
    code = []
    in_comment = False
    record_depth = 0
    field_comment = []

    def flush():
        nonlocal comment, code
        if code:
            groups.append((kind, comment_text(comment) if comment else "", code))
        comment, code = [], []

    for line in lines[start:]:
        s = line.strip()
        if s.startswith("PROCEDURE") or s == "BEGIN" or s.startswith("END "):
            break
        m = SECTION.match(s)
        if m:
            flush()
            kind = m.group(1)
            continue
        if kind is None or s.startswith("IMPORT"):
            continue
        if record_depth:
            # inside an exported record: keep exported fields
            if in_comment or (s.startswith("(*") and not EXPORTED_NAME.search(s)):
                field_comment.append(line)
                in_comment = "*)" not in s
                continue
            if s.startswith("END"):
                code.append(line)
                record_depth = 0
                continue
            if EXPORTED_NAME.search(s.split("(*")[0]):
                code.extend(field_comment)
                code.append(line)
            field_comment = []
            continue
        if in_comment:
            comment.append(line)
            in_comment = "*)" not in s
            continue
        if not s:
            flush()
            continue
        if s.startswith("(*"):
            if code:
                flush()
            comment.append(line)
            in_comment = "*)" not in s
            continue
        decl = s.split("(*")[0]
        if EXPORTED_NAME.search(decl.split("=")[0].split(":")[0]):
            code.append(line)
            if re.search(r"\bRECORD\b", decl) and not re.search(r"\bEND\b", decl):
                record_depth = 1
                field_comment = []
        elif code and not decl.rstrip().endswith(";"):
            code.append(line)  # a continuation
    flush()
    return groups


def procedures(lines, start):
    """Sections of exported procedures: (heading, introduction,
    [(name, header, comment)])."""
    sections = [("", "", [])]
    i = start
    while i < len(lines):
        s = lines[i].strip()
        h = HEADING.match(s)
        if h and (i == 0 or not lines[i - 1].strip()) and \
                (i + 1 == len(lines) or not lines[i + 1].strip()):
            sections.append((h.group(1), "", []))
        h = LONG_HEADING.match(s)
        if h:
            j = i
            while "*)" not in lines[j]:
                j += 1
            body = comment_text(["(*"] + lines[i + 1:j + 1])
            sections.append((h.group(1), body, []))
            i = j
        m = EXPORTED_PROC.match(s)
        if m and '["C"' not in s:
            header = [lines[i].rstrip()]
            depth = s.count("(") - s.count(")")
            while depth > 0 or not header[-1].rstrip().endswith(";"):
                i += 1
                header.append(lines[i].rstrip())
                depth += lines[i].count("(") - lines[i].count(")")
            sections[-1][2].append(
                (m.group(2), header, comment_block_before(lines, i - len(header) + 1) or ""))
        i += 1
    return [s for s in sections if s[2]]


def main():
    path = sys.argv[1]
    with open(path) as f:
        lines = f.read().split("\n")
    m = re.match(r"MODULE\s+(\w+);\s*(\(\*\s*(.*?)\s*\*\))?", lines[0])
    name, tagline = m.group(1), m.group(3) or ""
    intro, after = module_comment(lines)
    out = []
    out.append("# " + name + (": " + tagline if tagline else ""))
    out.append("")
    out.append("<!-- Made by doc/mkref.py from " + path.split("/")[-1] +
               "; edit the source, then make doc. -->")
    out.append("")
    out.append("\n\n".join(reflow(p) for p in paragraphs(intro)
                           if not p.startswith("Phase")))
    out.append("")

    titles = {"CONST": "Constants", "TYPE": "Types", "VAR": "Variables"}
    last = None
    for kind, comment, code in declarations(lines, after):
        if kind != last:
            out.append("## " + titles[kind])
            out.append("")
            last = kind
        out.append("```oberon")
        out.append(textwrap.dedent("\n".join(code)))
        out.append("```")
        out.append("")
        if comment:
            out.append(prose(comment))
            out.append("")

    out.append("## Procedures")
    out.append("")
    for heading, intro, procs in procedures(lines, after):
        if heading:
            out.append("### " + heading)
            out.append("")
        if intro:
            out.append(prose(intro))
            out.append("")
        for pname, header, comment in procs:
            out.append("#### " + pname)
            out.append("")
            out.append("```oberon")
            out.append("\n".join(header))
            out.append("```")
            out.append("")
            if comment:
                out.append(prose(comment))
                out.append("")
    sys.stdout.write("\n".join(out).rstrip() + "\n")


main()
