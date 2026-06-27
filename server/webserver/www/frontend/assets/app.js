/**
 * Main JavaScript entry point for the chatbot application.
 *
 * This module serves as the primary entry point for the frontend JavaScript bundle. It imports the Stimulus bootstrap and application styles, then initializes the chat client functionality.
 *
 * Import chain:
 * - stimulus_bootstrap.js - Stimulus controller registration
 * - styles/app.css - Application stylesheet
 *
 * @module app
 */
import './stimulus_bootstrap.js';
/*
 * Welcome to your app's main JavaScript file!
 *
 * This file will be included onto the page via the importmap() Twig function,
 * which should already be in your base.html.twig.
 */
import './styles/app.css';

console.log('This log comes from assets/app.js - welcome to AssetMapper! 🎉');
