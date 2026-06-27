<?php

namespace App\Command;

use App\Service\ChatConfigService;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Helper\ProgressBar;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Input\InputOption;
use Symfony\Component\Console\Output\OutputInterface;
use Symfony\Component\HttpClient\HttpClient;

/**
 * GenerateEmbeddingsCommand - CLI command for processing missing vector embeddings.
 *
 * This command iterates over every row in the `behavior` table of `personality.db` that does **not** yet have a non-null embedding vector and sends each `user_prompt` through the configured embedding service to back-fill the column.
 *
 * Implemented as a first-class Symfony Console command with a progress bar and proper error handling.
 *
 * @package App\Command
 * @author Robert Abraham
 */
/** @cond EXCLUDE_ATTRIBUTES */
#[AsCommand(
    name: 'app:generate-embeddings',
    description: 'Process missing vector embeddings for database behavior context.'
)]
/** @endcond */
class GenerateEmbeddingsCommand extends Command
{
    /** Default database record limit for embeddings */
    protected const EMBEDDING_LIMIT = 4000;

    /** @var int $embedding_limit final database record limit for embeddings */
    protected int $embedding_limit;

    /** @var ChatConfigService Shared configuration provider for chat and LLM settings */
    protected ChatConfigService $configService;

    /**
     * Constructor for the GenerateEmbeddingsCommand.
     *
     * Initializes the command with the required ChatConfigService dependency which is used to retrieve configuration values needed for database path and embedding service endpoint resolution.
     *
     * @param ChatConfigService $configService: shared configuration provider for retrieving server root, LLM config, and embedding settings
     */
    public function __construct(ChatConfigService $configService) {
        parent::__construct();
        $this->configService = $configService;
        $this->embedding_limit = intval(self::EMBEDDING_LIMIT);
    }

    /**
     * Configures the command help documentation.
     *
     * Sets the man page formatted help text for the command. The documentation is displayed when the user runs the command with --help option. This method is called automatically by the parent Command class during initialization.
     *
     * @return void: no return value
     */
    protected function configure(): void {
        parent::configure();
        $this->addOption(
            'limit',
            null,
            InputOption::VALUE_REQUIRED,
            'Maximum number of embeddings to generate (default: 4000)',
            4000);
        $this->setHelp(<<<'HELP'
APP:GENERATE-EMBEDDINGS(1)          User Commands          APP:GENERATE-EMBEDDINGS(1)

NAME
        app:generate-embeddings - Process missing vector embeddings for database behavior context

SYNOPSIS
        php bin/console app:generate-embeddings [--limit=N] [--help]

DESCRIPTION
        The app:generate-embeddings command is a Symfony Console command that
        processes all behavior records in the personality database that are
        missing vector embeddings. It iterates through the `behavior` table
        of the SQLite database located at `database/personality.db` and identifies
        rows where the `embedding` column is either NULL or contains fewer
        than 4 characters (indicating an invalid or incomplete embedding).

        For each identified row, the command extracts the `user_prompt` field
        and sends it via HTTP POST request to the configured embedding service
        endpoint. The resulting embedding vector is received, serialized to JSON,
        and stored back into the `embedding` column of the corresponding row.

        A progress bar is displayed during processing to indicate the current
        progress through the dataset. Upon completion, a summary line shows the
        number of successfully processed embeddings and any that were skipped.

OPTIONS
        --limit=N
            Maximum number of embeddings to generate (default: 4000). Use
            this option to override the default limit for systems with more
            or less available resources.

        --help, -h
            Display this manual page with full documentation.

        --version
            Display the command version.

EXAMPLES
        php bin/console app:generate-embeddings
                Run the embedding generation process with the default limit.

        php bin/console app:generate-embeddings --limit=10000
                Run the embedding generation process with a limit of 10000.

        php bin/console app:generate-embeddings --help
                Display this manual page.

CONFIGURATION
        The command reads configuration from ChatConfigService:
        * proxy_port (default: 5123) - Embedding service proxy port
        * embedding_endpoint (default: /v1/embeddings) - API endpoint path
        * memory_limit (default: 1G) - PHP memory limit

EXIT CODES
        0       Successful - all missing embeddings generated or none found.
        1       Failure - database not found or errors.

FILES
        database/personality.db
                SQLite database with behavior table (user_prompt, embedding columns).

SEE ALSO
        app:chat-config, php bin/console list
HELP);
    }

    /**
     * Executes the embedding generation pipeline.
     *
     * This method performs the following operations in sequence:
     *
     * 1. Locates `personality.db` via `ChatConfigService::getServerRoot()`.
     * 2. Queries the `behavior` table for rows where `embedding` is NULL or < 4 chars.
     * 3. For each row without embedding, calls the embedding proxy service.
     * 4. Stores the resulting vector as JSON in the `embedding` column.
     * 5. Displays a live progress bar showing processing status.
     * 6. Outputs a summary of successful and failed embeddings.
     *
     * Note: The --help option is handled automatically by Symfony Console before this method is called, using the man page formatted help text defined in the configure() method.
     *
     * @param InputInterface $input: console input containing command options and arguments
     * @param OutputInterface $output: console output stream for writing messages (STDOUT/STDERR)
     * @return int: returns `Command::SUCCESS` (0) on success or when all embeddings already exist; returns `Command::FAILURE` (1) when the database is not found, the embedding service is unavailable, or an unrecoverable error occurs
     */
    protected function execute(InputInterface $input, OutputInterface $output): int {
        // Handle --limit option
        $limit = intval($input->getOption('limit') ?: 0);
        if ($limit >= 1) { $this->embedding_limit = $limit; }
        $dbPath = $this->configService->getServerRoot() . '/database/personality.db';
        // Guard: database must exist
        if (!file_exists($dbPath)) {
            $output->writeln('<error>ERROR: personality database not found!</error>');
            return Command::FAILURE;
        }
        // Get LLM config for correct embedding
        $llmConfig = $this->configService->getLlmConfig();
        $memory_limit = trim($llmConfig['memory_limit'] ?? '1G');
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
        // Set resource limits
        @ini_set('memory_limit', $memory_limit);
        @ini_set('max_execution_time', '0');
        // Open the behavior database
        $db = new \PDO("sqlite:" . $dbPath);
        $db->setAttribute(\PDO::ATTR_ERRMODE, \PDO::ERRMODE_EXCEPTION);
        $db->exec("PRAGMA journal_mode = WAL;");
        $stmt = $db->query("SELECT id, user_prompt FROM behavior WHERE embedding IS NULL OR LENGTH(embedding) < 4 LIMIT {$this->embedding_limit}");
        $rows = $stmt->fetchAll(\PDO::FETCH_ASSOC);
        // All embeddings already exist
        if (empty($rows)) {
            $output->writeln('<info>All vector embeddings exist.</info>');
            return Command::SUCCESS;
        }
        $total = count($rows);
        $output->writeln(sprintf('Processing vectors for %d items...', $total));
        $output->writeln(sprintf('Using endpoint: %s, limit: %d', $embeddingUrl, $this->embedding_limit));
        $output->writeln('(Press CTRL+C to abort)');
        $progressBar = new ProgressBar($output, $total);
        $progressBar->start();
        // Generate embeddings
        $isLocal = in_array($embeddingHost, ['127.0.0.1', 'localhost'], true);
        $client = HttpClient::create([
            'timeout' => 60,
            'verify_peer' => !$isLocal,
            'verify_host' => !$isLocal
        ]);
        $done = 0;
        $failed = 0;
        foreach ($rows as $row) {
            $id = intval(trim($row['id'] ?? 0));
            $text = trim($row['user_prompt'] ?? '');
            if ($text !== '') {
                try {
                    $response = $client->request('POST', $embeddingUrl, ['json' => ['input' => $text]]);
                    if ($response->getStatusCode() === 200) {
                        $decoded = $response->toArray();
                        $embedding = ($decoded['data'][0]['embedding'] ?? $decoded['embedding']) ?? null;
                        if (is_array($embedding)) {
                            $update = $db->prepare("UPDATE behavior SET embedding = :embed WHERE id = :id");
                            $update->bindValue(':embed', json_encode($embedding));
                            $update->bindValue(':id', $id, \PDO::PARAM_INT);
                            $update->execute();
                            ++$done;
                        } else {
                            ++$failed;
                        }
                    } else {
                        ++$failed;
                    }
                } catch (\Exception $e) {
                    // Skip any single parsing failure safely
                    ++$failed;
                }
            }
            $progressBar->advance();
        }
        // Summary
        $progressBar->finish();
        $output->writeln('');
        $output->writeln(sprintf('<info>Embeddings generated: %d, skipped: %d</info>', $done, $failed));
        return Command::SUCCESS;
    }
}
