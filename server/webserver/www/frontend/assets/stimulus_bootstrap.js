/**
 * Stimulus framework bootstrap module.
 *
 * Initializes the Stimulus application and provides a registry for custom and third-party controllers. This is the standard Symfony Stimulus bundle entry point.
 *
 * @module stimulus_bootstrap
 */
import { startStimulusApp } from '@symfony/stimulus-bundle';

const app = startStimulusApp();
// register any custom, 3rd party controllers here
// app.register('some_controller_name', SomeImportedController);
