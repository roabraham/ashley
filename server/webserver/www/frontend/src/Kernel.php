<?php

namespace App;

use Symfony\Bundle\FrameworkBundle\Kernel\MicroKernelTrait;
use Symfony\Component\HttpKernel\Kernel as BaseKernel;

/**
 * Application Kernel.
 * The main Symfony kernel for the frontend chatbot application. Uses MicroKernelTrait for a minimal, convention-based configuration.
 * Custom log directory is configured to point to the shared server log folder.
 */
class Kernel extends BaseKernel
{
    use MicroKernelTrait;

    /**
     * Returns the log directory path for this kernel instance.
     * The log directory is set to the shared server log folder, located four levels up from this file (src → frontend → webserver → server → log).
     * @return string The absolute filesystem path to the log directory.
     */
    public function getLogDir(): string { return dirname(__DIR__, 4) . '/log'; }
}
