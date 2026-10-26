#!/usr/bin/env bash
# End-to-end smoke test for all nine tools. Uses a throwaway sample repo and data dirs; touches nothing else.
#   bash tests/smoke.sh
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export LOGBOOK_DIR=$T/logbook RBH_DIR=$T/rbh RW_CTX=$T/ctx
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
for t in proofpack scopesmith handoff envguard logbook clientcast pulse rbh datamorph; do export PATH="$ROOT/$t/bin:$PATH"; done
pass=0 fail=0
ok()   { echo "  ok    $1"; pass=$((pass + 1)); }
bad()  { echo "  FAIL  $1"; fail=$((fail + 1)); }
check() { local name=$1; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi; }
has()  { grep -q -- "$2" "$1"; }

echo "== building sample repo in $T/app"
APP=$T/app
mkdir -p "$APP/bin" "$APP/tests"
cd "$APP"
git init -q -b main
cat > README.md <<'EOF'
# Sample App

A tiny command-line app used to exercise the Reworkio tools end to end.
EOF
cat > bin/app <<'EOF'
#!/usr/bin/env python3
print("hello")
EOF
chmod +x bin/app
cat > tests/test_app.py <<'EOF'
import unittest
class T(unittest.TestCase):
    def test_ok(self):
        self.assertEqual(1 + 1, 2)
EOF
printf 'PORT=3000\nDEBUG=true\nDATABASE_URL=postgres://app:s3cretpass@db:5432/app\nAPI_KEY=abcd1234efgh5678ijkl\n' > .env
printf '.env\n__pycache__/\n' > .gitignore
git add -A && git commit -qm "feat: initial app"
echo "x = 1" > app.py && git add app.py && git commit -qm "fix(core): handle empty input"
git commit -q --allow-empty -m "docs: add usage notes"

echo "== proofpack"
proofpack "$APP" --json > "$T/proof.json"; rc=$?
check "exit 0 with passing tests" test $rc -eq 0
check "proof.json has 3 commits" python3 -c "import json,sys; d=json.load(open('$T/proof.json')); sys.exit(d['commits']['total']!=3)"
check "tests detected and passed" python3 -c "import json,sys; d=json.load(open('$T/proof.json')); sys.exit(not d['tests']['passed'])"
check "case-study.md written" has "$APP/proof/case-study.md" "## Verify it yourself"
check "badge written" has "$APP/proof/badge-tests.svg" "passing"
H1=$(git -C "$APP" archive --format=tar HEAD | sha256sum | cut -d' ' -f1)
check "checksum matches git archive" python3 -c "import json,sys; sys.exit(json.load(open('$T/proof.json'))['checksum']['sha256']!='$H1')"
echo "proof/" >> "$APP/.gitignore"; git -C "$APP" add .gitignore; git -C "$APP" commit -qm "chore: ignore proof output"

echo "== scopesmith"
scopesmith "$ROOT/examples/brief-acme.txt" --client "Acme Yoga" --out "$T/scope" --json > "$T/scope.json"
check "9 deliverables (7 bullets + hosting + training)" python3 -c "import json,sys; sys.exit(len(json.load(open('$T/scope.json'))['items'])!=9)"
check "payments categorised" python3 -c "import json,sys; d=json.load(open('$T/scope.json')); sys.exit('payments' not in [i['category'] for i in d['items']])"
check "deadline detected" python3 -c "import json,sys; sys.exit(json.load(open('$T/scope.json'))['detected']['deadline'] is None)"
check "sow.md written" has "$T/scope/sow.md" "## Milestones and payments"
echo "Build a dashboard with login. Must send email alerts." | scopesmith scope.plan > "$T/cap.json"
check "capability mode reads stdin" python3 -c "import json,sys; sys.exit(len(json.load(open('$T/cap.json'))['items'])<2)"

echo "== envguard"
cd "$APP"
envguard all "$APP" --json > "$T/eg1.json"; rc=$?
check "clean repo passes (untracked .env ignored)" test $rc -eq 0
printf 'aws_key = "AKIAIOSFODNN7EXAMPLE"\n' > leak.py
printf 'password = "Zx9!kq2Lm8vB"\n' >> leak.py
git add leak.py
envguard scan --staged "$APP" --json > "$T/eg2.json"; rc=$?
check "staged AWS key blocks (exit 1)" test $rc -eq 1
check "generic secret flagged" python3 -c "import json,sys; d=json.load(open('$T/eg2.json')); sys.exit('generic-secret-assignment' not in [f['rule'] for f in d['scan']['findings']])"
check "secret is masked" bash -c "! grep -q 'IOSFODNN7EXAMPLE' $T/eg2.json"
git reset -q leak.py && rm leak.py
envguard init-schema "$APP" >/dev/null
check ".env.schema drafted" has "$APP/.env.schema" "PORT"
sed -i 's/^PORT=3000/PORT=abc/' .env
envguard schema "$APP" --json > "$T/eg3.json"; rc=$?
check "bad PORT type fails schema" test $rc -eq 1
sed -i 's/^PORT=abc/PORT=3000/' .env
envguard install-hook "$APP" >/dev/null
check "pre-commit hook installed" has "$APP/.git/hooks/pre-commit" "envguard"
printf 'token = "ghp_%s"\n' "$(printf 'a%.0s' {1..36})" > leak2.py
git add leak2.py
if git commit -qm "oops" >/dev/null 2>&1; then bad "hook blocks a GitHub token commit"; else ok "hook blocks a GitHub token commit"; fi
git reset -q leak2.py && rm leak2.py

echo "== handoff"
handoff check "$APP" --json > "$T/h1.json"; rc=$?
check "check fails without .env.example" test $rc -eq 1
handoff env "$APP" >/dev/null
check ".env.example strips secrets" bash -c "grep -q '^API_KEY=$' $APP/.env.example && grep -q '^PORT=3000$' $APP/.env.example"
handoff runbook "$APP" --client "Acme" >/dev/null
check "HANDOFF.md has secrets checklist" has "$APP/HANDOFF.md" "Secrets checklist"
git add -A && git commit -qm "docs: handoff files" && git tag v1.0.0
handoff check "$APP" >/dev/null; rc=$?
check "check passes after fixes" test $rc -eq 0
handoff package "$APP" --client Acme --out "$T/dist" --json > "$T/pkg.json"
check "archive created" python3 -c "import json,os,sys; sys.exit(not os.path.isfile(json.load(open('$T/pkg.json'))['archive']))"
check "archive excludes .env" bash -c "! tar tzf $T/dist/*.tar.gz | grep -E '/\.env$'"
check "archive has SHA256SUMS" bash -c "tar tzf $T/dist/*.tar.gz | grep -q SHA256SUMS"
mkdir -p "$T/client" && echo "CLIENT_SECRET=keep" > "$T/client/.env" && echo old > "$T/client/stale.txt"
handoff sync "$APP" "$T/client" --json > "$T/s1.json"
check "dry run changes nothing" test ! -e "$T/client/README.md"
handoff sync "$APP" "$T/client" --apply >/dev/null
check "apply copies files" test -f "$T/client/README.md"
check "apply deletes stale files" test ! -e "$T/client/stale.txt"
check "client .env untouched" has "$T/client/.env" "CLIENT_SECRET=keep"

echo "== logbook"
mkdir -p "$LOGBOOK_DIR"
now=$(date +%s)
{ for i in 0 300 600 900 1200; do printf '%s\t%s\t\n' $((now - 7200 + i)) "$APP"; done
  printf '%s\t%s\tonboarded\n' $((now - 600)) /tmp; } > "$LOGBOOK_DIR/events.tsv"
logbook map "$APP" sample-app >/dev/null
logbook report --since 1d --rate 100 --json > "$T/lb.json"
check "sample-app session = 25 min -> 0.5 h" python3 -c "import json,sys; d={p['project']:p['hours'] for p in json.load(open('$T/lb.json'))['projects']}; sys.exit(d.get('sample-app')!=0.5)"
check "rw tool attribution" python3 -c "import json,sys; d={p['project']:p['hours'] for p in json.load(open('$T/lb.json'))['projects']}; sys.exit('onboarded' not in d)"
logbook add sample-app 1.5 --note "kickoff call" >/dev/null
logbook csv --since 1d --rate 100 --out "$T/inv.csv" 2>/dev/null
check "csv total includes manual hours" has "$T/inv.csv" "TOTAL,,2.10"
logbook hook > "$T/hook.zsh"
check "hook prints add-zsh-hook" has "$T/hook.zsh" "add-zsh-hook preexec"

echo "== clientcast"
logbook report --since 1d --json --project sample-app | clientcast "$APP" --client "Acme Yoga" --project sample-app --hours - --next "Stripe checkout" --json > "$T/cc.json"
check "commits grouped (Shipped/Fixed)" python3 -c "import json,sys; d=json.load(open('$T/cc.json')); sys.exit(not ({'Shipped','Fixed'} <= set(d['sections'])))"
check "hours included" python3 -c "import json,sys; sys.exit(json.load(open('$T/cc.json'))['hours']['hours']!=2.0)"
check "markdown has Next up" python3 -c "import json,sys; sys.exit('Next up' not in json.load(open('$T/cc.json'))['markdown'])"

echo "== pulse"
mkdir -p "$T/pulse" && cd "$T/pulse"
python3 -m http.server 18765 --bind 127.0.0.1 >/dev/null 2>&1 & SRV=$!
sleep 1
cat > pulse.json <<EOF
{"title": "Smoke status", "checks": [
  {"name": "local web", "type": "http", "url": "http://127.0.0.1:18765/", "contains": "Directory listing"},
  {"name": "closed port", "type": "tcp", "host": "127.0.0.1", "port": 18766, "timeout": 1},
  {"name": "disk", "type": "disk", "path": "/", "max_percent": 99.9},
  {"name": "command", "type": "command", "command": "true"}]}
EOF
pulse check --json > "$T/p1.json"; rc=$?
check "exit 1 when a check is down" test $rc -eq 1
check "http check up" python3 -c "import json,sys; r={x['name']:x['up'] for x in json.load(open('$T/p1.json'))['results']}; sys.exit(not r['local web'])"
check "closed port down" python3 -c "import json,sys; r={x['name']:x['up'] for x in json.load(open('$T/p1.json'))['results']}; sys.exit(r['closed port'])"
pulse page >/dev/null
check "status page rendered" has "$T/pulse/.pulse/site/index.html" "Some systems are degraded"
kill $SRV 2>/dev/null
pulse unit > "$T/unit.txt"
check "systemd unit printed" has "$T/unit.txt" "OnUnitActiveSec=60"

echo "== rbh"
mkdir -p "$RBH_DIR/sessions"
rbh start nginx-setup --title "Set up nginx on the Pi" >/dev/null
check "start creates active marker" test -f "$RBH_DIR/active"
s=$(date +%s)
{ printf '%s\t0\t0\t%s\tls -la\n' $s "$HOME"
  printf '%s\t0\t42\t%s\tsudo apt install -y nginx\n' $s "$HOME"
  printf '%s\t100\t1\t%s\tsudo systemctl strat nginx\n' $s "$HOME"
  printf '%s\t0\t0\t%s\trbh note "Configure the site"\n' $s "$HOME"
  printf '%s\t0\t1\t/etc/nginx\tsudo systemctl start nginx\n' $s
  printf '%s\t0\t1\t/etc/nginx\tsudo systemctl start nginx\n' $s
  printf '%s\t0\t0\t/etc/nginx\tcurl -u admin --password hunter22 http://localhost\n' $s
  printf '%s\t0\t0\t/etc/nginx\tcat > /tmp/site.conf <<EOF\\nserver { listen 80; }\\nEOF\n' $s
} > "$RBH_DIR/sessions/nginx-setup.tsv"
rbh stop > /dev/null
R=$RBH_DIR/runbooks/nginx-setup.md
check "runbook rendered" test -f "$R"
check "failed typo dropped" bash -c "! grep -q 'strat' $R"
check "noise (ls) dropped" bash -c "! grep -q 'ls -la' $R"
check "duplicate dropped" test "$(grep -c 'systemctl start nginx' "$R")" -eq 1
check "section heading from note" has "$R" "## Configure the site"
check "password masked" bash -c "grep -q 'password <REDACTED>' $R && ! grep -q hunter22 $R"
check "heredoc kept multi-line" has "$RBH_DIR/runbooks/nginx-setup.sh" "server { listen 80; }"
check "script has strict mode" has "$RBH_DIR/runbooks/nginx-setup.sh" "set -euo pipefail"
check "script is valid bash" bash -n "$RBH_DIR/runbooks/nginx-setup.sh"
rbh hook > "$T/rbh.zsh"
check "hook prints precmd" has "$T/rbh.zsh" "add-zsh-hook precmd"

echo "== datamorph"
D=$ROOT/examples/customers.csv
datamorph "$D" --trim --dedupe --cast price:float,signup_date:date --validate email:required,email:email --reject "$T/bad.csv" --sort price:desc --to json > "$T/dm.json" 2>/dev/null
check "dedupe + validate leave 4 rows" python3 -c "import json,sys; sys.exit(len(json.load(open('$T/dm.json')))!=4)"
check "dates normalised" python3 -c "import json,sys; d=json.load(open('$T/dm.json')); sys.exit(any(not r['signup_date'][:4].isdigit() for r in d))"
check "sorted by price desc" python3 -c "import json,sys; d=json.load(open('$T/dm.json')); sys.exit(d[0]['price']!=899.0)"
check "2 rejected rows written" test "$(($(wc -l < "$T/bad.csv") - 1))" -eq 2
datamorph "$D" --trim --dedupe --filter 'plan in monthly,annual' --derive 'yearly=price*12' --select name,plan,yearly --save-recipe "$T/r.json" --to md > "$T/dm.md" 2>/dev/null
check "recipe saved" has "$T/r.json" '"derive"'
datamorph "$D" --recipe "$T/r.json" --to md > "$T/dm2.md" 2>/dev/null
check "recipe replays identically" cmp -s "$T/dm.md" "$T/dm2.md"
check "derived column computed" has "$T/dm.md" "1068"
cat "$D" | datamorph data.transform --trim --stats > "$T/st.json"
check "capability mode + stats" has "$T/st.json" '"rows": 7'

echo
echo "passed $pass, failed $fail"
[[ $fail -eq 0 ]]
