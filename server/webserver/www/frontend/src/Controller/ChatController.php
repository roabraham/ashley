<?php

namespace App\Controller;

use App\Service\ChatConfigService;
use Symfony\Bundle\FrameworkBundle\Controller\AbstractController;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\HttpFoundation\Session\SessionInterface;
use Symfony\Component\Routing\Attribute\Route;
use Symfony\Component\HttpClient\HttpClient;
use Symfony\Contracts\HttpClient\HttpClientInterface;

/**
 * ChatController
 *
 * Handles all chatbot HTTP traffic including conversation management, session control, LLM relay, and vector-based behavior matching.
 *
 * ## Route map
 *
 * | Method | Path       | Action               |
 * |--------|------------|----------------------|
 * | GET    | /          | Render chat page     |
 * | POST   | /api/chat  | Unified chat API     |
 *
 * ## API actions (`action` POST field or JSON body)
 *
 * | Action                    | Response mode | Description                  |
 * |---------------------------|---------------|------------------------------|
 * | *(empty / send_message)*  | 1             | Send message to the LLM      |
 * | summarize                 | -             | Summarize conversation       |
 * | clear_session             | 1             | Clear server-side history    |
 * | get_conversation_history  | 1             | Fetch server-side history    |
 * | export_conversation       | 1             | Download history as JSON     |
 * | import_conversation       | 1             | Upload history from JSON     */
class ChatController extends AbstractController
{
    /** Context size */
    protected const DEFAULT_LLM_CTX_SIZE = 8192;

    /** Token safety margin */
    protected const DEFAULT_TOKEN_SAFETY_MARGIN = 256;

    /** Summary token number */
    protected const DEFAULT_MAX_SUMMARY_TOKENS = 256;

    /** Summary temperature */
    protected const DEFAULT_SUMMARY_TEMPERATURE = 0.3;

    /** Request timeout in seconds */
    protected const DEFAULT_REQUEST_TIMEOUT = 60;

    /** Valid chat roles */
    protected const VALID_ROLES = ['user', 'assistant', 'system'];

    /** @var ChatConfigService $configService: shared configuration provider */
    protected ChatConfigService $configService;

    /**
     * Constructor
     * @param ChatConfigService $configService Shared configuration provider
     */
    public function __construct(ChatConfigService $configService) {
        $this->configService = $configService;
    }

    // =========================================================================
    // PAGE RENDERER
    // =========================================================================

    /**
     * Render the chat UI page.
     *
     * @param SessionInterface $session Symfony session facade
     * @return Response Twig-rendered HTML page
     */
    #[Route('/', name: 'app_chat_index', methods: ['GET'])]
    public function index(SessionInterface $session): Response {
        $llmConfig = $this->configService->getLlmConfig();
        $persona   = $this->configService->getPersonaConfig();
        $responseMode = intval($persona['response_mode'] ?? 1);
        // Pre-calculate values that the template and JS need
        $llmCtxSize = intval($llmConfig['llm_ctx_size'] ?? self::DEFAULT_LLM_CTX_SIZE);
        $llmMaxResponseTokens = intval(floor($llmCtxSize * 0.25));
        $safetyMargin = intval($llmConfig['token_safety_margin'] ?? self::DEFAULT_TOKEN_SAFETY_MARGIN);
        $warningThreshold = max($llmCtxSize - ($llmMaxResponseTokens + $safetyMargin), 0);
        $hasSessionConversation = false;
        if ($responseMode == 1) {
            $history = $session->get('conversation_history', []);
            if (!empty($history)) {
                if (is_array($history)) { $hasSessionConversation = true; }
            }
        }
        $activePrompt = trim($persona['active_prompt']  ?? '');
        if (!empty($activePrompt)) {
            $string_replacements = $this->getStringReplacements($persona);
            if (!empty($string_replacements)) {
                foreach($string_replacements as $variable => $replacement) {
                    $activePrompt = trim(str_replace($variable, $replacement, $activePrompt));
                }
                $persona['active_prompt'] = $activePrompt;
            }
        }
        $requestTimeout = intval($llmConfig['request_timeout'] ?? self::DEFAULT_REQUEST_TIMEOUT);
        return $this->render('chat/index.html.twig', [
            'persona'                  => $persona,
            'llm_config'               => $llmConfig,
            'has_session_conversation' => $hasSessionConversation,
            'llm_ctx_size'             => $llmCtxSize,
            'llm_max_response_tokens'  => $llmMaxResponseTokens,
            'safety_margin'            => $safetyMargin,
            'warning_threshold'        => $warningThreshold,
            'request_timeout'          => $requestTimeout
        ]);
    }

    // =========================================================================
    // UNIFIED API ENTRY POINT
    // =========================================================================

    /**
     * Unified POST handler for all chat API actions.
     *
     * Canonical path: `/api/chat` (no trailing slash).
     *
     * @param Request        $request    Incoming Symfony request
     * @param SessionInterface $session  Symfony session
     * @return Response                  Action-specific response - either a
     *         JsonResponse for most actions or a file-download Response for
     *         the `export_conversation` action.
     */
    #[Route('/api/chat', name: 'app_chat_api', methods: ['POST'])]
    public function handleApi(Request $request, SessionInterface $session): Response {
        $llmConfig = $this->configService->getLlmConfig();
        $persona = $this->configService->getPersonaConfig();
        // Set limits
        $memory_limit = trim($llmConfig['memory_limit'] ?? '1G');
        @ini_set('memory_limit', $memory_limit);
        $requestTimeout = max(intval($llmConfig['request_timeout'] ?? self::DEFAULT_REQUEST_TIMEOUT), 60);
        set_time_limit($requestTimeout);
        //@ini_set('max_execution_time', $requestTimeout);
        // Accept action as JSON body field (preferred) or plain POST field.
        // For multipart/form-data (import) the body cannot be JSON-decoded, so
        // fall back to Symfony's parsed-POST parameters collection.
        $content  = $request->getContent();
        $data     = json_decode($content, true) ?? $request->request->all();
        $action   = strtolower(trim($data['action'] ?? ''));
        switch($action) {
            case 'clear_session': return $this->clearSession($session, $llmConfig, $persona);
            case 'get_conversation_history': return $this->getConversationHistory($session, $llmConfig, $persona);
            case 'export_conversation': return $this->exportConversation($session, $persona);
            case 'import_conversation': return $this->importConversation($request, $session, $persona);
            case 'summarize': return $this->summarizeHistory($data, $llmConfig, $persona);
            case 'send_message':
            case '': return $this->sendMessage($data, $request, $session, $llmConfig, $persona);
        }
        return $this->json(['error' => 'INVALID_ACTION'], Response::HTTP_BAD_REQUEST);
    }

    // =========================================================================
    // SESSION & HISTORY MANAGEMENT
    // =========================================================================

    /**
     * Return the full server-side conversation history as JSON.
     *
     * Only available in response mode 1 (session-based history).
     *
     * @param SessionInterface $session   Symfony session
     * @param array            $llmConfig LLM configuration from {@see ChatConfigService}
     * @param array            $persona   Persona configuration from {@see ChatConfigService}
     * @return JsonResponse
     */
    protected function getConversationHistory(SessionInterface $session, array $llmConfig, array $persona): JsonResponse {
        $responseMode = intval($persona['response_mode'] ?? 1);
        if ($responseMode != 1) {
            return $this->json([
                'error'   => 'INVALID_MODE',
                'message' => 'Get conversation history via API is only available in session-based response mode!'
            ], Response::HTTP_BAD_REQUEST);
        }
        $history = [];
        $stored  = $session->get('conversation_history', []);
        if (!empty($stored)) {
            if (is_array($stored)) {
                foreach ($stored as $msg) {
                    if (empty($msg['role'])) { continue; }
                    if (!isset($msg['content'])) { continue; }
                    $history[] = [
                        'role' => $msg['role'],
                        'content' => $msg['content']
                    ];
                }
            }
        }
        return $this->json(['success' => true, 'conversation_history' => $history]);
    }

    /**
     * Clear the server-side conversation history from the session.
     *
     * Only available in response mode 1.
     *
     * @param SessionInterface $session   Symfony session
     * @param array            $llmConfig LLM configuration from {@see ChatConfigService}
     * @param array            $persona   Persona configuration from {@see ChatConfigService}
     * @return JsonResponse
     */
    protected function clearSession(SessionInterface $session, array $llmConfig, array $persona): JsonResponse {
        $responseMode = intval($persona['response_mode'] ?? 1);
        if ($responseMode != 1) {
            return $this->json([
                'error'   => 'INVALID_MODE',
                'message' => 'Clear session via API is only available in session-based response mode!'
            ], Response::HTTP_BAD_REQUEST);
        }
        $history = $session->get('conversation_history', []);
        if (!empty($history)) {
            $session->remove('conversation_history');
            return $this->json(['success' => true, 'cleared' => true]);
        }
        // NO_DATA_TO_CLEAR is a 200 response so do not throw error
        // the JS client's `!res.ok` guard does not throw before JSON is decoded.
        return $this->json([
            'error'   => 'NO_DATA_TO_CLEAR',
            'message' => 'No data to clear!'
        ]);
    }

    /**
     * Export conversation history as a downloadable JSON file.
     *
     * Only available in response mode 1.
     *
     * @param SessionInterface $session   Symfony session
     * @param array            $persona   Persona configuration from {@see ChatConfigService}
     * @return Response                   File download response
     */
    protected function exportConversation(SessionInterface $session, array $persona): Response {
        $responseMode = intval($persona['response_mode'] ?? 1);
        if ($responseMode != 1) {
            return $this->json([
                'error'   => 'INVALID_MODE',
                'message' => 'Export via API is only available in response mode 1'
            ], Response::HTTP_BAD_REQUEST);
        }
        $history    = $session->get('conversation_history', []);
        if (empty($history)) {
            return $this->json([
                'error'   => 'NO_EXPORT_DATA',
                'message' => 'There is no data to export!'
            ]);
        }
        $exportData = [];
        foreach ($history as $msg) {
            if (empty($msg['role'])) { continue; }
            if (!isset($msg['content'])) { continue; }
            $exportData[] = [
                'role' => $msg['role'],
                'content' => $msg['content']
            ];
        }
        if (empty($exportData)) {
            return $this->json([
                'error'   => 'NO_EXPORT_DATA',
                'message' => 'There is no data to export!'
            ]);
        }
        $jsonOutput = json_encode($exportData, JSON_UNESCAPED_UNICODE);
        $filename   = 'conversation_' . date('Y-m-d_His') . '.json';
        $response = new Response($jsonOutput);
        $response->headers->set('Content-Type',        'application/json');
        $response->headers->set('Content-Disposition', "attachment; filename=\"{$filename}\"");
        return $response;
    }

    /**
     * Import a conversation history from an uploaded JSON file.
     *
     * Accepts multipart/form-data with a `conversation_file` field.
     * Returns a 200 response with the error embedded in the JSON body for every expected error condition.
     *
     * @param Request        $request    Incoming Symfony request (expects multipart)
     * @param SessionInterface $session  Symfony session
     * @param array          $persona    Persona configuration from {@see ChatConfigService}
     * @return JsonResponse
     */
    protected function importConversation(Request $request, SessionInterface $session, array $persona): JsonResponse {
        $responseMode = intval($persona['response_mode'] ?? 1);
        if ($responseMode != 1) {
            return $this->json([
                'error'   => 'INVALID_MODE',
                'message' => 'Import via API is only available in response mode 1'
            ]);
        }
        // Guard: the multipart field must be present in $_FILES
        if (!isset($_FILES['conversation_file'])) {
            return $this->json([
                'error'   => 'NO_FILE',
                'message' => 'No file uploaded or upload error!'
            ]);
        }
        $fileInfo = $_FILES['conversation_file'];
        // Guard: upload must have completed without error
        if (!isset($fileInfo['error']) || $fileInfo['error'] !== \UPLOAD_ERR_OK) {
            return $this->json([
                'error'   => 'NO_FILE',
                'message' => 'No file uploaded or upload error!'
            ]);
        }
        // Guard: temp file must physically exist
        $tmpFile = trim($fileInfo['tmp_name'] ?? '');
        if ($tmpFile == '') {
            return $this->json([
                'error'   => 'TEMP_FILE_NOT_FOUND',
                'message' => 'Temporary file not found!'
            ]);
        }
        if (!file_exists($tmpFile)) {
            return $this->json([
                'error'   => 'FILE_NOT_EXISTS',
                'message' => 'The file does not exist!'
            ]);
        }
        // Guard: temp file must be readable
        if (!is_readable($tmpFile)) {
            return $this->json([
                'error'   => 'FILE_READ_ERROR',
                'message' => 'Cannot read uploaded file!'
            ]);
        }
        $content = file_get_contents($tmpFile);
        if ($content === false) {
            return $this->json([
                'error'   => 'FILE_READ_ERROR',
                'message' => 'Cannot read uploaded file!'
            ]);
        }
        $importData = json_decode($content, true);
        if (empty($importData)) {
            return $this->json([
                'error'   => 'INVALID_JSON',
                'message' => 'Uploaded file does not contain valid JSON array!'
            ]);
        }
        if (!is_array($importData)) {
            return $this->json([
                'error'   => 'INVALID_JSON',
                'message' => 'Uploaded file does not contain valid JSON array!'
            ]);
        }
        $newHistory = [];
        foreach ($importData as $msg) {
            $role = trim((string) ($msg['role'] ?? ''));
            if (empty($role)) { continue; }
            if (!in_array($role, self::VALID_ROLES)) { continue; }
            if (!isset($msg['content'])) { continue; }
            $content = trim((string) $msg['content']);
            $newHistory[] = [
                'role'    => $role,
                'content' => $content
            ];
        }
        if (empty($newHistory)) {
            return $this->json([
                'error'   => 'NO_DATA',
                'message' => 'No data to import! The file contains no valid messages.'
            ]);
        }
        $session->set('conversation_history', $newHistory);
        return $this->json([
            'success'             => true,
            'conversation_history'=> $newHistory
        ]);
    }

    // =========================================================================
    // SUMMARIZATION
    // =========================================================================

    /**
     * Handle the `summarize` API action.
     *
     * Compresses conversation history via the LLM when the combined token count of history plus the pending message exceeds the context limit.
     *
     * @param array $data       Decoded request body
     * @param array $llmConfig  LLM configuration from {@see ChatConfigService}
     * @param array $persona    Persona configuration from {@see ChatConfigService}
     * @return JsonResponse
     */
    protected function summarizeHistory(array $data, array $llmConfig, array $persona): JsonResponse {
        try {
            $history = $data['conversation_history'] ?? [];
            if (empty($history)) { $history = []; }
            if (!is_array($history)) { $history = []; }
            $tokenCount = $this->estimateTokenCount($history);
            if (isset($data['pending_message'])) {
                if (is_string($data['pending_message'])) {
                    $pendingMsg = trim($data['pending_message']);
                    if ($pendingMsg != '') {
                        $tokenCount += intval(ceil(mb_strlen($pendingMsg, 'UTF-8') / 2.5));
                    }
                }
            }
            $active_prompt = trim($persona['active_prompt'] ?? '');
            if (!empty($active_prompt)) {
                $string_replacements = $this->getStringReplacements($persona);
                if (!empty($string_replacements)) {
                    foreach($string_replacements as $variable => $replacement) {
                        $active_prompt = trim(str_replace($variable, $replacement, $active_prompt));
                    }
                }
                if (!empty($active_prompt)) { $tokenCount += intval(ceil(mb_strlen($active_prompt, 'UTF-8') / 2.5)); }
            }
            $llmCtxSize = intval($llmConfig['llm_ctx_size'] ?? self::DEFAULT_LLM_CTX_SIZE);
            $safetyMargin = intval($llmConfig['token_safety_margin'] ?? self::DEFAULT_TOKEN_SAFETY_MARGIN);
            $maxRespTokens = intval(floor($llmCtxSize * 0.25));
            $warningThreshold = max($llmCtxSize - ($maxRespTokens + $safetyMargin), 0);
            if ($tokenCount <= $warningThreshold) {
                return $this->json(['success' => false, 'error' => 'NOT_NEEDED']);
            }
            $summarized = $this->doSummarize($history, $llmConfig, $persona);
            return $this->json(['success' => true, 'summarized_history' => $summarized]);
        } catch (\Exception $e) {
            return $this->json(['success' => false, 'error' => 'SERVER_ERROR: ' . $e->getMessage()]);
        }
    }

    /**
     * Estimate the total token count of an array of chat messages.
     *
     * @param array<string,array<string,mixed>> $messages Array of `{role, content}` messages
     * @return int Token count using the same `ceil(mb_strlen / 2.5)` heuristic.
     */
    protected function estimateTokenCount(array $messages): int {
        $total = 0;
        foreach ($messages as $msg) {
            if (!isset($msg['content'])) { continue; }
            $text = trim((string) $msg['content']);
            if ($text == '') { continue; }
            $total += intval(ceil(mb_strlen($text, 'UTF-8') / 2.5));
        }
        return $total;
    }

    /**
     * Prune conversation history by removing the oldest items until the total token count (history plus the incoming user message plus the system prompt) is within the configured warning threshold. Used in memory mode 1 where server-side summarisation is disabled.
     *
     * @param array<string,array<string,mixed>>  $history            Conversation history array
     * @param int                                $inputTokens        Estimated token count of the incoming user message
     * @param int                                $systemPromptTokens Estimated token count of the active system prompt
     * @param int                                $warningThreshold   Maximum allowed token count
     * @return array<string,array<string,mixed>> Pruned history array
     */
    protected function pruneHistoryByTokenCount(array $history, int $inputTokens, int $systemPromptTokens, int $warningThreshold): array {
        $total = $this->estimateTokenCount($history) + $inputTokens + $systemPromptTokens;
        while ($total > $warningThreshold && !empty($history)) {
            array_shift($history);
            $total = $this->estimateTokenCount($history) + $inputTokens + $systemPromptTokens;
        }
        return $history;
    }

    /**
     * Compress conversation history by asking the LLM for a short summary.
     *
     * Sends the most-recent messages (backwards from newest) to the LLM asking for a 2-3 sentence summary. Returns a single system-message array that the caller can use as replacement history.
     *
     * @param array<string,mixed> $history    Conversation history array
     * @param array<string,mixed> $llmConfig  LLM configuration from {@see ChatConfigService}
     * @param array<string,mixed> $persona    Persona configuration from {@see ChatConfigService}
     * @return array<string,array<string,mixed>> Single-message array or default summary
     */
    protected function doSummarize(array $history, array $llmConfig, array $persona): array {
        $llmCtxSize = intval($llmConfig['llm_ctx_size'] ?? self::DEFAULT_LLM_CTX_SIZE);
        $summaryPrompt = trim($persona['summary_prompt'] ?? '');
        $activePrompt = trim($persona['active_prompt']  ?? '');
        $summaryPromptText = 'Briefly summarize this conversation in 2-3 sentences, capturing the key topics and user requests. Be concise';
        $summaryPrefixText = 'Previous conversation summary';
        if (!empty($summaryPrompt)) {
            $configParts = explode(';', $summaryPrompt);
            foreach ($configParts as $part) {
                $part = trim($part);
                if ($part == '') { continue; }
                $pair = explode('=', $part, 2);
                if (count($pair) != 2) { continue; }
                $key = strtoupper(trim($pair[0]));
                $value = trim($pair[1]);
                if ($value == '') { continue; }
                switch($key) {
                    case 'SUMMARY_PROMPT': $summaryPromptText = $value; break;
                    case 'SUMMARY_PREFIX': $summaryPrefixText = $value; break;
                    case 'ACTIVE_PROMPT': $activePrompt = $value; break;
                }
            }
        }
        if (!empty($activePrompt)) {
            $string_replacements = $this->getStringReplacements($persona);
            if (!empty($string_replacements)) {
                foreach($string_replacements as $variable => $replacement) {
                    $activePrompt = trim(str_replace($variable, $replacement, $activePrompt));
                }
            }
        }
        // ── Build the conversation text to summarise ───────────────────────
        // Include the ": \n\n" suffix in header length
        // Also include the configured safety margin so the compression
        // window calculation mirrors the summarize threshold budgeting.
        $headerLength = intval(ceil(mb_strlen("{$summaryPromptText}:\n\n", 'UTF-8') / 2.5));
        if (!empty($activePrompt)) {
            $headerLength += intval(ceil(mb_strlen($activePrompt, 'UTF-8') / 2.5));
        }
        $currentTokens = $headerLength + intval($llmConfig['token_safety_margin'] ?? self::DEFAULT_TOKEN_SAFETY_MARGIN);
        $conversationText = '';
        $history_length = count($history);
        if ($history_length >= 1) {
            for ($i = $history_length - 1; $i >= 0; --$i) {
                $msg = $history[$i] ?? null;
                if (empty($msg)) { continue; }
                if (!is_array($msg)) { continue; }
                $role = trim((string) ($msg['role'] ?? ''));
                if (empty($role)) { continue; }
                if (!in_array($role, self::VALID_ROLES)) { continue; }
                $content = trim((string) ($msg['content'] ?? ''));
                if ($content == '') { continue; }
                $msgToAdd  = "{$role}: {$content}\n";
                $msgTokens = intval(ceil(mb_strlen($msgToAdd, 'UTF-8') / 2.5));
                if ($currentTokens + $msgTokens >= $llmCtxSize) { break; }
                $conversationText = "{$msgToAdd}{$conversationText}";
                $currentTokens += $msgTokens;
            }
        }
        if ($conversationText == '') {
            return [['role' => 'system', 'content' =>
                "{$summaryPrefixText}: [Previous conversation summary - key topics and user requests discussed]"
            ]];
        }
        $messages = [];
        if (!empty($activePrompt)) { $messages[] = ['role' => 'system', 'content' => $activePrompt]; }
        $messages[] = ['role' => 'user', 'content' => "{$summaryPromptText}:\n\n{$conversationText}"];
        // Call the LLM
        // Use proxy_url for summarization to route through nginx
        $llmHost = trim($llmConfig['llm_host'] ?? '127.0.0.1');
        $proxyPort = intval($llmConfig['proxy_port'] ?? 5123);
        $llmEndpoint = trim($llmConfig['llm_endpoint'] ?? '/v1/chat/completions');
        $llmUrl = sprintf('http://%s:%d%s', $llmHost, $proxyPort, $llmEndpoint);
        $maxSummaryTokens = min(
            self::DEFAULT_MAX_SUMMARY_TOKENS,
            intval(floor(floatval($llmConfig['llm_ctx_size'] ?? self::DEFAULT_LLM_CTX_SIZE) * 0.25))
        );
        $requestTimeout = max(intval($llmConfig['request_timeout'] ?? self::DEFAULT_REQUEST_TIMEOUT), 60);
        $client = HttpClient::create(['timeout' => $requestTimeout]);
        try {
            $response = $client->request('POST', $llmUrl, [
                'json' => [
                    'messages'    => $messages,
                    'stream'      => false,
                    'max_tokens'  => $maxSummaryTokens,
                    'temperature' => self::DEFAULT_SUMMARY_TEMPERATURE
                ]
            ]);
            if ($response->getStatusCode() === 200) {
                $decoded = $response->toArray();
                $summary = trim(($decoded['choices'][0]['message']['content'] ?? $decoded['content']) ?? '');
            }
        } catch (\Exception) { $summary = ''; }
        if ($summary == '') { $summary = '[Previous conversation summary - key topics and user requests discussed]'; }
        return [['role' => 'system', 'content' => "{$summaryPrefixText}: {$summary}"]];
    }

    // =========================================================================
    // MESSAGE SENDING
    // =========================================================================

    /**
     * Process an incoming chat message and return a reply.
     *
     * Flow:
     * 1. Session-blocking debounce check (re-entrant calls for the same session).
     * 2. Pre-flight services check (LLM + embedding must not both be disabled).
     * 3. Embedding behavior matching - short-circuit on DB match.
     * 4. Streaming-mode redirect (JS goes direct to llama.cpp via nginx location).
     * 5. Conversation history walk / summarization if token budget is exceeded.
     * 6. LLM proxy request with the configured host/port/endpoint.
     *
     * Session-blocking semantics:
     * `block_request` and `block_request_time` are written **only** immediately
     * before the LLM HTTP call and cleared on every exit path.
     *
     * @param array             $data        Decoded request body
     * @param Request           $request     Incoming Symfony request
     * @param SessionInterface  $session     Symfony session
     * @param array             $llmConfig   LLM configuration from {@see ChatConfigService}
     * @param array             $persona     Persona configuration from {@see ChatConfigService}
     * @return JsonResponse
     */
    protected function sendMessage(array $data, Request $request, SessionInterface $session, array $llmConfig, array $persona): JsonResponse {
        $llmEnabled = $llmConfig['llm_enabled'] ?? true;
        $embeddingEnabled = $llmConfig['embedding_enabled'] ?? true;
        $requestTimeout = max(intval($llmConfig['request_timeout'] ?? self::DEFAULT_REQUEST_TIMEOUT), 60);
        $responseMode = intval($persona['response_mode'] ?? 1);
        // Both services disabled
        if (!$llmEnabled && !$embeddingEnabled) {
            return $this->json([
                'error'   => 'NO_SERVICES_AVAILABLE',
                'message' => 'Both LLM and embedding services are disabled. Please enable at least one service.'
            ], Response::HTTP_SERVICE_UNAVAILABLE);
        }
        // Empty message guard
        $userMessage = trim((string) ($data['message'] ?? ''));
        if ($userMessage == '') {
            return $this->json(['reply' => 'Please type a message!']);
        }
        // Session-blocking / debounce check
        $blockTime = intval($session->get('block_request_time', 0));
        if ($session->get('block_request', false) && $blockTime > 0) {
            if ((time() - $blockTime) < $requestTimeout) {
                $botName  = trim($persona['chatbot_name'] ?? 'ChatBot');
                return $this->json(['reply' => "{$botName} is thinking!"]);
            }
        }
        // Embedding behavior matching (pre-LLM, short-circuits on hit)
        if (intval($persona['personality_id'] ?? 0) > 0 && $embeddingEnabled) {
            $behaviorResult = $this->tryBehaviorMatching($userMessage, $session, $llmConfig, $persona);
            if (!empty($behaviorResult)) { return $this->json($behaviorResult); }
        }
        // Streaming mode (response mode 2)
        if ($responseMode == 2) {
            if (!$llmEnabled) {
                return $this->json([
                    'reply' => "I'm sorry, I don't understand. Can you, please, be more specific?"
                ]);
            }
            return $this->json([
                'response_mode' => 2,
                'error'         => 'LLM_PROXY_NOT_AVAILABLE_IN_STREAMING_MODE',
                'message'       => 'LLM service proxy is not available in streaming mode. Please use direct llama.cpp connection.'
            ]);
        }
        // LLM disabled fallback
        if (!$llmEnabled) {
            return $this->json([
                'reply' => "I'm sorry, I don't understand. Can you, please, be more specific?"
            ]);
        }
        // Load conversation history
        $history = $session->get('conversation_history', []);
        if (empty($history)) { $history = []; }
        if (!is_array($history)) { $history = []; }
        // Build LLM message payload
        $messages = [];
        $active_prompt = trim($persona['active_prompt'] ?? '');
        if (!empty($active_prompt)) {
            $string_replacements = $this->getStringReplacements($persona);
            if (!empty($string_replacements)) {
                foreach($string_replacements as $variable => $replacement) {
                    $active_prompt = trim(str_replace($variable, $replacement, $active_prompt));
                }
            }
            $messages[] = ['role' => 'system', 'content' => $active_prompt];
        }
        $llmCtxSize = intval($llmConfig['llm_ctx_size'] ?? self::DEFAULT_LLM_CTX_SIZE);
        $safetyMargin = intval($llmConfig['token_safety_margin'] ?? self::DEFAULT_TOKEN_SAFETY_MARGIN);
        $llmMaxRespTokens = intval(floor($llmCtxSize * 0.25));
        $warningThreshold = max($llmCtxSize - ($llmMaxRespTokens + $safetyMargin), 0);
        // History compression check
        $historyTokens = $this->estimateTokenCount($history);
        $inputTokens = intval(ceil(mb_strlen($userMessage, 'UTF-8') / 2.5));
        $systemPromptTokens = empty($active_prompt) ? 0 : intval(ceil(mb_strlen($active_prompt, 'UTF-8') / 2.5));
        if (($historyTokens + $inputTokens + $systemPromptTokens) > $warningThreshold && !empty($history)) {
            $memoryMode = intval($persona['memory_mode'] ?? 1);
            if ($memoryMode === 1) {
                $history = $this->pruneHistoryByTokenCount($history, $inputTokens, $systemPromptTokens, $warningThreshold);
            } else {
                $summarized = $this->doSummarize($history, $llmConfig, $persona);
                if (!empty($summarized)) { $history = $summarized; }
            }
        }
        $messages = array_merge($messages, $history);
        $messages[] = ['role' => 'user', 'content' => $userMessage];
        // Write session block
        $session->set('block_request', 1);
        $session->set('block_request_time', time());
        // Request the LLM via the configured proxy
        $llmHost = trim($llmConfig['llm_host'] ?? '127.0.0.1');
        $proxyPort = intval($llmConfig['proxy_port'] ?? 5123);
        $llmEp = trim($llmConfig['llm_endpoint'] ?? '/v1/chat/completions');
        $url = sprintf('http://%s:%d%s', $llmHost, $proxyPort, $llmEp);
        // Release session lock so concurrent polls can run
        // IMPORTANT:
        // We MUST persist the current Symfony session state before releasing
        // the lock, otherwise conversation_history and other attributes are lost.
        // Persist session BEFORE long blocking HTTP request.
        // This releases the session lock safely via Symfony.
        $session->save();
        try {
            $client = HttpClient::create(['timeout' => $requestTimeout]);
            $response = $client->request('POST', $url, [
                'json' => [
                    'messages'   => $messages,
                    'stream'     => false,
                    'max_tokens' => $llmMaxRespTokens
                ]
            ]);
            $session->start();
            $this->clearBlock($session);
            if ($response->getStatusCode() === 200) {
                $result = $response->toArray();
                $reply = trim(($result['choices'][0]['message']['content'] ?? $result['content']) ?? '[Empty response]');
                $history[] = ['role' => 'user', 'content' => $userMessage];
                $history[] = ['role' => 'assistant', 'content' => $reply];
                $session->set('conversation_history', $history);
                $session->save();
                return $this->json(['reply' => $reply, 'response_mode' => 1]);
            }
            // Non-200 from the LLM
            $session->start();
            $this->clearBlock($session);
            $session->save();
            return $this->json(['reply' => 'No response received from LLM within time limit.'], Response::HTTP_INTERNAL_SERVER_ERROR);
        } catch (\Throwable $e) {
            // Hard error path
            // session_abort() discarded the in-memory session and the block
            // flags were never committed to disk.  Restart fresh so the user
            // can immediately retry - clearBlock + save ensures the clean state
            // is visible on the next request and kernel.terminate's later save
            // overwrites disk with the clean (unblocked) state.
            $session->start();
            $this->clearBlock($session);
            $session->save();
            return $this->json(['reply' => "Sorry, LLM seems unresponsive\n(timeout or network error: {$e->getMessage()})"], Response::HTTP_GATEWAY_TIMEOUT);
        }
    }

    // =========================================================================
    // BEHAVIOR MATCHING
    // =========================================================================

    /**
     * Attempt to match the user message against known personality behaviors using cosine similarity on pre-computed embedding vectors.
     *
     * Returns `null` if matching is not applicable, the DB does not exist, or no match exceeds the configured similarity threshold.
     *
     * @param string $userMessage   The incoming user message text
     * @param SessionInterface $session Symfony session
     * @param array<string,mixed> $llmConfig LLM configuration from {@see ChatConfigService}
     * @param array<string,mixed> $persona Persona configuration from {@see ChatConfigService}
     * @return array<string,mixed>|null The best match response or null
     */
    protected function tryBehaviorMatching(string $userMessage, SessionInterface $session, array $llmConfig, array $persona): ?array {
        $personalityDbPath = $this->configService->getPersonalityDbPath();
        if (!file_exists($personalityDbPath)) { return null; }
        try {
            $db = new \PDO("sqlite:{$personalityDbPath}");
            $db->setAttribute(\PDO::ATTR_ERRMODE, \PDO::ERRMODE_EXCEPTION);
            $db->exec("PRAGMA journal_mode = WAL;");
            // Embedding
            //$embeddingHost = $llmConfig['embedding_host'] ?? '127.0.0.1';
            $embeddingHost = '127.0.0.1';
            $embeddingPort = intval($llmConfig['proxy_port'] ?? 5123);
            $embeddingEndpoint = trim($llmConfig['embedding_endpoint'] ?? '/v1/embeddings');
            $embeddingUrl = sprintf(
                'http://%s:%d%s',
                $embeddingHost,
                $embeddingPort,
                $embeddingEndpoint
            );
            $client = HttpClient::create(['timeout' => 60]);
            $response = $client->request('POST', $embeddingUrl, ['json' => ['input' => $userMessage]]);
            if ($response->getStatusCode() !== 200) { return null; }
            $decoded = $response->toArray();
            $userVector = ($decoded['data'][0]['embedding'] ?? $decoded['embedding']) ?? null;
            if (!is_array($userVector)) { return null; }
            if (count($userVector) < 8) { return null; }
            // Similarity search
            $threshold = floatval($persona['behavior_similarity_threshold'] ?? 80) / 100;
            $personalityId = intval($persona['personality_id'] ?? 0);
            $stmt = $db->prepare(
                "SELECT id, similarity_threshold, embedding FROM behavior" .
                " WHERE (personality_id = :pid OR all_personalities != 0) AND embedding IS NOT NULL AND LENGTH(embedding) >= 4"
            );
            $stmt->bindValue(':pid', $personalityId, \PDO::PARAM_INT);
            $stmt->execute();
            $userNorm = 0.0;
            foreach ($userVector as $v) {
                $userNorm += $v * $v;
            }
            $userNorm = sqrt($userNorm);
            $bestScore = -1.0;
            $behaviorId = null;
            $bestThreshold = $threshold;
            while ($row = $stmt->fetch(\PDO::FETCH_ASSOC)) {
                $storedVector = json_decode($row['embedding'], true);
                if (!is_array($storedVector)) { continue; }
                if (count($storedVector) < 8) { continue; }
                $dot = 0.0;
                $normB = 0.0;
                $count = min(count($userVector), count($storedVector));
                for ($i = 0; $i < $count; $i++) {
                    $dot += ($userVector[$i] * $storedVector[$i]);
                    $normB += ($storedVector[$i] * $storedVector[$i]);
                }
                if ($normB <= 1e-12) { continue; }
                $denom = $userNorm * sqrt($normB);
                $similarity = ($denom > 1e-8) ? ($dot / $denom) : 0.0;
                $rowThreshold = floatval($row['similarity_threshold'] ?? $threshold);
                if ($similarity > $bestScore) {
                    $bestScore = $similarity;
                    $behaviorId = intval($row['id']);
                    $bestThreshold = ($rowThreshold > 0) ? $rowThreshold : $threshold;
                }
            }
            if (!$behaviorId || $bestScore < $bestThreshold) { return null; }
            // Fetch the matched behavior entry
            $stmt2 = $db->prepare("SELECT user_prompt, response_action, response_message FROM behavior WHERE id = :id LIMIT 1");
            $stmt2->bindValue(':id', $behaviorId, \PDO::PARAM_INT);
            $stmt2->execute();
            $match = $stmt2->fetch(\PDO::FETCH_ASSOC);
            if (!$match) { return null; }
            $responseAction = trim($match['response_action']  ?? '');
            $responseMessage = trim($match['response_message'] ?? '');
            $string_replacements = $this->getStringReplacements($persona);
            if (!empty($string_replacements)) {
                foreach($string_replacements as $variable => $replacement) {
                    if ($responseAction != '') { $responseAction = trim(str_replace($variable, $replacement, $responseAction)); }
                    if ($responseMessage != '') { $responseMessage = trim(str_replace($variable, $replacement, $responseMessage)); }
                }
            }
            // Build the result payload
            $result = [
                'match_confidence' => round($bestScore, 3),
                'behavior_id' => $behaviorId
            ];
            if ($responseAction != '') { $result['response_action'] = $responseAction; }
            if ($responseAction == '#LOOP_VIDEO') {
                $mediaData = $this->getRandomMediaData($db, $behaviorId, $session, $llmConfig);
                if (!empty($mediaData)) { $result['media_data'] = $mediaData; }
            }
            $db = null;
            if ($responseMessage != '') { $result['reply'] = $responseMessage; }
            if (intval($persona['response_mode'] ?? 1) != 1) { return $result; }
            // Update session history (response mode 1 only)
            $history = $session->get('conversation_history', []);
            if (empty($history)) { $history = []; }
            if (!is_array($history)) { $history = []; }
            $history[] = ['role' => 'user', 'content' => $userMessage];
            $historyEntry = $responseMessage;
            if ($responseAction != '' && $responseMessage == '') {
                $historyEntry = "*{$responseAction}*";
            } elseif ($responseAction != '') {
                $historyEntry = "*{$responseAction}* {$responseMessage}";
            }
            if ($historyEntry != '') { $history[] = ['role' => 'assistant', 'content' => $historyEntry]; }
            $session->set('conversation_history', $history);
            return $result;
        } catch (\Exception) {
            return null;
        }
    }

    /**
     * Return the built-in placeholder replacement map.
     *
     * The returned associative array is used to replace dynamic template variables in behavior responses and actions before they are sent back to the client.
     *
     * Currently supported placeholders:
     *
     * | Placeholder             | Example value                    |
     * |-------------------------|----------------------------------|
     * | {{PERSONA_FULL_NAME}}   | Ashley                           |
     * | {{PERSONA_DESCRIPTION}} | A smart and helpful AI assistant |
     * | {{CURRENT_DATE}}        | 2026-06-25                       |
     * | {{CURRENT_TIME}}        | 14:35                            |
     * | {{CURRENT_TIMESTAMP}}   | 2026-06-25 14:35:42              |
     * | {{TIMEZONE}}            | Europe/Berlin                    |
     *
     * Values are generated at runtime using the server's current timezone and locale-independent PHP date formatting.
     *
     * @param array<string,mixed> $persona Persona configuration from {@see ChatConfigService}
     * @return array<string,string> Associative array where the key is the placeholder token and the value is its runtime replacement.
     */
    protected function getStringReplacements(array $persona): array
    {
        return [
            '{{PERSONA_FULL_NAME}}'     => trim($persona['chatbot_name'] ?? 'ChatBot'),
            '{{PERSONA_DESCRIPTION}}'   => trim($persona['description'] ?? ''),
            '{{CURRENT_DATE}}'          => date('Y-m-d'),
            '{{CURRENT_TIME}}'          => date('H:i'),
            '{{CURRENT_TIMESTAMP}}'     => date('Y-m-d H:i:s'),
            '{{TIMEZONE}}'              => date_default_timezone_get()
        ];
    }

    // =========================================================================
    // MEDIA RANDOMIZER
    // =========================================================================

    /**
     * Pick a random media record for the given behavior, ensuring no repeats
     * until the track is exhausted, then reshuffle.
     *
     * @param \PDO $db      Connected personality database handle
     * @param int  $behaviorId   Behavior row to pull media for
     * @param SessionInterface $session   Symfony session (tracks used media in the current session)
     * @param array $llmConfig  LLM configuration from {@see ChatConfigService}
     * @return string|null   Base-32 media identifier, or null if none available
     */
    protected function getRandomMediaData(\PDO $db, int $behaviorId, SessionInterface $session, array $llmConfig): ?string {
        $maxMediaSession = intval($llmConfig['max_media_session'] ?? 255);
        if (empty($maxMediaSession)) { return null; }
        $stmt = $db->prepare("SELECT DISTINCT media.data FROM media" .
            " INNER JOIN behavior_media_xref ON behavior_media_xref.media_id = media.id" .
            " WHERE behavior_media_xref.behavior_id = :behavior_id"
        );
        $stmt->bindValue(':behavior_id', $behaviorId, \PDO::PARAM_INT);
        $stmt->execute();
        $mediaRecords = $stmt->fetchAll(\PDO::FETCH_COLUMN);
        if (empty($mediaRecords)) { return null; }
        $used = $session->get('media_data_used', []);
        $available = array_values(array_diff($mediaRecords, $used));
        if (empty($available)) {
            $session->remove('media_data_used');
            return $this->getRandomMediaData($db, $behaviorId, $session, $llmConfig);
        }
        $mediaData = trim($available[array_rand($available)]);
        if ($mediaData == '') { return null; }
        $used[] = $mediaData;
        if (count($used) > $maxMediaSession) {
            $used = array_slice($used, -1 * $maxMediaSession);
        }
        $session->set('media_data_used', $used);
        return $mediaData;
    }

    // =========================================================================
    // SESSION HELPERS
    // =========================================================================

    /**
     * Remove the block-request flags
     */
    protected function clearBlock(SessionInterface $session): void {
        $session->remove('block_request');
        $session->remove('block_request_time');
    }
}
