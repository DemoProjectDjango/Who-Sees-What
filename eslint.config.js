const eslintJs = require('@eslint/js');
const jestPlugin = require('eslint-plugin-jest');
const auraConfig = require('@salesforce/eslint-plugin-aura');
const lwcConfig = require('@salesforce/eslint-config-lwc/recommended');
const globals = require('globals');

const scopeConfigs = (configs, files) =>
    configs.map((config) => ({
        ...config,
        files
    }));

module.exports = [
    // Aura
    ...scopeConfigs(auraConfig.configs.recommended, ['**/aura/**/*.js']),
    ...scopeConfigs(auraConfig.configs.locker, ['**/aura/**/*.js']),

    // LWC
    ...scopeConfigs(lwcConfig, ['**/lwc/**/*.js']),

    // LWC Jest tests
    {
        files: ['**/lwc/**/*.test.js'],
        rules: {
            '@lwc/lwc/no-unexpected-wire-adapter-usages': 'off'
        },
        languageOptions: {
            globals: {
                ...globals.node
            }
        }
    },

    // Jest mocks
    {
        files: ['**/jest-mocks/**/*.js'],
        ...eslintJs.configs.recommended,
        languageOptions: {
            sourceType: 'module',
            ecmaVersion: 'latest',
            globals: {
                ...globals.node,
                ...globals.es2021,
                ...jestPlugin.environments.globals.globals
            }
        }
    }
];