/**
 * =============================================================================
 * Chatbot Application - Main JavaScript
 * =============================================================================
 * A robust, ES6-based cross-browser chat client that supports both legacy
 * (proxy-based) and streaming (direct llama.cpp) response modes.
 *
 * Features:
 * - Automatic fallback to defaults for any misconfigured values
 * - Client-side chat history storage for streaming mode
 * - Context window management via compression API
 * - Streaming response handling with proper error recovery
 * - HTML escaping for XSS prevention
 * - Memory-safe audio playback
 * - Bootstrap-based confirmation modal for accessibility
 * - Keyboard navigation (TAB + Arrow keys)
 * - New session reset with confirmation
 *
 * Compatibility: all modern browsers (Edge, Chrome, Firefox, Safari) and embedded
 * runtimes such as PHP Desktop (Chromium 2025) — ES6+.
 * Built on the ES6 standard (no IE/EdgeHTML transpilation needed). Browser-specific
 * compatibility shims were dropped; the modal accessibility layer (focus trap +
 * dismiss) is intentionally retained for embedded runtimes where Bootstrap's own
 * handlers do not fire reliably.
 *
 * AUDIT LOG (bugs fixed from original AI-generated version):
 * - BUG-1 [CRITICAL]: Streaming double-callback: finish_reason=stop AND result.done
 *   could both fire callback(). Fixed with a `completed` flag per stream.
 * - BUG-3 [CRITICAL]: compressHistoryViaApi .catch() and "unknown response" paths never
 *   called callback(). Caused permanent UI deadlock (isProcessing stuck true, input
 *   disabled forever). Fixed: callback() now called in all failure branches.
 * - BUG-4 [HIGH]: res.body.getReader() called without null-checking res.body first.
 *   Throws TypeError in some environments. Fixed with explicit null guard.
 * - BUG-6 [HIGH]: connectToLlamaDirect recursively called itself via
 *   compressHistoryViaApi with no depth guard. If compression never reduced tokens
 *   enough, infinite recursion → stack overflow. Fixed with skipCompression flag.
 * - BUG-2 [MEDIUM]: var replyText declared 3× in proceedWithSend callback via var
 *   hoisting. Correct-by-accident; renamed to distinct variables for clarity.
 * - BUG-5/7 [MEDIUM]: data.response_mode read before null/type guard in
 *   proceedWithSend. Reordered: null/type guard now comes first.
 * - WARN-2: SSE [DONE] sentinel used endsWith('[done]') which could match suffixes.
 *   Fixed to exact-match comparison after toLowerCase().
 * - WARN-4: reader.cancel() not called on early finish_reason exit. Fixed.
 * - WARN-7: Empty assistantMessage could be pushed to history on stream done.
 *   Fixed with length guard.
 * - BUG-8 [HIGH]: In response mode 2 the summarise POST to /api/chat performs a
 *   synchronous blocking LLM call. If that call is slow the request could appear to
 *   hang and the client saw an opaque failure ("Compression request failed: HTTP 404")
 *   even though summarisation on the LLM side had actually completed. Fixed on the
 *   client by issuing the request via fetch() with a native AbortController timeout
 *   derived from the configured request_timeout (always strictly below the server's
 *   own authoritative limit, and never sent to or overridden on the server), with
 *   bounded retry/back-off and in-flight request dedupe so a momentarily slow
 *   summarisation cannot wedge the chat. The web server's FastCGI timeout was removed
 *   so PHP runs up to its own max_execution_time; the server keeps sole authority
 *   over request duration (no client-influenced DDoS vector).
 * Additional hardening: role validation, config bounds checking, res.body null guard,
 * transformer try-catch, sender validation, idempotent finishProcessing, stream
 * abort on new session.
 *
 * This module is written as a single IIFE that loads directly via a <script> tag
 * (no bundler/transpilation), so it stays 100% ES6: const/let, arrow functions,
 * template literals, for...of, classes-free modules, async/await, and the native
 * AbortController/fetch/Streams APIs.
 *
 * NOTE: this client deliberately KEEPS the modal accessibility layer (focus trap
 * in handleModalKeydown, dismiss handling for [data-bs-dismiss]/.btn-close, and
 * focus-return on close). Bootstrap 5's own enforceFocus/keydown handlers are not
 * relied upon because they have been observed not to fire reliably in some embedded
 * runtimes — see showModal/hideModal. The TextDecoder usage is the native API
 * (no polyfill); feature-detection guards remain where the Streams API may be absent.
 * =============================================================================
 */

(function () {
    'use strict';

    // =============================================================================
    // SECTION 1: CONFIGURATION & DEFAULTS
    // =============================================================================

    /**
     * Default configuration values.
     * Used as fallback when PHP/Twig-injected globals are absent or malformed.
     */
    const DEFAULT_CONFIG = {
        CHATBOT_NAME: 'ChatBot',
        INITIAL_MESSAGE: null,
        MEMORY_MODE: 1, // 1 = prune (default), 2 = summarize (pseudo-infinite)
        RESPONSE_MODE: 1, // 1 = legacy (proxy), 2 = streaming (direct)
        LLM_ENDPOINT: '/v1/chat/completions',
        LLM_CTX_SIZE: 8192,
        LLM_MAX_RESPONSE_TOKENS: 2048,
        SAFETY_MARGIN: 256,
        EMBEDDING_ENABLED: true,
        LLM_ENABLED: true,
        SYSTEM_PROMPT: null,
        API_ENDPOINT: '/api/chat',
        REQUEST_TIMEOUT: 60 // server-configured request timeout (seconds)
    };

    /** Allowed message role values. Anything else is rejected on import/load. */
    const VALID_ROLES = { user: true, assistant: true, system: true };

    /**
     * Application state — single source of truth.
     */
    const AppState = {
        isProcessing: false,
        thinkingMessageDiv: null,
        currentAudio: null,
        streamingController: null,
        streamingMessageDiv: null,
        lastUserMessageDiv: null,
        userStoppedStream: false,
        memoryMode: DEFAULT_CONFIG.MEMORY_MODE,
        responseMode: DEFAULT_CONFIG.RESPONSE_MODE,
        chatHistory: [],
        hasSessionConversation: false,
        llmEndpoint: DEFAULT_CONFIG.LLM_ENDPOINT,
        llmCtxSize: DEFAULT_CONFIG.LLM_CTX_SIZE,
        llmMaxResponseTokens: DEFAULT_CONFIG.LLM_MAX_RESPONSE_TOKENS,
        safetyMargin: DEFAULT_CONFIG.SAFETY_MARGIN,
        embeddingEnabled: DEFAULT_CONFIG.EMBEDDING_ENABLED,
        llmEnabled: DEFAULT_CONFIG.LLM_ENABLED,
        warningThreshold: 0,
        systemPrompt: DEFAULT_CONFIG.SYSTEM_PROMPT,
        chatbotName: DEFAULT_CONFIG.CHATBOT_NAME,
        apiEndpoint: DEFAULT_CONFIG.API_ENDPOINT,
        requestTimeout: DEFAULT_CONFIG.REQUEST_TIMEOUT
    };

    /**
     * Cached DOM element references. Populated once in initDOM().
     */
    const DOM = {
        form: null,
        input: null,
        chatBox: null,
        submitBtn: null,
        stopBtn: null,
        importInput: null
    };

    /** Currently visible modal element for focus-trap management. */
    let activeModalEl = null;

    // =============================================================================
    // SECTION 2: UTILITY FUNCTIONS
    // =============================================================================

    /**
     * Safely read a configuration value from the global (window) scope.
     * Falls back to defaultValue for: undefined, null, or transformer errors.
     *
     * @param {string}   name         - Global variable name to read.
     * @param {*}        defaultValue - Value returned when the global is absent/invalid.
     * @param {function} [transformer] - Optional coercion function applied to the raw value.
     * @returns {*}
     */
    function getConfigValue(name, defaultValue, transformer) {
        try {
            if (typeof window[name] === 'undefined') { return defaultValue; }
            const value = window[name];
            if (value === null || value === undefined) { return defaultValue; }
            if (typeof transformer === 'function') {
                try {
                    return transformer(value);
                } catch (te) {
                    console.warn(`[Config] Transformer error for ${name}:`, te.message);
                    return defaultValue;
                }
            }
            return value;
        } catch (e) {
            console.warn(`[Config] Error reading ${name}:`, e.message);
            return defaultValue;
        }
    }

    /**
     * Parse an integer safely, accepting numeric strings, floats (truncated),
     * and anything parseInt() normally handles. Returns defaultValue on failure.
     *
     * @param {*}      value
     * @param {number} defaultValue
     * @returns {number}
     */
    function parseIntSafe(value, defaultValue) {
        try {
            if (value === null || value === undefined || value === '') { return defaultValue; }
            const parsed = parseInt(String(value), 10);
            return isNaN(parsed) ? defaultValue : parsed;
        } catch (e) {
            return defaultValue;
        }
    }

    /**
     * Escape HTML special characters to prevent XSS.
     * Non-string input returns an empty string rather than throwing.
     *
     * @param {*} text
     * @returns {string}
     */
    function escapeHtml(text) {
        if (typeof text !== 'string') { return ''; }
        const map = {
            '&': '&amp;',
            '<': '&lt;',
            '>': '&gt;',
            '"': '&quot;',
            "'": '&#039;'
        };
        return text.replace(/[&<>"']/g, (char) => map[char]);
    }

    /**
     * Convert markdown-style text to HTML for chat bubbles.
     *
     * Fenced code blocks (``` ... ```) are rendered as <pre><code> blocks
     * with preserved indentation. Inline code (`...`) is rendered as <code>.
     * All other text is HTML-escaped and newlines become <br/>.
     *
     * @param {string} text - Raw message text.
     * @returns {string} Safe HTML string for insertion into a bubble.
     */
    function formatMessageText(text) {
        if (typeof text !== 'string' || text.length === 0) { return ''; }
        const segments = text.split(/```/g);
        const result = [];
        for (let i = 0; i < segments.length; i++) {
            if (i % 2 === 1) {
                let code = segments[i];
                const firstLineEnd = code.indexOf('\n');
                if (firstLineEnd > -1) {
                    const possibleLang = code.substring(0, firstLineEnd).trim();
                    if (possibleLang.length > 0 && possibleLang.indexOf(' ') === -1) {
                        code = code.substring(firstLineEnd + 1);
                    }
                }
                if (code.length > 0 && code.charAt(code.length - 1) === '\n') {
                    code = code.slice(0, -1);
                }
                result.push('<pre><code>' + escapeHtml(code) + '</code></pre>');
                continue;
            }
            let segment = segments[i];
            segment = segment.replace(/`([^`]+)`/g, function(_, code) {
                return '<code>' + escapeHtml(code) + '</code>';
            });
            segment = segment.replace(/\n/g, '<br/>');
            result.push(segment);
        }
        return result.join('');
    }

    /**
     * Return true if value is a plain object (not null, not array, not Date, etc.).
     *
     * @param {*} value
     * @returns {boolean}
     */
    function isPlainObject(value) {
        return value !== null &&
               typeof value === 'object' &&
               !Array.isArray(value) &&
               Object.prototype.toString.call(value) === '[object Object]';
    }

    /**
     * Validate a single chat message entry.
     * Must be a plain object with a string role from VALID_ROLES and a string content.
     *
     * @param {*} msg
     * @returns {boolean}
     */
    function isValidMessage(msg) {
        if (!isPlainObject(msg)) { return false; }
        if (typeof msg.role !== 'string') { return false; }
        if (VALID_ROLES[msg.role.trim()] !== true) { return false; }
        return (typeof msg.content === 'string');
    }

    /**
     * Safe localStorage wrapper. All methods return null/false on error.
     */
    const Storage = {
        getItem(key) {
            try { return localStorage.getItem(key); }
            catch (e) { console.warn('[Storage] Read error:', e.message); return null; }
        },
        setItem(key, value) {
            try { localStorage.setItem(key, value); return true; }
            catch (e) { console.warn('[Storage] Write error:', e.message); return false; }
        },
        removeItem(key) {
            try { localStorage.removeItem(key); return true; }
            catch (e) { console.warn('[Storage] Remove error:', e.message); return false; }
        }
    };

    /**
     * Return the configured API endpoint URL.
     *
     * @returns {string}
     */
    function getApiUrl() {
        return AppState.apiEndpoint || DEFAULT_CONFIG.API_ENDPOINT || '/api/chat';
    }

    /**
     * Bootstrap-based confirmation modal helper.
     * Falls back to direct callback execution when Bootstrap or the modal markup is absent.
     */
    const ConfirmModal = {
        /**
         * Show a confirmation modal and invoke onConfirm when the user accepts.
         *
         * @param {string}   message   - Prompt text shown inside the modal.
         * @param {function} onConfirm - Callback invoked on confirmation.
         */
        show(message, onConfirm) {
            const modalEl   = document.getElementById('confirm-modal');
            const messageEl = document.getElementById('confirm-message');
            const okBtn     = document.getElementById('confirm-ok-btn');
            if (!modalEl || !messageEl || !okBtn) {
                // Modal markup missing — proceed immediately.
                if (typeof onConfirm === 'function') { onConfirm(); }
                return;
            }
            messageEl.textContent = message;
            // Store the pending callback; the OK button's handler is bound once
            // (see initEvents) so we never clone/replace the node — cloning left a
            // detached element that could hold focus and swallow Enter in some
            // embedded runtimes.
            confirmCallback = (typeof onConfirm === 'function') ? onConfirm : null;
            showModal(modalEl);
        }
    };

    /**
     * Show an error modal with the supplied message.
     *
     * @param {string} message
     */
    function showErrorModal(message) {
        const modalEl   = document.getElementById('error-modal');
        const messageEl = document.getElementById('error-message');
        if (!modalEl || !messageEl) {
            // Fallback: log to console if markup is missing.
            console.error('[Error Modal]', message);
            return;
        }
        messageEl.textContent = typeof message === 'string' ? message : String(message);
        showModal(modalEl);
    }

    /**
     * Return the element that should receive initial focus when a modal opens.
     * Per WAI-ARIA dialog guidance, focus goes to the primary/confirm action
     * (not the close "✕" button, which appears first in the DOM). Falls back to
     * the first focusable element, then the modal itself.
     *
     * @param {HTMLElement} modalEl
     * @returns {HTMLElement}
     */
    function getFocusTarget(modalEl) {
        const primary = modalEl.querySelector('.modal-footer .btn-primary, #confirm-ok-btn');
        if (primary && !primary.disabled) { return primary; }
        const focusableSelectors =
            'a[href], button:not([disabled]):not(.btn-close), input:not([disabled]), ' +
            'select:not([disabled]), textarea:not([disabled]), ' +
            '[tabindex]:not([tabindex="-1"])';
        const focusable = modalEl.querySelectorAll(focusableSelectors);
        return (focusable.length > 0) ? focusable[0] : modalEl;
    }

    /**
     * Keyboard handling for the open modal: Tab/Shift+Tab cycling and Escape to
     * close. Only acts on Tab/Escape so Enter/Space keep activating controls
     * normally. Works across all ES6-capable browsers and embedded runtimes.
     *
     * @param {KeyboardEvent} e
     */
    function handleModalKeydown(e) {
        if (!activeModalEl) { return; }
        if (e.key === 'Escape') {
            e.preventDefault();
            hideModal(activeModalEl);
            return;
        }
        if (e.key !== 'Tab') { return; }
        const focusable = activeModalEl.querySelectorAll(
            'a[href], button:not([disabled]), input:not([disabled]), ' +
            'select:not([disabled]), textarea:not([disabled]), ' +
            '[tabindex]:not([tabindex="-1"])'
        );
        if (focusable.length === 0) {
            e.preventDefault();
            activeModalEl.focus();
            return;
        }
        const first = focusable[0];
        const last  = focusable[focusable.length - 1];
        if (e.shiftKey) {
            if (document.activeElement === first ||
                    !activeModalEl.contains(document.activeElement)) {
                last.focus();
                e.preventDefault();
            }
        } else {
            if (document.activeElement === last ||
                    !activeModalEl.contains(document.activeElement)) {
                first.focus();
                e.preventDefault();
            }
        }
    }

    /**
     * The element that opened the current modal, so focus can return to it on
     * close. Captured defensively so a native file dialog (which steals focus
     * mid-flow) cannot leave it pointing at a stale/hidden element.
     * @type {HTMLElement|null}
     */
    let modalOpenerEl = null;

    /** Pending confirm callback, invoked when the OK button is activated. */
    let confirmCallback = null;

    /**
     * Confirm the currently open confirmation modal: hide it and run the
     * stored callback (if any). Bound once to the OK button in initEvents.
     */
    function confirmModalOk() {
        const cb = confirmCallback;
        confirmCallback = null;
        const modalEl = document.getElementById('confirm-modal');
        if (modalEl) { hideModal(modalEl); }
        if (typeof cb === 'function') { cb(); }
    }

    /**
     * Show a modal and move focus into it.
     *
     * We drive the modal entirely ourselves (display + .show class) and do NOT
     * use bootstrap.Modal: Bootstrap 5 installs its own enforceFocus/keydown
     * handlers on the document, which have been observed to conflict with the
     * handling below in some environments. Owning the modal fully keeps
     * keyboard control predictable. The .modal/.modal-dialog markup is
     * unchanged, so Bootstrap's styles still apply.
     *
     * Note: on embedded Chromium/CEF hosts, keyboard focus can fail to return
     * to the page after a *native* OS dialog (e.g. the file-import picker)
     * closes. That is a focus-handoff issue in the native host application
     * embedding the browser, not something a web page can reliably correct —
     * CEF's own focus callbacks don't fire in that state either, so there is
     * no DOM-level signal to hook. It needs a fix on the host side (e.g. the
     * host explicitly reclaiming input focus for the browser widget when the
     * app window is reactivated). This function still does the correct,
     * standard thing for every environment where focus behaves normally.
     *
     * @param {HTMLElement} modalEl
     */
    function showModal(modalEl) {
        // Record the opener only if it is a connected, visible element that is
        // not itself inside a modal — otherwise keep the previously known opener.
        const candidate = document.activeElement;
        if (candidate instanceof HTMLElement &&
                candidate.isConnected &&
                !candidate.closest('.modal') &&
                candidate !== modalEl) {
            modalOpenerEl = candidate;
        }
        modalEl.setAttribute('tabindex', '-1');
        modalEl.style.display = 'block';
        modalEl.style.backgroundColor = 'rgba(0,0,0,0.5)';
        modalEl.classList.add('show');
        activeModalEl = modalEl;
        document.addEventListener('keydown', handleModalKeydown);
        // Move focus into the modal immediately so keyboard users start inside it.
        try {
            getFocusTarget(modalEl).focus();
        } catch (e) {
            console.warn('[Modal] Could not move focus into modal:', e.message);
        }
    }

    /**
     * Hide the modal and restore focus to the element that opened it.
     *
     * @param {HTMLElement} modalEl
     */
    function hideModal(modalEl) {
        if (activeModalEl === modalEl) {
            activeModalEl = null;
            document.removeEventListener('keydown', handleModalKeydown);
        }
        modalEl.style.display = 'none';
        modalEl.classList.remove('show');
        // Return focus to the opener if it is still usable; fall back to the
        // chat input, then body, so focus never gets trapped on a closed modal.
        const nextFocus = (modalOpenerEl && modalOpenerEl.isConnected) ? modalOpenerEl : DOM.input;
        modalOpenerEl = null;
        try {
            if (nextFocus && typeof nextFocus.focus === 'function') {
                nextFocus.focus();
            } else if (document.body) {
                document.body.focus();
            }
        } catch (e) {
            console.warn('[Modal] Could not restore focus after close:', e.message);
        }
    }


    // =============================================================================
    // SECTION 3: TOKEN ESTIMATION & HISTORY MANAGEMENT
    // =============================================================================

    /**
     * Estimate token count for a text string using a character-based heuristic.
     * Deliberately fast and approximate (±20 % typical).
     *
     * @param {string} text
     * @returns {number}
     */
    function estimateTokens(text) {
        if (typeof text !== 'string' || text.length === 0) { return 0; }
        return Math.ceil(text.length / 2.5);
    }

    /**
     * Calculate the total estimated token count of the current chat history,
     * optionally including a pending user message that has not yet been appended.
     * Also includes the system prompt because it is always prepended to the
     * message payload sent to the LLM. Uses the same content-only heuristic
     * as the PHP backend (no role prefix).
     *
     * @param {string} [pendingMessage] - Message about to be sent.
     * @returns {number}
     */
    function getHistoryTokenCount(pendingMessage) {
        let total = 0;
        if (!Array.isArray(AppState.chatHistory)) { return 0; }
        for (const msg of AppState.chatHistory) {
            if (!isValidMessage(msg)) { continue; }
            total += estimateTokens(msg.content);
        }
        if (typeof pendingMessage === 'string' && pendingMessage.length > 0) {
            total += estimateTokens(pendingMessage);
        }
        if (typeof AppState.systemPrompt === 'string' && AppState.systemPrompt.length > 0) {
            total += estimateTokens(AppState.systemPrompt);
        }
        return total;
    }

    /**
     * Persist AppState.chatHistory to localStorage and refresh the export button.
     */
    function saveHistoryToStorage() {
        try {
            if (!Array.isArray(AppState.chatHistory)) { AppState.chatHistory = []; }
            Storage.setItem('assistant_chat_history', JSON.stringify(AppState.chatHistory));
            updateExportButtonVisibility();
        } catch (e) {
            console.warn('[History] Save failed:', e.message);
        }
    }

    /**
     * Show or hide the export button depending on whether there is anything to export.
     */
    function updateExportButtonVisibility() {
        const exportBtn = document.getElementById('export-conversation-btn');
        if (!exportBtn) { return; }
        let hasData;
        if (AppState.responseMode === 2) {
            hasData = Array.isArray(AppState.chatHistory) && AppState.chatHistory.length > 0;
        } else {
            hasData = AppState.hasSessionConversation === true;
        }
        exportBtn.style.display = hasData ? '' : 'none';
    }

    /**
     * Load chat history from localStorage into AppState.chatHistory.
     * Invalid or unrecognised entries are silently discarded.
     */
    function loadHistoryFromStorage() {
        try {
            const stored = Storage.getItem('assistant_chat_history');
            if (!stored) { AppState.chatHistory = []; return; }
            const parsed = JSON.parse(stored);
            if (!Array.isArray(parsed)) { AppState.chatHistory = []; return; }
            AppState.chatHistory = parsed.filter(isValidMessage);
        } catch (e) {
            console.warn('[History] Load failed:', e.message);
            AppState.chatHistory = [];
        }
    }

    /**
     * Clear the in-memory history and remove it from localStorage.
     */
    function clearHistory() {
        AppState.chatHistory = [];
        Storage.removeItem('assistant_chat_history');
    }

    /**
     * Fetch the conversation history from the API (response mode 1 only)
     * and render each message into the chat box.
     */
    function fetchConversationHistoryFromApi() {
        fetch(getApiUrl(), {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ action: 'get_conversation_history' })
        })
        .then((res) => {
            if (!res.ok) { throw new Error('HTTP ' + res.status); }
            return res.json();
        })
        .then((data) => {
            if (isPlainObject(data) && data.success === true &&
                    Array.isArray(data.conversation_history)) {
                for (const msg of data.conversation_history) {
                    if (!isValidMessage(msg)) { continue; }
                    appendMessage(msg.role, msg.content);
                }
            }
        })
        .catch((err) => {
            console.warn('[History] Fetch from API failed:', err.message);
        });
    }

    /**
     * Export the current conversation to a JSON file download.
     * In streaming mode (2) uses the in-memory history; in legacy mode (1)
     * requests the serialised history from the API.
     */
    function exportConversation() {
        if (AppState.responseMode === 2) {
            const dataToExport = Array.isArray(AppState.chatHistory) ? AppState.chatHistory : [];
            if (dataToExport.length === 0) {
                showErrorModal('There is no data to export!');
                return;
            }
            triggerJsonDownload(
                JSON.stringify(dataToExport, null, 2),
                `conversation_${isoFilenameTimestamp()}.json`
            );
            return;
        }
        // Mode 1: server-side export.
        fetch(getApiUrl(), {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ action: 'export_conversation' })
        })
        .then((res) => res.text())
        .then((text) => {
            // The server may return a JSON error envelope or raw JSON data.
            // Attempt to detect an error envelope; if it is one, throw.
            // If not (SyntaxError or no error key), treat the raw text as the export.
            try {
                const data = JSON.parse(text);
                if (isPlainObject(data) && data.error) {
                    throw new Error(data.message || 'Failed to export conversation');
                }
            } catch (e) {
                if (!(e instanceof SyntaxError)) { throw e; }
                // SyntaxError → raw non-JSON body (unusual but handled).
            }
            triggerJsonDownload(text, `conversation_${isoFilenameTimestamp()}.json`);
        })
        .catch((err) => {
            console.warn('[Export] Error:', err.message);
            showErrorModal('Failed to export conversation: ' + err.message);
        });
    }

    /**
     * Trigger a browser file download with JSON content.
     *
     * @param {string} jsonContent - The string content to download.
     * @param {string} filename    - Suggested filename for the download.
     */
    function triggerJsonDownload(jsonContent, filename) {
        try {
            const blob = new Blob([jsonContent], { type: 'application/json' });
            const url  = URL.createObjectURL(blob);
            const a    = document.createElement('a');
            a.href     = url;
            a.download = filename;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);
        } catch (e) {
            console.warn('[Download] Failed:', e.message);
            showErrorModal('Download failed: ' + e.message);
        }
    }

    /**
     * Return an ISO 8601 timestamp string safe for use in filenames
     * (colons and dots replaced with hyphens, trimmed to seconds).
     *
     * @returns {string}  e.g. "2025-04-15T14-30-00"
     */
    function isoFilenameTimestamp() {
        return new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
    }

    /**
     * Import a conversation from a JSON File object.
     * Validates structure and role values before accepting.
     *
     * @param {File} file
     */
    function importConversation(file) {
        if (!file) { return; }
        const reader = new FileReader();
        reader.onload = (e) => {
            try {
                const importedData = JSON.parse(e.target.result);
                if (!Array.isArray(importedData)) {
                    throw new Error('Invalid format: expected a JSON array.');
                }
                const validMessages = importedData
                    .filter(isValidMessage)
                    .map((msg) => ({
                        role: msg.role.trim(),
                        content: msg.content.trim()
                    }))
                    .filter((msg) => msg.content.length > 0);
                if (validMessages.length === 0) {
                    throw new Error('No data to import! The file contains no valid messages.');
                }
                if (AppState.responseMode === 2) {
                    AppState.chatHistory = validMessages;
                    saveHistoryToStorage();
                    if (DOM.chatBox) { DOM.chatBox.innerHTML = ''; }
                    AppState.lastUserMessageDiv = null;
                    displayInitialMessage();
                    displayChatHistory();
                    updateExportButtonVisibility();
                    return;
                }
                // Mode 1: send file to server.
                const formData = new FormData();
                formData.append('action', 'import_conversation');
                formData.append('conversation_file', file);
                fetch(getApiUrl(), { method: 'POST', body: formData })
                .then((res) => {
                    if (!res.ok) { throw new Error('HTTP ' + res.status); }
                    return res.json();
                })
                .then((data) => {
                    if (isPlainObject(data) && data.success === true &&
                            Array.isArray(data.conversation_history)) {
                        if (DOM.chatBox) { DOM.chatBox.innerHTML = ''; }
                        AppState.lastUserMessageDiv = null;
                        displayInitialMessage();
                        for (const msg of data.conversation_history) {
                            if (!isValidMessage(msg)) { continue; }
                            appendMessage(msg.role.trim(), msg.content.trim());
                        }
                        AppState.hasSessionConversation = true;
                        updateExportButtonVisibility();
                    } else {
                        throw new Error(
                            (isPlainObject(data) && typeof data.error === 'string')
                                ? data.error
                                : 'Import failed'
                        );
                    }
                })
                .catch((err) => {
                    console.warn('[Import] Server error:', err.message);
                    showErrorModal('Failed to import conversation: ' + err.message);
                });
            } catch (err) {
                console.warn('[Import] Parse error:', err.message);
                if (typeof err.message === 'string' &&
                        err.message.indexOf('No data to import') === 0) {
                    showErrorModal(err.message);
                } else {
                    showErrorModal(
                        'Failed to parse conversation file. ' +
                        'Please ensure it is a valid JSON file.'
                    );
                }
            }
        };
        reader.onerror = () => {
            showErrorModal('Failed to read file. Please try again.');
        };
        reader.readAsText(file);
    }

    /**
     * Reset to a blank session: clears history, resets UI, and notifies the server
     * if in legacy mode. Also aborts any active streaming connection.
     */
    function startNewSession() {
        // Abort any in-flight stream.
        abortActiveStream();
        if (AppState.responseMode === 1) {
            fetch(getApiUrl(), {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ action: 'clear_session' })
            })
            .then((res) => {
                if (!res.ok) { throw new Error('HTTP ' + res.status); }
                return res.json();
            })
            .then((data) => {
                const cleared = (isPlainObject(data) && (
                    (data.success === true && data.cleared) ||
                    data.error === 'NO_DATA_TO_CLEAR'
                ));
                if (!cleared) {
                    throw new Error(
                        (isPlainObject(data) && typeof data.error === 'string')
                            ? data.error
                            : 'Failed to clear session'
                    );
                }
                AppState.hasSessionConversation = false;
                if (DOM.chatBox) { DOM.chatBox.innerHTML = ''; }
                AppState.lastUserMessageDiv = null;
                displayInitialMessage();
                updateExportButtonVisibility();
            })
            .catch((err) => {
                console.warn('[Session] Clear error:', err.message);
                showErrorModal('Failed to start new session: ' + err.message);
            });
            return;
        }
        clearHistory();
        if (DOM.chatBox) { DOM.chatBox.innerHTML = ''; }
        AppState.lastUserMessageDiv = null;
        displayInitialMessage();
        updateExportButtonVisibility();
    }

    /**
     * Abort the currently active streaming controller, if any.
     */
    function abortActiveStream() {
        if (AppState.streamingController) {
            try { AppState.streamingController.abort(); } catch (e) { /* ignore */ }
            AppState.streamingController = null;
        }
    }

    /**
     * In-flight compression request, shared by all concurrent callers so the
     * server is never hit with duplicate summarise POSTs.
     * @type {Promise|null}
     */
    let _compressionInFlight = null;

    /**
     * Delete the oldest chat history items until the total estimated token
     * count (including an optional pending message) is at or below the
     * configured warning threshold. Used in memory mode 1 where server-side
     * summarisation is disabled and the conversation is kept short by
     * discarding the oldest turns instead.
     *
     * Cross-browser: uses Array.shift() which is ES3 and supported by every
     * browser that can run this application.
     *
     * @param {string} [pendingMessage] - Message about to be sent.
     */
    function pruneHistoryByTokenCount(pendingMessage) {
        if (!Array.isArray(AppState.chatHistory) || AppState.chatHistory.length === 0) { return; }
        let total = getHistoryTokenCount(pendingMessage);
        const maxTokens = Math.round(AppState.warningThreshold * 0.7);
        while (total > maxTokens && AppState.chatHistory.length > 0) {
            AppState.chatHistory.shift();
            total = getHistoryTokenCount(pendingMessage);
        }
        saveHistoryToStorage();
    }

    /**
     * Request the server to compress/summarise the current chat history when it
     * approaches the context limit. Always invokes callback() regardless of outcome
     * to prevent the UI from getting stuck.
     *
     * Robustness:
     * - A client-side AbortController timeout (kept strictly below the server's
     *   own authoritative request limit) guarantees the UI can never deadlock
     *   waiting on a hung request. The client never sends or overrides the
     *   server timeout — it only reads the configured value.
     * - Transient failures (network errors, 404/5xx) are retried with a short
     *   back-off so a momentarily slow summarisation does not wedge the chat.
     * - Concurrent callers share a single in-flight request (debounce/dedupe) so
     *   the LLM is not asked to summarise several times for one send cycle.
     *
     * FIX-BUG-3: Original code never called callback() in the .catch() path or in
     * the "unknown response" branch, causing a permanent UI deadlock.
     *
     * @param {string}        [pendingMessage] - Pending message for token estimation.
     * @param {function|null} [callback]       - Called after compression (or on error).
     */
    function compressHistoryViaApi(pendingMessage, callback) {
        const cb = typeof callback === 'function' ? callback : () => {};
        if (!Array.isArray(AppState.chatHistory) || AppState.chatHistory.length < 1) {
            cb();
            return;
        }

        // Dedupe: if a compression for the same (or any) turn is already running,
        // wait for it instead of firing a second, competing summarise request.
        if (_compressionInFlight) {
            _compressionInFlight.then(cb, cb);
            return;
        }

        const payload = {
            action: 'summarize',
            conversation_history: AppState.chatHistory
        };
        if (typeof pendingMessage === 'string' && pendingMessage.length > 0) {
            payload.pending_message = pendingMessage;
        }

        // The server enforces its own authoritative request timeout server-side
        // (the user-configured request_timeout, with no fixed minimum — PHP runs
        // up to its max_execution_time). The client must NEVER send or override
        // it. We only READ that configured value so the client's AbortController
        // timeout stays strictly below it, ensuring we always get to decide what
        // happens on a slow summarisation instead of inheriting an opaque error.
        const serverTimeoutSec = (typeof AppState.requestTimeout === 'number' && AppState.requestTimeout > 0)
            ? AppState.requestTimeout
            : DEFAULT_CONFIG.REQUEST_TIMEOUT;
        const CLIENT_TIMEOUT_MS = Math.max((serverTimeoutSec - 5) * 1000, 5000);
        const MAX_ATTEMPTS = 2;
        // Brief delay before a retry so a transient upstream blip is not hit
        // instantly again. Kept small relative to the overall request budget.
        const RETRY_BACKOFF_MS = 1000;

        const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

        /**
         * Perform a single compression attempt using fetch + AbortController.
         * Resolves with the parsed JSON payload, or rejects on network/HTTP/timeout.
         */
        async function attempt(attemptNo) {
            showThinkingMessage();
            const controller = new AbortController();
            const timeoutId = setTimeout(() => controller.abort(), CLIENT_TIMEOUT_MS);
            try {
                const response = await fetch(getApiUrl(), {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(payload),
                    signal: controller.signal
                });
                if (!response.ok) {
                    throw new Error('HTTP ' + response.status);
                }
                return await response.json();
            } catch (err) {
                // Map an AbortController timeout to an explicit timeout error.
                if (err && err.name === 'AbortError') {
                    const timeoutErr = new Error('timeout');
                    timeoutErr.name = 'AbortError';
                    throw timeoutErr;
                }
                throw err;
            } finally {
                clearTimeout(timeoutId);
            }
        }

        /**
         * Run attempts with bounded retry and process the result into AppState.
         */
        async function runWithRetry(attemptNo) {
            try {
                const data = await attempt(attemptNo);
                removeThinkingMessage();
                if (isPlainObject(data) && data.success === true && Array.isArray(data.summarized_history)) {
                    AppState.chatHistory = data.summarized_history.filter(isValidMessage);
                    saveHistoryToStorage();
                    return { done: true };
                }
                if (isPlainObject(data) && data.error === 'NOT_NEEDED') {
                    return { done: true };
                }
                console.warn(
                    '[History] Compression returned unexpected response:',
                    isPlainObject(data) ? data.error : 'non-object'
                );
                return { done: true };
            } catch (err) {
                const isAbort = err && err.name === 'AbortError';
                if (attemptNo < MAX_ATTEMPTS) {
                    console.warn(
                        `[History] Compression request failed (attempt ${attemptNo}), retrying:`,
                        err.message
                    );
                    await sleep(RETRY_BACKOFF_MS);
                    return runWithRetry(attemptNo + 1);
                }
                removeThinkingMessage();
                console.warn('[History] Compression request failed:', err.message);
                return { done: true, error: isAbort ? 'timeout' : 'error' };
            }
        }

        _compressionInFlight = runWithRetry(1).then(
            (result) => {
                _compressionInFlight = null;
                try { cb(); } catch (e) { /* ignore */ }
                return result;
            },
            (err) => {
                _compressionInFlight = null;
                removeThinkingMessage();
                console.warn('[History] Compression request failed:', err && err.message);
                try { cb(); } catch (e) { /* ignore */ }
            }
        );
    }

    // =============================================================================
    // SECTION 4: UI HELPER FUNCTIONS
    // =============================================================================

    /**
     * Append a chat bubble to the chat box.
     *
     * @param {string} sender  - 'user' or any other value (treated as chatbot).
     * @param {string} [text]  - Message text (HTML-escaped before insertion).
     * @param {string} [action] - Optional action/emote prefix.
     */
    function appendMessage(sender, text, action, messageClass) {
        if (!DOM.chatBox) {
            console.warn('[UI] Chat box not initialised');
            return null;
        }
        const senderStr = typeof sender === 'string' ? sender : 'chatbot';
        const messageDiv = document.createElement('div');
        const extraClass = (typeof messageClass === 'string' && messageClass.length > 0) ? (' ' + messageClass) : '';
        messageDiv.className = 'message ' + (senderStr === 'user' ? 'user-message' : 'chatbot-message') + extraClass;
        messageDiv.setAttribute('tabindex', '-1');
        let html = '';
        if (typeof action === 'string' && action.length > 0) {
            html += `<span style="font-style:italic;">*${escapeHtml(action.trim())}*</span> `;
        }
        if (typeof text === 'string' && text.length > 0) {
            // Unescape literal \n sequences that some LLMs emit as the two characters \n.
            const fixedText = text.replace(/\\n/g, '\n');
            html += formatMessageText(fixedText);
        }
        messageDiv.innerHTML = `<div class="bubble">${html}</div>`;
        try {
            DOM.chatBox.appendChild(messageDiv);
            DOM.chatBox.scrollTop = DOM.chatBox.scrollHeight;
        } catch (e) {
            console.warn('[UI] Append error:', e.message);
        }
        return messageDiv;
    }

    /**
     * Append a looping video message to the chat box.
     * Shows a spinner while the HEAD request confirms the video exists.
     *
     * @param {string} videoFileName - Filename relative to the media/ directory.
     */
    function appendVideoMessage(videoFileName) {
        if (!DOM.chatBox || typeof videoFileName !== 'string' || videoFileName.length === 0) {
            return;
        }
        const messageDiv = document.createElement('div');
        messageDiv.className = 'message chatbot-message';
        const videoPath = 'media/' + encodeURIComponent(videoFileName);
        const loadingDiv = document.createElement('div');
        loadingDiv.className = 'text-center mt-2 mb-3 w-100';
        loadingDiv.innerHTML =
            '<div class="spinner-border text-secondary" role="status" ' +
            'style="width:2rem;height:2rem;">' +
            '<span class="visually-hidden">Loading...</span></div>' +
            '<div class="small text-muted mt-2">Loading video...</div>';
        messageDiv.appendChild(loadingDiv);
        DOM.chatBox.appendChild(messageDiv);
        DOM.chatBox.scrollTop = DOM.chatBox.scrollHeight;
        fetch(videoPath, { method: 'HEAD' })
        .then((response) => {
            if (!response.ok) { throw new Error('Video not found'); }
            const videoContainer = document.createElement('div');
            videoContainer.className = 'video-container mt-2 mb-3 w-100 text-center';
            const video = document.createElement('video');
            video.src         = videoPath;
            video.controls    = true;
            video.loop        = true;
            video.playsInline = true;
            video.muted       = true;
            video.autoplay    = true;
            video.className   = 'chat-video rounded shadow-sm';
            video.style.maxHeight = '240px';
            video.style.width     = 'auto';
            messageDiv.innerHTML = '';
            videoContainer.appendChild(video);
            messageDiv.appendChild(videoContainer);
            DOM.chatBox.scrollTop = DOM.chatBox.scrollHeight;
        })
        .catch(() => {
            const errorDiv = document.createElement('div');
            errorDiv.className = 'alert alert-warning mt-2 mb-3 w-100';
            errorDiv.innerHTML =
                '<strong class="me-2">Video not found:</strong>' +
                escapeHtml(videoFileName);
            messageDiv.innerHTML = '';
            messageDiv.appendChild(errorDiv);
            DOM.chatBox.scrollTop = DOM.chatBox.scrollHeight;
        });
    }

    /**
     * Insert a "…is thinking" indicator at the bottom of the chat box.
     */
    function showThinkingMessage() {
        if (!DOM.chatBox) { return; }
        AppState.thinkingMessageDiv = document.createElement('div');
        AppState.thinkingMessageDiv.className = 'message chatbot-message thinking';
        AppState.thinkingMessageDiv.innerHTML =
            `<div class="bubble"><em>${escapeHtml(AppState.chatbotName)}` +
            ' is thinking<span class="dots">.</span></em></div>';
        DOM.chatBox.appendChild(AppState.thinkingMessageDiv);
        DOM.chatBox.scrollTop = DOM.chatBox.scrollHeight;
        animateDots(AppState.thinkingMessageDiv.querySelector('.dots'));
    }

    /**
     * Remove the thinking indicator if it is present.
     */
    function removeThinkingMessage() {
        if (AppState.thinkingMessageDiv &&
                AppState.thinkingMessageDiv.parentNode) {
            AppState.thinkingMessageDiv.parentNode.removeChild(
                AppState.thinkingMessageDiv
            );
        }
        AppState.thinkingMessageDiv = null;
    }

    /**
     * Animate the trailing dots in a thinking bubble.
     * Stops automatically when the thinking div is removed.
     *
     * @param {Element|null} span - The .dots element to animate.
     */
    function animateDots(span) {
        if (!span) { return; }
        let dots = 1;
        const intervalId = setInterval(() => {
            if (!AppState.thinkingMessageDiv) {
                clearInterval(intervalId);
                return;
            }
            dots = (dots % 3) + 1;
            span.textContent = '.'.repeat(dots);
        }, 500);
    }

    /**
     * Decode a base64 WAV string and play it through the Web Audio API.
     * Stops any currently playing audio first.
     *
     * @param {string} base64 - Base64-encoded WAV data.
     */
    function playAudioFromBase64(base64) {
        if (typeof base64 !== 'string' || base64.length === 0) { return; }
        try {
            // Stop and release any previously playing audio.
            if (AppState.currentAudio) {
                try {
                    AppState.currentAudio.pause();
                    AppState.currentAudio.src = '';
                } catch (e) { /* ignore */ }
                AppState.currentAudio = null;
            }
            let byteCharacters;
            try {
                byteCharacters = atob(base64);
            } catch (e) {
                console.warn('[Audio] Base64 decode error:', e.message);
                return;
            }
            if (typeof byteCharacters !== 'string') {
                console.warn('[Audio] Decoded value is not a string');
                return;
            }
            const byteArray = new Uint8Array(byteCharacters.length);
            for (let i = 0; i < byteCharacters.length; i++) {
                byteArray[i] = byteCharacters.charCodeAt(i);
            }
            const audioBlob = new Blob([byteArray], { type: 'audio/wav' });
            const audioUrl  = URL.createObjectURL(audioBlob);
            const audio     = new Audio(audioUrl);
            AppState.currentAudio = audio;
            audio.onended = () => {
                URL.revokeObjectURL(audioUrl);
                AppState.currentAudio = null;
            };
            audio.onerror = () => {
                URL.revokeObjectURL(audioUrl);
                AppState.currentAudio = null;
                console.warn('[Audio] Playback error');
            };
            audio.play().catch((err) => {
                console.warn('[Audio] Play blocked by browser policy:', err.message);
                AppState.currentAudio = null;
            });
        } catch (e) {
            console.warn('[Audio] Unexpected error:', e.message);
        }
    }

    // =============================================================================
    // SECTION 5: STREAMING MODE — DIRECT LLAMA.CPP CONNECTION
    // =============================================================================

    /**
     * Open a streaming connection directly to the llama.cpp server, progressively
     * render the response, and push the completed exchange to chat history.
     *
     * FIX-BUG-1: Added `completed` flag to prevent the callback from firing twice
     * when both a finish_reason chunk and the natural stream-end (result.done)
     * arrive in the same session.
     *
     * FIX-BUG-4: res.body is null-checked before calling .getReader().
     *
     * FIX-BUG-6: A `skipCompression` parameter prevents infinite recursion when
     * compression does not reduce token count below the threshold.
     *
     * @param {string}   userMessage      - The message to send.
     * @param {function} callback         - Invoked with the final reply string (or null).
     * @param {boolean}  [skipCompression] - If true, skip the pre-flight compression check.
     */
    async function connectToLlamaDirect(userMessage, callback, skipCompression) {
        if (typeof userMessage !== 'string' || userMessage.trim().length === 0) {
            if (typeof callback === 'function') { callback(null); }
            return;
        }
        // FIX-BUG-6: Only attempt compression once per send cycle.
        if (!skipCompression) {
            const currentTokens = getHistoryTokenCount(userMessage);
            if (currentTokens > AppState.warningThreshold && AppState.chatHistory.length > 0) {
                if (AppState.memoryMode === 1) {
                    pruneHistoryByTokenCount(userMessage);
                } else {
                    await new Promise((resolve) => {
                        compressHistoryViaApi(userMessage, () => resolve());
                    });
                    return connectToLlamaDirect(userMessage, callback, true);
                }
            }
        }
        // Build the messages array: optional system prompt + history + new user turn.
        const messages = [];
        if (typeof AppState.systemPrompt === 'string' &&
                AppState.systemPrompt.length > 0) {
            messages.push({ role: 'system', content: AppState.systemPrompt });
        }
        if (Array.isArray(AppState.chatHistory)) {
            for (const msg of AppState.chatHistory) {
                if (isValidMessage(msg)) {
                    messages.push({ role: msg.role, content: msg.content });
                }
            }
        }
        messages.push({ role: 'user', content: userMessage });
        let payload;
        try {
            payload = JSON.stringify({
                messages: messages,
                stream: true,
                max_tokens: AppState.llmMaxResponseTokens
            });
        } catch (e) {
            console.warn('[Stream] Payload serialisation error:', e.message);
            if (typeof callback === 'function') { callback(null); }
            return;
        }
        // Abort any previous in-flight request.
        abortActiveStream();
        AppState.streamingController = new AbortController();
        const streamFetchOpts = {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Accept': 'text/event-stream'
            },
            body: payload,
            signal: AppState.streamingController.signal
        };

        // Double-callback guard so finish_reason=stop AND the natural stream-end
        // (result.done) cannot both fire the caller's callback. (FIX-BUG-1)
        let completed = false;
        let assistantMessage = '';

        // Create the streaming message bubble.
        const messageDiv = document.createElement('div');
        messageDiv.className = 'message chatbot-message';
        messageDiv.innerHTML =
            '<div class="bubble">' +
            '<span class="stream-content"></span>' +
            '</div>';
        AppState.streamingMessageDiv = messageDiv;
        if (DOM.chatBox) {
            DOM.chatBox.scrollTop = DOM.chatBox.scrollHeight;
        }

        /**
         * Finalise the stream: hide the cursor dot, persist the exchange,
         * and invoke the caller's callback. Idempotent via `completed`.
         *
         * @param {ReadableStreamDefaultReader} reader - The reader to cancel.
         */
        function finalise(reader) {
            if (completed) { return; }
            completed = true;
            try {
                const dots = messageDiv.querySelector('.dots');
                if (dots) { dots.style.display = 'none'; }
                const shouldSave = (assistantMessage.length > 0 && (!AppState.userStoppedStream));
                if (shouldSave) {
                    AppState.chatHistory.push({ role: 'user', content: userMessage });
                    AppState.chatHistory.push({ role: 'assistant', content: assistantMessage });
                    saveHistoryToStorage();
                }
                if (AppState.userStoppedStream) { AppState.userStoppedStream = false; }
                AppState.streamingMessageDiv = null;
                if (reader) {
                    reader.cancel().catch(() => { /* ignore */ });
                }
                if (typeof callback === 'function') {
                    try {
                        callback(shouldSave ? assistantMessage : null);
                    } catch (cbErr) {
                        console.warn('[Stream] Callback error:', cbErr.message);
                        try { finishProcessing(); } catch (fpErr) { /* ignore */ }
                    }
                }
            } catch (e) {
                console.warn('[Stream] Finalise error:', e.message);
                try { finishProcessing(); } catch (fpErr) { /* ignore */ }
            }
        }

        /**
         * Process a single decoded SSE line. Returns true if the stream
         * reached a terminal finish_reason and should stop.
         */
        function handleLine(line) {
            if (typeof line !== 'string') { return false; }
            line = line.trim();
            if (line.length < 6 || line.indexOf('data: ') !== 0) { return false; }
            const dataStr = line.substring(6).trim();
            // Exact-match the [DONE] sentinel (case-insensitive). (FIX-WARN-2)
            if (dataStr.toUpperCase() === '[DONE]') { return false; }
            try {
                const data    = JSON.parse(dataStr);
                const choices = data && Array.isArray(data.choices) ? data.choices : null;
                const choice0 = choices && choices.length > 0 ? choices[0] : null;
                const delta   = choice0 && isPlainObject(choice0.delta) ? choice0.delta : null;
                const content = delta && typeof delta.content === 'string' ? delta.content : '';
                if (content.length > 0) {
                    assistantMessage += content;
                    const contentSpan = messageDiv.querySelector('.stream-content');
                    if (contentSpan) {
                        contentSpan.innerHTML = formatMessageText(assistantMessage);
                        if (DOM.chatBox && !messageDiv.parentNode) {
                            DOM.chatBox.appendChild(messageDiv);
                            DOM.chatBox.scrollTop = DOM.chatBox.scrollHeight;
                        } else if (DOM.chatBox) {
                            DOM.chatBox.scrollTop = DOM.chatBox.scrollHeight;
                        }
                    }
                }
                const finishReason = choice0 &&
                    typeof choice0.finish_reason === 'string'
                    ? choice0.finish_reason
                    : null;
                return finishReason === 'stop' ||
                       finishReason === 'length' ||
                       finishReason === 'abort';
            } catch (e) {
                // Malformed JSON in an SSE line — skip it.
                return false;
            }
        }

        // FIX-BUG-4: res.body is null-checked before calling .getReader().
        let reader;
        try {
            const res = await fetch(AppState.llmEndpoint, streamFetchOpts);
            if (!res.ok) { throw new Error('HTTP ' + res.status); }
            if (!res.body || typeof res.body.getReader !== 'function') {
                throw new Error('Response body is null; Streams API may not be supported.');
            }
            reader = res.body.getReader();
            const decoder = new TextDecoder();
            let buffer = '';

            while (true) {
                const result = await reader.read();
                if (result.done) { break; }
                let chunk = '';
                if (result.value instanceof Uint8Array ||
                        (typeof ArrayBuffer !== 'undefined' && result.value instanceof ArrayBuffer)) {
                    chunk = decoder.decode(result.value, { stream: true });
                } else {
                    chunk = String(result.value);
                }
                buffer += chunk;
                const lines = buffer.split('\n');
                buffer = lines.pop() || '';   // Keep the incomplete tail.
                for (const line of lines) {
                    if (handleLine(line)) {
                        finalise(reader);
                        return;
                    }
                }
            }
            finalise(reader);
        } catch (err) {
            // Stream read error (includes AbortError on cancellation).
            if (err && err.name !== 'AbortError') {
                console.warn('[Stream] Connection error:', err.message);
            }
            try {
                if (typeof callback === 'function') { callback(null); }
            } catch (cbErr) {
                console.warn('[Stream] Connection callback error:', cbErr.message);
                try { finishProcessing(); } catch (fpErr) { /* ignore */ }
            }
        }
    }

    // =============================================================================
    // SECTION 6: API COMMUNICATION
    // =============================================================================

    /**
     * POST a user message to the proxy API and invoke callback with the parsed response.
     * On any error, callback receives { error: '<description>' }.
     *
     * @param {string}   message
     * @param {function} callback - Receives a plain object response or { error: string }.
     */
    function sendToApi(message, callback) {
        if (typeof message !== 'string' || message.trim().length === 0) {
            if (typeof callback === 'function') {
                callback({ error: 'Invalid message' });
            }
            return;
        }
        fetch(getApiUrl(), {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ message: message })
        })
        .then((res) => {
            if (!res.ok) { throw new Error('HTTP ' + res.status); }
            return res.json();
        })
        .then((data) => {
            const safeData = isPlainObject(data) ? data : {};
            if (AppState.responseMode === 1 && !safeData.error) {
                AppState.hasSessionConversation = true;
                updateExportButtonVisibility();
            }
            if (typeof callback === 'function') {
                try { callback(safeData); } catch (e) { /* ignore */ }
            }
        })
        .catch((err) => {
            console.warn('[API] Error:', err.message);
            if (typeof callback === 'function') {
                try { callback({ error: 'Connection error', message: err.message }); } catch (e) { /* ignore */ }
            }
        });
    }

    // =============================================================================
    // SECTION 7: MAIN FORM SUBMIT HANDLER
    // =============================================================================

    /**
     * Handle a form submission: validate input, lock the UI, display the user
     * message, and route to the appropriate send path.
     */
    function handleFormSubmit() {
        if (AppState.isProcessing) { return; }
        AppState.userStoppedStream = false;
        if (!DOM.input) { return; }
        const rawValue = DOM.input.value;
        const message  = typeof rawValue === 'string' ? rawValue.trim() : '';
        if (message.length === 0) {
            DOM.input.classList.add('is-invalid');
            DOM.input.focus();
            return;
        }
        DOM.input.classList.remove('is-invalid');
        AppState.isProcessing = true;
        DOM.input.disabled = true;
        if (DOM.submitBtn) {
            DOM.submitBtn.disabled = true;
            if (AppState.responseMode === 2) { DOM.submitBtn.style.display = 'none'; }
        }
        if (DOM.stopBtn && AppState.responseMode === 2) {
            DOM.stopBtn.disabled = false;
            DOM.stopBtn.style.display = '';
        }
        const userMsgDiv = appendMessage('user', message);
        AppState.lastUserMessageDiv = userMsgDiv;
        DOM.input.value = '';
        DOM.input.classList.remove('is-invalid');
        DOM.input.style.height = 'auto';
        // In streaming mode, history is entirely client-side. Check compression here
        // before either the embedding or direct-LLM paths.
        if (AppState.responseMode === 2 && getHistoryTokenCount(message) > AppState.warningThreshold && AppState.chatHistory.length > 0) {
            if (AppState.memoryMode === 1) {
                pruneHistoryByTokenCount(message);
            } else {
                compressHistoryViaApi(message, () => {
                    if (!AppState.isProcessing) { return; }
                    proceedWithSend(message);
                });
                return;
            }
        }
        proceedWithSend(message);
    }

    /**
     * Continue the send flow after any necessary pre-flight compression.
     * Routes to either direct streaming or the proxy API.
     *
     * FIX-BUG-5/7: Null/type guard on the API response is now the very first check
     * inside the sendToApi callback, before any property access.
     *
     * FIX-BUG-2: distinct variable names per usage site make data flow explicit.
     *
     * @param {string} message - The validated, trimmed user message.
     */
    function proceedWithSend(message) {
        // Streaming mode without embedding → connect directly to llama.cpp.
        if (AppState.responseMode === 2 && !AppState.embeddingEnabled) {
            if (AppState.llmEnabled) {
                connectToLlamaDirect(message, () => finishProcessing());
            } else {
                appendMessage('chatbot', "I'm sorry, I don't understand. Can you, please, be more specific?");
                finishProcessing();
            }
            return;
        }
        showThinkingMessage();
        sendToApi(message, (data) => {
            removeThinkingMessage();
            // FIX-BUG-5/7: Guard first, before touching any property.
            if (!isPlainObject(data)) {
                appendMessage('chatbot', 'Invalid response from server.');
                finishProcessing();
                return;
            }
            // Detect a server-requested mode upgrade.
            if (typeof data.response_mode === 'number' && data.response_mode === 2) {
                AppState.responseMode = 2;
            }
            // Error handling
            if (typeof data.error === 'string' && data.error.length > 0) {
                const errCode   = data.error;
                const errDetail = typeof data.message === 'string' ? data.message : '';
                if (errCode === 'NO_SERVICES_AVAILABLE') {
                    appendMessage(
                        'chatbot',
                        errDetail.length > 0
                            ? 'Error: ' + errDetail
                            : 'Error: Both LLM and embedding services are disabled. ' +
                              'Please check configuration.'
                    );
                    finishProcessing();
                    return;
                }
                if (errCode === 'LLM_PROXY_NOT_AVAILABLE_IN_STREAMING_MODE') {
                    console.log('[API] Streaming mode: using direct connection.');
                    if (AppState.llmEnabled) {
                        connectToLlamaDirect(message, () => finishProcessing());
                    } else if (typeof data.reply === 'string' && data.reply.trim().length > 0) {
                        appendMessage('chatbot', data.reply.trim());
                        finishProcessing();
                    } else {
                        appendMessage('chatbot', "I'm sorry, I don't understand. Can you, please, be more specific?");
                        finishProcessing();
                    }
                    return;
                }
                // Generic / unknown error.
                appendMessage(
                    'chatbot',
                    'Error: ' + (errDetail.length > 0 ? errDetail : errCode)
                );
                finishProcessing();
                return;
            }
            // Streaming-mode block_request
            if (AppState.responseMode === 2 && data.block_request) {
                connectToLlamaDirect(message, () => finishProcessing());
                return;
            }
            // Optional TTS audio
            if (typeof data.audio_data === 'string' && data.audio_data.length > 0) {
                playAudioFromBase64(data.audio_data);
            }
            // Response with an action verb
            if (typeof data.response_action === 'string' &&
                    data.response_action.trim().length > 0) {
                const action = data.response_action.trim();
                if (action === '#LOOP_VIDEO' &&
                        typeof data.media_data === 'string' &&
                        data.media_data.length > 0) {
                    appendVideoMessage(data.media_data);
                    const videoReply = (typeof data.reply === 'string') ? data.reply.trim() : '';
                    if (videoReply.length > 0) {
                        appendMessage('chatbot', videoReply);
                        if (AppState.responseMode === 2) {
                            AppState.chatHistory.push({ role: 'user',      content: message });
                            AppState.chatHistory.push({ role: 'assistant', content: videoReply });
                            saveHistoryToStorage();
                        }
                    }
                    finishProcessing();
                    return;
                }
                // All other action types.
                const actionReply = (typeof data.reply === 'string') ? data.reply.trim() : '';
                appendMessage('chatbot', actionReply, action);
                if (AppState.responseMode === 2 && actionReply.length > 0) {
                    AppState.chatHistory.push({ role: 'user',      content: message });
                    AppState.chatHistory.push({ role: 'assistant', content: actionReply });
                    saveHistoryToStorage();
                }
                finishProcessing();
                return;
            }
            // Plain text reply
            if (typeof data.reply === 'string') {
                const plainReply = data.reply.trim();
                if (plainReply.length > 0) {
                    appendMessage('chatbot', plainReply);
                    if (AppState.responseMode === 2) {
                        AppState.chatHistory.push({ role: 'user',      content: message });
                        AppState.chatHistory.push({ role: 'assistant', content: plainReply });
                        saveHistoryToStorage();
                    }
                }
            }
            finishProcessing();
        });
    }

    /** Stop the ongoing llama.cpp stream in streaming mode and reset the UI. */
    function handleStop() {
        if (AppState.responseMode !== 2) { return; }
        if (!AppState.isProcessing) { return; }
        AppState.userStoppedStream = true;
        abortActiveStream();
        if (AppState.streamingMessageDiv && AppState.streamingMessageDiv.parentNode) {
            AppState.streamingMessageDiv.parentNode.removeChild(AppState.streamingMessageDiv);
        }
        AppState.streamingMessageDiv = null;
        if (AppState.lastUserMessageDiv && AppState.lastUserMessageDiv.parentNode) {
            AppState.lastUserMessageDiv.parentNode.removeChild(AppState.lastUserMessageDiv);
        }
        AppState.lastUserMessageDiv = null;
        removeThinkingMessage();
        appendMessage('chatbot', 'Request canceled by user.', null, 'cancel-message');
        finishProcessing();
    }

    /**
     * Re-enable the input UI after a send cycle completes.
     * Idempotent: safe to call multiple times.
     */
    function finishProcessing() {
        AppState.isProcessing = false;
        if (DOM.input) {
            DOM.input.disabled = false;
            DOM.input.classList.remove('is-invalid');
            try { DOM.input.focus(); } catch (e) { /* ignore focus errors */ }
        }
        if (DOM.submitBtn) {
            DOM.submitBtn.disabled = false;
            DOM.submitBtn.style.display = '';
        }
        if (DOM.stopBtn && AppState.responseMode === 2) {
            DOM.stopBtn.disabled = true;
            DOM.stopBtn.style.display = 'none';
        }
    }

    // =============================================================================
    // SECTION 8: EVENT HANDLERS
    // =============================================================================

    /** Auto-grow the textarea as the user types. */
    function handleInput() {
        if (!DOM.input) { return; }
        DOM.input.style.height = 'auto';
        DOM.input.style.height = DOM.input.scrollHeight + 'px';
        DOM.input.classList.remove('is-invalid');
    }

    /**
     * Handle keydown events on the input:
     * - Enter (without Shift) → submit.
     * - ArrowUp / ArrowDown → navigate message bubbles.
     *
     * @param {KeyboardEvent} e
     */
    function handleKeydown(e) {
        if (!e) { return; }
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            e.stopPropagation();
            e.stopImmediatePropagation();
            handleFormSubmit();
            return;
        }
        if (e.key === 'ArrowUp' || e.key === 'ArrowDown') {
            if (!DOM.chatBox) { return; }
            e.preventDefault();
            e.stopImmediatePropagation();
            const messages     = DOM.chatBox.querySelectorAll('.message');
            const messageCount = messages.length;
            if (messageCount === 0) { return; }
            const activeEl     = document.activeElement;
            let currentIndex = -1;
            for (let i = 0; i < messageCount; i++) {
                if (activeEl === messages[i]) { currentIndex = i; break; }
            }
            const newIndex = e.key === 'ArrowUp'
                ? (currentIndex <= 0 ? messageCount - 1 : currentIndex - 1)
                : (currentIndex >= messageCount - 1 ? 0 : currentIndex + 1);
            messages[newIndex].setAttribute('tabindex', '0');
            messages[newIndex].focus();
            if (currentIndex >= 0 && currentIndex !== newIndex) {
                messages[currentIndex].removeAttribute('tabindex');
            }
        }
    }

    /**
     * Handle the form submit event.
     *
     * @param {Event} e
     */
    function handleSubmit(e) {
        if (e) {
            e.preventDefault();
            e.stopPropagation();
        }
        try {
            handleFormSubmit();
        } catch (err) {
            console.error('[Form] Submit handler error:', err);
            finishProcessing();
        }
        return false;
    }

    // =============================================================================
    // SECTION 9: INITIALIZATION
    // =============================================================================

    /** Populate the DOM cache. */
    function initDOM() {
        DOM.form        = document.getElementById('chat-form');
        DOM.input       = document.getElementById('user-input');
        DOM.chatBox     = document.getElementById('chat-box');
        DOM.importInput = document.getElementById('import-conversation-input');
        DOM.stopBtn     = document.getElementById('stop-btn');
        DOM.submitBtn   = document.getElementById('submit-btn');
    }

    /**
     * Read and validate all configuration globals, applying bounds and
     * falling back to defaults on any malformed value.
     */
    function initConfig() {
        AppState.chatbotName = getConfigValue(
            'CHATBOT_NAME',
            DEFAULT_CONFIG.CHATBOT_NAME,
            (v) => String(v)
        );
        AppState.memoryMode = getConfigValue(
            'MEMORY_MODE',
            DEFAULT_CONFIG.MEMORY_MODE,
            (v) => parseIntSafe(v, DEFAULT_CONFIG.MEMORY_MODE)
        );
        AppState.responseMode = getConfigValue(
            'RESPONSE_MODE',
            DEFAULT_CONFIG.RESPONSE_MODE,
            (v) => parseIntSafe(v, DEFAULT_CONFIG.RESPONSE_MODE)
        );
        if (AppState.responseMode !== 1 && AppState.responseMode !== 2) {
            AppState.responseMode = DEFAULT_CONFIG.RESPONSE_MODE;
        }
        // Build the full streaming endpoint URL.
        const rawEndpoint = getConfigValue(
            'LLM_ENDPOINT',
            DEFAULT_CONFIG.LLM_ENDPOINT,
            (v) => {
                v = String(v).trim();
                return v.length > 0 ? v : DEFAULT_CONFIG.LLM_ENDPOINT;
            }
        );
        const llmHostUrl = getConfigValue(
            'LLM_HOST_URL',
            '/llamacpp/',
            (v) => String(v)
        );
        const baseUrl  = llmHostUrl.replace(/\/+$/, '');
        const endpoint = rawEndpoint.indexOf('/') === 0 ? rawEndpoint : '/' + rawEndpoint;
        AppState.llmEndpoint = baseUrl + endpoint;
        AppState.llmCtxSize = getConfigValue(
            'LLM_CTX_SIZE',
            DEFAULT_CONFIG.LLM_CTX_SIZE,
            (v) => {
                const n = parseIntSafe(v, DEFAULT_CONFIG.LLM_CTX_SIZE);
                return n > 0 ? n : DEFAULT_CONFIG.LLM_CTX_SIZE;
            }
        );
        AppState.llmMaxResponseTokens = getConfigValue(
            'LLM_MAX_RESPONSE_TOKENS',
            DEFAULT_CONFIG.LLM_MAX_RESPONSE_TOKENS,
            (v) => {
                const n = parseIntSafe(v, DEFAULT_CONFIG.LLM_MAX_RESPONSE_TOKENS);
                return n > 0 ? n : DEFAULT_CONFIG.LLM_MAX_RESPONSE_TOKENS;
            }
        );
        AppState.safetyMargin = getConfigValue(
            'SAFETY_MARGIN',
            DEFAULT_CONFIG.SAFETY_MARGIN,
            (v) => {
                const n = parseIntSafe(v, DEFAULT_CONFIG.SAFETY_MARGIN);
                return n >= 0 ? n : DEFAULT_CONFIG.SAFETY_MARGIN;
            }
        );
        AppState.embeddingEnabled = getConfigValue(
            'EMBEDDING_ENABLED',
            DEFAULT_CONFIG.EMBEDDING_ENABLED,
            (v) => v === true || v === 'true' || v === 1 || v === '1'
        );
        AppState.llmEnabled = getConfigValue(
            'LLM_ENABLED',
            DEFAULT_CONFIG.LLM_ENABLED,
            (v) => v === true || v === 'true' || v === 1 || v === '1'
        );
        AppState.systemPrompt = getConfigValue(
            'SYSTEM_PROMPT',
            DEFAULT_CONFIG.SYSTEM_PROMPT,
            (v) => v === null ? null : String(v)
        );
        AppState.apiEndpoint = getConfigValue(
            'API_ENDPOINT',
            DEFAULT_CONFIG.API_ENDPOINT,
            (v) => String(v)
        );
        AppState.requestTimeout = getConfigValue(
            'REQUEST_TIMEOUT',
            DEFAULT_CONFIG.REQUEST_TIMEOUT,
            (v) => {
                const n = parseIntSafe(v, DEFAULT_CONFIG.REQUEST_TIMEOUT);
                return n > 0 ? n : DEFAULT_CONFIG.REQUEST_TIMEOUT;
            }
        );
        // Derive the compression threshold from validated values.
        const calculated = AppState.llmCtxSize -
                         (AppState.llmMaxResponseTokens + AppState.safetyMargin);
        AppState.warningThreshold = Math.max(calculated, 0);
    }

    /** Attach all event listeners. */
    function initEvents() {
        if (DOM.input) {
            DOM.input.addEventListener('input', handleInput);
            DOM.input.addEventListener('keydown', handleKeydown);
        }
        if (DOM.submitBtn) {
            DOM.submitBtn.addEventListener('click', (e) => {
                e.preventDefault();
                e.stopPropagation();
                handleFormSubmit();
            });
        }
        const exportBtn = document.getElementById('export-conversation-btn');
        if (exportBtn) {
            exportBtn.addEventListener('click', (e) => {
                e.preventDefault();
                e.stopPropagation();
                exportConversation();
            });
        }
        const importBtn = document.getElementById('import-conversation-btn');
        if (importBtn) {
            importBtn.addEventListener('click', (e) => {
                e.preventDefault();
                e.stopPropagation();
                if (DOM.importInput) { DOM.importInput.click(); }
            });
        }
        if (DOM.importInput) {
            DOM.importInput.addEventListener('change', (e) => {
                const files = e.target && e.target.files;
                if (!files || files.length === 0) { return; }
                const file = files[0];
                const isJson = (typeof file.type === 'string' &&
                              file.type === 'application/json') ||
                             (typeof file.name === 'string' &&
                              file.name.slice(-5).toLowerCase() === '.json');
                if (isJson) {
                    ConfirmModal.show(
                        'Are you sure you want to import this conversation? ' +
                        'Current conversation will be replaced.',
                        () => importConversation(file)
                    );
                } else {
                    showErrorModal('Please select a valid JSON file.');
                }
                // Reset so the same file can be re-selected if needed.
                DOM.importInput.value = '';
            });
        }
        const newSessionBtn = document.getElementById('new-session-btn');
        if (newSessionBtn) {
            newSessionBtn.addEventListener('click', () => {
                ConfirmModal.show(
                    'Are you sure you want to start a new session? ' +
                    'All chat history will be permanently deleted.',
                    () => startNewSession()
                );
            });
        }
        if (DOM.stopBtn) {
            DOM.stopBtn.addEventListener('click', (e) => {
                e.preventDefault();
                e.stopPropagation();
                handleStop();
            });
        }
        // Confirm-modal OK button: bound once (never cloned) so it always keeps a
        // single, live reference — Enter/Space activate it normally and focus can
        // never get stranded on a detached clone.
        const confirmOkBtn = document.getElementById('confirm-ok-btn');
        if (confirmOkBtn) {
            confirmOkBtn.addEventListener('click', confirmModalOk);
        }
        // Abort any active stream if the page is navigated away.
        window.addEventListener('beforeunload', () => {
            abortActiveStream();
        });
        // Robust modal dismissal for close buttons ([data-bs-dismiss="modal"] /
        // .btn-close). In some embedded runtimes (e.g. PHP Desktop, Chromium 2025)
        // Bootstrap's own dismiss handler does not fire reliably, so we explicitly
        // close the matching modal on click to keep it keyboard- and click-accessible.
        document.addEventListener('click', (e) => {
            const dismissBtn = e.target.closest ? e.target.closest('[data-bs-dismiss="modal"], .btn-close') : null;
            if (!dismissBtn) { return; }
            const modal = dismissBtn.closest('.modal');
            if (modal) {
                e.preventDefault();
                e.stopPropagation();
                hideModal(modal);
            }
        });
    }

    /**
     * Display the configured initial greeting from the chatbot (if set).
     * Called once per session before history is rendered.
     */
    function displayInitialMessage() {
        const initialMessage = getConfigValue(
            'INITIAL_MESSAGE',
            null,
            (v) => v === null ? null : String(v)
        );
        if (typeof initialMessage === 'string' && initialMessage.length > 0) {
            appendMessage('chatbot', initialMessage);
        }
    }

    /**
     * Render the in-memory chatHistory into the chat box.
     * Called on page load in streaming mode (2).
     */
    function displayChatHistory() {
        if (!Array.isArray(AppState.chatHistory) ||
                AppState.chatHistory.length === 0) { return; }
        for (const msg of AppState.chatHistory) {
            if (isValidMessage(msg)) {
                appendMessage(msg.role, msg.content);
            }
        }
    }

    /**
     * Application entry point.
     */
    function init() {
        try {
            initDOM();
            if (!DOM.form || !DOM.input || !DOM.chatBox) {
                console.error('[Init] Required DOM elements not found. Aborting.');
                return;
            }
            initConfig();
            AppState.hasSessionConversation = getConfigValue(
                'HAS_SESSION_CONVERSATION',
                false,
                (v) => v === true || v === 'true' || v === 1 || v === '1'
            );
            displayInitialMessage();
            if (AppState.responseMode === 1) {
                if (AppState.hasSessionConversation) {
                    fetchConversationHistoryFromApi();
                }
            } else if (AppState.responseMode === 2) {
                loadHistoryFromStorage();
                displayChatHistory();
            }
            updateExportButtonVisibility();
            initEvents();
            console.log('[Init] Chatbot initialised successfully');
            console.log('[Init] Memory mode:',         AppState.memoryMode);
            console.log('[Init] Response mode:',       AppState.responseMode);
            console.log('[Init] Chatbot name:',        AppState.chatbotName);
            console.log('[Config] llmCtxSize:',        AppState.llmCtxSize);
            console.log('[Config] maxResponseTokens:', AppState.llmMaxResponseTokens);
            console.log('[Config] safetyMargin:',      AppState.safetyMargin);
            console.log('[Config] warningThreshold:',  AppState.warningThreshold);
            console.log('[Config] llmEndpoint:',       AppState.llmEndpoint);
            console.log('[Config] requestTimeout:',    AppState.requestTimeout);
        } catch (e) {
            console.error('[Init] Fatal error during initialisation:', e.message, e);
        }
    }

    // =============================================================================
    // GLOBAL ERROR SAFEGUARDS
    // =============================================================================

    if (typeof window !== 'undefined') {
        window.addEventListener('unhandledrejection', (e) => {
            if (e && e.reason) {
                const msg = (e.reason && e.reason.message) ? e.reason.message : String(e.reason);
                console.warn('[Global] Unhandled promise rejection:', msg);
            }
        });
    }

    // =============================================================================
    // STARTUP
    // =============================================================================

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
}());
