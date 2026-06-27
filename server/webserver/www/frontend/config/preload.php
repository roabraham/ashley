<?php

/**
 * PHP Preloading Configuration.
 *
 * Loads the Symfony container preload file when it exists for improved performance in production environments. This file is automatically included by PHP's opcache.preload directive.
 *
 * @see https://www.php.net/manual/en/opcache.preloading.php
 */
if (file_exists(dirname(__DIR__).'/var/cache/prod/App_KernelProdContainer.preload.php')) {
    require dirname(__DIR__).'/var/cache/prod/App_KernelProdContainer.preload.php';
}
