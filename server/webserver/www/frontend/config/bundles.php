<?php

/**
 * Symfony Bundle Configuration.
 *
 * Registers all bundles (plugins) that extend the Symfony application. Each bundle provides specific functionality:
 * - FrameworkBundle: Core Symfony framework features
 * - TwigBundle: Templating engine support
 * - SecurityBundle: Authentication and authorization
 * - DoctrineBundle: Database ORM support
 * - StimulusBundle: JavaScript controller integration
 * - TurboBundle: SPA-like navigation without full page reloads
 * - WebProfilerBundle: Development debugging tools (dev environment)
 * - MakerBundle: Code generation utilities (dev environment)
 * - MonologBundle: Logging support
 * - TwigExtraBundle: Additional Twig extensions
 *
 * @see https://symfony.com/doc/current/bundles.html
 */
return [
    Symfony\Bundle\FrameworkBundle\FrameworkBundle::class => ['all' => true],
    Doctrine\Bundle\DoctrineBundle\DoctrineBundle::class => ['all' => true],
    Doctrine\Bundle\MigrationsBundle\DoctrineMigrationsBundle::class => ['all' => true],
    Symfony\Bundle\DebugBundle\DebugBundle::class => ['dev' => true],
    Symfony\Bundle\TwigBundle\TwigBundle::class => ['all' => true],
    Symfony\Bundle\WebProfilerBundle\WebProfilerBundle::class => ['dev' => true, 'test' => true],
    Symfony\UX\StimulusBundle\StimulusBundle::class => ['all' => true],
    Symfony\UX\Turbo\TurboBundle::class => ['all' => true],
    Twig\Extra\TwigExtraBundle\TwigExtraBundle::class => ['all' => true],
    Symfony\Bundle\SecurityBundle\SecurityBundle::class => ['all' => true],
    Symfony\Bundle\MonologBundle\MonologBundle::class => ['all' => true],
    Symfony\Bundle\MakerBundle\MakerBundle::class => ['dev' => true],
];
