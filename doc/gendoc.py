"""FreePascal Documentation Generator.

Extracts docstrings and code signatures from FreePascal source files
(.pas, .lpr, .pp) and generates Markdown documentation (.md).

Usage:
    python gendoc.py --input <source> --output <doc.md> [--verbose]
    python gendoc.py                              # launch GUI
"""

from __future__ import annotations

import argparse
import logging
import os
import re
import sys
import tempfile
import threading
from typing import Any, Dict, List, Optional, Tuple

import tkinter as tk
from tkinter import filedialog, messagebox, ttk

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

MAX_FILE_SIZE_BYTES: int = 10 * 1024 * 1024  # 10 MB safety limit
SUPPORTED_ENCODINGS: List[str] = ["utf-8", "latin-1", "cp1252"]
SUPPORTED_EXTENSIONS: Tuple[str, ...] = (".lpr", ".pas", ".pp", ".p")
LOOKAHEAD_LINES: int = 10

# ===========================================================================
# User Guide
# ===========================================================================
#
# OVERVIEW
# --------
# gendoc.py extracts docstrings and code signatures from FreePascal source
# files (.pas, .lpr, .pp, .p) and generates clean, readable Markdown
# documentation (.md).
#
# It is designed to work even with messy legacy Pascal code by:
#   - Ignoring implementation bodies and only documenting declarations
#   - Tracking class context to prepend class names to members
#   - Handling platform-specific code blocks ({$IFDEF})
#   - Producing PDF-friendly Markdown with working anchor links
#
# REQUIREMENTS
# ------------
#   - Python 3.8 or higher
#   - Standard library only (no external dependencies for the core engine)
#   - Tkinter (usually included with Python; required only for GUI mode)
#
# USAGE
# -----
#   python gendoc.py --input <source> --output <doc.md> [--verbose]
#   python gendoc.py                                                # GUI
#
# SUPPORTED PASCAL CONSTRUCTS
# ---------------------------
#   Class definition      TMyClass = class(TBase)      -> Classes and Types
#   Record definition     TMyRecord = record           -> Classes and Types
#   Type alias            TMyType = Integer;           -> Classes and Types
#   External function     function Foo(...): Integer;  -> Methods and Functions
#   External procedure    procedure Bar(...);          -> Methods and Functions
#   Method declaration    procedure Execute; override; -> Methods and Functions
#   Constructor/Destructor constructor Create(...);     -> Methods and Functions
#   Field declaration     FName: String;               -> Fields and Properties
#   Property declaration  property Name: String read FName; -> Fields and Properties
#   Constant declaration  MAX_SIZE = 1024;             -> Constants
#   Variable declaration  var Count: Integer;          -> Fields and Properties
#
# WHAT IS NOT DOCUMENTED
# ----------------------
#   - Implementation bodies (inside begin ... end; blocks)
#   - Implementation signatures (e.g. procedure TMyClass.Execute;)
#   - Local variables inside method bodies
#   - Control flow statements (if, for, while, case, try)
#   - Assignment statements (:=)
#   - Compiler directives ({$IFDEF}, {$DEFINE}, {$I})
#   - Comments without associated declarations (further than 10 lines away)
#
# COMMENT FORMAT
# --------------
#   { FName: The display name of the user. }
#   FName: String;
#
#   { Execute: Main processing loop. }
#   procedure Execute;
#
# HOW IT WORKS
# ------------
#   1. Reading: Multi-encoding fallback (UTF-8, Latin-1, CP1252).
#   2. Parsing: Scans block comments { ... } and looks ahead up to 10 lines
#      for the next non-comment code signature.
#   3. Context Tracking:
#        - Class context: ClassName = class( sets class mode.
#          Members are prefixed with ClassName. in documentation.
#        - Section context: const, type, var keywords set the section
#          for subsequent declarations so they are categorized correctly.
#        - Platform context: {$IFDEF MSWINDOWS} / {$IFDEF UNIX} wraps
#          are tracked using a stack (supports nesting). {$ENDIF} /
#          {$IFEND} restore the previous platform context, preventing
#          platform leakage into subsequent code.
#        - Platform annotation: All items inside an IFDEF block are
#          annotated with the platform name suffix (e.g. Symbol (MSWINDOWS)).
#        - Class boundary: end; resets class context.
#   4. Filtering: Excludes class-qualified implementations, implementation
#      statements, and non-declaration lines.
#   5. Categorization: Types, Methods, Fields, or Constants.
#   6. Generation: Atomic write via temporary file and os.replace().
#
# OUTPUT STRUCTURE
# ----------------
#   # ModuleName (Type) API Documentation
#   **Overview:** Top-level description from the file header.
#   ## Table of Contents
#   ## Classes and Types
#   ## Methods and Functions
#   ## Fields and Properties
#   ## Constants
#
# SAFETY FEATURES
# ---------------
#   - File size limit: Rejects files larger than 10 MB
#   - Atomic writes: Uses temporary files and os.replace() to prevent data loss
#   - Encoding fallback: Tries UTF-8, Latin-1, and CP1252 automatically
#   - Path normalization: Strips whitespace and normalizes paths
#   - Thread safety: GUI operations are marshaled back to the main thread
#   - Input validation: Validates file existence and output path
#
# TROUBLESHOOTING
# ---------------
#   "Source file not found"
#       Verify the input path is correct. Use absolute paths if needed.
#
#   "File size exceeds safety limit"
#       The source file is larger than 10 MB. Increase MAX_FILE_SIZE_BYTES.
#
#   "Could not read file with any supported encoding"
#       Convert the file to UTF-8 before processing.
#
#   "Output file error"
#       Ensure you have write permissions to the output directory.
#
#   Missing declarations in output
#       Ensure comments are directly above declarations (within 10 lines).
#       Use Name: Description format inside { ... } comments.
#
#   Duplicate headings
#       All items inside {$IFDEF} blocks are annotated with the
#       platform name suffix (e.g. Symbol (MSWINDOWS) / (UNIX)).
#
# LIMITATIONS
# -----------
#   - Lookahead window: Only scans 10 lines ahead of a comment.
#   - Simple parsing: Regex-based; may not handle all Pascal syntax edge cases.
#   - No cross-file references: Only processes a single source file at a time.
#   - No nested class tracking: Assumes a flat class structure.
#
# ===========================================================================

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Custom Exceptions
# ---------------------------------------------------------------------------


class DocGeneratorError(Exception):
    """Base exception for documentation generation errors."""


class SourceFileError(DocGeneratorError):
    """Raised when the source Pascal file cannot be read or is invalid."""


class OutputFileError(DocGeneratorError):
    """Raised when the output Markdown file cannot be written."""


# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------


def _normalize_path(file_path: str) -> str:
    """Normalize and validate a filesystem path.

    Args:
        file_path: Raw path string.

    Returns:
        Normalized absolute path.

    Raises:
        ValueError: If the path is empty or results in an empty string.
    """
    normalized = os.path.normpath(file_path.strip())
    if not normalized:
        raise ValueError("Path must not be empty.")
    return normalized


def _read_source_file(file_path: str) -> str:
    """Read a Pascal source file using multi-encoding fallbacks.

    Args:
        file_path: Absolute path to the source file.

    Returns:
        File contents as a string.

    Raises:
        SourceFileError: If the file cannot be read with any supported encoding
            or exceeds the safety size limit.
    """
    if not os.path.isfile(file_path):
        raise SourceFileError(f"Source file not found: {file_path}")

    file_size = os.path.getsize(file_path)
    if file_size > MAX_FILE_SIZE_BYTES:
        raise SourceFileError(
            f"File size exceeds safety limit ({file_size / (1024 * 1024):.1f} MB > {MAX_FILE_SIZE_BYTES / (1024 * 1024):.0f} MB)."
        )

    content = ""
    for encoding in SUPPORTED_ENCODINGS:
        try:
            with open(file_path, "r", encoding=encoding) as fh:
                content = fh.read()
            logger.debug("Successfully read %s with encoding %s", file_path, encoding)
            break
        except (UnicodeDecodeError, MemoryError) as exc:
            logger.debug("Failed to read %s with %s: %s", file_path, encoding, exc)
            continue

    if not content:
        raise SourceFileError(
            "Could not read file with any supported encoding "
            f"({', '.join(SUPPORTED_ENCODINGS)})."
        )

    return content


def _extract_module_title(content: str) -> str:
    """Extract the module title from Pascal source content.

    Args:
        content: Full source file text.

    Returns:
        Human-readable module title string.
    """
    match = re.search(
        r"\b(program|unit|library)\s+([a-zA-Z0-9_]+);",
        content,
        re.IGNORECASE,
    )
    if match:
        module_type = match.group(1).capitalize()
        module_name = match.group(2)
        return f"{module_name} ({module_type}) API Documentation"
    return "Pascal Program Reference"


def _extract_top_description(content: str) -> str:
    """Extract the top-level description block from the source file.

    Args:
        content: Full source file text.

    Returns:
        Description text, or empty string if not found.
    """
    match = re.search(r"^\s*\{\s*(.*?)\s*\}", content, re.DOTALL)
    return match.group(1).strip() if match else ""


def _extract_class_name(code_sig: str) -> Optional[str]:
    """Extract the class name from a class definition signature.

    Args:
        code_sig: Code signature string.

    Returns:
        Class name, or None if not found.
    """
    match = re.search(
        r"\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:class|record)\b",
        code_sig,
        re.IGNORECASE,
    )
    return match.group(1) if match else None


def _is_implementation_signature(code_sig: str) -> bool:
    """Check whether a signature is a class-qualified implementation.

    Args:
        code_sig: Code signature string.

    Returns:
        True if the signature is an implementation body (e.g. TClass.Method).
    """
    return bool(
        re.search(
            r"\b(function|procedure|constructor|destructor)\s+[A-Za-z_][A-Za-z0-9_]*\.",
            code_sig,
            re.IGNORECASE,
        )
    )


def _is_declaration(code_sig: str) -> bool:
    """Check whether a code signature looks like a Pascal declaration.

    Args:
        code_sig: Code signature string.

    Returns:
        True if the signature resembles a declaration.
    """
    decl_pattern = re.compile(
        r"^(?:"
        r"[A-Za-z_][A-Za-z0-9_]*\s*:"  # Name: Type;
        r"|[A-Za-z_][A-Za-z0-9_]*\s*="  # Name = ...
        r"|(?:function|procedure|constructor|destructor)\s+"
        r"|(?:class|type|record|const|var|property|end;)\b"
        r"|[A-Za-z_][A-Za-z0-9_]*\s*=\s*class\s*\("
        r"|[A-Za-z_][A-Za-z0-9_]*\s*=\s*record\b"
        r")",
        re.IGNORECASE,
    )
    return bool(decl_pattern.match(code_sig))


def _is_implementation_statement(code_sig: str) -> bool:
    """Check whether a signature is an implementation statement.

    Args:
        code_sig: Code signature string.

    Returns:
        True if the signature is an implementation statement.
    """
    impl_keywords = (
        "if ",
        "try",
        "begin",
        "case ",
        "for ",
        "while ",
        "repeat",
        "raise ",
        "exit",
        "break",
        "continue",
        "close",
        "free",
        "create",
        "destroy",
        "assign",
        "inherited",
        "result",
        "asm",
        "writeln",
        "write(",
        "read(",
    )
    sig_lower = code_sig.lower()
    return (
        any(sig_lower.startswith(kw) for kw in impl_keywords)
        or ":=" in code_sig
        or sig_lower.startswith("var ")
        or bool(re.match(r"^[a-z][A-Za-z0-9_]*\(", code_sig))
        or sig_lower.startswith(("program ", "unit ", "library "))
    )


def _categorize_signature(
    code_sig: str, section_context: str = "", in_class: bool = False
) -> Optional[str]:
    """Categorize a code signature into a documentation section.

    Args:
        code_sig: Code signature string.
        section_context: The current Pascal section keyword ('const', 'type',
            'var', or empty). Used to disambiguate declarations that lack the
            section keyword on the same line (e.g. ``MY_CONST = 100;`` inside
            a ``const`` block).
        in_class: Whether the signature appears inside a class/record body.
            When True, section context does not override field categorization.

    Returns:
        One of 'methods', 'types', 'constants', 'fields', or None.
    """
    sig_lower = code_sig.lower()
    if sig_lower.startswith(("function", "procedure", "constructor", "destructor")):
        return "methods"
    if "class(" in sig_lower or sig_lower.startswith("type") or "record" in sig_lower:
        return "types"
    if section_context == "const" or sig_lower.startswith("const "):
        return "constants"
    if section_context == "type" and not in_class:
        return "types"
    return "fields"


def parse_pascal_source(file_path: str) -> Dict[str, Any]:
    """Parse a Pascal source file and categorize its docstrings and signatures.

    Reads a Pascal file using multi-encoding fallbacks, extracts the top-level
    module header description, and iterates over lines to locate block comments
    ``{ ... }`` paired with their target code signatures.

    Args:
        file_path: The absolute or relative system path to the Pascal source file.

    Returns:
        A dictionary containing structured documentation data:
            - ``title`` (str): The inferred title of the Pascal module.
            - ``desc`` (str): Top-level overview/description of the file.
            - ``constants`` (List[Dict[str, str]]): Extracted constant definitions.
            - ``types`` (List[Dict[str, str]]): Extracted type/class definitions.
            - ``methods`` (List[Dict[str, str]]): Extracted routine signatures.
            - ``fields`` (List[Dict[str, str]]): Extracted fields/variables.

    Raises:
        SourceFileError: If the file cannot be found, is too large, or cannot
            be decoded.
    """
    file_path = _normalize_path(file_path)
    content = _read_source_file(file_path)
    lines = content.splitlines()

    program_title = _extract_module_title(content)
    program_desc = _extract_top_description(content)

    constants: List[Dict[str, str]] = []
    types_classes: List[Dict[str, str]] = []
    methods: List[Dict[str, str]] = []
    fields: List[Dict[str, str]] = []

    current_class: Optional[str] = None
    in_class: bool = False
    current_platform: str = ""
    platform_stack: List[str] = []
    current_section: str = ""

    comment_pattern = re.compile(r"\{\s*([^$].*?)\s*\}", re.DOTALL)

    for i, line in enumerate(lines):
        stripped = line.strip()
        stripped_lower = stripped.lower()

        # Track structural boundaries
        if stripped == "end;":
            in_class = False
            current_class = None
            current_section = ""
            continue

        # Track platform directives (IFDEF / IFEND / ELSE) using a stack
        ifdef_match = re.match(r"\{\$IFDEF\s+(\w+)\s*\}", stripped, re.IGNORECASE)
        if ifdef_match:
            current_platform = ifdef_match.group(1)
            platform_stack.append(current_platform)
            continue
        if stripped_lower.startswith(("{$endif", "{$ifend")):
            if platform_stack:
                platform_stack.pop()
            current_platform = platform_stack[-1] if platform_stack else ""
            continue
        if stripped_lower.startswith("{$else"):
            current_platform = ""
            continue

        # Track Pascal section keywords (const, type, var) for categorization
        if stripped_lower == "const" or stripped_lower.startswith("const "):
            current_section = "const"
        elif stripped_lower == "type" or stripped_lower.startswith("type "):
            current_section = "type"
        elif stripped_lower == "var" or stripped_lower.startswith("var "):
            current_section = "var"
        elif stripped_lower.startswith("begin"):
            current_section = ""
        elif stripped_lower.startswith("implementation"):
            current_section = ""
            in_class = False
            current_class = None

        match = comment_pattern.search(line)
        if not match:
            continue

        comment_text = match.group(1).strip()
        if not comment_text:
            continue

        # Lookahead: Inspect the next N lines to locate the associated code line
        code_sig = ""
        for next_line in lines[i + 1 : min(i + LOOKAHEAD_LINES + 1, len(lines))]:
            next_stripped = next_line.strip()
            if (
                next_stripped
                and not next_stripped.startswith("{")
                and not next_stripped.startswith("//")
            ):
                code_sig = next_stripped
                break

        if not code_sig:
            continue

        # Track class context: only actual class/record definitions set context
        if re.search(r"=\s*class\s*\(", code_sig, re.IGNORECASE):
            class_name = _extract_class_name(code_sig)
            if class_name:
                current_class = class_name
                in_class = True
            else:
                current_class = None
                in_class = False

        # Skip implementation bodies
        if _is_implementation_signature(code_sig):
            continue

        # Skip implementation statements that are not declarations
        if _is_implementation_statement(code_sig):
            continue

        # Skip anything that doesn't look like a Pascal declaration
        if not _is_declaration(code_sig):
            continue

        # Extract 'SymbolName: Description' pairing if available
        if ":" in comment_text:
            symbol_name, description = comment_text.split(":", 1)
            symbol_name = symbol_name.strip()
            description = description.strip()
        else:
            symbol_name = ""
            description = comment_text

        # Prepend class name to symbol heading ONLY if inside a class definition
        # and the symbol is not the class itself
        display_symbol = symbol_name
        if (
            in_class
            and current_class
            and symbol_name
            and symbol_name != current_class
        ):
            display_symbol = f"{current_class}.{symbol_name}"

        # Append platform suffix to ALL items inside conditional blocks
        if current_platform:
            display_symbol = f"{display_symbol} ({current_platform})"

        entry: Dict[str, str] = {
            "symbol": display_symbol,
            "desc": description,
            "sig": code_sig,
        }

        category = _categorize_signature(code_sig, current_section, in_class)
        if category == "methods":
            methods.append(entry)
        elif category == "types":
            types_classes.append(entry)
        elif category == "constants":
            constants.append(entry)
        elif category == "fields":
            fields.append(entry)

    logger.info(
        "Parsed %s: %d types, %d methods, %d fields, %d constants",
        file_path,
        len(types_classes),
        len(methods),
        len(fields),
        len(constants),
    )

    return {
        "title": program_title,
        "desc": program_desc,
        "constants": constants,
        "types": types_classes,
        "methods": methods,
        "fields": fields,
    }


# ---------------------------------------------------------------------------
# Markdown Generation
# ---------------------------------------------------------------------------


def _write_toc(fh: Any, parsed_data: Dict[str, Any]) -> None:
    """Write the Table of Contents to the Markdown file.

    Args:
        fh: Open file handle.
        parsed_data: Parsed documentation data.
    """
    fh.write("## Table of Contents\n")
    if parsed_data["types"]:
        fh.write("- [Classes and Types](#classes-and-types)\n")
    if parsed_data["methods"]:
        fh.write("- [Methods and Functions](#methods-and-functions)\n")
    if parsed_data["fields"]:
        fh.write("- [Fields and Properties](#fields-and-properties)\n")
    if parsed_data["constants"]:
        fh.write("- [Constants](#constants)\n")
    fh.write("\n---\n\n")


def _write_section(
    fh: Any,
    section_title: str,
    items: List[Dict[str, str]],
    default_symbol: str,
) -> None:
    """Write a documentation section to the Markdown file.

    Args:
        fh: Open file handle.
        section_title: Section heading text.
        items: List of documentation entries.
        default_symbol: Fallback symbol name when none is provided.
    """
    if not items:
        return

    fh.write(f"## {section_title}\n\n")
    for item in items:
        symbol_heading = item["symbol"] if item["symbol"] else default_symbol
        fh.write(f"### `{symbol_heading}`\n")
        fh.write(f"{item['desc']}\n\n")
        if item["sig"]:
            fh.write(f"```pascal\n{item['sig']}\n```\n\n")
    fh.write("---\n\n")


def generate_markdown(parsed_data: Dict[str, Any], output_path: str) -> None:
    """Generate a structured Markdown document from parsed Pascal symbol data.

    Utilizes an atomic write strategy (writing to a temporary file before
    replacement) to prevent file corruption if execution fails unexpectedly.

    Args:
        parsed_data: Dictionary containing module metadata and categorized
            symbol lists.
        output_path: Target filesystem path for the output ``.md`` document.

    Raises:
        OutputFileError: If the output directory cannot be created or the
            temporary file cannot be atomically replaced.
    """
    output_dir = os.path.dirname(os.path.abspath(output_path))
    os.makedirs(output_dir, exist_ok=True)

    temp_fd, temp_path = tempfile.mkstemp(
        dir=output_dir, prefix="doc_tmp_", suffix=".md"
    )

    try:
        with os.fdopen(temp_fd, "w", encoding="utf-8") as fh:
            fh.write(f"# {parsed_data['title']}\n\n")
            if parsed_data["desc"]:
                fh.write(f"**Overview:** {parsed_data['desc']}\n\n")
            fh.write("---\n\n")

            _write_toc(fh, parsed_data)

            _write_section(
                fh, "Classes and Types", parsed_data["types"], "Type Definition"
            )
            _write_section(
                fh, "Methods and Functions", parsed_data["methods"], "Routine"
            )
            _write_section(
                fh, "Fields and Properties", parsed_data["fields"], "Field"
            )
            _write_section(
                fh, "Constants", parsed_data["constants"], "Constant"
            )

        os.replace(temp_path, output_path)
        logger.info("Documentation successfully written to %s", output_path)

    except OSError as exc:
        if os.path.exists(temp_path):
            os.remove(temp_path)
        raise OutputFileError(
            f"Failed to write output file {output_path}: {exc}"
        ) from exc


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _build_parser() -> argparse.ArgumentParser:
    """Build the command-line argument parser.

    Returns:
        Configured ArgumentParser instance.
    """
    parser = argparse.ArgumentParser(
        prog="gendoc",
        description=(
            "FreePascal Documentation Generator. "
            "Extracts docstrings and signatures from Pascal source files "
            "and generates Markdown documentation."
        ),
    )
    parser.add_argument(
        "--input",
        "-i",
        required=False,
        help="Path to the Pascal source file (.lpr, .pas, .pp).",
    )
    parser.add_argument(
        "--output",
        "-o",
        required=False,
        help="Path to the output Markdown file (.md).",
    )
    parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Enable verbose logging output.",
    )
    parser.add_argument(
        "--gui",
        action="store_true",
        help="Force launch the graphical user interface.",
    )
    return parser


def run_cli(args: argparse.Namespace) -> int:
    """Execute the CLI workflow.

    Args:
        args: Parsed command-line arguments.

    Returns:
        Exit code (0 for success, non-zero for failure).
    """
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s: %(message)s",
    )

    if not args.input or not args.output:
        logger.error("Both --input and --output must be provided in CLI mode.")
        return 1

    try:
        parsed = parse_pascal_source(args.input)
        generate_markdown(parsed, args.output)
    except SourceFileError as exc:
        logger.error("Source file error: %s", exc)
        return 1
    except OutputFileError as exc:
        logger.error("Output file error: %s", exc)
        return 1
    except DocGeneratorError as exc:
        logger.error("Documentation generation failed: %s", exc)
        return 1

    return 0


# ---------------------------------------------------------------------------
# GUI
# ---------------------------------------------------------------------------


class DocGeneratorGUI:
    """Tkinter-based Graphical User Interface for the FreePascal DocGenerator.

    Provides file dialogs for selecting source Pascal files and output Markdown
    paths, displays processing states, and offloads heavy file parsing to a
    background thread to keep the main GUI thread responsive.
    """

    def __init__(self, root: tk.Tk) -> None:
        """Initialize the GUI layout, options, widgets, and state variables.

        Args:
            root: The primary Tkinter root window instance.
        """
        self.root = root
        self.root.title("FreePascal DocGenerator")
        self.root.geometry("620x300")
        self.root.resizable(False, False)

        style = ttk.Style()
        style.theme_use("clam")

        frame = ttk.Frame(root, padding=20)
        frame.pack(fill=tk.BOTH, expand=True)

        ttk.Label(
            frame,
            text="Pascal Source File (.lpr / .pas / .pp):",
            font=("Segoe UI", 9, "bold"),
        ).grid(row=0, column=0, sticky="w", pady=(0, 2))

        self.input_entry = ttk.Entry(frame, width=54)
        self.input_entry.grid(row=1, column=0, padx=(0, 5), pady=(0, 12))

        ttk.Button(
            frame,
            text="Browse...",
            command=self.browse_input,
        ).grid(row=1, column=1, pady=(0, 12))

        ttk.Label(
            frame,
            text="Output Markdown Path (.md):",
            font=("Segoe UI", 9, "bold"),
        ).grid(row=2, column=0, sticky="w", pady=(0, 2))

        self.output_entry = ttk.Entry(frame, width=54)
        self.output_entry.grid(row=3, column=0, padx=(0, 5), pady=(0, 15))

        ttk.Button(
            frame,
            text="Browse...",
            command=self.browse_output,
        ).grid(row=3, column=1, pady=(0, 15))

        self.status_var = tk.StringVar(value="Ready")
        self.status_label = ttk.Label(
            frame,
            textvariable=self.status_var,
            font=("Segoe UI", 8, "italic"),
            foreground="gray",
        )
        self.status_label.grid(row=4, column=0, columnspan=2, sticky="w", pady=(0, 5))

        self.gen_btn = ttk.Button(
            frame,
            text="Generate Documentation",
            command=self.start_generation_thread,
        )
        self.gen_btn.grid(row=5, column=0, columnspan=2, sticky="ew", ipady=4)

    def browse_input(self) -> None:
        """Open a file dialog for selecting an input Pascal source file.

        Automatically proposes a default output destination (``DOCUMENTATION.md``)
        if the output path entry field is currently blank.
        """
        filename = filedialog.askopenfilename(
            title="Select Pascal File",
            filetypes=[
                ("Pascal Source Files", "*.lpr *.pas *.pp *.p"),
                ("All Files", "*.*"),
            ],
        )
        if filename:
            normalized_path = os.path.normpath(filename)
            self.input_entry.delete(0, tk.END)
            self.input_entry.insert(0, normalized_path)

            if not self.output_entry.get().strip():
                base_dir = os.path.dirname(normalized_path)
                default_out = os.path.join(base_dir, "DOCUMENTATION.md")
                self.output_entry.insert(0, default_out)

    def browse_output(self) -> None:
        """Open a file dialog for choosing the output Markdown file destination."""
        filename = filedialog.asksaveasfilename(
            title="Save Documentation As",
            defaultextension=".md",
            filetypes=[("Markdown Files", "*.md"), ("All Files", "*.*")],
        )
        if filename:
            self.output_entry.delete(0, tk.END)
            self.output_entry.insert(0, os.path.normpath(filename))

    def set_ui_state(self, is_processing: bool) -> None:
        """Toggle interactive UI controls and update the status label.

        Args:
            is_processing: True to disable controls during generation,
                           False to re-enable when finished.
        """
        state = tk.DISABLED if is_processing else tk.NORMAL
        self.gen_btn.config(state=state)

        if is_processing:
            self.status_var.set("Processing source file...")
            self.status_label.config(foreground="blue")
        else:
            self.status_var.set("Ready")
            self.status_label.config(foreground="gray")

    def start_generation_thread(self) -> None:
        """Validate path inputs and trigger background execution thread."""
        in_path = self.input_entry.get().strip()
        out_path = self.output_entry.get().strip()

        if not in_path:
            messagebox.showerror(
                "Validation Error", "Please select a Pascal input file."
            )
            return

        if not os.path.exists(in_path):
            messagebox.showerror(
                "Validation Error", f"The input file does not exist:\n{in_path}"
            )
            return

        if not out_path:
            messagebox.showerror(
                "Validation Error",
                "Please specify a destination path for the Markdown file.",
            )
            return

        self.set_ui_state(True)

        threading.Thread(
            target=self._worker_process,
            args=(in_path, out_path),
            daemon=True,
        ).start()

    def _worker_process(self, in_path: str, out_path: str) -> None:
        """Worker thread entry point for parsing source and generating file.

        Args:
            in_path: Validated input source path.
            out_path: Target Markdown output path.
        """
        try:
            parsed = parse_pascal_source(in_path)
            generate_markdown(parsed, out_path)
            self.root.after(0, self._on_success, out_path)
        except SourceFileError as exc:
            self.root.after(0, self._on_failure, f"Source file error: {exc}")
        except OutputFileError as exc:
            self.root.after(0, self._on_failure, f"Output file error: {exc}")
        except DocGeneratorError as exc:
            self.root.after(0, self._on_failure, f"Generation error: {exc}")

    def _on_success(self, out_path: str) -> None:
        """Handle successful generation events on the main thread.

        Args:
            out_path: Path where output was written.
        """
        self.set_ui_state(False)
        messagebox.showinfo(
            "Success",
            f"Documentation successfully generated!\n\nSaved to:\n{out_path}",
        )

    def _on_failure(self, error_msg: str) -> None:
        """Handle background task failure events on the main thread.

        Args:
            error_msg: String description of the error encountered.
        """
        self.set_ui_state(False)
        messagebox.showerror(
            "Execution Error",
            f"Failed to generate documentation:\n\n{error_msg}",
        )


# ---------------------------------------------------------------------------
# Entry Points
# ---------------------------------------------------------------------------


def main() -> int:
    """Main entry point for the FreePascal Documentation Generator.

    Parses command-line arguments and dispatches to CLI or GUI mode.

    Returns:
        Exit code (0 for success, non-zero for failure).
    """
    parser = _build_parser()
    args = parser.parse_args()

    if args.gui or (not args.input and not args.output):
        root = tk.Tk()
        app = DocGeneratorGUI(root)
        root.mainloop()
        return 0

    return run_cli(args)


if __name__ == "__main__":
    sys.exit(main())
