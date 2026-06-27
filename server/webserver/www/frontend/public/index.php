<?php

use App\Kernel;

/**
 * Frontend application entry point.
 * Creates and returns the Symfony Kernel instance for each HTTP request. This file is the bootstrap for the web application and handles environment configuration through the runtime context array.
 * @param array $context Runtime context containing APP_ENV and APP_DEBUG keys.
 * @return Kernel The configured Symfony kernel instance.
 */
require_once dirname(__DIR__).'/vendor/autoload_runtime.php';

return static function (array $context) {
    return new Kernel($context['APP_ENV'], (bool) $context['APP_DEBUG']);
};
