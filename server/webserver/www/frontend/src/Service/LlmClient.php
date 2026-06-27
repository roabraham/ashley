<?php

namespace App\Service;

use Symfony\Component\HttpClient\HttpClient;
use Symfony\Contracts\HttpClient\HttpClientInterface;

/**
 * LlmClient
 *
 * Thin, reusable HTTP client for communicating with the LLM proxy and
 * embedding service.
 *
 * ## Responsibilities (SRP)
 *
 * - `estimateTokenCount()` – shared token-counting utility.
 * - `sendChatRequest()`    – POST to a chat-completion endpoint and extract
 *                            the assistant message from the response.
 *
 * ## Configuration
 *
 * The configured internal host, port and endpoints come from
 * {@see ChatConfigService::getLlmConfig()} and are injected at construction
 * time - there are no hard-coded defaults in this class.
 */
class LlmClient
{
    /**
     * The concrete Symfony HTTP client instance.
     *
     * @var HttpClientInterface
     */
    protected HttpClientInterface $httpClient;

    /**
     * LLM host as configured in {@see wrapper.db} / {@see wrapper.json}.
     *
     * @var string
     */
    protected string $llmHost;

    /**
     * LLM proxy port as configured in {@see wrapper.db} / {@see wrapper.json}.
     *
     * @var int
     */
    protected int $proxyPort;

    /**
     * LLM API endpoint path (e.g. `/v1/chat/completions`).
     *
     * @var string
     */
    protected string $llmEndpoint;

    /**
     * Embedding API endpoint path (e.g. `/v1/embeddings`).
     *
     * @var string
     */
    protected string $embeddingEndpoint;

    /**
     * Build the client with explicit configuration.
     *
     * A constructor with named parameters (not a global DI container) means this class can be instantiated both inside Symfony (via service injection) and in standalone scripts (via `new`) with identical behaviour.
     *
     * @param string $llmHost             LLM service host
     * @param int    $proxyPort           LLM proxy port
     * @param string $llmEndpoint         LLM chat-completion endpoint path
     * @param string $embeddingEndpoint   Embeddings endpoint path
     * @param int    $timeout             HTTP timeout in seconds
     */
    public function __construct(
        string $llmHost = '127.0.0.1',
        int $proxyPort = 5123,
        string $llmEndpoint = '/v1/chat/completions',
        string $embeddingEndpoint = '/v1/embeddings',
        int $timeout = 60
    ) {
        $this->llmHost         = $llmHost;
        $this->proxyPort       = $proxyPort;
        $this->llmEndpoint     = $llmEndpoint;
        $this->embeddingEndpoint = $embeddingEndpoint;
        $this->httpClient      = HttpClient::create(['timeout' => $timeout]);
    }

    /**
     * Build a full base URL for the LLM proxy.
     *
     * @return string e.g. `http://127.0.0.1:5123/v1/chat/completions`
     */
    protected function getLlmBaseUrl(): string
    {
        return sprintf(
            'http://%s:%d%s',
            $this->llmHost,
            $this->proxyPort,
            $this->llmEndpoint
        );
    }

    /**
     * Build a full base URL for the embeddings endpoint.
     *
     * @return string e.g. `http://127.0.0.1:5123/v1/embeddings`
     */
    protected function getEmbeddingUrl(): string
    {
        return sprintf(
            'http://%s:%d%s',
            $this->llmHost,
            $this->proxyPort,
            $this->embeddingEndpoint
        );
    }

    /**
     * Estimate the token count of a string (`ceil(mb_strlen / 2.5)`).
     *
     * @param string $text Input text to inspect
     * @return int Token count estimate
     */
    public function estimateTokenCount(string $text): int
    {
        $trimmed = trim($text ?? '');
        if ($trimmed === '') { return 0; }
        return (int) ceil(mb_strlen($trimmed, 'UTF-8') / 2.5);
    }

    /**
     * Send a chat-completion POST request to the configured LLM proxy.
     *
     * @param string      $url     Full proxy URL to POST to (overrides the
     *                             configured base URL when provided)
     * @param array<mixed> $messages Message array in OpenAI format
     * @param array<mixed> $options  Extra request options (merged under `json`)
     * @return string|null The assistant reply text, or null on failure
     */
    public function sendChatRequest(string $url, array $messages, array $options = []): ?string {
        $payload = ['messages' => $messages, 'stream' => false];
        foreach ($options as $key => $value) {
            $payload[$key] = $value;
        }
        try {
            $response = $this->httpClient->request('POST', $url, ['json' => $payload]);
            if ($response->getStatusCode() !== 200) { return null; }
            $data = $response->toArray();
            return ($data['choices'][0]['message']['content'] ?? $data['content']) ?? null;
        } catch (\Exception) {
            return null;
        }
        return null;
    }

    /**
     * Request embedding vectors for the given texts.
     *
     * @param string|array<string> $texts Single text or array of texts
     * @return array<int,array<float>>|null  Array of vector arrays, or null on failure
     */
    public function requestEmbeddings(string|array $texts): ?array
    {
        try {
            $response = $this->httpClient->request('POST', $this->getEmbeddingUrl(), [
                'json' => ['input' => $texts]
            ]);
            if ($response->getStatusCode() !== 200) { return null; }
            $data = $response->toArray();
            return $data['data'] ?? null;
        } catch (\Exception) {
            return null;
        }
        return null;
    }
}
