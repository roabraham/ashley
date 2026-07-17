/**
 * =============================================================================
 * Chatbot Application - Main JavaScript
 * =============================================================================
 * A robust, cross-browser compatible chat client that supports both legacy
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
 * Compatibility: PHP Desktop (Feb 2025), all modern browsers, ES6+
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
 *   client by deriving the AbortController timeout from the configured request_timeout
 *   (always strictly below the server's own authoritative limit, and never sent to or
 *   overridden on the server), with bounded retry/back-off and in-flight request dedupe
 *   so a momentarily slow summarisation cannot wedge the chat. The web server's FastCGI
 *   timeout was removed so PHP runs up to its own max_execution_time; the server keeps
 *   sole authority over request duration (no client-influenced DDoS vector).
 * Additional hardening: role validation, config bounds checking, res.body null guard,
 *   transformer try-catch, sender validation, idempotent finishProcessing, stream
 *   abort on new session.
 * =============================================================================
 */

(function () {
    'use strict';

    // Polyfill TextDecoder for EdgeHTML/legacy WebView environments
    if (typeof TextDecoder === 'undefined') {
        window.TextDecoder = function () {};
        TextDecoder.prototype.decode = function (bytes) {
            if (typeof bytes === 'string') { return bytes; }
            var result = '';
            for (var i = 0; i < bytes.length; i++) {
                result += String.fromCharCode(bytes[i]);
            }
            return result;
        };
    }

    // =============================================================================
    // SECTION 1: CONFIGURATION & DEFAULTS
    // =============================================================================

    /**
     * Default configuration values.
     * Used as fallback when PHP/Twig-injected globals are absent or malformed.
     */
    var DEFAULT_CONFIG = {
        CHATBOT_NAME: 'ChatBot',
        INITIAL_MESSAGE: null,
        RESPONSE_MODE: 1, // 1 = legacy (proxy), 2 = streaming (direct)
        LLM_ENDPOINT: '/v1/chat/completions',
        LLM_CTX_SIZE: 8192,
        LLM_MAX_RESPONSE_TOKENS: 2048,
        SAFETY_MARGIN: 256,
        EMBEDDING_ENABLED: true,
        SYSTEM_PROMPT: null,
        API_ENDPOINT: '/api/chat',
        REQUEST_TIMEOUT: 300 // server-configured request timeout (seconds)
    };

    /** Allowed message role values. Anything else is rejected on import/load. */
    var VALID_ROLES = { 'user': true, 'assistant': true, 'system': true };

    /**
     * Application state — single source of truth.
     */
    var AppState = {
        isProcessing: false,
        thinkingMessageDiv: null,
        currentAudio: null,
        streamingController: null,
        streamingMessageDiv: null,
        lastUserMessageDiv: null,
        userStoppedStream: false,
        responseMode: DEFAULT_CONFIG.RESPONSE_MODE,
        chatHistory: [],
        hasSessionConversation: false,
        llmEndpoint: DEFAULT_CONFIG.LLM_ENDPOINT,
        llmCtxSize: DEFAULT_CONFIG.LLM_CTX_SIZE,
        llmMaxResponseTokens: DEFAULT_CONFIG.LLM_MAX_RESPONSE_TOKENS,
        safetyMargin: DEFAULT_CONFIG.SAFETY_MARGIN,
        embeddingEnabled: DEFAULT_CONFIG.EMBEDDING_ENABLED,
        warningThreshold: 0,
        systemPrompt: DEFAULT_CONFIG.SYSTEM_PROMPT,
        chatbotName: DEFAULT_CONFIG.CHATBOT_NAME,
        apiEndpoint: DEFAULT_CONFIG.API_ENDPOINT,
        requestTimeout: DEFAULT_CONFIG.REQUEST_TIMEOUT
    };

    /**
     * Cached DOM element references. Populated once in initDOM().
     */
    var DOM = {
        form: null,
        input: null,
        chatBox: null,
        submitBtn: null,
        stopBtn: null,
        importInput: null
    };

    /** Currently visible modal element for focus-trap management. */
    var activeModalEl = null;

    /** Element that had focus before a modal opened, restored on close. */
    var previouslyFocused = null;

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
            var value = window[name];
            if (value === null || value === undefined) { return defaultValue; }
            if (typeof transformer === 'function') {
                try {
                    return transformer(value);
                } catch (te) {
                    console.warn('[Config] Transformer error for ' + name + ':', te.message);
                    return defaultValue;
                }
            }
            return value;
        } catch (e) {
            console.warn('[Config] Error reading ' + name + ':', e.message);
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
            var parsed = parseInt(String(value), 10);
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
        var map = {
            '&': '&amp;',
            '<': '&lt;',
            '>': '&gt;',
            '"': '&quot;',
            "'": '&#039;'
        };
        return text.replace(/[&<>"']/g, function (char) { return map[char]; });
    }

    /**
     * Convert newline characters to HTML <br/> tags.
     * Non-string input returns an empty string.
     *
     * @param {*} text
     * @returns {string}
     */
    function nl2br(text) {
        if (typeof text !== 'string') { return ''; }
        return text.replace(/\n/g, '<br/>');
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
    var Storage = {
        getItem: function (key) {
            try { return localStorage.getItem(key); }
            catch (e) { console.warn('[Storage] Read error:', e.message); return null; }
        },
        setItem: function (key, value) {
            try { localStorage.setItem(key, value); return true; }
            catch (e) { console.warn('[Storage] Write error:', e.message); return false; }
        },
        removeItem: function (key) {
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
    var ConfirmModal = {
        /**
         * Show a confirmation modal and invoke onConfirm when the user accepts.
         *
         * @param {string}   message   - Prompt text shown inside the modal.
         * @param {function} onConfirm - Callback invoked on confirmation.
         */
        show: function (message, onConfirm) {
            var modalEl   = document.getElementById('confirm-modal');
            var messageEl = document.getElementById('confirm-message');
            var okBtn     = document.getElementById('confirm-ok-btn');
            if (!modalEl || !messageEl || !okBtn) {
                // Modal markup missing — proceed immediately.
                if (typeof onConfirm === 'function') { onConfirm(); }
                return;
            }
            messageEl.textContent = message;
            // Clone the button to eliminate any previously attached listeners.
            var newOkBtn = okBtn.cloneNode(true);
            okBtn.parentNode.replaceChild(newOkBtn, okBtn);
            newOkBtn.addEventListener('click', function () {
                hideModal(modalEl);
                if (typeof onConfirm === 'function') { onConfirm(); }
            });
            showModal(modalEl);
        }
    };

    /**
     * Show an error modal with the supplied message.
     *
     * @param {string} message
     */
    function showErrorModal(message) {
        var modalEl   = document.getElementById('error-modal');
        var messageEl = document.getElementById('error-message');
        if (!modalEl || !messageEl) {
            // Fallback: log to console if markup is missing.
            console.error('[Error Modal]', message);
            return;
        }
        messageEl.textContent = typeof message === 'string' ? message : String(message);
        showModal(modalEl);
    }

    /**
     * Trap keyboard focus inside the currently open modal.
     * Required because EdgeHTML does not reliably enforce Bootstrap's
     * built-in focus trap.
     *
     * @param {KeyboardEvent} e
     */
    function handleModalFocusTrap(e) {
        if (!activeModalEl) { return; }
        if (e.key !== 'Tab') { return; }
        var focusableSelectors =
            'a[href], button:not([disabled]), input:not([disabled]), ' +
            'select:not([disabled]), textarea:not([disabled]), ' +
            '[tabindex]:not([tabindex="-1"])';
        var focusableElements = activeModalEl.querySelectorAll(focusableSelectors);
        if (focusableElements.length === 0) {
            e.preventDefault();
            return;
        }
        var first = focusableElements[0];
        var last  = focusableElements[focusableElements.length - 1];
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
     * Show a Bootstrap modal, or fall back to manual display.
     * Also activates a manual focus trap for EdgeHTML compatibility.
     *
     * @param {HTMLElement} modalEl
     */
    function showModal(modalEl) {
        previouslyFocused = document.activeElement;
        if (typeof bootstrap !== 'undefined' && bootstrap.Modal) {
            var modal = new bootstrap.Modal(modalEl);
            modal.show();
            setTimeout(function () {
                var computed = window.getComputedStyle(modalEl);
                if (computed.display !== 'none') {
                    activeModalEl = modalEl;
                    document.addEventListener('keydown', handleModalFocusTrap);
                }
            }, 100);
            return;
        }
        modalEl.style.display = 'block';
        modalEl.style.backgroundColor = 'rgba(0,0,0,0.5)';
        modalEl.classList.add('show');
        activeModalEl = modalEl;
        document.addEventListener('keydown', handleModalFocusTrap);
    }

    /**
     * Hide a Bootstrap modal, or fall back to manual hide.
     * Releases the focus trap and restores focus to the previously
     * focused element.
     *
     * @param {HTMLElement} modalEl
     */
    function hideModal(modalEl) {
        if (activeModalEl === modalEl) {
            activeModalEl = null;
            document.removeEventListener('keydown', handleModalFocusTrap);
        }
        if (typeof bootstrap !== 'undefined' && bootstrap.Modal) {
            var modal = bootstrap.Modal.getInstance(modalEl);
            if (modal) { modal.hide(); }
            if (previouslyFocused && typeof previouslyFocused.focus === 'function') {
                previouslyFocused.focus();
            }
            previouslyFocused = null;
            return;
        }
        modalEl.style.display = 'none';
        modalEl.classList.remove('show');
        if (previouslyFocused && typeof previouslyFocused.focus === 'function') {
            previouslyFocused.focus();
        }
        previouslyFocused = null;
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
     *
     * @param {string} [pendingMessage] - Message about to be sent.
     * @returns {number}
     */
    function getHistoryTokenCount(pendingMessage) {
        var total = 0;
        if (!Array.isArray(AppState.chatHistory)) { return 0; }
        for (var i = 0; i < AppState.chatHistory.length; i++) {
            var msg = AppState.chatHistory[i];
            if (!isValidMessage(msg)) { continue; }
            total += estimateTokens(msg.role + ': ' + msg.content);
        }
        if (typeof pendingMessage === 'string' && pendingMessage.length > 0) {
            total += estimateTokens('user: ' + pendingMessage);
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
        var exportBtn = document.getElementById('export-conversation-btn');
        if (!exportBtn) { return; }
        var hasData;
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
            var stored = Storage.getItem('assistant_chat_history');
            if (!stored) { AppState.chatHistory = []; return; }
            var parsed = JSON.parse(stored);
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
        .then(function (res) {
            if (!res.ok) { throw new Error('HTTP ' + res.status); }
            return res.json();
        })
        .then(function (data) {
            if (isPlainObject(data) && data.success === true &&
                    Array.isArray(data.conversation_history)) {
                for (var i = 0; i < data.conversation_history.length; i++) {
                    var msg = data.conversation_history[i];
                    if (!isValidMessage(msg)) { continue; }
                    appendMessage(msg.role, msg.content);
                }
            }
        })
        .catch(function (err) {
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
            var dataToExport = Array.isArray(AppState.chatHistory) ? AppState.chatHistory : [];
            if (dataToExport.length === 0) {
                showErrorModal('There is no data to export!');
                return;
            }
            triggerJsonDownload(
                JSON.stringify(dataToExport, null, 2),
                'conversation_' + isoFilenameTimestamp() + '.json'
            );
            return;
        }
        // Mode 1: server-side export.
        fetch(getApiUrl(), {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ action: 'export_conversation' })
        })
        .then(function (res) { return res.text(); })
        .then(function (text) {
            // The server may return a JSON error envelope or raw JSON data.
            // Attempt to detect an error envelope; if it is one, throw.
            // If not (SyntaxError or no error key), treat the raw text as the export.
            try {
                var data = JSON.parse(text);
                if (isPlainObject(data) && data.error) {
                    throw new Error(data.message || 'Failed to export conversation');
                }
            } catch (e) {
                if (!(e instanceof SyntaxError)) { throw e; }
                // SyntaxError → raw non-JSON body (unusual but handled).
            }
            triggerJsonDownload(text, 'conversation_' + isoFilenameTimestamp() + '.json');
        })
        .catch(function (err) {
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
            var blob = new Blob([jsonContent], { type: 'application/json' });
            var url  = URL.createObjectURL(blob);
            var a    = document.createElement('a');
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
        var reader = new FileReader();
        reader.onload = function (e) {
            try {
                var importedData = JSON.parse(e.target.result);
                if (!Array.isArray(importedData)) {
                    throw new Error('Invalid format: expected a JSON array.');
                }
                var validMessages = importedData
                    .filter(isValidMessage)
                    .map(function (msg) {
                        return {
                            role: msg.role.trim(),
                            content: msg.content.trim()
                        };
                    })
                    .filter(function (msg) {
                        return msg.content.length > 0;
                    });
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
                var formData = new FormData();
                formData.append('action', 'import_conversation');
                formData.append('conversation_file', file);
                fetch(getApiUrl(), { method: 'POST', body: formData })
                .then(function (res) {
                    if (!res.ok) { throw new Error('HTTP ' + res.status); }
                    return res.json();
                })
                .then(function (data) {
                    if (isPlainObject(data) && data.success === true &&
                            Array.isArray(data.conversation_history)) {
                        if (DOM.chatBox) { DOM.chatBox.innerHTML = ''; }
                        AppState.lastUserMessageDiv = null;
                        displayInitialMessage();
                        for (var i = 0; i < data.conversation_history.length; i++) {
                            var msg = data.conversation_history[i];
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
                .catch(function (err) {
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
        reader.onerror = function () {
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
            .then(function (res) {
                if (!res.ok) { throw new Error('HTTP ' + res.status); }
                return res.json();
            })
            .then(function (data) {
                var cleared = (isPlainObject(data) && (
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
            .catch(function (err) {
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
    var _compressionInFlight = null;

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
        var cb = typeof callback === 'function' ? callback : function () {};
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

        var payload = {
            action: 'summarize',
            conversation_history: AppState.chatHistory
        };
        if (typeof pendingMessage === 'string' && pendingMessage.length > 0) {
            payload.pending_message = pendingMessage;
        }

        // The server enforces its own authoritative request timeout server-side
        // (the user-configured request_timeout, with no fixed minimum — PHP runs
        // up to its max_execution_time). The client must NEVER send or override
        // it. We only READ that configured value so the client's abort timeout
        // stays strictly below it, ensuring we always get to decide what happens
        // on a slow summarisation instead of inheriting an opaque upstream error.
        var serverTimeoutSec = (typeof AppState.requestTimeout === 'number' && AppState.requestTimeout > 0)
            ? AppState.requestTimeout
            : DEFAULT_CONFIG.REQUEST_TIMEOUT;
        var CLIENT_TIMEOUT_MS = Math.max((serverTimeoutSec - 5) * 1000, 5000);
        var MAX_ATTEMPTS = 2;
        // Brief delay before a retry so a transient upstream blip is not hit
        // instantly again. Kept small relative to the overall request budget.
        var RETRY_BACKOFF_MS = 1000;

        function attempt(attemptNo) {
            showThinkingMessage();
            var controller = ('AbortController' in window) ? new AbortController() : null;
            var timer = null;
            if (controller && typeof controller.signal !== 'undefined') {
                timer = setTimeout(function () {
                    try { controller.abort(); } catch (e) { /* ignore */ }
                }, CLIENT_TIMEOUT_MS);
            }
            var fetchOpts = {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload)
            };
            if (controller) { fetchOpts.signal = controller.signal; }
            return fetch(getApiUrl(), fetchOpts)
                .then(function (res) {
                    if (!res.ok) { throw new Error('HTTP ' + res.status); }
                    return res.json();
                })
                .then(function (data) {
                    removeThinkingMessage();
                    if (isPlainObject(data) && data.success === true && Array.isArray(data.summarized_history)) {
                        AppState.chatHistory = data.summarized_history.filter(isValidMessage);
                        saveHistoryToStorage();
                        return { done: true };
                    }
                    if (isPlainObject(data) && data.error === 'NOT_NEEDED') {
                        return { done: true };
                    }
                    // Unknown/unexpected response — log and continue rather than freeze.
                    // FIX-BUG-3b: Original code omitted cb() here.
                    console.warn(
                        '[History] Compression returned unexpected response:',
                        isPlainObject(data) ? data.error : 'non-object'
                    );
                    return { done: true };
                })
                .catch(function (err) {
                    // AbortError => our own client timeout (handled as retryable).
                    var isAbort = err && err.name === 'AbortError';
                    if (attemptNo < MAX_ATTEMPTS) {
                        console.warn(
                            '[History] Compression request failed (attempt ' +
                            attemptNo + '), retrying:',
                            err.message
                        );
                        // Wait out the back-off, then retry with a fresh controller.
                        return new Promise(function (resolve) {
                            setTimeout(resolve, RETRY_BACKOFF_MS);
                        }).then(function () {
                            return attempt(attemptNo + 1);
                        });
                    }
                    // FIX-BUG-3: Original code omitted cb() here.
                    removeThinkingMessage();
                    console.warn('[History] Compression request failed:', err.message);
                    return { done: true, error: isAbort ? 'timeout' : 'error' };
                })
                .then(function (result) {
                    if (timer) { clearTimeout(timer); }
                    return result;
                });
        }

        _compressionInFlight = attempt(1).then(function (result) {
            _compressionInFlight = null;
            cb();
            return result;
        }, function (err) {
            _compressionInFlight = null;
            removeThinkingMessage();
            console.warn('[History] Compression request failed:', err && err.message);
            cb();
        });
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
        var senderStr = typeof sender === 'string' ? sender : 'chatbot';
        var messageDiv = document.createElement('div');
        var extraClass = (typeof messageClass === 'string' && messageClass.length > 0) ? (' ' + messageClass) : '';
        messageDiv.className = 'message ' + (senderStr === 'user' ? 'user-message' : 'chatbot-message') + extraClass;
        messageDiv.setAttribute('tabindex', '-1');
        var html = '';
        if (typeof action === 'string' && action.length > 0) {
            html += '<span style="font-style:italic;">*' +
                    escapeHtml(action.trim()) +
                    '*</span> ';
        }
        if (typeof text === 'string' && text.length > 0) {
            // Unescape literal \n sequences that some LLMs emit as the two characters \n.
            var fixedText = text.replace(/\\n/g, '\n');
            html += nl2br(escapeHtml(fixedText));
        }
        messageDiv.innerHTML = '<div class="bubble">' + html + '</div>';
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
        var messageDiv = document.createElement('div');
        messageDiv.className = 'message chatbot-message';
        var videoPath = 'media/' + encodeURIComponent(videoFileName);
        var loadingDiv = document.createElement('div');
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
        .then(function (response) {
            if (!response.ok) { throw new Error('Video not found'); }
            var videoContainer = document.createElement('div');
            videoContainer.className = 'video-container mt-2 mb-3 w-100 text-center';
            var video = document.createElement('video');
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
        .catch(function () {
            var errorDiv = document.createElement('div');
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
            '<div class="bubble"><em>' +
            escapeHtml(AppState.chatbotName) +
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
        var dots = 1;
        var intervalId = setInterval(function () {
            if (!AppState.thinkingMessageDiv) {
                clearInterval(intervalId);
                return;
            }
            dots = (dots % 3) + 1;
            span.textContent = Array(dots + 1).join('.');
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
            var byteCharacters;
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
            var byteArray = new Uint8Array(byteCharacters.length);
            for (var i = 0; i < byteCharacters.length; i++) {
                byteArray[i] = byteCharacters.charCodeAt(i);
            }
            var audioBlob = new Blob([byteArray], { type: 'audio/wav' });
            var audioUrl  = URL.createObjectURL(audioBlob);
            var audio     = new Audio(audioUrl);
            AppState.currentAudio = audio;
            audio.onended = function () {
                URL.revokeObjectURL(audioUrl);
                AppState.currentAudio = null;
            };
            audio.onerror = function () {
                URL.revokeObjectURL(audioUrl);
                AppState.currentAudio = null;
                console.warn('[Audio] Playback error');
            };
            audio.play().catch(function (err) {
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
    function connectToLlamaDirect(userMessage, callback, skipCompression) {
        if (typeof userMessage !== 'string' || userMessage.trim().length === 0) {
            if (typeof callback === 'function') { callback(null); }
            return;
        }
        // FIX-BUG-6: Only attempt compression once per send cycle.
        if (!skipCompression) {
            var currentTokens = getHistoryTokenCount(userMessage);
            if (currentTokens > AppState.warningThreshold &&
                    AppState.chatHistory.length > 0) {
                compressHistoryViaApi(userMessage, function () {
                    // Pass skipCompression=true to avoid a second compression attempt.
                    connectToLlamaDirect(userMessage, callback, true);
                });
                return;
            }
        }
        // Build the messages array: optional system prompt + history + new user turn.
        var messages = [];
        if (typeof AppState.systemPrompt === 'string' &&
                AppState.systemPrompt.length > 0) {
            messages.push({ role: 'system', content: AppState.systemPrompt });
        }
        if (Array.isArray(AppState.chatHistory)) {
            for (var i = 0; i < AppState.chatHistory.length; i++) {
                var msg = AppState.chatHistory[i];
                if (isValidMessage(msg)) {
                    messages.push({ role: msg.role, content: msg.content });
                }
            }
        }
        messages.push({ role: 'user', content: userMessage });
        var payload;
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
        fetch(AppState.llmEndpoint, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Accept': 'text/event-stream'
            },
            body: payload,
            signal: AppState.streamingController.signal
        })
        .then(function (res) {
            if (!res.ok) { throw new Error('HTTP ' + res.status); }
            // FIX-BUG-4: res.body can be null in some environments.
            if (!res.body) {
                throw new Error('Response body is null; Streams API may not be supported.');
            }

            return res.body.getReader();
        })
        .then(function (reader) {
            var decoder = new TextDecoder();
            var buffer = '';
            var assistantMessage = '';
            var completed = false;  // FIX-BUG-1: double-callback guard.
            // Create the streaming message bubble.
            var messageDiv = document.createElement('div');
            messageDiv.className = 'message chatbot-message';
            messageDiv.innerHTML =
                '<div class="bubble">' +
                '<span class="stream-content"></span>' +
                '<span class="dots">.</span>' +
                '</div>';
            AppState.streamingMessageDiv = messageDiv;
            if (DOM.chatBox) {
                DOM.chatBox.appendChild(messageDiv);
                DOM.chatBox.scrollTop = DOM.chatBox.scrollHeight;
            }

            /**
             * Finalise the stream: hide the cursor dot, persist the exchange,
             * and invoke the caller's callback. Idempotent via `completed`.
             *
             * @param {ReadableStreamDefaultReader} rdr - The reader to cancel.
             */
            function finalise(rdr) {
                if (completed) { return; }
                completed = true;
                var dots = messageDiv.querySelector('.dots');
                if (dots) { dots.style.display = 'none'; }
                var shouldSave = (assistantMessage.length > 0 && (!AppState.userStoppedStream));
                if (shouldSave) {
                    AppState.chatHistory.push({ role: 'user',      content: userMessage });
                    AppState.chatHistory.push({ role: 'assistant', content: assistantMessage });
                    saveHistoryToStorage();
                }
                if (AppState.userStoppedStream) { AppState.userStoppedStream = false; }
                AppState.streamingMessageDiv = null;
                if (rdr && typeof rdr.cancel === 'function') {
                    try {
                        var cancelResult = rdr.cancel();
                        if (cancelResult && typeof cancelResult.catch === 'function') {
                            cancelResult.catch(function () {});
                        }
                    } catch (e) { /* ignore */ }
                }
                if (typeof callback === 'function') {
                    try {
                        callback(shouldSave ? assistantMessage : null);
                    } catch (cbErr) {
                        console.warn('[Stream] Callback error:', cbErr.message);
                        finishProcessing();
                    }
                }
            }

            /**
             * Recursively read chunks from the SSE stream.
             */
            function readChunk() {
                reader.read().then(function (result) {
                    if (result.done) {
                        finalise(reader);
                        return;
                    }
                    // Decode the chunk; guard against non-Uint8Array values.
                    try {
                        var chunk = (result.value instanceof Uint8Array ||
                                     (typeof ArrayBuffer !== 'undefined' &&
                                      result.value instanceof ArrayBuffer))
                            ? decoder.decode(result.value, { stream: true })
                            : String(result.value);
                        buffer += chunk;
                    } catch (e) {
                        console.warn('[Stream] Decode error:', e.message);
                    }
                    // Process complete SSE lines.
                    var lines = buffer.split('\n');
                    buffer = lines.pop() || '';   // Keep the incomplete tail.
                    for (var j = 0; j < lines.length; j++) {
                        var line = lines[j];
                        if (typeof line !== 'string') { continue; }
                        line = line.trim();
                        if (line.length < 6 || line.indexOf('data: ') !== 0) { continue; }
                        var dataStr = line.substring(6).trim();
                        // FIX-WARN-2: Exact-match the [DONE] sentinel (case-insensitive).
                        if (dataStr.toUpperCase() === '[DONE]') { continue; }
                        try {
                            var data    = JSON.parse(dataStr);
                            var choices = data && Array.isArray(data.choices) ? data.choices : null;
                            var choice0 = choices && choices.length > 0 ? choices[0] : null;
                            // Accumulate delta content.
                            var delta   = choice0 && isPlainObject(choice0.delta) ? choice0.delta : null;
                            var content = delta && typeof delta.content === 'string' ? delta.content : '';
                            if (content.length > 0) {
                                assistantMessage += content;
                                var contentSpan = messageDiv.querySelector('.stream-content');
                                if (contentSpan) {
                                    contentSpan.innerHTML = nl2br(escapeHtml(assistantMessage));
                                    if (DOM.chatBox) {
                                        DOM.chatBox.scrollTop = DOM.chatBox.scrollHeight;
                                    }
                                }
                            }
                            // Check for a terminal finish_reason.
                            var finishReason = choice0 &&
                                typeof choice0.finish_reason === 'string'
                                ? choice0.finish_reason
                                : null;
                            if (finishReason === 'stop' ||
                                    finishReason === 'length' ||
                                    finishReason === 'abort') {
                                finalise(reader);
                                return;  // Stop reading; finalise() handles the rest.
                            }
                        } catch (e) {
                            // Malformed JSON in an SSE line — skip it.
                        }
                    }
                    if (!completed) { readChunk(); }
                }).catch(function (err) {
                    // Stream read error (includes AbortError on cancellation).
                    if (err && err.name !== 'AbortError') {
                        console.warn('[Stream] Read error:', err.message);
                    }
                    finalise(reader);
                });
            }
            readChunk();
        })
        .catch(function (err) {
            if (err && err.name !== 'AbortError') {
                console.warn('[Stream] Connection error:', err.message);
            }
            if (typeof callback === 'function') { callback(null); }
        });
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
        .then(function (res) {
            if (!res.ok) { throw new Error('HTTP ' + res.status); }
            return res.json();
        })
        .then(function (data) {
            // Ensure we always pass a plain object to the callback.
            var safeData = isPlainObject(data) ? data : {};
            if (AppState.responseMode === 1 && !safeData.error) {
                AppState.hasSessionConversation = true;
                updateExportButtonVisibility();
            }
            if (typeof callback === 'function') { callback(safeData); }
        })
        .catch(function (err) {
            console.warn('[API] Error:', err.message);
            if (typeof callback === 'function') {
                callback({ error: 'Connection error', message: err.message });
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
        var rawValue = DOM.input.value;
        var message  = typeof rawValue === 'string' ? rawValue.trim() : '';
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
        var userMsgDiv = appendMessage('user', message);
        AppState.lastUserMessageDiv = userMsgDiv;
        DOM.input.value = '';
        DOM.input.classList.remove('is-invalid');
        DOM.input.style.height = 'auto';
        // In streaming mode, history is entirely client-side. Check compression here
        // before either the embedding or direct-LLM paths.
        if (AppState.responseMode === 2 &&
                getHistoryTokenCount(message) > AppState.warningThreshold &&
                AppState.chatHistory.length > 0) {
            compressHistoryViaApi(message, function () {
                if (!AppState.isProcessing) { return; }
                proceedWithSend(message);
            });
            return;
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
     * FIX-BUG-2: var replyText was declared three times in the original function
     * body (all hoisted to the same binding, correct-by-accident). Each usage site
     * now uses a distinct variable name to make data flow explicit.
     *
     * @param {string} message - The validated, trimmed user message.
     */
    function proceedWithSend(message) {
        // Streaming mode without embedding → connect directly to llama.cpp.
        if (AppState.responseMode === 2 && !AppState.embeddingEnabled) {
            connectToLlamaDirect(message, function () { finishProcessing(); });
            return;
        }
        showThinkingMessage();
        sendToApi(message, function (data) {
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
                var errCode   = data.error;
                var errDetail = typeof data.message === 'string' ? data.message : '';
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
                    connectToLlamaDirect(message, function () { finishProcessing(); });
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
                connectToLlamaDirect(message, function () { finishProcessing(); });
                return;
            }
            // Optional TTS audio
            if (typeof data.audio_data === 'string' && data.audio_data.length > 0) {
                playAudioFromBase64(data.audio_data);
            }
            // Response with an action verb
            if (typeof data.response_action === 'string' &&
                    data.response_action.trim().length > 0) {
                var action = data.response_action.trim();
                if (action === '#LOOP_VIDEO' &&
                        typeof data.media_data === 'string' &&
                        data.media_data.length > 0) {
                    appendVideoMessage(data.media_data);
                    var videoReply = (typeof data.reply === 'string') ? data.reply.trim() : '';
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
                var actionReply = (typeof data.reply === 'string') ? data.reply.trim() : '';
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
                var plainReply = data.reply.trim();
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
            if (typeof e.preventDefault === 'function') { e.preventDefault(); }
            if (typeof e.stopPropagation === 'function') { e.stopPropagation(); }
            if (typeof e.stopImmediatePropagation === 'function') { e.stopImmediatePropagation(); }
            e.returnValue = false;
            handleFormSubmit();
            return;
        }
        if (e.key === 'ArrowUp' || e.key === 'ArrowDown') {
            if (!DOM.chatBox) { return; }
            if (typeof e.preventDefault === 'function') { e.preventDefault(); }
            if (typeof e.stopImmediatePropagation === 'function') { e.stopImmediatePropagation(); }
            var messages     = DOM.chatBox.querySelectorAll('.message');
            var messageCount = messages.length;
            if (messageCount === 0) { return; }
            var activeEl     = document.activeElement;
            var currentIndex = -1;
            for (var i = 0; i < messageCount; i++) {
                if (activeEl === messages[i]) { currentIndex = i; break; }
            }
            var newIndex = e.key === 'ArrowUp'
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
            if (typeof e.preventDefault === 'function') { e.preventDefault(); }
            if (typeof e.stopPropagation === 'function') { e.stopPropagation(); }
            e.returnValue = false;
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
            function (v) { return String(v); }
        );
        AppState.responseMode = getConfigValue(
            'RESPONSE_MODE',
            DEFAULT_CONFIG.RESPONSE_MODE,
            function (v) { return parseIntSafe(v, DEFAULT_CONFIG.RESPONSE_MODE); }
        );
        if (AppState.responseMode !== 1 && AppState.responseMode !== 2) {
            AppState.responseMode = DEFAULT_CONFIG.RESPONSE_MODE;
        }
        // Build the full streaming endpoint URL.
        var rawEndpoint = getConfigValue(
            'LLM_ENDPOINT',
            DEFAULT_CONFIG.LLM_ENDPOINT,
            function (v) {
                v = String(v).trim();
                return v.length > 0 ? v : DEFAULT_CONFIG.LLM_ENDPOINT;
            }
        );
        var llmHostUrl = getConfigValue(
            'LLM_HOST_URL',
            '/llamacpp/',
            function (v) { return String(v); }
        );
        var baseUrl  = llmHostUrl.replace(/\/+$/, '');
        var endpoint = rawEndpoint.indexOf('/') === 0 ? rawEndpoint : '/' + rawEndpoint;
        AppState.llmEndpoint = baseUrl + endpoint;
        AppState.llmCtxSize = getConfigValue(
            'LLM_CTX_SIZE',
            DEFAULT_CONFIG.LLM_CTX_SIZE,
            function (v) {
                var n = parseIntSafe(v, DEFAULT_CONFIG.LLM_CTX_SIZE);
                return n > 0 ? n : DEFAULT_CONFIG.LLM_CTX_SIZE;
            }
        );
        AppState.llmMaxResponseTokens = getConfigValue(
            'LLM_MAX_RESPONSE_TOKENS',
            DEFAULT_CONFIG.LLM_MAX_RESPONSE_TOKENS,
            function (v) {
                var n = parseIntSafe(v, DEFAULT_CONFIG.LLM_MAX_RESPONSE_TOKENS);
                return n > 0 ? n : DEFAULT_CONFIG.LLM_MAX_RESPONSE_TOKENS;
            }
        );
        AppState.safetyMargin = getConfigValue(
            'SAFETY_MARGIN',
            DEFAULT_CONFIG.SAFETY_MARGIN,
            function (v) {
                var n = parseIntSafe(v, DEFAULT_CONFIG.SAFETY_MARGIN);
                return n >= 0 ? n : DEFAULT_CONFIG.SAFETY_MARGIN;
            }
        );
        AppState.embeddingEnabled = getConfigValue(
            'EMBEDDING_ENABLED',
            DEFAULT_CONFIG.EMBEDDING_ENABLED,
            function (v) {
                return v === true || v === 'true' || v === 1 || v === '1';
            }
        );
        AppState.systemPrompt = getConfigValue(
            'SYSTEM_PROMPT',
            DEFAULT_CONFIG.SYSTEM_PROMPT,
            function (v) { return v === null ? null : String(v); }
        );
        AppState.apiEndpoint = getConfigValue(
            'API_ENDPOINT',
            DEFAULT_CONFIG.API_ENDPOINT,
            function (v) { return String(v); }
        );
        AppState.requestTimeout = getConfigValue(
            'REQUEST_TIMEOUT',
            DEFAULT_CONFIG.REQUEST_TIMEOUT,
            function (v) {
                var n = parseIntSafe(v, DEFAULT_CONFIG.REQUEST_TIMEOUT);
                return n > 0 ? n : DEFAULT_CONFIG.REQUEST_TIMEOUT;
            }
        );
        // Derive the compression threshold from validated values.
        var calculated = AppState.llmCtxSize -
                         (AppState.llmMaxResponseTokens + AppState.safetyMargin);
        AppState.warningThreshold = Math.max(calculated, 0);
    }

    /** Attach all event listeners. */
    function initEvents() {
        if (DOM.input) {
            DOM.input.addEventListener('input',   handleInput);
            DOM.input.addEventListener('keydown', handleKeydown);
        }
        if (DOM.submitBtn) {
            DOM.submitBtn.addEventListener('click', function (e) {
                if (e) {
                    if (typeof e.preventDefault === 'function') { e.preventDefault(); }
                    if (typeof e.stopPropagation === 'function') { e.stopPropagation(); }
                    if (typeof e.stopImmediatePropagation === 'function') { e.stopImmediatePropagation(); }
                    e.returnValue = false;
                }
                handleFormSubmit();
            });
        }
        var exportBtn = document.getElementById('export-conversation-btn');
        if (exportBtn) {
            exportBtn.addEventListener('click', function (e) {
                if (e) {
                    if (typeof e.preventDefault === 'function') { e.preventDefault(); }
                    if (typeof e.stopPropagation === 'function') { e.stopPropagation(); }
                    e.returnValue = false;
                }
                exportConversation();
            });
        }
        var importBtn = document.getElementById('import-conversation-btn');
        if (importBtn) {
            importBtn.addEventListener('click', function (e) {
                if (e) {
                    if (typeof e.preventDefault === 'function') { e.preventDefault(); }
                    if (typeof e.stopPropagation === 'function') { e.stopPropagation(); }
                    e.returnValue = false;
                }
                if (DOM.importInput) { DOM.importInput.click(); }
            });
        }
        if (DOM.importInput) {
            DOM.importInput.addEventListener('change', function (e) {
                var files = e.target && e.target.files;
                if (!files || files.length === 0) { return; }
                var file = files[0];
                var isJson = (typeof file.type === 'string' &&
                              file.type === 'application/json') ||
                             (typeof file.name === 'string' &&
                              file.name.slice(-5).toLowerCase() === '.json');
                if (isJson) {
                    ConfirmModal.show(
                        'Are you sure you want to import this conversation? ' +
                        'Current conversation will be replaced.',
                        function () { importConversation(file); }
                    );
                } else {
                    showErrorModal('Please select a valid JSON file.');
                }
                // Reset so the same file can be re-selected if needed.
                DOM.importInput.value = '';
            });
        }
        var newSessionBtn = document.getElementById('new-session-btn');
        if (newSessionBtn) {
            newSessionBtn.addEventListener('click', function () {
                ConfirmModal.show(
                    'Are you sure you want to start a new session? ' +
                    'All chat history will be permanently deleted.',
                    function () { startNewSession(); }
                );
            });
        }
        if (DOM.stopBtn) {
            DOM.stopBtn.addEventListener('click', function (e) {
                if (e) {
                    if (typeof e.preventDefault === 'function') { e.preventDefault(); }
                    if (typeof e.stopPropagation === 'function') { e.stopPropagation(); }
                    e.returnValue = false;
                }
                handleStop();
            });
        }
        // Abort any active stream if the page is navigated away.
        window.addEventListener('beforeunload', function () {
            abortActiveStream();
        });
        // EdgeHTML-compatible modal dismiss handler.
        // Bootstrap's data-bs-dismiss="modal" does not work reliably in Edge,
        // so we explicitly close modals on click.
        document.addEventListener('click', function (e) {
            var dismissBtn = e.target.closest('[data-bs-dismiss="modal"], .btn-close');
            if (!dismissBtn) { return; }
            var modal = dismissBtn.closest('.modal');
            if (modal) {
                if (e) {
                    if (typeof e.preventDefault === 'function') { e.preventDefault(); }
                    if (typeof e.stopPropagation === 'function') { e.stopPropagation(); }
                    e.returnValue = false;
                }
                hideModal(modal);
            }
        });
    }

    /**
     * Display the configured initial greeting from the chatbot (if set).
     * Called once per session before history is rendered.
     */
    function displayInitialMessage() {
        var initialMessage = getConfigValue(
            'INITIAL_MESSAGE',
            null,
            function (v) { return v === null ? null : String(v); }
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
        for (var i = 0; i < AppState.chatHistory.length; i++) {
            var msg = AppState.chatHistory[i];
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
                function (v) {
                    return v === true || v === 'true' || v === 1 || v === '1';
                }
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
            console.log('[Init] Response mode:',       AppState.responseMode);
            console.log('[Init] Chatbot name:',        AppState.chatbotName);
            console.log('[Config] llmCtxSize:',        AppState.llmCtxSize);
            console.log('[Config] maxResponseTokens:', AppState.llmMaxResponseTokens);
            console.log('[Config] safetyMargin:',      AppState.safetyMargin);
            console.log('[Config] warningThreshold:',  AppState.warningThreshold);
            console.log('[Config] llmEndpoint:',       AppState.llmEndpoint);
        } catch (e) {
            console.error('[Init] Fatal error during initialisation:', e.message, e);
        }
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
