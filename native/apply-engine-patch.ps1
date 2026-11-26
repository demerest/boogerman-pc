# Applies the Boogerman engine patches (boot-assist / lockstep / bus-ack / traces)
# to the vendored segagenesisrecomp submodule. Idempotent: skips if already applied.
# The submodule itself points at the public upstream base; these patches are the
# per-game engine work and live in THIS repo (never pushed to the upstream repo).
$ErrorActionPreference = 'Stop'
$git = 'C:\Program Files\Git\cmd\git.exe'
$root = 'S:\home\dev\boogerman-pc\native\segagenesisrecomp'
$diff = 'S:\home\dev\boogerman-pc\native\segagenesisrecomp.diff'

& $git -C $root apply --reverse --check $diff 2>$null
if ($LASTEXITCODE -eq 0) { "engine patch already applied" } else {
  & $git -C $root apply --check $diff
  if ($LASTEXITCODE -ne 0) { "engine patch does not apply cleanly (submodule moved?)"; exit 1 }
  & $git -C $root apply $diff
  "engine patch applied"
}

# s53: PEA+RTS computed-jump codegen fix lives in the NESTED m68k-recomp-core
# submodule (its gitlink must stay at the public base too), so it is carried
# as a second patch applied inside that checkout.
$core = "$root\external\m68k-recomp-core"
$cdiff = 'S:\home\dev\boogerman-pc\native\m68k-recomp-core-pea-rts.diff'
& $git -C $core apply --reverse --check $cdiff 2>$null
if ($LASTEXITCODE -eq 0) { "core codegen patch already applied"; exit 0 }
& $git -C $core apply --check $cdiff
if ($LASTEXITCODE -ne 0) { "core codegen patch does not apply cleanly (submodule moved?)"; exit 1 }
& $git -C $core apply $cdiff
"core codegen patch applied"
