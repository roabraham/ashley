<?php

use Symfony\Component\Dotenv\Dotenv;

/**
 * PHPUnit test bootstrap file.
 *
 * Initializes the Symfony environment and loads environment variables for testing. This file is automatically loaded by PHPUnit before running test suites.
 */

// Load Composer autoloader for all project dependencies.
require dirname(__DIR__).'/vendor/autoload.php';

// Boot the Symfony Dotenv component to load environment variables from .env file.
if (method_exists(Dotenv::class, 'bootEnv')) {
    (new Dotenv())->bootEnv(dirname(__DIR__).'/.env');
}

// Set a permissive umask in debug mode for file permission consistency.
if ($_SERVER['APP_DEBUG']) {
    umask(0000);
}
