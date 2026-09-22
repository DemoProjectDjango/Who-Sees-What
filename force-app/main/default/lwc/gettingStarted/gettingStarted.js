import { LightningElement } from 'lwc';

/**
 * Tab-level shell for onboarding.
 *
 * This content used to live inline in Permission Explorer's WHERE column,
 * shown only while no user was selected — so it disappeared the moment you
 * needed it again mid-session, and cost the WHERE column real height (see
 * peAppColumn.css) for content most people read once. It now has its own
 * tab; Permission Explorer's WHERE column just points here in its empty
 * state instead of carrying the full copy.
 *
 * All the actual content and the Setup deep links live in c-pe-getting-
 * started, reused as-is rather than duplicated.
 */
export default class GettingStarted extends LightningElement {}
