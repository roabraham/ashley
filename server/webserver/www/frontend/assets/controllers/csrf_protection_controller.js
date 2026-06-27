/**
 * CSRF Protection Controller for Symfony forms.
 *
 * Provides client-side CSRF token generation and management for Symfony's SameOriginCsrfTokenManager. Handles token generation, cookie management, and header injection for Turbo-driven form submissions.
 *
 * @module csrf_protection_controller
 */

/**
 * Regular expression for validating CSRF token names.
 * Format: 4-22 characters of letters, digits, hyphens, or underscores.
 *
 * @constant {RegExp}
 */
const nameCheck = /^[-_a-zA-Z0-9]{4,22}$/;

/**
 * Regular expression for validating CSRF token values.
 * Format: 24+ characters of URL-safe base64 characters.
 *
 * @constant {RegExp}
 */
const tokenCheck = /^[-_/+a-zA-Z0-9]{24,}$/;

/**
 * Generate and double-submit a CSRF token in a form field and a cookie, as defined by Symfony's SameOriginCsrfTokenManager.
 * Listens for form submit events and ensures CSRF tokens are properly injected into both form fields and cookies before submission.
 * @param {HTMLFormElement} event.target - The form element being submitted.
 */
document.addEventListener('submit', function (event) {
    generateCsrfToken(event.target);
}, true);

/**
 * When @hotwired/turbo handles form submissions, send the CSRF token in a header in addition to a cookie. The `framework.csrf_protection.check_header` config option needs to be enabled for the header to be checked.
 * @param {CustomEvent} event - Turbo submit-start event containing form details.
 */
document.addEventListener('turbo:submit-start', function (event) {
    const h = generateCsrfHeaders(event.detail.formSubmission.formElement);
    Object.keys(h).map(function (k) {
        event.detail.formSubmission.fetchRequest.headers[k] = h[k];
    });
});

/**
 * When @hotwired/turbo handles form submissions, remove the CSRF cookie once a form has been submitted to prevent token reuse.
 * @param {CustomEvent} event - Turbo submit-end event containing form details.
 */
document.addEventListener('turbo:submit-end', function (event) {
    removeCsrfToken(event.detail.formSubmission.formElement);
});

/**
 * Generate and set CSRF token values in a form element. Creates a cookie-based CSRF token when needed and sets both the form field value and cookie for double-submit validation.
 * @param {HTMLFormElement} formElement - The form containing the CSRF token field.
 * @returns {void} - no return value.
 */
export function generateCsrfToken (formElement) {
    const csrfField = formElement.querySelector('input[data-controller="csrf-protection"], input[name="_csrf_token"]');

    if (!csrfField) {
        return;
    }

    let csrfCookie = csrfField.getAttribute('data-csrf-protection-cookie-value');
    let csrfToken = csrfField.value;

    if (!csrfCookie && nameCheck.test(csrfToken)) {
        csrfField.setAttribute('data-csrf-protection-cookie-value', csrfCookie = csrfToken);
        csrfField.defaultValue = csrfToken = btoa(String.fromCharCode.apply(null, (window.crypto || window.msCrypto).getRandomValues(new Uint8Array(18))));
    }
    csrfField.dispatchEvent(new Event('change', { bubbles: true }));

    if (csrfCookie && tokenCheck.test(csrfToken)) {
        const cookie = csrfCookie + '_' + csrfToken + '=' + csrfCookie + '; path=/; samesite=strict';
        document.cookie = window.location.protocol === 'https:' ? '__Host-' + cookie + '; secure' : cookie;
    }
}

/**
 * Generate CSRF headers for AJAX/form requests.
 * Extracts CSRF token and cookie values to construct headers for double-submit cookie validation in Symfony's CSRF protection.
 * @param {HTMLFormElement} formElement - The form containing CSRF token fields.
 * @returns {Object.<string, string>} Headers object keyed by CSRF cookie name.
 */
export function generateCsrfHeaders (formElement) {
    const headers = {};
    const csrfField = formElement.querySelector('input[data-controller="csrf-protection"], input[name="_csrf_token"]');

    if (!csrfField) {
        return headers;
    }

    const csrfCookie = csrfField.getAttribute('data-csrf-protection-cookie-value');

    if (tokenCheck.test(csrfField.value) && nameCheck.test(csrfCookie)) {
        headers[csrfCookie] = csrfField.value;
    }

    return headers;
}

/**
 * Remove CSRF cookie after form submission.
 * Clears the CSRF cookie by setting its max-age to 0, preventing token reuse and maintaining security best practices.
 * @param {HTMLFormElement} formElement - The form containing CSRF token fields.
 * @returns {void} - no return value.
 */
export function removeCsrfToken (formElement) {
    const csrfField = formElement.querySelector('input[data-controller="csrf-protection"], input[name="_csrf_token"]');

    if (!csrfField) {
        return;
    }

    const csrfCookie = csrfField.getAttribute('data-csrf-protection-cookie-value');

    if (tokenCheck.test(csrfField.value) && nameCheck.test(csrfCookie)) {
        const cookie = csrfCookie + '_' + csrfField.value + '=0; path=/; samesite=strict; max-age=0';

        document.cookie = window.location.protocol === 'https:' ? '__Host-' + cookie + '; secure' : cookie;
    }
}

/* stimulusFetch: 'lazy' */
export default 'csrf-protection-controller';
