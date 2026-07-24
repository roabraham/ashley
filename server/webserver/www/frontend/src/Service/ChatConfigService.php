<?php

namespace App\Service;

/**
 * ChatConfigService
 *
 * Configuration sources for chatbot settings:
 *
 * - Persona settings from {@see personality.json} and {@see personality.db}
 * - LLM / embedding engine settings from {@see wrapper.json} and {@see wrapper.db}
 * - Nginx proxy location from {@see web_server_config} in {@see wrapper.db}
 *
 * All public getters return plain arrays for direct instantiation.
 */
class ChatConfigService {
    /**
     * Absolute path to the shared server root.
     *
     * Walk-up path:
     *   {@code src/Service/ } → {@code frontend/ } → {@code server/ }
     * which resolves to {@code config/} folder.
     */
    protected string $serverRoot;

    /**
     * Absolute path to the wrapper SQLite database (e.g. `database/wrapper.db`).
     *
     * Sourced from the `WRAPPER_DB_PATH` environment variable (see .env), falling back to a `database/wrapper.db` file next to the server root.
     */
    protected string $wrapperDbPath;

    /**
     * Absolute path to the personality SQLite database (e.g. `database/personality.db`).
     *
     * Sourced from the `PERSONALITY_DB_PATH` environment variable (see .env), falling back to a `database/personality.db` file next to the server root.
     */
    protected string $personalityDbPath;

    /**
     * Absolute path to the wrapper JSON configuration file (e.g. `config/wrapper.json`).
     *
     * Sourced from the `WRAPPER_JSON_PATH` environment variable (see .env), falling back to a `config/wrapper.json` file next to the server root.
     */
    protected string $wrapperJsonPath;

    /**
     * Absolute path to the personality JSON configuration file (e.g. `config/personality.json`).
     *
     * Sourced from the `PERSONALITY_JSON_PATH` environment variable (see .env), falling back to a `config/personality.json` file next to the server root.
     */
    protected string $personalityJsonPath;

    /**
     * Build the service, resolving the server root at construction time.
     *
     * Designed to work without a Symfony container by computing {$serverRoot} relative to the physical location of this class file. Database and JSON configuration locations are injected via the corresponding parameters (resolved from the environment) and fall back to the server root when not provided.
     *
     * @param string|null $wrapperDbPath Injected `WRAPPER_DB_PATH` value
     * @param string|null $personalityDbPath Injected `PERSONALITY_DB_PATH` value
     * @param string|null $wrapperJsonPath Injected `WRAPPER_JSON_PATH` value
     * @param string|null $personalityJsonPath Injected `PERSONALITY_JSON_PATH` value
     */
    public function __construct(?string $wrapperDbPath = null, ?string $personalityDbPath = null, ?string $wrapperJsonPath = null, ?string $personalityJsonPath = null) {
        $this->serverRoot = realpath(dirname(__DIR__, 5));
        if (!$this->serverRoot) { throw new \RuntimeException('Could not reliably determine the server root directory!'); }
        $this->wrapperDbPath = "{$this->serverRoot}/database/wrapper.db";
        $wrapperDbPathFixed = trim($wrapperDbPath ?? '');
        if ($wrapperDbPathFixed) { $this->wrapperDbPath = $wrapperDbPathFixed; }
        $this->personalityDbPath = "{$this->serverRoot}/database/personality.db";
        $personalityDbPathFixed = trim($personalityDbPath ?? '');
        if ($personalityDbPathFixed) { $this->personalityDbPath = $personalityDbPathFixed; }
        $this->wrapperJsonPath = "{$this->serverRoot}/config/wrapper.json";
        $wrapperJsonPathFixed = trim($wrapperJsonPath ?? '');
        if ($wrapperJsonPathFixed) { $this->wrapperJsonPath = $wrapperJsonPathFixed; }
        $this->personalityJsonPath = "{$this->serverRoot}/config/personality.json";
        $personalityJsonPathFixed = trim($personalityJsonPath ?? '');
        if ($personalityJsonPathFixed) { $this->personalityJsonPath = $personalityJsonPathFixed; }
    }

    /**
     * Return the absolute path to the shared server root.
     *
     * Used by other services (e.g. `BehaviorMatcher`) that need direct
     * filesystem access to the personality database.
     *
     * @return string Absolute filesystem path
     */
    public function getServerRoot(): string { return $this->serverRoot; }

    /**
     * Return the absolute path to the wrapper SQLite database.
     *
     * Sourced from the `WRAPPER_DB_PATH` environment variable.
     *
     * @return string Absolute filesystem path
     */
    public function getWrapperDbPath(): string { return $this->wrapperDbPath; }

    /**
     * Return the absolute path to the personality SQLite database.
     *
     * Sourced from the `PERSONALITY_DB_PATH` environment variable.
     *
     * @return string Absolute filesystem path
     */
    public function getPersonalityDbPath(): string { return $this->personalityDbPath; }

    /**
     * Return the absolute path to the wrapper JSON configuration file.
     *
     * Sourced from the `WRAPPER_JSON_PATH` environment variable.
     *
     * @return string Absolute filesystem path
     */
    public function getWrapperJsonPath(): string { return $this->wrapperJsonPath; }

    /**
     * Return the absolute path to the personality JSON configuration file.
     *
     * Sourced from the `PERSONALITY_JSON_PATH` environment variable.
     *
     * @return string Absolute filesystem path
     */
    public function getPersonalityJsonPath(): string { return $this->personalityJsonPath; }

    /**
     * Return the LLM / embedding engine configuration.
     *
     * Sources (in priority order; later overrides earlier):
     * 1. Hardcoded defaults.
     * 2. {@see wrapper.db} {@code config} and {@code config_data} tables - the active engine record selected via the {@code llama_engine} ID from {@see wrapper.json}.
     * 3. {@see wrapper.json} - JSON file overrides ({@code proxy_port}, {@code embedding}, {@code parameters}, {@code embedding_parameters}).
     * 4. {@see wrapper.db} {@code web_server_config} table - the {@code NGINX_PROXY_LOCATION} value (highest priority for proxy_location).
     *
     * @return array<string,mixed> Key-value map
     */
    public function getLlmConfig(): array {
        //Check Wrapper Database availability
        $wrapperDbPath = $this->wrapperDbPath;
        if (!file_exists($wrapperDbPath)) {
            throw new \RuntimeException("Wrapper database not found: {$wrapperDbPath}!");
        }
        //Hard-coded defaults
        $config = [
            'llm_host'             => '127.0.0.1',
            'llm_port'             => 8080,
            'llm_endpoint'         => '/v1/chat/completions',
            'embedding_host'       => '127.0.0.1',
            'embedding_port'       => 0,
            'embedding_endpoint'   => '/v1/embeddings',
            'embedding_ctx_size'   => 8192,
            'llm_ctx_size'         => 8192,
            'llm_enabled'          => true,
            'embedding_enabled'    => true,
            'proxy_location'       => '/llamacpp/',
            'proxy_port'           => 5123,
            'memory_limit'         => '1G',
            'request_timeout'      => 300,
            'max_media_session'    => 255,
            'token_safety_margin'  => 256,
            'max_summary_tokens'   => 256,
            'summary_temperature'  => 0.3,
            'engine_id'            => null
        ];
        $wrapperJsonPath = $this->wrapperJsonPath;
        // Priority 1: wrapper.db engine configuration (sets SQLite defaults)
        try {
            $db = new \PDO("sqlite:{$wrapperDbPath}");
            $db->setAttribute(\PDO::ATTR_ERRMODE, \PDO::ERRMODE_EXCEPTION);
            $db->exec("PRAGMA busy_timeout = 5000");
            $db->exec("PRAGMA journal_mode = WAL;");
            // Select active engine by llama_engine ID from wrapper.json
            $engineId = null;
            if (file_exists($wrapperJsonPath)) {
                try {
                    $wjson = json_decode(file_get_contents($wrapperJsonPath), true);
                    if ($wjson && is_array($wjson)) {
                        $engineId = intval(trim($wjson['llama_engine'] ?? 0));
                    }
                } catch (\Exception) {}
            }
            $hasEmbeddingModel = false;
            $hasLlmModel       = false;
            $embeddingHost     = null;
            $embeddingPort     = null;
            $embeddingCtxSize  = null;
            $llmHost           = null;
            $llmPort           = null;
            $llmCtxSizeTmp     = null;
            $sql = "SELECT id, server, endpoint, embedding_endpoint, proxy_port FROM config";
            if ($engineId >= 1) {
                $sql .= " WHERE id = :id LIMIT 1";
                $stmt = $db->prepare($sql);
                $stmt->bindValue(':id', $engineId, \PDO::PARAM_INT);
                $stmt->execute();
            } else {
                $sql .= " ORDER BY priority DESC, id ASC LIMIT 1";
                $stmt = $db->query($sql);
            }
            $row = $stmt->fetch(\PDO::FETCH_ASSOC);
            if ($row) {
                $engineId = intval(trim($row['id'] ?? ''));
                $config['engine_id'] = $engineId;
                $llmEp = trim($row['endpoint'] ?? '');
                $embEp = trim($row['embedding_endpoint'] ?? '');
                if (!empty($llmEp)) { $config['llm_endpoint'] = '/' . trim(ltrim($llmEp, '/')); }
                if (!empty($embEp)) { $config['embedding_endpoint'] = '/' . trim(ltrim($embEp, '/')); }
                $proxyPortRaw = intval(trim($row['proxy_port'] ?? ''));
                if ($proxyPortRaw > 0) { $config['proxy_port'] = $proxyPortRaw; }
            }
            if ($engineId >= 1) {
                try {
                    $dataSql = "SELECT config_data.name AS name, config_data.value AS value, config_data_type.name AS type_name, config_data.enable_server AS enable_server FROM config_data LEFT JOIN config_data_type ON config_data_type.id = config_data.type_id WHERE config_id = :cid";
                    $dataStmt = $db->prepare($dataSql);
                    $dataStmt->bindValue(':cid', $engineId, \PDO::PARAM_INT);
                    $dataStmt->execute();
                    $dataRows = $dataStmt->fetchAll(\PDO::FETCH_ASSOC);
                    if ($dataRows) {
                        foreach ($dataRows as $r) {
                            $name = strtolower(trim($r['name'] ?? ''));
                            $value = trim($r['value'] ?? '');
                            $typeName = strtoupper(trim($r['type_name'] ?? ''));
                            $enableServer = (intval(trim($r['enable_server'] ?? '0')) !== 0);
                            if ($name == 'model' && $enableServer) {
                                if ($typeName == 'EMBEDDING') {
                                    $hasEmbeddingModel = true;
                                } else {
                                    $hasLlmModel = true;
                                }
                                continue;
                            }
                            if ($name == 'port' && $enableServer) {
                                if ($typeName === 'EMBEDDING') {
                                    $embeddingPort = intval($value);
                                } else {
                                    $llmPort = intval($value);
                                }
                                continue;
                            }
                            if ($name == 'host' && $enableServer) {
                                if ($typeName === 'EMBEDDING') {
                                    $embeddingHost = $value;
                                } else {
                                    $llmHost = $value;
                                }
                                continue;
                            }
                            if (in_array($name, ['ctx_size', 'ctx-size']) && $enableServer) {
                                if ($typeName === 'EMBEDDING') {
                                    $embeddingCtxSize = intval($value);
                                } else {
                                    $llmCtxSizeTmp = intval($value);
                                }
                                continue;
                            }
                        }
                    }
                    if ($embeddingHost) { $config['embedding_host'] = $embeddingHost; }
                    if ($embeddingPort > 0) { $config['embedding_port'] = $embeddingPort; }
                    if ($embeddingCtxSize > 0) { $config['embedding_ctx_size'] = $embeddingCtxSize; }
                    if ($llmHost) { $config['llm_host'] = $llmHost; }
                    if ($llmPort > 0) { $config['llm_port'] = $llmPort; }
                    if ($llmCtxSizeTmp > 0) { $config['llm_ctx_size'] = $llmCtxSizeTmp; }
                    $config['llm_enabled'] = (!empty($config['llm_endpoint']) && $hasLlmModel);
                    $config['embedding_enabled'] = (!empty($config['embedding_endpoint']) && $hasEmbeddingModel);
                } catch (\Exception) {
                    // Fails silently - defaults remain
                }
            }
            $db = null;
        } catch (\Exception $e) {
            // Fails silently - defaults remain
        }
        // Priority 2: wrapper.json overrides (highest priority, applied last)
        if (file_exists($wrapperJsonPath)) {
            try {
                $json = json_decode(file_get_contents($wrapperJsonPath), true);
                if ($json && is_array($json)) {
                    $proxyPortJson = intval(trim($json['proxy_port'] ?? 0));
                    if ($proxyPortJson > 0) { $config['proxy_port'] = $proxyPortJson; }
                    $proxyTimeoutJson = intval(trim($json['proxy_timeout'] ?? 0));
                    if ($proxyTimeoutJson > 0) { $config['request_timeout'] = $proxyTimeoutJson; }
                    if (isset($json['llm_enabled'])) {
                        $llm = $json['llm_enabled'];
                        if (is_numeric($llm)) {
                            $config['llm_enabled'] = (intval($llm) !== 0);
                        } else {
                            $config['llm_enabled'] = (!in_array(strtolower(trim(strval($llm))), ['0', 'false', 'no']));
                        }
                    }
                    if (isset($json['embedding'])) {
                        $emb = $json['embedding'];
                        if (is_numeric($emb)) {
                            $config['embedding_enabled'] = (intval($emb) !== 0);
                        } else {
                            $config['embedding_enabled'] = (!in_array(strtolower(trim(strval($emb))), ['0', 'false', 'no']));
                        }
                    }
                    if (isset($json['parameters'])) {
                        if (is_array($json['parameters'])) {
                            if (!empty($json['parameters'])) {
                                foreach ($json['parameters'] as $name => $value) {
                                    $nl = strtolower(trim($name));
                                    if ($nl === 'port') {
                                        $llmPort = intval(trim($value));
                                        if ($llmPort > 0) { $config['llm_port'] = $llmPort; }
                                        continue;
                                    }
                                    if ($nl === 'host') {
                                        $llmHost = trim($value);
                                        if ($llmHost) { $config['llm_host'] = $llmHost; }
                                        continue;
                                    }
                                    if (in_array($nl, ['ctx_size', 'ctx-size'])) {
                                        $llmCtxSizeTmp = intval(trim($value));
                                        if ($llmCtxSizeTmp > 0) { $config['llm_ctx_size'] = $llmCtxSizeTmp; }
                                    }
                                }
                            }
                        }
                    }
                    if (isset($json['embedding_parameters'])) {
                        if (is_array($json['embedding_parameters'])) {
                            if (!empty($json['embedding_parameters'])) {
                                foreach ($json['embedding_parameters'] as $name => $value) {
                                    $nl = strtolower(trim($name));
                                    if ($nl === 'port') {
                                        $embeddingPort = intval(trim($value));
                                        if ($embeddingPort > 0) { $config['embedding_port'] = $embeddingPort; }
                                        continue;
                                    }
                                    if ($nl === 'host') {
                                        $embeddingHost = trim($value);
                                        if ($embeddingHost) { $config['embedding_host'] = $embeddingHost; }
                                        continue;
                                    }
                                    if (in_array($nl, ['ctx_size', 'ctx-size'])) {
                                        $embeddingCtxSize = intval(trim($value));
                                        if ($embeddingCtxSize > 0) { $config['embedding_ctx_size'] = $embeddingCtxSize; }
                                    }
                                }
                            }
                        }
                    }
                }
            } catch (\Exception) {
                // Fails silently if invalid JSON - defaults from SQLite remain
            }
        }
        // Nginx proxy_location from web_server_config table
        try {
            $db2 = new \PDO("sqlite:{$wrapperDbPath}");
            $db2->setAttribute(\PDO::ATTR_ERRMODE, \PDO::ERRMODE_EXCEPTION);
            $db2->exec("PRAGMA busy_timeout = 5000");
            $db2->exec("PRAGMA journal_mode = WAL;");
            $stmt = $db2->query("SELECT value FROM web_server_config WHERE UPPER(TRIM(name)) LIKE 'NGINX_PROXY_LOCATION' LIMIT 1");
            $locRow = $stmt->fetch(\PDO::FETCH_ASSOC);
            if ($locRow) {
                $location = trim($locRow['value'] ?? '');
                if ($location) { $config['proxy_location'] = $location; }
            }
        } catch (\Exception $e) {
            // Ignore - default proxy_location stays
        }
        if (empty($config['llm_endpoint'])) { $config['llm_enabled'] = false; }
        if (empty($config['embedding_endpoint'])) { $config['embedding_enabled'] = false; }
        return $config;
    }

    /**
     * Return the persona / chatbot personality configuration.
     *
     * Mirrors the persona configuration from the original application.
     *
     * Sources (in priority order; later overrides earlier):
     * 1. Hardcoded defaults matching the original application.
     * 2. {@see personality.db} - active personality row from the {@code personalities} table (selected by name from the JSON file, otherwise the highest-priority active row).
     * 3. {@see personality.json} - JSON file overrides applied on top of the database row.
     *
     * @return array<string,mixed> Key-value map whose keys match the original
     *         {@code $persona_config} array so controllers share the same
     *         interface.
     */
    public function getPersonaConfig(): array {
        $persona = [
            'personality_name'              => null,
            'chatbot_name'                  => 'ChatBot',
            'description'                   => null,
            'initial_message'               => null,
            'avatar_img'                    => null,
            'background_img'                => null,
            'css_override'                  => null,
            'active_prompt'                 => null,
            'summary_prompt'                => null,
            'personality_id'                => null,
            'behavior_similarity_threshold' => 80,
            'memory_mode'                   => 1,
            'response_mode'                 => 1
        ];
        $personalityName = null;
        // personality.json - read selectors (personality name, full_name, etc.)
        $jsonData = null;
        $personalityJsonPath = $this->personalityJsonPath;
        if (file_exists($personalityJsonPath)) {
            try {
                $jsonData = json_decode(file_get_contents($personalityJsonPath), true);
                if ($jsonData && is_array($jsonData)) {
                    $personalityName = trim($jsonData['personality'] ?? '');
                }
            } catch (\Exception) {
                // Fails silently
            }
        }
        // personality.db - query active personality row
        $personalityDbPath = $this->personalityDbPath;
        if (file_exists($personalityDbPath)) {
            try {
                $db = new \PDO("sqlite:" . $personalityDbPath);
                $db->setAttribute(\PDO::ATTR_ERRMODE, \PDO::ERRMODE_EXCEPTION);
                $db->exec("PRAGMA busy_timeout = 5000");
                $db->exec("PRAGMA journal_mode = WAL;");
                if ($personalityName) {
                    $stmt = $db->prepare("SELECT * FROM personalities WHERE name LIKE :name AND is_active = 1 LIMIT 1");
                    $stmt->bindValue('name', $personalityName, \PDO::PARAM_STR);
                    $stmt->execute();
                } else {
                    $stmt = $db->query("SELECT * FROM personalities WHERE is_active = 1 ORDER BY priority DESC, id ASC LIMIT 1");
                }
                $data = $stmt->fetch(\PDO::FETCH_ASSOC);
                if ($data) {
                    if (empty($personalityName)) { $personalityName = trim($data['name'] ?? ''); }
                    $persona['personality_id'] = intval(trim($data['id'] ?? 0));
                    $full_name = trim($data['full_name'] ?? '');
                    if ($full_name) { $persona['chatbot_name'] = $full_name; }
                    $persona['description'] = trim($data['description'] ?? '');
                    $persona['initial_message'] = trim($data['initial_message'] ?? '');
                    $persona['active_prompt'] = trim($data['system_prompt'] ?? '');
                    $persona['summary_prompt'] = trim($data['summary_prompt'] ?? '');
                    $persona['css_override'] = trim($data['css_override'] ?? '');
                    $similarity_threshold = intval(trim($data['behavior_similarity_threshold'] ?? 0));
                    if ($similarity_threshold >= 1) { $persona['behavior_similarity_threshold']  = $similarity_threshold; }
                    // Format base-64 images stored in the DB
                    foreach (['avatar' => 'avatar_img', 'background_image' => 'background_img'] as $dbField => $cfgKey) {
                        $imgRaw = trim($data[$dbField] ?? '');
                        if (empty($imgRaw)) { continue; }
                        $imgJson = json_decode($imgRaw, true);
                        if (!isset($imgJson['content'])) { continue; }
                        $persona[$cfgKey] = $this->formatBase64Image($imgJson['content'], $imgJson['filename'] ?? '');
                    }
                }
            } catch (\Exception $e) {
                // Fails silently
            }
        }
        $persona['personality_name'] = $personalityName;
        // personality.json - apply field overrides (highest priority)
        if ($jsonData && is_array($jsonData)) {
            $full_name = trim($jsonData['full_name'] ?? '');
            if ($full_name) { $persona['chatbot_name'] = $full_name; }
            $description = trim($jsonData['description'] ?? '');
            if ($description) { $persona['description'] = $description; }
            $initial_message = trim($jsonData['initial_message'] ?? '');
            if ($initial_message) { $persona['initial_message'] = $initial_message; }
            $system_prompt = trim($jsonData['system_prompt'] ?? '');
            if ($system_prompt) { $persona['active_prompt'] = $system_prompt; }
            $css_override = trim($jsonData['css_override'] ?? '');
            if ($css_override) { $persona['css_override'] = $css_override; }
            $summary_prompt = trim($jsonData['summary_prompt'] ?? '');
            if ($summary_prompt) { $persona['summary_prompt'] = $summary_prompt; }
            if (isset($jsonData['memory_mode'])) {
                $mm = intval($jsonData['memory_mode']);
                if (in_array($mm, [1, 2], true)) { $persona['memory_mode'] = $mm; }
            }
            if (isset($jsonData['response_mode'])) {
                $rm = intval($jsonData['response_mode']);
                if (in_array($rm, [1, 2], true)) { $persona['response_mode'] = $rm; }
            }
            $similarity_threshold = intval(trim($jsonData['behavior_similarity_threshold'] ?? 0));
            if ($similarity_threshold >= 1) { $persona['behavior_similarity_threshold']  = $similarity_threshold; }
            // Format base-64 images from JSON overrides
            foreach (['avatar' => 'avatar_img', 'background_image' => 'background_img'] as $jsonField => $cfgKey) {
                if (!isset($jsonData[$jsonField])) { continue; }
                if (!is_array($jsonData[$jsonField])) { continue; }
                if (!isset($jsonData[$jsonField]['content'])) { continue; }
                $persona[$cfgKey] = $this->formatBase64Image($jsonData[$jsonField]['content'], $jsonData[$jsonField]['filename'] ?? '');
            }
        }
        return $persona;
    }

    /**
     * Format a raw base-64 image payload as a proper data-URI string.
     *
     * Strips any existing `data:image/…;base64,` prefix before re-encoding
     * so that double-encoded blobs are handled gracefully.
     *
     * @param string $base64Content Raw base-64 data (with or without prefix)
     * @param string $filename      Filename whose extension drives MIME detection
     * @return string Complete `data:<mime>;base64,<data>` URI
     */
    protected function formatBase64Image(string $base64Content, string $filename): string {
        $content = trim($base64Content ?? '');
        // Strip any existing prefix if it got stuck in the raw data
        if (str_starts_with($content, 'data:image')) {
            $content = preg_replace('/^data:image\/(.+);base64,/', '', $content);
        }
        $mime = 'image/jpeg';
        $ext = strtolower(pathinfo(trim($filename ?? ''), PATHINFO_EXTENSION));
        switch ($ext) {
            case 'png': $mime = 'image/png'; break;
            case 'gif': $mime = 'image/gif'; break;
            case 'webp': $mime = 'image/webp'; break;
            case 'bmp': $mime = 'image/bmp'; break;
        }
        return "data:{$mime};base64,{$content}";
    }
}
