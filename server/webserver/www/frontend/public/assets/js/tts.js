/**
 * =============================================================================
 * Text-to-Speech (TTS) Client - Standalone JavaScript
 * =============================================================================
 * A robust, ES6-based cross-browser client for the standalone TTS API
 * (/api/tts). It lets the user type short text, send it to the configured TTS
 * server, play the synthesized audio, and download the result.
 *
 * Features:
 * - Automatic fallback to defaults for any misconfigured values
 * - Character counter with hard max-length tied to tts_max_tokens
 * - Binary audio response handling (blob URL) — no base64 exposed to the user
 * - Play / stop / download the generated audio
 * - HTML escaping for XSS prevention
 * - Bootstrap-based error modal for accessibility
 * - Keyboard navigation (Enter to play)
 * - Works standalone (no chat.js required) and can be imported by chat.js later
 *
 * Compatibility: all modern browsers (Edge, Chrome, Firefox, Safari) and
 * embedded runtimes such as PHP Desktop (Chromium 2025) — ES6+.
 * Built on the ES6 standard (no IE/EdgeHTML transpilation needed).
 *
 * This module is written as a single IIFE that loads directly via a <script>
 * tag (no bundler/transpilation), so it stays 100% ES6: const/let, arrow
 * functions, template literals, async/await, and the native
 * AbortController/fetch/Blob/URL APIs.
 *
 * The TTS service address and limits come from PHP/Twig-injected globals
 * (TTS_API_ENDPOINT, TTS_MAX_CHARS, TTS_MAX_TOKENS, TTS_REQUEST_TIMEOUT).
 * TTS fallback (if any) is resolved at the PHP configuration level, not here.
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
        API_ENDPOINT: '/api/tts',
        MAX_CHARS: 160,           // floor(64 * 2.5) for the default tts_max_tokens=64
        MAX_TOKENS: 64,
        REQUEST_TIMEOUT: 60,
        DEFAULT_THEME: 'LIGHT'
    };

    /** Characters-per-token ratio used for the token estimate (UTF-8). Mirrors the PHP backend. */
    const CHARS_PER_TOKEN = 2.5;

    /**
     * Application state — single source of truth.
     */
    const AppState = {
        isPlaying: false,
        currentAudio: null,
        cachedText: null,
        audioBlobUrl: null,
        audioContentType: 'audio/mpeg',
        defaultTheme: DEFAULT_CONFIG.DEFAULT_THEME,
        apiEndpoint: DEFAULT_CONFIG.API_ENDPOINT,
        maxChars: DEFAULT_CONFIG.MAX_CHARS,
        maxTokens: DEFAULT_CONFIG.MAX_TOKENS,
        requestTimeout: DEFAULT_CONFIG.REQUEST_TIMEOUT,
        /**
         * Sub-state for the chunked/pipelined chat-speech synthesiser.
         * Kept separate from the standalone TTS UI state so the two features
         * never clobber each other's audio resources.
         */
        speech: {
            isSpeaking: false,
            chunks: [],        // texts awaiting synthesis (in order)
            blobs: [],         // parallel array of {blobUrl, contentType}|null
            fetchIndex: 0,     // next chunk to request from the TTS API
            playIndex: 0,      // next chunk to play back
            currentAudio: null,// HTMLAudioElement for the chunk currently playing
            aborted: false     // set true by stopSpeech() to cancel in-flight work
        }
    };

    /** Cached DOM element references. Populated once in initDOM(). */
    const DOM = {
        input: null,
        charCount: null,
        maxCharsEl: null,
        playBtn: null,
        downloadBtn: null,
        stopBtn: null,
        status: null,
        body: null
    };

    // =============================================================================
    // SECTION 2: THEME TOGGLE — Light/Dark Mode
    // =============================================================================
    // Persists the user's theme preference in localStorage under the key
    // 'tts_theme'. Values are stored UPPERCASE ('LIGHT' or 'DARK'),
    // and all read/write operations are case-insensitive and trimmed of
    // surrounding whitespace. On first visit (no stored value), the
    // admin-configured 'default_theme' is consulted: only 'DARK'
    // (case-insensitive) enables dark mode; any other value falls back
    // to light mode.
    // Cross-browser: try/catch around all localStorage calls; graceful
    // fallback to light mode on any error.
    // =============================================================================

    /** localStorage key for persisting the user's theme preference. */
    const THEME_STORAGE_KEY = 'tts_theme';

    /**
     * Apply a theme by adding or removing the .dark-mode class on <body>.
     *
     * @param {'LIGHT'|'DARK'} theme
     */
    function applyTheme(theme) {
        if (typeof theme !== 'string') { return; }
        try {
            if (theme.toUpperCase().trim() === 'DARK') {
                document.body.classList.add('dark-mode');
            } else {
                document.body.classList.remove('dark-mode');
            }
        } catch (e) {
            console.warn('[Theme] Failed to apply theme:', e.message);
        }
    }

    /**
     * Return the stored theme from localStorage, or null if absent/error.
     *
     * @returns {string|null}
     */
    function getStoredTheme() {
        try {
            const stored = localStorage.getItem(THEME_STORAGE_KEY);
            if (typeof stored !== 'string') { return null; }
            return stored.toUpperCase().trim();
        } catch (e) {
            console.warn('[Theme] Failed to read localStorage:', e.message);
        }
        return null;
    }

    /**
     * Store the theme preference in localStorage.
     *
     * @param {'LIGHT'|'DARK'} theme
     * @returns {boolean} true if stored successfully
     */
    function storeTheme(theme) {
        try {
            const themeFixed = theme.toUpperCase().trim();
            localStorage.setItem(THEME_STORAGE_KEY, themeFixed);
            return true;
        } catch (e) {
            console.warn('[Theme] Failed to write localStorage:', e.message);
            return false;
        }
    }

    /**
     * Return the default theme applied when no stored user preference exists.
     *
     * @returns {string} The normalized default theme value; 'LIGHT' is the
     *                   ultimate fallback when the setting is absent/invalid.
     */
    function getDefaultTheme() {
        try {
            const t = AppState.defaultTheme;
            if (typeof t !== 'string') { return DEFAULT_CONFIG.DEFAULT_THEME; }
            return t.toUpperCase().trim();
        } catch (e) {
            console.warn('[Theme] Failed to read default theme:', e.message);
        }
        return DEFAULT_CONFIG.DEFAULT_THEME;
    }

    /**
     * Initialise the theme on page load.
     */
    function initTheme() {
        const stored = getStoredTheme();
        const theme = (stored === null ? getDefaultTheme() : stored);
        applyTheme(theme);
        updateThemeToggleButton(theme);
    }

    /**
     * Toggle between light and dark mode, save the new preference and update the toggle button icon.
     */
    function toggleTheme() {
        const isCurrentlyDark = document.body.classList.contains('dark-mode');
        const newTheme = isCurrentlyDark ? 'LIGHT' : 'DARK';
        applyTheme(newTheme);
        storeTheme(newTheme);
        updateThemeToggleButton(newTheme);
    }

    /**
     * Bind the theme toggle button click handler.
     * Null-guarded so it works even on the TTS disabled error page where no TTS-specific DOM elements exist.
     */
    function bindThemeToggle() {
        const btn = document.getElementById('theme-toggle-btn');
        if (!btn) { return; }
        btn.addEventListener('click', (e) => {
            e.preventDefault();
            e.stopPropagation();
            toggleTheme();
        });
    }

    /**
     * Update the theme toggle button text/icons to reflect the current theme.
     *
     * @param {'LIGHT'|'DARK'} theme
     */
    function updateThemeToggleButton(theme) {
        const btn = document.getElementById('theme-toggle-btn');
        if (!btn) { return; }
        const sunSpan = btn.querySelector('.theme-icon-sun');
        const moonSpan = btn.querySelector('.theme-icon-moon');
        if (theme.toUpperCase().trim() === 'DARK') {
            if (sunSpan) { sunSpan.style.display = 'none'; }
            if (moonSpan) { moonSpan.style.display = 'inline'; }
        } else {
            if (sunSpan) { sunSpan.style.display = 'inline'; }
            if (moonSpan) { moonSpan.style.display = 'none'; }
        }
    }

    // =============================================================================
    // SECTION 3: UTILITIES & CONFIG HELPERS
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
     * Estimate token count for a text string using a character-based heuristic.
     * Deliberately fast and approximate (±20 % typical).
     *
     * @param {string} text
     * @returns {number}
     */
    function estimateTokens(text) {
        if (typeof text !== 'string' || text.length === 0) { return 0; }
        return Math.ceil(text.length / CHARS_PER_TOKEN);
    }

    // =============================================================================
    // SECTION 4: MODAL HELPERS
    // =============================================================================

    /**
     * Show an error modal with the supplied message.
     *
     * @param {string} message
     */
    function showErrorModal(message) {
        const modalEl = document.getElementById('error-modal');
        const messageEl = document.getElementById('error-message');
        if (!modalEl || !messageEl) {
            console.error('[Error Modal]', message);
            return;
        }
        messageEl.textContent = typeof message === 'string' ? message : String(message);
        showModal(modalEl);
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
     * @param {HTMLElement} modalEl
     */
    function showModal(modalEl) {
        modalEl.setAttribute('tabindex', '-1');
        modalEl.style.display = 'block';
        modalEl.style.backgroundColor = 'rgba(0,0,0,0.5)';
        modalEl.classList.add('show');
        // Move focus into the modal immediately so keyboard users start inside it.
        try {
            const focusable =
                modalEl.querySelector('.modal-footer .btn-primary, #confirm-ok-btn') ||
                modalEl.querySelector('a[href], button:not([disabled]):not(.btn-close), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])') ||
                modalEl;
            focusable.focus();
        } catch (e) {
            console.warn('[Modal] Could not move focus into modal:', e.message);
        }
        document.addEventListener('keydown', handleModalKeydown);
    }

    /**
     * Hide the modal.
     *
     * @param {HTMLElement} modalEl
     */
    function hideModal(modalEl) {
        modalEl.style.display = 'none';
        modalEl.classList.remove('show');
        document.removeEventListener('keydown', handleModalKeydown);
    }

    /**
     * Keyboard handling for the open modal: Escape to close.
     *
     * @param {KeyboardEvent} e
     */
    function handleModalKeydown(e) {
        if (!e || e.key !== 'Escape') { return; }
        e.preventDefault();
        const modal = document.getElementById('error-modal');
        if (modal) { hideModal(modal); }
    }

    // =============================================================================
    // SECTION 5: UI HELPERS
    // =============================================================================

    /**
     * Update the character counter and enforce the max-length limit.
     */
    function updateCharCount() {
        if (!DOM.input || !DOM.charCount || !DOM.maxCharsEl) { return; }
        const value = typeof DOM.input.value === 'string' ? DOM.input.value : '';
        const len = value.length;
        DOM.charCount.textContent = String(len);
        // Visual hint when approaching/at the limit.
        if (len >= AppState.maxChars) {
            DOM.input.classList.add('is-invalid');
        } else {
            DOM.input.classList.remove('is-invalid');
        }
        DOM.playBtn.disabled = (len === 0);
    }

    /**
     * Set a user-visible status message.
     *
     * @param {string} msg   - Message text (plain text, escaped before insert).
     * @param {string} [type] - 'info' | 'success' | 'error' | 'muted'
     */
    function setStatus(msg, type) {
        if (!DOM.status) { return; }
        DOM.status.textContent = typeof msg === 'string' ? msg : String(msg);
        DOM.status.className = 'small';
        if (type === 'success') { DOM.status.classList.add('text-success'); }
        else if (type === 'error') { DOM.status.classList.add('text-danger'); }
        else if (type === 'muted') { DOM.status.classList.add('text-muted'); }
    }

    /**
     * Stop any currently playing audio and release resources.
     */
    function stopAudio() {
        if (AppState.currentAudio) {
            try {
                // Detach handlers first so stopping does not trigger spurious
                // onerror/onended callbacks when we clear the source below.
                AppState.currentAudio.onerror = null;
                AppState.currentAudio.onended = null;
                AppState.currentAudio.pause();
                AppState.currentAudio.src = '';
            } catch (e) { /* ignore */ }
            AppState.currentAudio = null;
        }
        // Keep AppState.audioBlobUrl intact so the Download button remains
        // usable after stopping playback. The blob URL is revoked when new
        // audio is generated (revokeBlobUrl) or on page unload.
        AppState.isPlaying = false;
        updatePlaybackButtons();
    }

    /**
     * Revoke any previously created blob URL to avoid memory leaks.
     */
    function revokeBlobUrl() {
        if (AppState.audioBlobUrl) {
            try { URL.revokeObjectURL(AppState.audioBlobUrl); } catch (e) { /* ignore */ }
            AppState.audioBlobUrl = null;
        }
    }

    /**
     * Enable/disable playback-related buttons based on state.
     */
    function updatePlaybackButtons() {
        if (!DOM.playBtn || !DOM.downloadBtn || !DOM.stopBtn || !DOM.input) { return; }
        const hasInput = (typeof DOM.input.value === 'string' && DOM.input.value.trim().length > 0);
        DOM.playBtn.disabled = !hasInput || AppState.isPlaying;
        DOM.downloadBtn.disabled = !AppState.audioBlobUrl || AppState.isPlaying;
        DOM.stopBtn.disabled = !AppState.isPlaying;
        DOM.stopBtn.style.display = AppState.isPlaying ? '' : 'none';
    }

    /**
     * Play an audio blob URL through an HTMLAudioElement.
     *
     * @param {string} blobUrl - Object URL pointing at the audio blob.
     */
    function playAudio(blobUrl) {
        if (typeof blobUrl !== 'string' || blobUrl.length === 0) { return; }
        try {
            stopAudio();
            const audio = new Audio(blobUrl);
            AppState.currentAudio = audio;
            AppState.isPlaying = true;
            updatePlaybackButtons();
            audio.onended = () => {
                AppState.isPlaying = false;
                AppState.currentAudio = null;
                updatePlaybackButtons();
                setStatus('Playback finished.', 'success');
            };
            audio.onerror = () => {
                AppState.isPlaying = false;
                AppState.currentAudio = null;
                updatePlaybackButtons();
                // Keep AppState.audioBlobUrl intact so Download still works after
                // a playback error. Only detach this handler to avoid re-entry.
                audio.onerror = null;
                setStatus('Playback error: the browser could not play this audio format.', 'error');
                console.warn('[Audio] Playback error');
            };
            audio.play().catch((err) => {
                AppState.isPlaying = false;
                AppState.currentAudio = null;
                updatePlaybackButtons();
                audio.onerror = null;
                setStatus('Playback blocked by browser policy: ' + escapeHtml(err.message), 'error');
                console.warn('[Audio] Play blocked:', err.message);
            });
        } catch (e) {
            AppState.isPlaying = false;
            AppState.currentAudio = null;
            updatePlaybackButtons();
            setStatus('Unexpected playback error: ' + escapeHtml(e.message), 'error');
            console.warn('[Audio] Unexpected error:', e.message);
        }
    }

    /**
     * Trigger a browser file download with the given blob URL and filename.
     *
     * @param {string} blobUrl - Object URL pointing at the audio blob.
     * @param {string} filename - Suggested filename for the download.
     */
    function triggerAudioDownload(blobUrl, filename) {
        if (typeof blobUrl !== 'string' || blobUrl.length === 0) {
            showErrorModal('No audio available to download.');
            return;
        }
        try {
            const a = document.createElement('a');
            a.href = blobUrl;
            a.download = filename;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
        } catch (e) {
            console.warn('[Download] Failed:', e.message);
            showErrorModal('Download failed: ' + escapeHtml(e.message));
        }
    }

    // =============================================================================
    // SECTION 6: API COMMUNICATION
    // =============================================================================

    /**
     * Return the configured TTS API endpoint URL.
     *
     * @returns {string}
     */
    function getApiUrl() {
        return AppState.apiEndpoint || DEFAULT_CONFIG.API_ENDPOINT || '/api/tts';
    }

    /**
     * Send text to the TTS API and return the response as raw audio bytes plus
     * the Content-Type reported by the server.
     *
     * The server returns raw binary audio (Content-Type forwarded as-is).
     *
     * @param {string} text - The text to synthesize.
     * @returns {Promise<{buffer: ArrayBuffer, contentType: string}>}
     * @throws {Error} On network, HTTP, or JSON error responses.
     */
    async function sendToTtsApi(text) {
        if (typeof text !== 'string' || text.trim().length === 0) {
            throw new Error('Invalid text');
        }
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), AppState.requestTimeout * 1000);
        try {
            const response = await fetch(getApiUrl(), {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ input: text }),
                signal: controller.signal
            });
            if (!response.ok) {
                // Try to read a JSON error envelope from the server.
                let detail = 'HTTP ' + response.status;
                try {
                    const data = await response.json();
                    if (isPlainObject(data) && typeof data.message === 'string') {
                        detail = data.message;
                    } else if (isPlainObject(data) && typeof data.error === 'string') {
                        detail = data.error;
                    }
                } catch (e) {
                    // Not JSON — fall back to the HTTP status text.
                }
                throw new Error(detail);
            }
            const buffer = await response.arrayBuffer();
            const contentType = (response.headers && typeof response.headers.get === 'function')
                ? (response.headers.get('content-type') || 'audio/mpeg')
                : 'audio/mpeg';
            return { buffer, contentType };
        } finally {
            clearTimeout(timeoutId);
        }
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

    // =============================================================================
    // SECTION 7: MAIN ACTION HANDLERS
    // =============================================================================

    /**
     * Handle the Play button: validate input, call the TTS API, create a blob
     * URL from the binary audio response, and play it.
     */
    async function handlePlay() {
        if (AppState.isPlaying || !DOM.input) { return; }
        const text = typeof DOM.input.value === 'string' ? DOM.input.value.trim() : '';
        if (text.length === 0) {
            DOM.input.classList.add('is-invalid');
            DOM.input.focus();
            return;
        }
        // Client-side pre-validation: enforce max length before hitting the server.
        if (text.length > AppState.maxChars) {
            DOM.input.classList.add('is-invalid');
            DOM.input.focus();
            setStatus('Text too long: ' + text.length + ' / ' + AppState.maxChars + ' characters.', 'error');
            return;
        }
        DOM.input.classList.remove('is-invalid');
        // Play the cached audio when the textarea content is unchanged since
        // the last generation. Only call the TTS API when there is no cached
        // audio or the content has changed.
        if (AppState.audioBlobUrl && AppState.cachedText === text) {
            setStatus('Playing cached audio.', 'info');
            updatePlaybackButtons();
            playAudio(AppState.audioBlobUrl);
            return;
        }
        revokeBlobUrl();
        setStatus('Generating audio...', 'info');
        updatePlaybackButtons();
        try {
            const result = await sendToTtsApi(text);
            const blob = new Blob([result.buffer], { type: result.contentType });
            const blobUrl = URL.createObjectURL(blob);
            AppState.audioBlobUrl = blobUrl;
            AppState.cachedText = text;
            AppState.audioContentType = result.contentType;
            setStatus('Audio ready.', 'success');
            updatePlaybackButtons();
            playAudio(blobUrl);
        } catch (err) {
            const msg = (err && typeof err.message === 'string') ? err.message : 'Unknown error';
            setStatus('TTS error: ' + escapeHtml(msg), 'error');
            console.warn('[TTS] Error:', err.message);
        }
    }

    /**
     * Handle the Download button: download the last generated audio blob.
     */
    function handleDownload() {
        if (!AppState.audioBlobUrl) {
            showErrorModal('No audio available to download. Generate audio first.');
            return;
        }
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
        const ext = (typeof AppState.audioContentType === 'string' &&
                AppState.audioContentType.indexOf('wav') !== -1) ? 'wav' : 'mp3';
        triggerAudioDownload(AppState.audioBlobUrl, 'tts_' + timestamp + '.' + ext);
    }

    /**
     * Handle the Stop button: stop playback and reset UI.
     */
    function handleStop() {
        stopAudio();
        setStatus('Playback stopped.', 'muted');
    }

    // =============================================================================
    // SECTION 7.5: CHUNKED & PIPELINED CHAT SPEECH (reused by chat.js)
    // =============================================================================
    /**
     * Characters treated as sentence-closing (final) punctuation. A chunk may end
     * at any of these so that the audio sounds like complete sentences.
     * @type {string}
     */
    const SENTENCE_END_PUNCTUATION = '.?!…';

    /**
     * Characters treated as subsentence boundaries. Used when a single sentence
     * is longer than the max TTS token count; we cut at the last such mark that
     * still fits so the audio stays as natural as possible.
     * @type {string}
     */
    const SUBSENTENCE_PUNCTUATION = ',;:-()';

    /**
     * Split `$text` into chunks that all fit the max TTS token count, cutting only
     * at natural boundaries so the synthesized audio sounds as natural as possible.
     *
     * Chunking precedence (longest prefix that still fits `maxTokens`):
     *  1. End at the last sentence-closing punctuation mark (`.`, `?`, `!`, `…`).
     *  2. Else end at the last subsentence mark (`,`, `;`, `:`, `-`, `(`, `)`).
     *  3. Else end at the last whole word (a space).
     *  4. Else (a single word/token is too long) raw-cut by character to fit.
     *
     * The next chunk always begins immediately after the cut point (leading
     * whitespace is trimmed so playback does not start with a pause).
     *
     * @param {string} text      - Text to split into TTS-sized chunks.
     * @param {number} maxTokens - Maximum allowed estimated token count per chunk.
     * @returns {Array<string>} Ordered array of non-empty chunks. Empty when the
     *          input is empty/whitespace-only.
     */
    function splitIntoChunks(text, maxTokens) {
        const chunks = [];
        if (typeof text !== 'string') { return chunks; }
        if (!Number.isFinite(maxTokens) || maxTokens < 1) { maxTokens = DEFAULT_CONFIG.MAX_TOKENS; }
        const maxChars = Math.floor(maxTokens * CHARS_PER_TOKEN);
        if (maxChars < 1) { return chunks; }

        let remaining = text;
        while (remaining.length > 0) {
            // Trim leading whitespace so chunks never start with a pause.
            remaining = remaining.replace(/^\s+/, '');
            if (remaining.length === 0) { break; }

            // The whole remainder fits in one chunk.
            if (remaining.length <= maxChars) {
                chunks.push(remaining);
                break;
            }

            const searchLimit = Math.min(maxChars, remaining.length);
            let lastSentenceEnd = -1;
            let lastSubsentence = -1;
            let lastSpace = -1;

            // Scan the prefix that fits the token budget for the best boundary.
            for (let i = 0; i < searchLimit; i++) {
                const ch = remaining[i];
                if (SENTENCE_END_PUNCTUATION.indexOf(ch) !== -1) {
                    lastSentenceEnd = i;
                } else if (SUBSENTENCE_PUNCTUATION.indexOf(ch) !== -1) {
                    lastSubsentence = i;
                } else if (ch === ' ') {
                    lastSpace = i;
                }
            }

            let splitIndex = -1;
            if (lastSentenceEnd !== -1) {
                splitIndex = lastSentenceEnd;          // include the punctuation
            } else if (lastSubsentence !== -1) {
                splitIndex = lastSubsentence;          // include the subsentence mark
            } else if (lastSpace !== -1) {
                splitIndex = lastSpace - 1;            // cut before the trailing space
            }

            if (splitIndex !== -1 && splitIndex >= 0) {
                chunks.push(remaining.slice(0, splitIndex + 1));
                remaining = remaining.slice(splitIndex + 1);
            } else {
                // Rule 4: raw-cut by character to force the chunk into the limit.
                chunks.push(remaining.slice(0, maxChars));
                remaining = remaining.slice(maxChars);
            }
        }
        return chunks;
    }

    /**
     * Request a single chunk of synthesized audio from the TTS API.
     * Reuses the existing sendToTtsApi() so the chat path hits the same endpoint
     * and error handling as the standalone TTS UI.
     *
     * @param {string} text - Chunk text to synthesize (already validated to fit).
     * @returns {Promise<{buffer: ArrayBuffer, contentType: string}>}
     */
    async function fetchSpeechChunk(text) {
        return sendToTtsApi(text);
    }

    /**
     * Revoke every blob URL held in the speech blob cache and clear it.
     * Called by stopSpeech() and when a chunk finishes playing.
     *
     * @param {Array<{blobUrl:string,contentType:string}|null>} blobs
     * @param {number} [startIndex] - Optional first index to revoke (default 0).
     */
    function revokeSpeechBlobs(blobs, startIndex) {
        const start = (typeof startIndex === 'number' && startIndex >= 0) ? startIndex : 0;
        for (let i = start; i < blobs.length; i++) {
            const info = blobs[i];
            if (info && typeof info.blobUrl === 'string' && info.blobUrl.length > 0) {
                try { URL.revokeObjectURL(info.blobUrl); } catch (e) { /* ignore */ }
            }
        }
    }

    /**
     * Stop any in-flight chat speech, clear the chunk queue and release all audio
     * resources. Safe to call at any time, including when no speech is active.
     * This is the entry point chat.js uses to interrupt TTS when the user sends a
     * new message (conversation takes priority over TTS).
     */
    function stopSpeech() {
        const s = AppState.speech;
        s.aborted = true;
        if (s.currentAudio) {
            try {
                s.currentAudio.onerror = null;
                s.currentAudio.onended = null;
                s.currentAudio.pause();
                s.currentAudio.src = '';
            } catch (e) { /* ignore */ }
            s.currentAudio = null;
        }
        revokeSpeechBlobs(s.blobs, 0);
        s.chunks = [];
        s.blobs = [];
        s.fetchIndex = 0;
        s.playIndex = 0;
        s.aborted = false;
        s.isSpeaking = false;
    }

    /**
     * Return true when a chat speech synthesis is currently active (speaking or
     * still queuing/fetching chunks).
     *
     * @returns {boolean}
     */
    function isSpeechActive() {
        return AppState.speech.isSpeaking === true;
    }

    /**
     * Play the speech chunk at AppState.speech.playIndex, assuming its blob URL
     * is already cached. When playback ends, advance to the next chunk (which may
     * already be fetched thanks to pipelining). On error, skip to the next chunk
     * so a single bad chunk never silences the rest of the response.
     */
    function playSpeechChunk() {
        const s = AppState.speech;
        const idx = s.playIndex;
        const info = s.blobs[idx];
        if (!info || typeof info.blobUrl !== 'string' || info.blobUrl.length === 0) {
            return; // not yet fetched — will be started once its fetch completes
        }

        const audio = new Audio(info.blobUrl);
        s.currentAudio = audio;

        const finishCurrent = () => {
            if (s.currentAudio === audio) {
                s.currentAudio = null;
            }
            try { URL.revokeObjectURL(info.blobUrl); } catch (e) { /* ignore */ }
            s.blobs[idx] = null;
            s.playIndex = idx + 1;
        };

        audio.onended = () => {
            finishCurrent();
            if (s.aborted) { s.isSpeaking = false; return; }
            if (s.playIndex < s.chunks.length) {
                const next = s.blobs[s.playIndex];
                if (next && typeof next.blobUrl === 'string') {
                    playSpeechChunk(); // next chunk already fetched
                }
                // else: next chunk will be played automatically once its fetch
                // completes (see fetchSpeechChunk pipeline below).
            } else {
                s.isSpeaking = false;
            }
        };

        audio.onerror = () => {
            if (s.currentAudio === audio) { s.currentAudio = null; }
            try { URL.revokeObjectURL(info.blobUrl); } catch (e) { /* ignore */ }
            s.blobs[idx] = null;
            s.playIndex = idx + 1;
            if (s.aborted) { s.isSpeaking = false; return; }
            if (s.playIndex < s.chunks.length) {
                const next = s.blobs[s.playIndex];
                if (next && typeof next.blobUrl === 'string') {
                    playSpeechChunk();
                }
            } else {
                s.isSpeaking = false;
            }
        };

        audio.play().catch((err) => {
            // Autoplay policy or similar: treat as an error and move on.
            if (s.currentAudio === audio) { s.currentAudio = null; }
            try { URL.revokeObjectURL(info.blobUrl); } catch (e) { /* ignore */ }
            s.blobs[idx] = null;
            s.playIndex = idx + 1;
            if (s.aborted) { s.isSpeaking = false; return; }
            if (s.playIndex < s.chunks.length) {
                const next = s.blobs[s.playIndex];
                if (next && typeof next.blobUrl === 'string') {
                    playSpeechChunk();
                }
            } else {
                s.isSpeaking = false;
            }
        });
    }

    /**
     * Pipeline: fetch the next chunk (at AppState.speech.fetchIndex) from the TTS
     * API, cache its blob URL, and (if it is the chunk due to play and nothing is
     * playing yet) start playback. Then recursively fetch the following chunk so
     * synthesis stays ahead of playback without waiting for audio to finish.
     *
     * Only one fetch is in flight at a time, keeping the browser happy while still
     * making long-text synthesis as seamless as possible.
     */
    function fetchNextSpeechChunk() {
        const s = AppState.speech;
        if (s.aborted || s.fetchIndex >= s.chunks.length) { return; }

        const idx = s.fetchIndex;
        s.fetchIndex += 1;

        fetchSpeechChunk(s.chunks[idx]).then((result) => {
            if (s.aborted) {
                // No blob URL was created yet, so there is nothing to revoke.
                return;
            }
            const blob = new Blob([result.buffer], { type: result.contentType || 'audio/mpeg' });
            const blobUrl = URL.createObjectURL(blob);
            s.blobs[idx] = { blobUrl: blobUrl, contentType: result.contentType || 'audio/mpeg' };

            // If this is the chunk due to play and nothing is playing, start it.
            if (idx === s.playIndex && !s.currentAudio && !s.aborted) {
                playSpeechChunk();
            }
            // Keep the pipeline full: request the next chunk immediately.
            fetchNextSpeechChunk();
        }).catch((err) => {
            // A single chunk failure must not abort the whole response: skip it.
            if (s.aborted) { return; }
            console.warn('[TTS] Chunk fetch failed, skipping:', (err && err.message) || err);
            fetchNextSpeechChunk();
        });
    }

    /**
     * Speak a chunked, pipelined rendering of `$text` through the TTS API.
     *
     * The text is split into chunks that each respect the max TTS token limit,
     * chunks are sent to the TTS API one at a time (pipelined ahead of playback),
     * and playback proceeds in strict order, one chunk after the previous one
     * finishes. Audio blobs are cached client-side in order until played.
     *
     * Safe to call repeatedly: any previous speech is stopped first (chat
     * interruption semantics).
     *
     * @param {string} text - The assistant reply text to synthesize and speak.
     * @returns {void}
     */
    function speakText(text) {
        stopSpeech(); // chat interruption: drop any previous speech immediately
        const s = AppState.speech;

        if (typeof text !== 'string' || text.trim().length === 0) {
            s.isSpeaking = false;
            return;
        }
        if (window.TTS_ENABLED !== true) {
            // TTS not explicitly enabled on this page: do not speak.
            // (undefined / false / any other value all mean "do not speak".)
            s.isSpeaking = false;
            return;
        }

        s.chunks = splitIntoChunks(text, AppState.maxTokens);
        s.blobs = s.chunks.map(() => null);
        s.fetchIndex = 0;
        s.playIndex = 0;
        s.aborted = false;
        s.isSpeaking = true;

        if (s.chunks.length === 0) {
            s.isSpeaking = false;
            return;
        }
        fetchNextSpeechChunk();
    }

    // =============================================================================
    // SECTION 8: EVENT HANDLERS
    // =============================================================================

    /** Attach all event listeners. */
    function initEvents() {
        if (DOM.input) {
            DOM.input.addEventListener('input', (e) => {
                updateCharCount();
                // Invalidate the cached audio whenever the textarea content
                // changes, so Play/Download regenerate from the TTS API.
                if (AppState.audioBlobUrl || AppState.cachedText !== null) {
                    AppState.cachedText = null;
                    revokeBlobUrl();
                    setStatus('Content changed. Generate audio again.', 'muted');
                    updatePlaybackButtons();
                }
            });
            // Enter (without Shift) -> play.
            DOM.input.addEventListener('keydown', (e) => {
                if (!e) { return; }
                if (e.key === 'Enter' && !e.shiftKey) {
                    e.preventDefault();
                    e.stopPropagation();
                    e.stopImmediatePropagation();
                    handlePlay();
                }
            });
        }
        if (DOM.playBtn) {
            DOM.playBtn.addEventListener('click', (e) => {
                e.preventDefault();
                e.stopPropagation();
                handlePlay();
            });
        }
        if (DOM.downloadBtn) {
            DOM.downloadBtn.addEventListener('click', (e) => {
                e.preventDefault();
                e.stopPropagation();
                handleDownload();
            });
        }
        if (DOM.stopBtn) {
            DOM.stopBtn.addEventListener('click', (e) => {
                e.preventDefault();
                e.stopPropagation();
                handleStop();
            });
        }
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
        // Release audio resources and revoke blob URLs when the page is navigated away.
        window.addEventListener('beforeunload', () => {
            stopAudio();
            revokeBlobUrl();
        });
    }

    // =============================================================================
    // SECTION 9: INITIALIZATION
    // =============================================================================

    /** Populate the DOM cache. */
    function initDOM() {
        DOM.input      = document.getElementById('tts-input');
        DOM.charCount  = document.getElementById('tts-char-count');
        DOM.maxCharsEl = document.getElementById('tts-max-chars');
        DOM.playBtn    = document.getElementById('tts-play-btn');
        DOM.downloadBtn= document.getElementById('tts-download-btn');
        DOM.stopBtn    = document.getElementById('tts-stop-btn');
        DOM.status     = document.getElementById('tts-status');
        DOM.body       = document.body;
    }

    /**
     * Read and validate all configuration globals, applying bounds and
     * falling back to defaults on any malformed value.
     */
    function initConfig() {
        AppState.apiEndpoint = getConfigValue(
            'TTS_API_ENDPOINT',
            DEFAULT_CONFIG.API_ENDPOINT,
            (v) => String(v)
        );
        AppState.maxChars = getConfigValue(
            'TTS_MAX_CHARS',
            DEFAULT_CONFIG.MAX_CHARS,
            (v) => {
                const n = parseIntSafe(v, DEFAULT_CONFIG.MAX_CHARS);
                return n > 0 ? n : DEFAULT_CONFIG.MAX_CHARS;
            }
        );
        AppState.maxTokens = getConfigValue(
            'TTS_MAX_TOKENS',
            DEFAULT_CONFIG.MAX_TOKENS,
            (v) => {
                const n = parseIntSafe(v, DEFAULT_CONFIG.MAX_TOKENS);
                return n > 0 ? n : DEFAULT_CONFIG.MAX_TOKENS;
            }
        );
        AppState.requestTimeout = getConfigValue(
            'TTS_REQUEST_TIMEOUT',
            DEFAULT_CONFIG.REQUEST_TIMEOUT,
            (v) => {
                const n = parseIntSafe(v, DEFAULT_CONFIG.REQUEST_TIMEOUT);
                return n > 0 ? n : DEFAULT_CONFIG.REQUEST_TIMEOUT;
            }
        );
        AppState.defaultTheme = getConfigValue(
            'DEFAULT_THEME',
            DEFAULT_CONFIG.DEFAULT_THEME,
            (v) => {
                if (typeof v !== 'string') { return DEFAULT_CONFIG.DEFAULT_THEME; }
                return v.toUpperCase().trim();
            }
        );
        // Reflect server max-chars in the textarea attribute (defense in depth;
        // the Twig template already sets maxlength from the same server value).
        if (DOM.input && DOM.maxCharsEl) {
            DOM.input.setAttribute('maxlength', String(AppState.maxChars));
            DOM.maxCharsEl.textContent = String(AppState.maxChars);
        }
    }

    /**
     * Application entry point.
     */
    function init() {
        try {
            initDOM();
            initConfig();
            // Theme initializes independently of TTS service state so light/dark mode always works, even when the TTS service is disabled.
            initTheme();
            bindThemeToggle();
            initEvents();
            if (!DOM.input || !DOM.playBtn) {
                console.error(
                    '[Init] Required TTS DOM elements not found. ' +
                    'TTS functionality disabled (service likely disabled).'
                );
                return;
            }
            updateCharCount();
            console.log('[Init] TTS client initialised successfully');
            console.log('[Init] maxChars:',    AppState.maxChars);
            console.log('[Init] maxTokens:',   AppState.maxTokens);
            console.log('[Init] requestTimeout:', AppState.requestTimeout);
            console.log('[Init] apiEndpoint:',   AppState.apiEndpoint);
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
    // PUBLIC API — exposed for chat.js (and any other consumer) to drive chat TTS
    // =============================================================================
    /**
     * Public TTS façade consumed by chat.js.
     *
     * @typedef {Object} TTSApi
     * @property {function(string):void} speak   - Synthesize + speak text (chunked & pipelined).
     * @property {function():void}     stop      - Interrupt speech and clear all queued audio.
     * @property {function():boolean}  isSpeaking - True while speech is active.
     */
    if (typeof window !== 'undefined') {
        window.TTS = {
            /**
             * Speak the given text through the TTS API (chat integration).
             * Stops any in-flight speech first.
             *
             * @param {string} text
             */
            speak: speakText,
            /** Stop all speech and release cached audio resources. */
            stop: stopSpeech,
            /** Return true while speech is active (speaking or fetching chunks). */
            isSpeaking: isSpeechActive
        };
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
