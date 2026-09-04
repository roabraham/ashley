# Coding Guidelines

This document defines the official coding conventions for the project. It applies to every source file, in every language, and to every contributor, human or AI.

All rules below are mandatory. A change that violates a rule in this document is, by definition, not ready for review.

---

## 1. Readability and Structure

The code must be well-structured, well-formatted, fully documented, and easy to read, understand, and update.

* One purpose per file, per unit, per class, per function. Long files are split before they become hard to navigate.
* Prefer clarity over cleverness. Prefer small, single-purpose functions over long, multi-purpose ones.
* No dead code, no commented-out blocks, no abandoned "TODO" notes.
* Every source file starts with a header comment that describes its purpose in one or two sentences.
* Code, identifiers, comments, and documentation are written in English.
* No emojis, no decorative characters, and no non-ASCII glyphs in source files, comments, documentation, or commit messages.

### 1.1 Documentation

* Every public symbol is documented. The contract, inputs, outputs, side effects, and the meaning of every parameter and return value are described in prose.
* Inline comments explain *why*, not *what*. The code already shows what is being done.
* Comments are kept up to date. A stale comment is removed or corrected in the same change as the code it describes.

### 1.2 Formatting

* Indentation is consistent within each file. The width matches the convention of the language already used in the file.
* Tabs are never mixed with spaces.
* No trailing whitespace. Files end with exactly one newline.
* Source files are saved as UTF-8 without BOM.
* Unused imports are removed.

### 1.3 Safety, security, and robustness

* The code is safe, secure, and robust.
* All modifications are verified.

---

## 2. Error and Exception Handling

The code must handle errors and exceptions everywhere, with explicit error codes and/or messages. Silent failure is not allowed.

* Every function or method that can fail must signal failure. The way it signals failure follows the convention of the language in use (exceptions, return codes, tagged results), but the rule is the same: silent failure is not allowed.
* Every error path includes a human-readable message that describes what went wrong and, where possible, why.
* Where appropriate, the message includes the underlying cause (the original system, library, or framework error).
* Errors are handled at the layer where they can be meaningfully acted upon. Lower layers raise or return; upper layers catch, log, and translate.
* Empty catch or except blocks are forbidden in general, because silent failure hides real problems. An empty handler is only acceptable in special cases, such as silent, recoverable errors inside a loop, and must always be accompanied by a comment explaining why swallowing the error is the correct behaviour. In all other cases the empty handler must be removed or replaced with an explicit log statement and a justification.
* Broad catch-all handlers (`Exception`, `Throwable`, etc.) are avoided. The most specific exception type that covers the expected failure is used.
* Resources that need explicit release are protected by the language equivalent of `try ... finally` so they are released on every path.

### 2.1 Error codes and messages

* Every public error path uses an error code in addition to the message. Error codes are stable across releases and are part of the public contract.
* Error codes are consistent within the block where they are used. They may be strings, numbers, or enumerations; the format itself is not fixed, but the chosen format is applied uniformly across the same module, class, unit, or error domain.
* Error messages are full sentences, end with a period, and include enough context for an operator to identify the cause without reading the source.
* Whether error codes are defined as named constants or inlined depends on the surrounding code; the rule is that the chosen approach is applied consistently within the same block.

---

## 3. Naming Conventions

The code must not mix separators, casing, and other naming conventions. Always use the convention already major in the surrounding code.

* When extending an existing file, match what is already there.
* When creating a new file, match the convention of the closest analogous file in the same language and framework.
* Names are descriptive. Single-letter names are restricted to trivial loop counters and mathematical coordinates.
* No name shadows an outer-scope variable without a strong reason. When such a reason exists, the inner variable is renamed rather than the outer one.
* Magic numbers and magic strings are forbidden. Each literal with business meaning is a named constant.

---

## 4. Pascal Coding Conventions

The following rules apply to all Free Pascal and Delphi source files in the project.

### 4.1 Error handling and memory cleanup

* Every function or procedure is wrapped in a `try ... except ... finally ... end` block.
* The outer `try ... finally` block handles memory cleanup. Even on a program crash, allocated memory must be freed. Memory leaks are completely unacceptable.
* The inner `try ... except` block handles error codes and messages for exceptions.
* Usage of `try ... except ... finally` must be consistent across the codebase.

### 4.2 Memory management

* Before freeing any allocated item, always check if it is actually allocated using `Assigned(...)`.
* Never double-free memory.
* Prefer `FreeAndNil` over `Object.Free` when releasing objects.
* Before freeing a node, check whether it is referenced by another pointer. This commonly occurs with JSON objects, where a child node may be part of the root node. Freeing the root node first and then the child node (or vice versa) must not cause an error.

### 4.3 Scope

* Use local variables whenever possible. Global or member variables of a type are introduced only when there is a good reason. Do not make the application unreasonably complicated.

### 4.4 Documentation

* The code is well-documented so that PasDoc can find the documentation comments and generate proper documentation for the code.

---

## 5. PHP Coding Conventions

The following rules apply to all PHP source files in the project. The project uses Symfony 8. The lowest supported PHP version is PHP 8.4. All PHP code must be fully compatible with PHP 8.4.

### 5.1 Structure and formatting

* The code follows the PSR-12 coding standard.
* Indentation is 4 spaces. Tabs are never mixed with spaces.
* No trailing whitespace. Files end with exactly one newline.
* Source files are saved as UTF-8 without BOM.
* Unused imports are removed.
* One purpose per file, per class, per method. Long files are split before they become hard to navigate.
* Names are descriptive. Single-letter names are restricted to trivial loop counters and mathematical coordinates.
* No unnecessary shortings. The code is developer-friendly and easy to understand and update.

### 5.2 Documentation

* The code is well-documented so that Doxygen can find the documentation comments and generate proper documentation for the code.
* Every public class, method, and function has a documentation block that describes its purpose, parameters, return values, and possible exceptions.
* Inline comments explain *why*, not *what*. The code already shows what is being done.
* Comments are kept up to date. A stale comment is removed or corrected in the same change as the code it describes.

### 5.3 Type declarations

* Every method and function declares parameter types and return types.
* Strict types are declared at the top of every file.
* Nullable types are written explicitly.
* Properties are typed.

### 5.4 Error handling

* Failure is signalled by throwing an exception. Functions document their possible exceptions.
* Empty catch blocks are forbidden in general. An empty handler is only acceptable in special cases, such as silent, recoverable errors inside a loop, and must always be accompanied by a comment explaining why swallowing the error is the correct behaviour.
* Broad catch-all handlers are avoided. The most specific exception type that covers the expected failure is used.

### 5.5 Symfony conventions

* Services are obtained through constructor injection.
* Controllers extend the Symfony AbstractController or use attributes for routing.
* One responsibility per service. Fat controllers or services are split into smaller, focused classes.

---

## 6. JavaScript Coding Conventions

The following rules apply to all JavaScript source files in the project.

### 6.1 Language version and compatibility

* The code uses pure ES6 (ECMAScript 2015) features.
* The code maintains 100% cross-browser compatibility among all major browsers (Chrome, Firefox, Edge, Safari, etc.).
* Instead of browser detection, feature detection is used with fallback implementation if a special feature is not supported by a browser.

### 6.2 Structure and formatting

* The code is well formatted, structured, and easy to read.
* One purpose per file, per function, per class. Long files are split before they become hard to navigate.
* Prefer clarity over cleverness. Prefer small, single-purpose functions over long, multi-purpose ones.
* No dead code, no commented-out blocks, no abandoned "TODO" notes.
* Names are descriptive. Single-letter names are restricted to trivial loop counters and mathematical coordinates.
* No unnecessary shortings. The code is developer-friendly and easy to understand and update.

### 6.3 Documentation

* The code is well-documented so that Doxygen can find the documentation comments and generate proper documentation for the code.
* Every public function, class, and method has a documentation block that describes its purpose, parameters, return values, and possible exceptions.
* Inline comments explain *why*, not *what*. The code already shows what is being done.
* Comments are kept up to date. A stale comment is removed or corrected in the same change as the code it describes.

### 6.4 Error handling

* Failure is signalled by throwing an error or returning a rejected Promise. Functions document their possible exceptions.
* Empty catch blocks are forbidden in general. An empty handler is only acceptable in special cases, such as silent, recoverable errors inside a loop, and must always be accompanied by a comment explaining why swallowing the error is the correct behaviour.
* Broad catch-all handlers are avoided. The most specific error type that covers the expected failure is used.
* Network errors, JSON parse errors, and DOM errors are caught and surfaced to the user with a visible message.
* Promises are awaited or returned; floating promise chains are forbidden.

### 6.5 Browser compatibility

* Feature detection is used instead of browser detection.
* When a feature is not supported by a browser, a fallback implementation is provided.

---

## 7. AI Contributor Instructions

Any AI assistant contributing to this repository must, in addition to all the rules above:

* Read this `GUIDELINES.md` in full before producing or modifying any file.
* Read the existing source of the file being changed, and of its closest neighbours in the same directory, to learn the local conventions.
* Match the surrounding style. When the local style conflicts with a general rule in this document, the local style wins for that file, but the discrepancy is reported in the change description so it can be reconciled.
* **Implement only what was asked.** Do not rewrite entire components and do not expand the scope of a task beyond the user's request. Make as minimal a change as possible, and only touch the code that is required to satisfy the request.
* **Coding guidelines apply to new code and to refactored code only.** Do not modify a working component just because it does not follow these guidelines. Existing, working code is left untouched unless the user explicitly asks for the change.
* Never invent or modify a public API without documenting the change in the same change.
* Never introduce a new dependency without explicit approval.
* Never delete or rewrite existing tests. Tests are updated alongside the code they cover, never silently replaced.
* Never commit secrets or generated artifacts.
* When unsure about a rule, prefer the more restrictive interpretation and ask before acting.

---

End of document.
