# rw combo ship-release [dir] [client]
# Security gate -> readiness check -> proof pack -> delivery package. Stops at the first failure.
combo() {
  setopt localoptions pipefail
  local dir=${1:-$PWD} client=${2:-}
  rw run envguard all $dir || { print -u2 'ship-release: fix the envguard findings first'; return 1; }
  rw run handoff check $dir || { print -u2 'ship-release: resolve the handoff blockers first'; return 1; }
  rw run proofpack $dir || return 1
  rw run handoff package $dir ${client:+--client} $client --json | rw ctx set deliver.package
  print "package details saved: rw ctx get deliver.package"
}
