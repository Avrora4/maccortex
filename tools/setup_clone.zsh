#!/usr/bin/env zsh
# setup_clone.zsh <machine-id>
# Run once per clone. `git clone` transfers neither hooks nor local config, so
# each machine (m3air16, m4air32) must run this right after cloning.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

machine="${1:-$(git config --get maccortex.machine || true)}"
case "$machine" in
  m3air16|m4air32) ;;   # machine IDs are fixed; adding one requires an ADR
  *) print -u2 "usage: $0 <m3air16|m4air32>"; exit 1 ;;
esac

chmod +x .githooks/* tools/*.zsh
git config core.hooksPath .githooks                  # enforce repository rules
git config blame.ignoreRevsFile .git-blame-ignore-revs
git config pull.rebase true                          # two machines, one linear history
git config rebase.autoStash true
git config fetch.prune true
git config maccortex.machine "$machine"              # read by tools/bench_context.zsh

# Both machines must commit under the same identity (ADR-0004). The address is
# public by choice: it is already visible in the author's other repositories.
expected_email="asagiprog@gmail.com"
email=$(git config --get user.email || true)
if [[ "$email" != "$expected_email" ]]; then
  print -u2 "⚠ user.email is '$email', expected '$expected_email'"
  print -u2 "  fix: git config --global user.email \"$expected_email\""
fi

print "✓ ${machine}: hooks=$(git config core.hooksPath), author=$(git config user.name) <${email}>"
