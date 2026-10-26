# rw combo weekly-update <repo> <client> [logbook-project]
# Logbook hours for the last 7 days -> Clientcast update written to weekly-update.md (not sent).
combo() {
  setopt localoptions pipefail
  local repo=${1:?usage: rw combo weekly-update <repo> <client> [project]} client=${2:?client name}
  local project=${3:-${${1:A}:t}}
  rw do time.report --since 7d --project $project \
    | rw run clientcast $repo --client $client --project $project --hours - --out weekly-update.md
}
