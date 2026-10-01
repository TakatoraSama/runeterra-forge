# _env.sh — shared environment for the headless test scripts.
#
# Sourced (not executed) by run_tests.sh, offline_selftest.sh and
# lan_selftest.sh right after their `set -uo pipefail` line. It:
#   1. loads tools/local.env (per-machine settings, gitignored),
#   2. makes sure GNU coreutils `timeout` wins on Git Bash / MSYS / Cygwin,
#   3. provides fu_require_godot for the "is this a usable Godot binary" check.
#
# Precedence for G47/OUT: an already-exported environment variable wins over
# tools/local.env, which wins over the script default (the scripts still apply
# their own `G47="${G47:-…}"` defaults after sourcing this file).
#
# This file must stay POSIX sh compatible: on Windows the scripts are started
# with `sh` (Git Bash), because direct execution and WSL's bash both misbehave.

# Directory of this file, so this works from any cwd.
_FU_ENV_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)

# --- tools/local.env --------------------------------------------------------
if [ -f "$_FU_ENV_DIR/local.env" ]; then
	# Remember what the caller exported, source the file, then put back any
	# variable that was already set — an explicit export always wins.
	_FU_ENV_HAD_G47=${G47+1}
	_FU_ENV_HAD_OUT=${OUT+1}
	_FU_ENV_OLD_G47=${G47-}
	_FU_ENV_OLD_OUT=${OUT-}
	# shellcheck source=/dev/null
	. "$_FU_ENV_DIR/local.env"
	if [ -n "$_FU_ENV_HAD_G47" ]; then G47=$_FU_ENV_OLD_G47; fi
	if [ -n "$_FU_ENV_HAD_OUT" ]; then OUT=$_FU_ENV_OLD_OUT; fi
	unset _FU_ENV_HAD_G47 _FU_ENV_HAD_OUT _FU_ENV_OLD_G47 _FU_ENV_OLD_OUT
fi

# --- GNU timeout on Windows -------------------------------------------------
case $(uname -s 2>/dev/null) in
MINGW* | MSYS* | CYGWIN*)
	# Git's usr/bin has GNU coreutils; C:\WINDOWS\system32 also has a
	# `timeout.exe` that would swallow the arguments instead of timing out.
	if [ -x /usr/bin/timeout ]; then
		PATH="/usr/bin:$PATH"
		export PATH
	fi
	case $(command -v timeout 2>/dev/null) in
	/usr/bin/timeout*) ;;
	*)
		echo "FAIL: 'timeout' does not resolve to GNU coreutils (/usr/bin/timeout)." >&2
		echo "      Run the scripts from Git Bash ('sh tools/<script>.sh'), not from WSL's bash." >&2
		exit 1
		;;
	esac
	# No pipe here: with `set -o pipefail` a SIGPIPE from `grep -q` would look
	# like a failure.
	case $(timeout --version 2>&1) in
	*"GNU coreutils"*) ;;
	*)
		echo "FAIL: 'timeout --version' does not report GNU coreutils on this PATH." >&2
		echo "      Run the scripts from Git Bash ('sh tools/<script>.sh')." >&2
		exit 1
		;;
	esac
	;;
esac

# --- Godot binary check -----------------------------------------------------
# Call after the script has applied its own default, i.e. when $G47 is final.
fu_require_godot() {
	if [ -n "$G47" ] && [ -x "$G47" ]; then
		return 0
	fi
	echo "FAIL: Godot binary not found or not executable: ${G47:-<unset>}" >&2
	echo "      Set it in tools/local.env (copy tools/local.env.example) or export it," >&2
	echo "      e.g.  G47=/path/to/Godot_v4.7.2-stable_linux.x86_64 sh tools/run_tests.sh" >&2
	echo "      On Windows use Git Bash and run the scripts with 'sh': on this PC plain" >&2
	echo "      'bash' may be WSL's bash, which drops G47 and cannot see the Windows path." >&2
	exit 1
}

