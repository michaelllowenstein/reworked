# rw combo sync-onboarded [--apply]
# Mirror the Onboarded dev copy to the client copy. Dry run unless --apply; .env and .git are never touched.
combo() {
  rw run handoff sync ~/develop/integrations/onboarded ~/onboarded "$@"
}
