#!/usr/bin/env bash
# Move, rename or copy secrets in a Vault KV v2 engine.
# Run `hack/vault-kv-mv.sh --help` for usage.
set -euo pipefail

usage() {
  cat <<'EOF'
Move, rename or copy secrets in a Vault KV v2 engine.

Usage:
  hack/vault-kv-mv.sh [options] SRC DST
  hack/vault-kv-mv.sh [options] -f FILE

Paths are relative to the mount, e.g. framsburg/hermes (not secret/data/...).
A SRC ending in "/" is a folder: every secret below it moves to DST/, keeping
the layout. With -r, SRC is the secret itself plus the folder of the same name.

Each secret is copied (latest version and custom metadata), read back and
compared, and only then removed from SRC. Nothing is written until all
destinations have been checked for conflicts.

Options:
  -m, --mount MOUNT  KV v2 mount (default: secret)
  -c, --copy         keep SRC (default: move)
  -r, --recursive    also move the folder SRC/ (implied by a trailing "/")
      --purge        remove SRC with all versions and metadata
                     (default: soft-delete the latest version, which
                     `vault kv undelete` can restore)
      --force        overwrite an existing DST
  -n, --dry-run      print the plan and stop
  -y, --yes          do not ask for confirmation
  -f, --file FILE    read "SRC DST" pairs from FILE, one per line
                     ("#" comments and blank lines are ignored)
  -h, --help         show this help

Only the latest version is copied; the version history stays with SRC.
Secret values are never printed.

Needs vault and jq, VAULT_ADDR, and a token with read/list on SRC, write on
DST and delete on SRC (e.g. `vault login -method=oidc`).

Examples:
  # rename one secret
  hack/vault-kv-mv.sh framsburg/hermes framsburg/test/hermes
  # move a folder, keep the old one until the apps are switched over
  hack/vault-kv-mv.sh --copy framsburg/paperless/ framsburg/test/paperless/
  # several moves from a file, preview only
  hack/vault-kv-mv.sh -n -f moves.txt
EOF
}

die() { echo "error: $*" >&2; exit 1; }
log() { echo "$*" >&2; }

mount=secret copy=false recursive=false purge=false force=false dry_run=false yes=false file=""
args=()
while [ $# -gt 0 ]; do
  case "$1" in
    -m|--mount) [ $# -ge 2 ] || die "$1 needs a value"; mount=$2; shift 2 ;;
    -c|--copy) copy=true; shift ;;
    -r|--recursive) recursive=true; shift ;;
    --purge) purge=true; shift ;;
    --force) force=true; shift ;;
    -n|--dry-run) dry_run=true; shift ;;
    -y|--yes) yes=true; shift ;;
    -f|--file) [ $# -ge 2 ] || die "$1 needs a value"; file=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; args+=("$@"); break ;;
    -*) die "unknown option $1 (see --help)" ;;
    *) args+=("$1"); shift ;;
  esac
done

pairs=()
if [ -n "$file" ]; then
  [ ${#args[@]} -eq 0 ] || die "use either -f FILE or SRC DST, not both"
  [ -r "$file" ] || die "cannot read $file"
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%%#*}
    read -r s d extra <<<"$line" || true
    [ -z "${s:-}" ] && continue
    [ -n "${d:-}" ] && [ -z "${extra:-}" ] || die "$file: expected 'SRC DST', got: $line"
    pairs+=("$s" "$d")
  done <"$file"
  [ ${#pairs[@]} -gt 0 ] || die "$file contains no moves"
else
  [ ${#args[@]} -eq 2 ] || { usage >&2; exit 1; }
  pairs=("${args[0]}" "${args[1]}")
fi

command -v vault >/dev/null || die "vault CLI not found"
command -v jq >/dev/null || die "jq not found"
[ -n "${VAULT_ADDR:-}" ] || die "VAULT_ADDR is not set"
vault token lookup >/dev/null 2>&1 || die "no valid Vault token (vault login -method=oidc)"

# Normalise a path: no leading "/", no "<mount>/" or "<mount>/data/" prefix.
norm() {
  local p=${1#/}
  p=${p#"$mount"/data/}
  p=${p#"$mount"/}
  printf '%s' "$p"
}

# Latest version of a secret as compact JSON, or fail if it doesn't exist (or is deleted).
read_data() { vault kv get -format=json -mount="$mount" "$1" 2>/dev/null | jq -ce '.data.data // empty'; }
exists() { read_data "$1" >/dev/null 2>&1; }

# All secrets below folder $1 (with trailing "/"), as paths relative to the mount.
walk() {
  local dir=$1 entry entries
  entries=$(vault kv list -format=json -mount="$mount" "$dir" 2>/dev/null | jq -r '.[]') || return 0
  while IFS= read -r entry; do
    case "$entry" in
      "") ;;
      */) walk "$dir$entry" ;;
      *) printf '%s\n' "$dir$entry" ;;
    esac
  done <<<"$entries"
}

# Expand the requested moves into "src dst" pairs of single secrets.
plan_src=() plan_dst=()
add() { plan_src+=("$1"); plan_dst+=("$2"); }
i=0
while [ $i -lt ${#pairs[@]} ]; do
  src=$(norm "${pairs[$i]}") dst=$(norm "${pairs[$((i + 1))]}")
  i=$((i + 2))
  [ -n "$src" ] && [ -n "$dst" ] || die "empty path in '${pairs[$((i - 2))]} ${pairs[$((i - 1))]}'"
  if [ "${src%/}" != "$src" ]; then
    folder=true
    src=${src%/} dst=${dst%/}
  else
    folder=$recursive
    dst=${dst%/}
    if exists "$src"; then add "$src" "$dst"; elif [ "$folder" = false ]; then die "$src: no such secret (use a trailing / for a folder)"; fi
  fi
  if [ "$folder" = true ]; then
    found=$(walk "$src/")
    [ -n "$found" ] || [ "$recursive" = true ] || die "$src/: folder is empty or does not exist"
    while IFS= read -r s; do
      [ -n "$s" ] && add "$s" "$dst/${s#"$src"/}"
    done <<<"$found"
  fi
done
[ ${#plan_src[@]} -gt 0 ] || die "nothing to move"

# Check the whole plan before writing anything.
problems=0
for ((n = 0; n < ${#plan_src[@]}; n++)); do
  s=${plan_src[$n]} d=${plan_dst[$n]}
  if [ "$s" = "$d" ]; then log "conflict: $s -> itself"; problems=$((problems + 1)); fi
  for ((m = 0; m < n; m++)); do
    if [ "${plan_dst[$m]}" = "$d" ]; then log "conflict: $d is the target of $s and ${plan_src[$m]}"; problems=$((problems + 1)); fi
  done
  if [ "$force" = false ] && exists "$d"; then log "conflict: $d already exists (--force to overwrite)"; problems=$((problems + 1)); fi
done
[ $problems -eq 0 ] || die "$problems conflict(s), nothing changed"

if [ "$copy" = true ]; then action=copy; elif [ "$purge" = true ]; then action="move (purge source)"; else action="move (soft-delete source)"; fi
log "Vault: $VAULT_ADDR  mount: $mount  action: $action"
for ((n = 0; n < ${#plan_src[@]}; n++)); do log "  ${plan_src[$n]}  ->  ${plan_dst[$n]}"; done
log "${#plan_src[@]} secret(s)"

if [ "$dry_run" = true ]; then log "dry run, nothing changed"; exit 0; fi
if [ "$yes" = false ]; then
  [ -t 0 ] || die "not a terminal; pass --yes to proceed without confirmation"
  read -r -p "Proceed? [y/N] " answer
  case "$answer" in y|Y|yes) ;; *) die "aborted, nothing changed" ;; esac
fi

done_count=0
for ((n = 0; n < ${#plan_src[@]}; n++)); do
  s=${plan_src[$n]} d=${plan_dst[$n]}
  data=$(read_data "$s") || die "$s: read failed ($done_count of ${#plan_src[@]} done)"
  printf '%s' "$data" | vault kv put -mount="$mount" "$d" - >/dev/null ||
    die "$d: write failed ($done_count of ${#plan_src[@]} done; $s untouched)"

  custom=$(vault kv metadata get -format=json -mount="$mount" "$s" 2>/dev/null | jq -r '.data.custom_metadata // {} | to_entries[] | "\(.key)=\(.value)"') || custom=""
  if [ -n "$custom" ]; then
    meta_args=()
    while IFS= read -r kv; do meta_args+=("-custom-metadata=$kv"); done <<<"$custom"
    vault kv metadata put -mount="$mount" "${meta_args[@]}" "$d" >/dev/null ||
      die "$d: custom metadata copy failed ($done_count of ${#plan_src[@]} done; $s untouched)"
  fi

  copied=$(read_data "$d") || die "$d: read-back failed ($s untouched)"
  [ "$(jq -S . <<<"$data")" = "$(jq -S . <<<"$copied")" ] || die "$d: read-back differs from $s ($s untouched)"

  if [ "$copy" = false ]; then
    if [ "$purge" = true ]; then
      vault kv metadata delete -mount="$mount" "$s" >/dev/null || die "$s: purge failed (copy at $d is complete)"
    else
      vault kv delete -mount="$mount" "$s" >/dev/null || die "$s: delete failed (copy at $d is complete)"
    fi
  fi
  done_count=$((done_count + 1))
  log "ok  $s -> $d"
done
log "done: ${#plan_src[@]} secret(s), $action"
