<?php

namespace App\Service;

use Doctrine\DBAL\Connection;
use Doctrine\DBAL\DriverManager;

/**
 * DatabaseConnection
 *
 * Provides Doctrine DBAL connections to the wrapper and personality SQLite databases.
 * Centralizes connection creation and configuration to avoid code duplication.
 * This is a low-level service - it does NOT depend on any other service.
 */
class DatabaseConnection
{
    /** SQLite busy timeout in milliseconds for wrapper database */
    protected const WRAPPER_BUSY_TIMEOUT_MS = 5000;

    /** SQLite busy timeout in seconds for personality database */
    protected const PERSONALITY_BUSY_TIMEOUT_SECONDS = 3;

    /** SQLite deterministic function flag for custom LOWER() function */
    protected const SQLITE_DETERMINISTIC_FLAG = 0x000000800;

    /** Escape character for LIKE patterns */
    protected const SQLITE_LIKE_ESCAPE_CHAR = '\\';

    /** @var string wrapper database filepath */
    protected string $wrapperDbPath;

    /** @var string personality database filepath */
    protected string $personalityDbPath;

    /**
     * Build the service, resolving the server root at construction time.
     *
     * Designed to work without a Symfony container by computing {$serverRoot} relative to the physical location of this class file.
     * Database paths are injected via the corresponding parameters (resolved from the environment) and fall back to the server root when not provided.
     *
     * @param string|null $wrapperDbPath Injected `WRAPPER_DB_PATH` value
     * @param string|null $personalityDbPath Injected `PERSONALITY_DB_PATH` value
     */
    public function __construct(?string $wrapperDbPath = null, ?string $personalityDbPath = null)
    {
        $serverRoot = realpath(dirname(__DIR__, 5));
        if (!$serverRoot) { throw new \RuntimeException('Could not reliably determine the server root directory!'); }
        $this->wrapperDbPath = "{$serverRoot}/database/wrapper.db";
        $wrapperDbPathFixed = trim($wrapperDbPath ?? '');
        if ($wrapperDbPathFixed) { $this->wrapperDbPath = $wrapperDbPathFixed; }
        $this->personalityDbPath = "{$serverRoot}/database/personality.db";
        $personalityDbPathFixed = trim($personalityDbPath ?? '');
        if ($personalityDbPathFixed) { $this->personalityDbPath = $personalityDbPathFixed; }
    }

    /**
     * Get a Doctrine DBAL connection to the wrapper database.
     *
     * @return Connection An open DBAL connection to wrapper.db
     * @throws \RuntimeException When the wrapper database file does not exist
     */
    public function getWrapperConnection(): Connection
    {
        if (!file_exists($this->wrapperDbPath)) {
            throw new \RuntimeException("Wrapper database not found: {$this->wrapperDbPath}!");
        }
        $connection = DriverManager::getConnection([
            'driver'        => 'pdo_sqlite',
            'path'          => $this->wrapperDbPath,
            'driverOptions' => [
                \PDO::ATTR_TIMEOUT => self::WRAPPER_BUSY_TIMEOUT_MS / 1000,
                \PDO::ATTR_ERRMODE => \PDO::ERRMODE_EXCEPTION,
            ],
        ]);
        $connection->executeStatement("PRAGMA journal_mode = WAL;");
        $connection->executeStatement("PRAGMA busy_timeout = " . self::WRAPPER_BUSY_TIMEOUT_MS . ";");
        return $connection;
    }

    /**
     * Get a Doctrine DBAL connection to the personality database.
     *
     * The connection includes a Unicode-aware LOWER() function override for proper
     * case-insensitive matching across UTF-8 characters.
     *
     * @return Connection An open DBAL connection to personality.db
     * @throws \RuntimeException When the personality database file does not exist
     */
    public function getPersonalityConnection(): Connection
    {
        if (!file_exists($this->personalityDbPath)) {
            throw new \RuntimeException("Personality database not found: {$this->personalityDbPath}!");
        }
        $connection = DriverManager::getConnection([
            'driver'        => 'pdo_sqlite',
            'path'          => $this->personalityDbPath,
            'driverOptions' => [
                \PDO::ATTR_TIMEOUT => self::PERSONALITY_BUSY_TIMEOUT_SECONDS,
                \PDO::ATTR_ERRMODE => \PDO::ERRMODE_EXCEPTION,
            ],
        ]);
        $connection->executeStatement("PRAGMA journal_mode = WAL;");
        $connection->executeStatement("PRAGMA busy_timeout = " . (self::PERSONALITY_BUSY_TIMEOUT_SECONDS * 1000) . ";");

        // Register Unicode-aware LOWER() function
        $nativeConnection = $connection->getNativeConnection();
        if ($nativeConnection instanceof \PDO) {
            $nativeConnection->sqliteCreateFunction(
                'lower',
                static function (?string $value): ?string {
                    return ($value === null) ? null : mb_strtolower($value, 'UTF-8');
                },
                1,
                self::SQLITE_DETERMINISTIC_FLAG
            );
        }
        return $connection;
    }

    /**
     * Escape LIKE wildcards in a search term.
     *
     * @param string $term The search term to escape
     * @return string The term with LIKE special characters escaped
     */
    public function escapeLikeWildcards(string $term): string
    {
        $escapeChar = self::SQLITE_LIKE_ESCAPE_CHAR;
        return str_replace(
            [$escapeChar, '%', '_'],
            ["{$escapeChar}{$escapeChar}", "{$escapeChar}%", "{$escapeChar}_"],
            $term
        );
    }

    /**
     * Get the LIKE escape character as a SQL string literal.
     *
     * @return string The escape character quoted as a SQL string literal
     */
    public function getLikeEscapeLiteral(): string
    {
        return "'" . self::SQLITE_LIKE_ESCAPE_CHAR . "'";
    }
}
