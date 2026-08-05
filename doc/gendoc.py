"""FreePascal Documentation Generator.

This module provides a GUI application and backend utilities to extract
docstrings and code signatures from FreePascal source files (.pas, .lpr, .pp)
and compile them into Markdown documentation files (.md).

Features:
    - Safe multi-encoding file reading (UTF-8, Latin-1, CP1252)
    - Threaded file processing to preserve GUI responsiveness
    - Atomic file saving via temporary files to prevent data loss
    - Categorization of symbols into Methods, Types, Constants, and Fields
"""

import os
import re
import sys
import tempfile
import threading
from typing import Any, Dict, List, Tuple
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

# Maximum file size safety threshold to prevent memory exhaustion (10 MB)
MAX_FILE_SIZE_BYTES: int = 10 * 1024 * 1024


def parse_pascal_source(file_path: str) -> Dict[str, Any]:
    """Parses a Pascal source file and categorizes its docstrings and signatures.

    Reads a Pascal file using multi-encoding fallbacks, extracts the top-level
    module header description, and iterates over lines to locate block comments
    `{ ... }` paired with their target code signatures.

    Args:
        file_path: The absolute or relative system path to the Pascal source file.

    Returns:
        A dictionary containing structured documentation data:
            - 'title' (str): The inferred title of the Pascal module.
            - 'desc' (str): Top-level overview/description of the file.
            - 'constants' (List[Dict[str, str]]): Extracted constant definitions.
            - 'types' (List[Dict[str, str]]): Extracted type/class definitions.
            - 'methods' (List[Dict[str, str]]): Extracted routine signatures.
            - 'fields' (List[Dict[str, str]]): Extracted fields/variables.

    Raises:
        FileNotFoundError: If the path provided does not exist or is not a file.
        ValueError: If the file size exceeds MAX_FILE_SIZE_BYTES or cannot be read.
    """
    if not os.path.isfile(file_path):
        raise FileNotFoundError(f"Source file not found: {file_path}")

    # Enforce maximum file size constraint
    file_size = os.path.getsize(file_path)
    if file_size > MAX_FILE_SIZE_BYTES:
        raise ValueError(
            f"File size exceeds safety limit ({file_size / (1024 * 1024):.1f} MB > 10 MB)."
        )

    # Multi-encoding read attempt to accommodate legacy source code encodings
    content: str = ""
    encodings: List[str] = ['utf-8', 'latin-1', 'cp1252']
    for enc in encodings:
        try:
            with open(file_path, 'r', encoding=enc) as f:
                content = f.read()
            break
        except (UnicodeDecodeError, MemoryError):
            continue

    if not content:
        raise ValueError("Could not read file or file is empty.")

    # Extract top module description block if present at the top of the file
    top_desc_match = re.search(r'^\s*\{\s*(.*?)\s*\}', content, re.DOTALL)
    program_desc: str = top_desc_match.group(1).strip() if top_desc_match else ""

    lines: List[str] = content.splitlines()

    # Determine default or explicit module title (program, unit, or library)
    program_title: str = "Pascal Program Reference"
    prog_match = re.search(
        r'\b(program|unit|library)\s+([a-zA-Z0-9_]+);', content, re.IGNORECASE
    )
    if prog_match:
        module_type = prog_match.group(1).capitalize()
        module_name = prog_match.group(2)
        program_title = f"{module_name} ({module_type}) API Documentation"

    # Collections for categorized symbols
    constants: List[Dict[str, str]] = []
    types_classes: List[Dict[str, str]] = []
    methods: List[Dict[str, str]] = []
    fields: List[Dict[str, str]] = []

    # Match standard block comments '{ ... }' while filtering compiler directives '{$ ... }'
    comment_pattern = re.compile(r'\{\s*([^$].*?)\s*\}', re.DOTALL)

    for i, line in enumerate(lines):
        match = comment_pattern.search(line)
        if not match:
            continue

        comment_text = match.group(1).strip()
        if not comment_text:
            continue

        # Lookahead: Inspect the next 10 lines to locate the associated code line
        code_sig: str = ""
        for next_line in lines[i + 1:min(i + 11, len(lines))]:
            stripped = next_line.strip()
            # Ignore blank lines, secondary block comments, and single-line comments
            if stripped and not stripped.startswith('{') and not stripped.startswith('//'):
                code_sig = stripped
                break

        # Extract 'SymbolName: Description' pairing if available
        if ':' in comment_text:
            symbol_name, description = comment_text.split(':', 1)
            symbol_name = symbol_name.strip()
            description = description.strip()
        else:
            symbol_name = ""
            description = comment_text

        entry: Dict[str, str] = {
            'symbol': symbol_name,
            'desc': description,
            'sig': code_sig
        }

        # Categorize entries according to signature keywords
        sig_lower = code_sig.lower()
        if sig_lower.startswith(('function', 'procedure', 'constructor', 'destructor')):
            methods.append(entry)
        elif 'class(' in sig_lower or sig_lower.startswith('type') or 'record' in sig_lower:
            types_classes.append(entry)
        elif sig_lower.startswith('const') or any(k in sig_lower for k in ['job_object', 'instance_prefix']):
            constants.append(entry)
        else:
            fields.append(entry)

    return {
        'title': program_title,
        'desc': program_desc,
        'constants': constants,
        'types': types_classes,
        'methods': methods,
        'fields': fields
    }


def generate_markdown(parsed_data: Dict[str, Any], output_path: str) -> None:
    """Generates a structured Markdown document from parsed Pascal symbol data.

    Utilizes an atomic write strategy (writing to a temporary file before replacement)
    to prevent file corruption if execution fails unexpectedly.

    Args:
        parsed_data: Dictionary containing module metadata and categorized symbol lists.
        output_path: Target filesystem path for the output `.md` document.

    Raises:
        OSError: If directory creation or atomic file replacement fails.
        Exception: Re-raises any writing errors after cleaning temporary files.
    """
    output_dir = os.path.dirname(os.path.abspath(output_path))
    if not os.path.exists(output_dir):
        os.makedirs(output_dir, exist_ok=True)

    # Generate temporary file descriptor in target folder for atomic writing
    temp_fd, temp_path = tempfile.mkstemp(dir=output_dir, prefix="doc_tmp_", suffix=".md")

    try:
        with os.fdopen(temp_fd, 'w', encoding='utf-8') as f:
            # Header section
            f.write(f"# {parsed_data['title']}\n\n")
            if parsed_data['desc']:
                f.write(f"**Overview:** {parsed_data['desc']}\n\n")
            f.write("---\n\n")

            # Table of Contents section
            f.write("## Table of Contents\n")
            if parsed_data['types']:
                f.write("- [Classes & Types](#classes--types)\n")
            if parsed_data['methods']:
                f.write("- [Methods & Functions](#methods--functions)\n")
            if parsed_data['fields']:
                f.write("- [Fields & Properties](#fields--properties)\n")
            if parsed_data['constants']:
                f.write("- [Constants](#constants)\n")
            f.write("\n---\n\n")

            def write_section(section_title: str, items: List[Dict[str, str]], default_symbol: str) -> None:
                """Helper function to format and write individual section groups."""
                if not items:
                    return
                f.write(f"## {section_title}\n\n")
                for item in items:
                    symbol_heading = item['symbol'] if item['symbol'] else default_symbol
                    f.write(f"### `{symbol_heading}`\n")
                    f.write(f"{item['desc']}\n\n")
                    if item['sig']:
                        f.write(f"```pascal\n{item['sig']}\n```\n\n")
                f.write("---\n\n")

            # Write individual documentation sections
            write_section("Classes & Types", parsed_data['types'], "Type Definition")
            write_section("Methods & Functions", parsed_data['methods'], "Routine")
            write_section("Fields & Properties", parsed_data['fields'], "Field")
            write_section("Constants", parsed_data['constants'], "Constant")

        # Atomically replace destination file with completed temp file
        os.replace(temp_path, output_path)

    except Exception:
        # Cleanup temporary residual file in case of error
        if os.path.exists(temp_path):
            os.remove(temp_path)
        raise


class DocGeneratorGUI:
    """Tkinter-based Graphical User Interface for the FreePascal DocGenerator.

    Provides file dialogs for selecting source Pascal files and output Markdown
    paths, displays processing states, and offloads heavy file parsing to a
    background thread to keep the main GUI thread responsive.
    """

    def __init__(self, root: tk.Tk) -> None:
        """Initializes the GUI layout, options, widgets, and state variables.

        Args:
            root: The primary Tkinter root window instance.
        """
        self.root = root
        self.root.title("FreePascal DocGenerator")
        self.root.geometry("620x300")
        self.root.resizable(False, False)

        # Configure global theme style
        style = ttk.Style()
        style.theme_use('clam')

        # Main layout frame
        frame = ttk.Frame(root, padding=20)
        frame.pack(fill=tk.BOTH, expand=True)

        # Input File Selection Controls
        ttk.Label(
            frame,
            text="Pascal Source File (.lpr / .pas / .pp):",
            font=('Segoe UI', 9, 'bold')
        ).grid(row=0, column=0, sticky='w', pady=(0, 2))

        self.input_entry = ttk.Entry(frame, width=54)
        self.input_entry.grid(row=1, column=0, padx=(0, 5), pady=(0, 12))

        ttk.Button(
            frame,
            text="Browse...",
            command=self.browse_input
        ).grid(row=1, column=1, pady=(0, 12))

        # Output File Selection Controls
        ttk.Label(
            frame,
            text="Output Markdown Path (.md):",
            font=('Segoe UI', 9, 'bold')
        ).grid(row=2, column=0, sticky='w', pady=(0, 2))

        self.output_entry = ttk.Entry(frame, width=54)
        self.output_entry.grid(row=3, column=0, padx=(0, 5), pady=(0, 15))

        ttk.Button(
            frame,
            text="Browse...",
            command=self.browse_output
        ).grid(row=3, column=1, pady=(0, 15))

        # Status & Feedback Indicator
        self.status_var = tk.StringVar(value="Ready")
        self.status_label = ttk.Label(
            frame,
            textvariable=self.status_var,
            font=('Segoe UI', 8, 'italic'),
            foreground="gray"
        )
        self.status_label.grid(row=4, column=0, columnspan=2, sticky='w', pady=(0, 5))

        # Primary Action Button
        self.gen_btn = ttk.Button(
            frame,
            text="Generate Documentation",
            command=self.start_generation_thread
        )
        self.gen_btn.grid(row=5, column=0, columnspan=2, sticky='ew', ipady=4)

    def browse_input(self) -> None:
        """Opens a file dialog for selecting an input Pascal source file.

        Automatically proposes a default output destination (`DOCUMENTATION.md`)
        if the output path entry field is currently blank.
        """
        filename = filedialog.askopenfilename(
            title="Select Pascal File",
            filetypes=[("Pascal Source Files", "*.lpr *.pas *.pp *.p"), ("All Files", "*.*")]
        )
        if filename:
            normalized_path = os.path.normpath(filename)
            self.input_entry.delete(0, tk.END)
            self.input_entry.insert(0, normalized_path)

            # Auto-populate output path if empty
            if not self.output_entry.get().strip():
                base_dir = os.path.dirname(normalized_path)
                default_out = os.path.join(base_dir, "DOCUMENTATION.md")
                self.output_entry.insert(0, default_out)

    def browse_output(self) -> None:
        """Opens a file dialog for choosing the output Markdown file destination."""
        filename = filedialog.asksaveasfilename(
            title="Save Documentation As",
            defaultextension=".md",
            filetypes=[("Markdown Files", "*.md"), ("All Files", "*.*")]
        )
        if filename:
            self.output_entry.delete(0, tk.END)
            self.output_entry.insert(0, os.path.normpath(filename))

    def set_ui_state(self, is_processing: bool) -> None:
        """Toggles interactive UI controls and updates the status label.

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
        """Validates path inputs and triggers background execution thread."""
        in_path = self.input_entry.get().strip()
        out_path = self.output_entry.get().strip()

        # Input Validation Checks
        if not in_path:
            messagebox.showerror("Validation Error", "Please select a Pascal input file.")
            return

        if not os.path.exists(in_path):
            messagebox.showerror("Validation Error", f"The input file does not exist:\n{in_path}")
            return

        if not out_path:
            messagebox.showerror("Validation Error", "Please specify a destination path for the Markdown file.")
            return

        self.set_ui_state(True)

        # Launch background worker daemon thread
        threading.Thread(
            target=self._worker_process,
            args=(in_path, out_path),
            daemon=True
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
            # Marshal UI response back onto the main thread safely
            self.root.after(0, self._on_success, out_path)
        except Exception as e:
            self.root.after(0, self._on_failure, str(e))

    def _on_success(self, out_path: str) -> None:
        """Handles successful generation events on the main thread.

        Args:
            out_path: Path where output was written.
        """
        self.set_ui_state(False)
        messagebox.showinfo("Success", f"Documentation successfully generated!\n\nSaved to:\n{out_path}")

    def _on_failure(self, error_msg: str) -> None:
        """Handles background task failure events on the main thread.

        Args:
            error_msg: String description of the error encountered.
        """
        self.set_ui_state(False)
        messagebox.showerror("Execution Error", f"Failed to generate documentation:\n\n{error_msg}")


if __name__ == '__main__':
    root = tk.Tk()
    app = DocGeneratorGUI(root)
    root.mainloop()
