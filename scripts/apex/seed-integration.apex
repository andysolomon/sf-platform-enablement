// Phase 5 seed (referenced by .gitlab-ci.yml SF_SEED_SCRIPT). Runs post-install in the
// staging scratch org. Emits one startup log so the install has visible, queryable activity.
Logger.info('frs-platform seed: environment ready', 'SEED-' + String.valueOf(System.now().getTime()));
