#!/usr/bin/env bash
# Shared DerivedData path validation for the host simulator gate.

mt_canonical_derived_data_path() {
  local path="${1:-}"
  local base
  local canonical
  local parent

  case "$path" in
    /*) ;;
    *)
      echo "DerivedData path must be absolute: $path" >&2
      return 1
      ;;
  esac

  if [ -e "$path" ] || [ -L "$path" ]; then
    canonical="$(realpath "$path")" || {
      echo "cannot resolve DerivedData path: $path" >&2
      return 1
    }
  else
    base="${path##*/}"
    parent="${path%/*}"
    [ -n "$parent" ] || parent="/"
    case "$base" in
      ""|.|..)
        echo "DerivedData path has an invalid terminal component: $path" >&2
        return 1
        ;;
    esac
    [ -d "$parent" ] || {
      echo "DerivedData parent does not exist: $parent" >&2
      return 1
    }
    parent="$(realpath "$parent")" || {
      echo "cannot resolve DerivedData parent: $path" >&2
      return 1
    }
    case "$parent" in
      /) canonical="/$base" ;;
      *) canonical="$parent/$base" ;;
    esac
  fi

  case "$canonical" in
    /*) printf '%s\n' "$canonical" ;;
    *)
      echo "DerivedData path did not resolve absolutely: $path" >&2
      return 1
      ;;
  esac
}

mt_refuse_tmp_derived_data() {
  local canonical
  local path="${1:-}"
  local prefix="${2:-}"

  canonical="$(mt_canonical_derived_data_path "$path")" || {
    echo "$prefix refused: cannot resolve DerivedData path: $path (#612)" >&2
    return 1
  }
  # Load-bearing: these lower-case canonical patterns rely on realpath above
  # normalizing case aliases and filesystem symlinks (including /tmp and
  # /var/tmp). Any replacement canonicalizer must preserve that behavior or a
  # case-only alias silently bypasses the temporary-root guard.
  case "$canonical/" in
    /private/tmp/|/private/tmp/*|\
    /private/var/tmp/|/private/var/tmp/*|\
    /private/var/folders/*/T/|/private/var/folders/*/T/*)
      echo "$prefix refused: DerivedData path resolves under system-managed temporary storage; use \$HOME/Library/Caches/making-tracks-gates/<seat> (#612)" >&2
      return 1
      ;;
  esac
  printf '%s\n' "$canonical"
}
