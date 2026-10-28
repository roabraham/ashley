<?php

namespace App\Controller;

use App\Service\ConfigService;
use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\HttpClient\HttpClient;
use Symfony\Component\HttpClient\Exception\TransportExceptionInterface;
use Symfony\Component\Routing\Attribute\Route;

/**
 * TTScontroller
 *
 * Standalone text-to-speech API controller.
 *
 * Relays TTS (text-to-speech) requests to the configured TTS server and returns the synthesized audio to the caller. Completely independent of the chat API: no LLM, no embedding, no chat sessions, no conversation history, no database access. The chat API remains able to call this endpoint later (e.g. for narrating assistant replies) because nothing here restricts its usage.
 *
 * The TTS service address and limits come exclusively from ConfigService (tts_host, proxy_port, tts_endpoint, tts_max_tokens, tts_enabled, ...). TTS fallback (if any) is resolved at configuration level, not here.
 *
 * ## Route map
 *
 * | Method | Path     | Action             |
 * |--------|----------|--------------------|
 * | GET    | /tts     | Render TTS UI page |
 * | POST   | /api/tts | Synthesize speech  |
 *
 * ## Request
 *
 * JSON body:
 *
 * ```json
 * {
 *   "input": "Hello there, I am Ashley, your local AI assistant. How can I help you today?"
 * }
 * ```
 *
 * ## Responses
 *
 * | Status | Content                  | Meaning                        |
 * |--------|--------------------------|--------------------------------|
 * | 200    | audio binary             | Synthesized speech (raw bytes) |
 * | 400    | application/json         | Validation / token-limit error |
 * | 502    | application/json         | TTS server unreachable / error |
 *
 * On success the raw response body of the TTS server is forwarded as-is, with its Content-Type header (falling back to `audio/mpeg`), so callers can play the audio directly without any base64 round-trip.
 */
class TTScontroller extends AbstractController
{
    /** Characters-per-token ratio used for the token estimate (UTF-8). Mirrors the heuristic used elsewhere in the app. */
    protected const CHARS_PER_TOKEN = 2.5;

    /** When true, oversized TTS inputs are truncated to tts_max_tokens instead of being rejected with a 400 error. Turn this on to send partial requests to the TTS server; turn it off to fail fast with a standard error response. */
    protected const process_partial_requests = true;

    /** Default request timeout in seconds */
    protected const DEFAULT_REQUEST_TIMEOUT = 60;

    /** @var ConfigService $configService Shared configuration provider */
    protected ConfigService $configService;

    /**
     * Constructor
     *
     * @param ConfigService $configService Shared configuration provider
     */
    public function __construct(ConfigService $configService) {
        $this->configService = $configService;
    }

    // =========================================================================
    // PAGE RENDERER
    // =========================================================================

    /**
     * Render the standalone TTS UI page.
     *
     * Completely independent of the chat API: no persona, no avatar, no system prompt, no conversation history. Just a simple text input for narrating short texts through the configured TTS service.
     *
     * @return Response Twig-rendered HTML page, or an elegant error page when the TTS service is disabled
     */
    #[Route('/tts', name: 'app_tts_index', methods: ['GET'])]
    public function index(): Response {
        $ttsConfig = $this->configService->getLlmConfig();
        $ttsEnabled = $ttsConfig['tts_enabled'] ?? false;
        $ttsMaxTokens = max(intval(trim($ttsConfig['tts_max_tokens'] ?? 64)), 1);
        // Characters-per-token ratio mirrors the server-side heuristic so the client-side max-length matches what the server accepts.
        $maxChars = max(intval(floor($ttsMaxTokens * self::CHARS_PER_TOKEN)), 1);
        if (!$ttsEnabled) {
            // Elegant error page: TTS disabled but user navigated here anyway.
            return $this->render('tts/index.html.twig', [
                'tts_enabled'  => false,
                'tts_max_tokens'=> $ttsMaxTokens,
                'tts_max_chars' => $maxChars,
                'error_message' => 'The text-to-speech service is currently disabled. Enable it in the wrapper configuration.'
            ]);
        }
        // Normal TTS UI
        return $this->render('tts/index.html.twig', [
            'tts_enabled'  => true,
            'tts_max_tokens'=> $ttsMaxTokens,
            'tts_max_chars' => $maxChars,
            'request_timeout'=> max(intval(trim($ttsConfig['request_timeout'] ?? self::DEFAULT_REQUEST_TIMEOUT)), 1)
        ]);
    }

    // =========================================================================
    // API ENTRY POINT
    // =========================================================================

    /**
     * Synthesize speech from text and return the audio produced by the TTS server.
     *
     * Canonical path: `/api/tts` (no trailing slash).
     *
     * Flow:
     * 1. Verify TTS service is enabled in configuration.
     * 2. Decode and validate the JSON request body (`input` field).
     * 3. Estimate the token count of the input and enforce `tts_max_tokens`.
     * 4. Forward the request to the configured TTS server.
     * 5. Return the TTS server's audio response as-is to the caller.
     *
     * @param Request $request Incoming Symfony request (expects JSON body)
     * @return Response Binary audio response on success, Json error on error
     */
    #[Route('/api/tts', name: 'app_tts_api', methods: ['POST'])]
    public function tts(Request $request): Response {
        $ttsConfig = $this->configService->getLlmConfig();
        // TTS must be enabled before anything else happens
        $ttsEnabled = $ttsConfig['tts_enabled'] ?? false;
        if (!$ttsEnabled) {
            return $this->json([
                'error'   => 'TTS_SERVICE_DISABLED',
                'message' => 'TTS service is disabled!'
            ], Response::HTTP_BAD_REQUEST);
        }
        // Decode the JSON request body
        $content = $request->getContent();
        $data = json_decode($content, true);
        if (!is_array($data)) {
            return $this->json([
                'error'   => 'INVALID_JSON',
                'message' => 'Request body must be a valid JSON object!'
            ], Response::HTTP_BAD_REQUEST);
        }
        // Validate the `input` field
        $rawInput = $data['input'] ?? '';
        if (!is_string($rawInput)) {
            return $this->json([
                'error'   => 'INVALID_INPUT',
                'message' => 'The "input" field must be a string!'
            ], Response::HTTP_BAD_REQUEST);
        }
        $input = trim($rawInput);
        if ($input === '') {
            return $this->json([
                'error'   => 'EMPTY_INPUT',
                'message' => 'The "input" field is required and must not be empty!'
            ], Response::HTTP_BAD_REQUEST);
        }
        // Token limit: estimate tokens and reject or truncate oversized requests
        $ttsMaxTokens = max(intval($ttsConfig['tts_max_tokens'] ?? 64), 1);
        $estimatedTokens = intval(ceil(mb_strlen($input, 'UTF-8') / self::CHARS_PER_TOKEN));
        if ($estimatedTokens > $ttsMaxTokens) {
            if (!self::process_partial_requests) {
                return $this->json([
                    'error'   => 'TTS_TOKEN_LIMIT_EXCEEDED',
                    'message' => 'Input exceeds the maximal TTS token count (' . $estimatedTokens . ' > ' . $ttsMaxTokens . ')!'
                ], Response::HTTP_BAD_REQUEST);
            }
            $input = $this->truncateToTokenLimit($input, $ttsMaxTokens);
        }
        // Build the TTS server URL from the configuration
        $ttsHost = trim($ttsConfig['tts_host'] ?? '127.0.0.1');
        if ($ttsHost == '') { $ttsHost = '127.0.0.1'; }
        $proxyPort = intval($ttsConfig['proxy_port'] ?? 5123);
        if ($proxyPort <= 0) { $proxyPort = 5123; }
        $ttsEndpoint = trim($ttsConfig['tts_endpoint'] ?? '/v1/audio/speech');
        if ($ttsEndpoint == '') { $ttsEndpoint = '/v1/audio/speech'; }
        if (!str_starts_with($ttsEndpoint, '/')) { $ttsEndpoint = '/' . $ttsEndpoint; }
        $url = sprintf('http://%s:%d%s', $ttsHost, $proxyPort, $ttsEndpoint);
        $requestTimeout = max(intval(trim($ttsConfig['request_timeout'] ?? self::DEFAULT_REQUEST_TIMEOUT)), 1);
        $client = HttpClient::create(['timeout' => $requestTimeout, 'max_duration' => $requestTimeout]);
        try {
            $response = $client->request('POST', $url, [
                'json' => ['input' => $input]
            ]);
            $statusCode = $response->getStatusCode();
            $body = $response->getContent();
            if (empty($body)) {
                return $this->json([
                    'error'   => 'TTS_EMPTY_RESPONSE',
                    'message' => 'The TTS server returned no audio!'
                ], Response::HTTP_BAD_GATEWAY);
            }
            // Forward the TTS server's Content-Type so the caller knows the audio format
            $contentType = $this->extractContentType($response->getHeaders());
            if ($contentType == '') { $contentType = 'audio/mpeg'; }
            return new Response($body, $statusCode, ['Content-Type' => $contentType]);
        } catch (TransportExceptionInterface $e) {
            // Network error, DNS failure, connection refused, timeout, etc.
            return $this->json([
                'error'   => 'TTS_SERVER_UNREACHABLE',
                'message' => 'Cannot reach the TTS server: ' . $e->getMessage()
            ], Response::HTTP_BAD_GATEWAY);
        } catch (\Throwable $e) {
            return $this->json([
                'error'   => 'TTS_SERVER_ERROR',
                'message' => 'TTS request failed: ' . $e->getMessage()
            ], Response::HTTP_BAD_GATEWAY);
        }
    }

    // =========================================================================
    // HELPERS
    // =========================================================================

    /**
     * Cut `$text` down so its estimated token count does not exceed `$maxTokens`.
     *
     * Uses the same `ceil(mb_strlen / 2.5)` heuristic as the rest of the app.
     *
     * @param string $text  Input text to truncate
     * @param int    $maxTokens Maximum allowed token count
     * @return string Truncated text (never empty when called with a non-empty input)
     */
    protected function truncateToTokenLimit(string $text, int $maxTokens): string {
        $maxChars = max(intval(floor($maxTokens * self::CHARS_PER_TOKEN)), 0);
        if ($maxChars <= 0 || mb_strlen($text, 'UTF-8') <= $maxChars) { return $text; }
        return trim(mb_substr($text, 0, $maxChars, 'UTF-8'));
    }

    /**
     * Extract the first value of a header from an array of response headers.
     *
     * Symfony HttpClient getHeaders() returns an associative array of header name => string|array|null. This helper is defensive against missing headers, array values, and unexpected casing.
     *
     * @param array<string,string|array<string>|null> $headers Response headers
     * @return string First header value, or empty string when the header is absent
     */
    protected function extractContentType(array $headers): string {
        if (empty($headers)) { return ''; }
        foreach ($headers as $key => $value) {
            $keyValidated = strtolower(trim($key ?? ''));
            if (empty($keyValidated)) { continue; }
            if ($keyValidated != 'content-type') { continue; }
            $valueFinal = $value;
            if (is_array($valueFinal)) { $valueFinal = ($valueFinal[0] ?? ''); }
            $valueFinal = trim((string) $valueFinal);
            if (empty($valueFinal)) { return ''; }
            return $valueFinal;
        }
        return '';
    }
}
