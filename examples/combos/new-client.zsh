# rw combo new-client <brief-file> <client name>
# Brief -> scope + SOW draft; the scope JSON is shared with other tools on the context bus.
combo() {
  setopt localoptions pipefail
  local brief=${1:?usage: rw combo new-client <brief-file> <client>} client=${2:?client name}
  local out="scope-${${client// /-}:l}"
  rw run scopesmith $brief --client "$client" --out $out --json | rw ctx set scope.plan
  print "SOW draft: $out/sow.md   (scope JSON: rw ctx get scope.plan)"
}
