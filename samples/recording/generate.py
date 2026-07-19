#!/usr/bin/env python3
"""Generate the Tattan recording sample JSON.

Import via Tattan → Settings → Data → Backup → Import…

Before recording:
  1. Export your current data (Settings → Data → Backup → Export…) to a safe place.
  2. Quit Tattan and move ~/Library/Application Support/Tattan/*.store* aside (e.g. into ~/AI/trash/).
  3. Launch Tattan and Import this file.
After recording, restore the store files you moved aside.

Usage:
    python3 generate.py
    python3 generate.py --out custom.json
    python3 generate.py --base-date 2026-08-01T09:00:00Z
"""
from __future__ import annotations

import argparse
import base64
import json
import random
import struct
import zlib
from datetime import datetime, timedelta, timezone

DEFAULT_BASE_DATE = datetime(2026, 7, 18, 12, 0, 0, tzinfo=timezone.utc)
SEED = 20260718


# --- PNG (stdlib only) --------------------------------------------------------

def _chunk(tag: bytes, data: bytes) -> bytes:
    length = struct.pack(">I", len(data))
    crc = zlib.crc32(tag + data) & 0xffffffff
    return length + tag + data + struct.pack(">I", crc)


def make_gradient_png(width, height, start_rgb, end_rgb):
    """Solid top→bottom RGB gradient PNG."""
    signature = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    raw = bytearray()
    for y in range(height):
        t = y / max(1, height - 1)
        r = round(start_rgb[0] + (end_rgb[0] - start_rgb[0]) * t)
        g = round(start_rgb[1] + (end_rgb[1] - start_rgb[1]) * t)
        b = round(start_rgb[2] + (end_rgb[2] - start_rgb[2]) * t)
        raw.append(0)  # filter: None
        raw.extend((r, g, b) * width)
    idat = zlib.compress(bytes(raw), 9)
    return signature + _chunk(b"IHDR", ihdr) + _chunk(b"IDAT", idat) + _chunk(b"IEND", b"")


# --- RTF ----------------------------------------------------------------------

RTF_HEADER = r"{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0\fnil Helvetica;}}\f0\fs28 "
RTF_FOOTER = r"}"


def _rtf_escape(s):
    return s.replace("\\", r"\\").replace("{", r"\{").replace("}", r"\}")


def make_rtf(plain, bold_phrase):
    if bold_phrase and bold_phrase in plain:
        before, _, after = plain.partition(bold_phrase)
        return f"{RTF_HEADER}{_rtf_escape(before)}\\b {_rtf_escape(bold_phrase)}\\b0 {_rtf_escape(after)}{RTF_FOOTER}"
    return f"{RTF_HEADER}{_rtf_escape(plain)}{RTF_FOOTER}"


# --- Serialization helpers ----------------------------------------------------

def iso(dt):
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# --- Static content -----------------------------------------------------------

def build_tags():
    return [
        {"name": "Email",     "sortOrder": 0},
        {"name": "Templates", "sortOrder": 1},
        {"name": "Code",      "sortOrder": 2},
        {"name": "Markdown",  "sortOrder": 3},
        {"name": "Colors",    "sortOrder": 4},
        {"name": "Personal",  "sortOrder": 5},
    ]


COLORS = [
    ("Red",     "#EF4444"),
    ("Orange",  "#F97316"),
    ("Amber",   "#F59E0B"),
    ("Yellow",  "#EAB308"),
    ("Lime",    "#84CC16"),
    ("Green",   "#22C55E"),
    ("Emerald", "#10B981"),
    ("Teal",    "#14B8A6"),
    ("Cyan",    "#06B6D4"),
    ("Sky",     "#0EA5E9"),
    ("Blue",    "#3B82F6"),
    ("Indigo",  "#6366F1"),
    ("Violet",  "#8B5CF6"),
    ("Purple",  "#A855F7"),
    ("Fuchsia", "#D946EF"),
    ("Pink",    "#EC4899"),
    ("Rose",    "#F43F5E"),
    ("Slate",   "#64748B"),
    ("Neutral", "#737373"),
    ("Stone",   "#78716C"),
]


def build_snippets():
    out = []

    def add(title, content, tags):
        out.append({
            "title": title,
            "content": content,
            "tags": tags,
            "sortOrder": len(out),
            "hotkey": None,
        })

    # Email (4)
    add("Meeting follow-up",
        "Hi,\n\nThanks for the great discussion today. As agreed, I'll send over the revised proposal by the end of the week. "
        "Let me know if anything else comes up in the meantime.\n\nCheers,",
        ["Email"])
    add("Thanks reply",
        "Really appreciate the quick turnaround — this is exactly what we needed.",
        ["Email"])
    add("Sign-off casual",
        "Cheers,\nKen",
        ["Email"])
    add("Out of office",
        "I'm out of the office until further notice. For urgent matters, please reach the team at hello@example.com. "
        "I'll get back to you as soon as I can.",
        ["Email"])

    # Templates (5) — showcase template variables
    add("Weekly report",
        "{{date:yyyy-MM-dd}} Weekly report\n\nProject: {{ask:project name}}\n\n## Highlights\n{{cursor}}\n\n## Next week\n- ",
        ["Templates"])
    add("Meeting minutes",
        "# Meeting notes — {{date}}\n\nAttendees: {{ask:attendees}}\n\n## Agenda\n1. {{cursor}}\n\n## Action items\n- ",
        ["Templates"])
    add("Bug report",
        "Title: {{ask:bug title}}\n\nSteps:\n1. {{ask:steps}}\n\nExpected: {{ask:expected}}\nActual: {{ask:actual}}\n\n"
        "Environment: macOS {{ask:macOS version|26 Tahoe}}",
        ["Templates"])
    add("Standup update",
        "Standup {{date}}\n\nYesterday: {{ask:yesterday}}\nToday: {{ask:today}}\nBlockers: {{ask:blockers|none}}",
        ["Templates"])
    add("Quote clipboard",
        "> {{clipboard}}\n\n— quoted on {{date}}",
        ["Templates"])

    # Code (5)
    add("SwiftUI View skeleton",
        "struct MyView: View {\n    var body: some View {\n        Text(\"Hello, world!\")\n    }\n}",
        ["Code"])
    add("Conventional commit — feat",
        "feat: add ",
        ["Code"])
    add("curl POST JSON",
        "curl -X POST https://api.example.com/endpoint \\\n  -H \"Content-Type: application/json\" \\\n  -d '{\"key\": \"value\"}'",
        ["Code"])
    add("Git undo last commit (keep changes)",
        "git reset --soft HEAD~1",
        ["Code"])
    add("Console log with label",
        "console.log('[debug]', );",
        ["Code"])

    # Markdown (3)
    add("Markdown table 3x3",
        "| Column A | Column B | Column C |\n| --- | --- | --- |\n|  |  |  |\n|  |  |  |\n|  |  |  |",
        ["Markdown"])
    add("Markdown Swift code block",
        "```swift\n\n```",
        ["Markdown"])
    add("PR checklist",
        "- [ ] Tests added\n- [ ] Docs updated\n- [ ] Screenshots attached\n- [ ] CI green",
        ["Markdown"])

    # Colors (20)
    for name, hex_code in COLORS:
        add(f"{name} — {hex_code}", hex_code, ["Colors"])

    # Personal (3 — all clearly fake demo data)
    add("Demo mailing address (US)",
        "Jane Doe\n123 Sample Street\nDemo City, CA 94000\nUnited States",
        ["Personal"])
    add("Demo phone number",
        "+1 (555) 123-4567",
        ["Personal"])
    add("Demo email signature",
        "Jane Doe\nProduct Manager · Example Co.\njane@example.com · +1 (555) 123-4567",
        ["Personal"])

    return out


URLS = [
    "https://github.com/Clipy/Clipy",
    "https://developer.apple.com/documentation/swiftui/view",
    "https://developer.apple.com/documentation/swiftdata",
    "https://news.ycombinator.com/item?id=39283847",
    "https://swift.org/blog/swift-6.0-released/",
    "https://www.hackingwithswift.com/quick-start/swiftui",
    "https://tailwindcss.com/docs/installation",
    "https://en.wikipedia.org/wiki/Clipboard_(computing)",
    "https://stackoverflow.com/questions/24102176/how-to-get-the-current-date-in-swift",
    "https://developer.apple.com/design/human-interface-guidelines/menu-bar-extras",
    "https://kagi.com/search?q=swiftui+menubar+app",
    "https://apple.stackexchange.com/questions/58990",
    "https://www.jetbrains.com/fleet/",
    "https://vercel.com/docs",
    "https://astro.build/blog/",
    "https://blog.mozilla.org/en/products/firefox/",
    "https://www.raywenderlich.com/library",
    "https://blog.hubspot.com/marketing/product-launch",
    "https://www.figma.com/community/file/example",
    "https://obsidian.md/plugins",
    "https://brew.sh/",
    "https://sketch.com/blog/",
    "https://www.notion.so/help/create-a-database",
    "https://github.com/ken297/tattan/releases",
    "https://khamsin.jp/blog/",
]  # 25

SENTENCES = [
    "The clipboard manager for people who value simplicity.",
    "Please review the attached document at your earliest convenience.",
    "I think we should move the deadline to next Friday.",
    "Menu bar apps in macOS have come a long way since Yosemite.",
    "The right approach is to fail fast and iterate.",
    "Let's schedule a follow-up call for next week.",
    "Thanks so much for your help on this project!",
    "Try double-tapping the right Command key to summon Tattan.",
    "Version 1.0 shipped with clipboard history and snippets.",
    "Every keystroke matters when you use a tool a hundred times a day.",
    "We should measure twice and cut once here.",
    "Kudos to the team for a great launch.",
    "Ship early, ship often.",
    "The best interface is no interface — unless it's this menu bar.",
    "Consider adopting an accessibility-first mindset from day one.",
    "Rich text and images are handled transparently.",
    "The hotkey binding was inspired by an old macOS app.",
    "Please respond by end of day Thursday.",
    "Attached please find the updated project timeline.",
    "Looking forward to hearing from you soon.",
]  # 20

CODE = [
    "userIdentifier",
    "try await service.fetchSnippets()",
    "@Environment(\\.dismiss) private var dismiss",
    "struct ContentView: View { }",
    "#Preview { ContentView() }",
    "NSPasteboard.general.setString(text, forType: .string)",
    ".frame(maxWidth: .infinity, alignment: .leading)",
    "let uuid = UUID().uuidString",
    "^(?:https?://)?[\\w.-]+\\.[a-z]{2,}$",
    "SELECT * FROM users WHERE created_at > '2026-06-01' ORDER BY id DESC;",
    "Task { await viewModel.load() }",
    "guard let data = try? Data(contentsOf: url) else { return }",
    "import SwiftUI",
    "func makeContainer() -> ModelContainer { fatalError() }",
    "DispatchQueue.main.async { }",
]  # 15

NUMBERS = [
    "550e8400-e29b-41d4-a716-446655440000",
    "ORDER-2026-00847",
    "$1,234.56",
    "SKU-A7F3-99B1",
    "TRK9384712893",
    "47.6062° N, 122.3321° W",
    "€2,499.00",
    "ISBN 978-4-06-521234-5",
    "Confirmation: NX7-J24Q-88",
    "Version 1.2.3-beta.4",
]  # 10

MAIL_PHONE = [
    "hello@example.com",
    "sample.user@example.org",
    "+1 (555) 987-6543",
    "+81 90-5555-1234",
    "support@example.net",
    "demo+dev@example.com",
    "+44 20 5555 0199",
    "press@example.co",
]  # 8

TERMINAL = [
    "git log --oneline -20",
    "brew upgrade",
    "defaults write com.apple.finder AppleShowAllFiles YES",
    "killall Finder",
    "xcodebuild -project Tattan.xcodeproj -scheme Tattan build",
    "swiftlint --fix",
    "git push origin main",
    "pmset -g batt",
    "curl -I https://khamsin.jp",
    "open /Applications/Tattan.app",
]  # 10

FILENAMES = [
    "screenshot-2026-07-15-152743.png",
    "~/Downloads/spec-draft-v2.pdf",
    "/Users/demo/Projects/tattan/CLAUDE.md",
    "report_2026Q2_final_v3.xlsx",
    "~/Documents/Meeting notes 2026-07-10.md",
]  # 5

RTF_ITEMS = [
    ("Bold reminder: Ship the release notes tomorrow.", "Ship the release notes"),
    ("Highlight: The customer needs a fix by EOD.", "customer needs a fix"),
    ("Note: All hands meeting moved to 3pm.", "All hands meeting"),
]  # 3

GRADIENTS = [
    ((45, 212, 191),  (30, 64,  175)),   # teal → blue
    ((251, 146, 60),  (220, 38,  38)),   # orange → red
    ((168, 85,  247), (236, 72,  153)),  # purple → pink
]  # 3

FILE_REF = ["/Users/demo/Desktop/mockup-v3.sketch"]  # 1


# --- History assembly ---------------------------------------------------------

def build_history(base_date):
    items = []
    window_s = 14 * 24 * 3600  # 14 days

    def stamp():
        created_offset_s = random.uniform(0, window_s)
        created = base_date - timedelta(seconds=created_offset_s)
        if random.random() < 0.2:  # 20% re-copied later (drift toward base_date)
            copied_offset_s = random.uniform(0, created_offset_s)
            copied = created + timedelta(seconds=copied_offset_s)
        else:
            copied = created
        return created, copied

    def push_text(text):
        created, copied = stamp()
        items.append({
            "kind": "text",
            "createdAt": iso(created),
            "copiedAt":  iso(copied),
            "plainText": text,
            "rtfBase64": None,
            "imageBase64": None,
            "filePaths": None,
        })

    for lst in (URLS, SENTENCES, CODE, NUMBERS, MAIL_PHONE, TERMINAL, FILENAMES):
        for entry in lst:
            push_text(entry)

    for plain, bold in RTF_ITEMS:
        created, copied = stamp()
        rtf = make_rtf(plain, bold)
        items.append({
            "kind": "richText",
            "createdAt": iso(created),
            "copiedAt":  iso(copied),
            "plainText": plain,
            "rtfBase64": base64.b64encode(rtf.encode("utf-8")).decode("ascii"),
            "imageBase64": None,
            "filePaths": None,
        })

    for start_rgb, end_rgb in GRADIENTS:
        created, copied = stamp()
        png = make_gradient_png(200, 200, start_rgb, end_rgb)
        items.append({
            "kind": "image",
            "createdAt": iso(created),
            "copiedAt":  iso(copied),
            "plainText": None,
            "rtfBase64": None,
            "imageBase64": base64.b64encode(png).decode("ascii"),
            "filePaths": None,
        })

    created, copied = stamp()
    items.append({
        "kind": "fileReference",
        "createdAt": iso(created),
        "copiedAt":  iso(copied),
        "plainText": None,
        "rtfBase64": None,
        "imageBase64": None,
        "filePaths": FILE_REF,
    })

    if len(items) != 100:
        raise SystemExit(f"expected 100 history items, got {len(items)}")

    random.shuffle(items)  # so kinds intermingle in the history view
    return items


def main():
    ap = argparse.ArgumentParser(description="Generate the Tattan recording sample JSON.")
    ap.add_argument("--base-date", default=None,
                    help="ISO 8601 timestamp used as the reference 'now' for the history window. Default: 2026-07-18T12:00:00Z.")
    ap.add_argument("--out", default="tattan-recording-sample.json")
    args = ap.parse_args()

    if args.base_date:
        base = datetime.fromisoformat(args.base_date.replace("Z", "+00:00")).astimezone(timezone.utc)
    else:
        base = DEFAULT_BASE_DATE

    random.seed(SEED)

    payload = {
        "format": "tattan-export",
        "version": 1,
        "exportedAt": iso(base),
        "tags": build_tags(),
        "snippets": build_snippets(),
        "history": build_history(base),
    }

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, sort_keys=True, ensure_ascii=False)

    print(f"Wrote {len(payload['snippets'])} snippets and {len(payload['history'])} history items → {args.out}")


if __name__ == "__main__":
    main()
