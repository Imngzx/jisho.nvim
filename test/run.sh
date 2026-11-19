#!/usr/bin/env bash
# Run every spec (or the ones given) in its own clean, offline Neovim.
#   test/run.sh                      # all specs
#   test/run.sh test/search_spec.lua # some specs
# The cache goes to a throwaway XDG_CACHE_HOME: the real
# ~/.cache/nvim/jisho_cache.json is never touched.
set -u
cd "$(dirname "$0")/.."

specs=("$@")
[ ${#specs[@]} -eq 0 ] && specs=(test/*_spec.lua)

fail=0
for spec in "${specs[@]}"; do
  echo "$spec"
  tmp=$(mktemp -d)
  # -c is used instead of -l: an error in the spec file must not be
  # swallowed, so a load failure exits through `cquit`.
  XDG_CACHE_HOME="$tmp" timeout 60 nvim --headless -u NONE -i NONE --cmd 'set rtp^=.' \
    -c 'runtime plugin/jisho.lua' \
    -c "lua local ok, err = pcall(dofile, '$spec'); if not ok then io.stdout:write('  LOAD FAIL ', tostring(err), '\n'); vim.cmd('cquit! 1') end" \
    </dev/null || fail=1
  rm -rf "$tmp"
done

[ $fail -eq 0 ] && echo "all specs passed" || echo "SOME SPECS FAILED"
exit $fail
