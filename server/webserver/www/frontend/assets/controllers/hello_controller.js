/**
 * Hello Stimulus Controller.
 *
 * This is an example Stimulus controller that demonstrates the basic controller structure. Any element with a data-controller="hello" attribute will cause this controller to be executed.
 *
 * The controller name "hello" is derived from the filename:
 * hello_controller.js → "hello"
 *
 * @example
 * // HTML usage:
 * // <div data-controller="hello"></div>
 *
 * @module hello_controller
 */
import { Controller } from '@hotwired/stimulus';

export default class extends Controller {

    /**
     * Called when the controller is connected to the DOM element. Sets the element's text content to a greeting message.
     * @returns {void} - no return value.
     */
    connect() {
        this.element.textContent = 'Hello Stimulus! Edit me in assets/controllers/hello_controller.js';
    }
}
