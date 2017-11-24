#!/usr/bin/env bash
#shellcheck disable=SC2068,SC2206
set -e

dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
self="$(basename "$0")"

BOULDER_IP="$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.Gateway}}{{end}}' boulder)" \
	&& export BOULDER_IP

# shellcheck source=./tests/test-functions.sh
source "$dir/tests/test-functions.sh"

usage() {
	cat <<EOUSAGE

usage: $self [-t test ...] image:tag [...]
   ie: $self debian:stretch
       $self -t utc python:3
       $self -t utc python:3 -t python-hy

This script processes the specified Docker images to test their running
environments.
EOUSAGE
}

# arg handling
opts="$(getopt -o 'ht:c:?' --long 'dry-run,help,test:,config:,keep-namespace' -- "$@" || { usage >&2 && false; })"
eval set -- "$opts"

declare -A argTests=()
declare -a configs=()
dryRun=
keepNamespace=
while true; do
	flag=$1
	shift
	case "$flag" in
		--dry-run) dryRun=1 ;;
		--help|-h|'-?') usage && exit 0 ;;
		--test|-t) argTests["$1"]=1 && shift ;;
		--config|-c) configs+=("$(readlink -f "$1")") && shift ;;
		--keep-namespace) keepNamespace=1 ;;
		--) break ;;
		*)
			{
				echo "error: unknown flag: $flag"
				usage
			} >&2
			exit 1
			;;
	esac
done

if [ $# -eq 0 ]; then
	usage >&2
	exit 1
fi

# declare configuration variables
declare -a globalTests=()
declare -A testAlias=()
declare -A imageTests=()
declare -A globalExcludeTests=()
declare -A explicitTests=()

# if there are no user-specified configs, use the default config
if [ ${#configs} -eq 0 ]; then
	configs+=("$dir/config.sh")
fi

# load the configs
declare -A testPaths=()
for conf in "${configs[@]}"; do
  # shellcheck source=./config.sh
	source "$conf"

	# Determine the full path to any newly-declared tests
	confDir="$(dirname "$conf")"

	for testName in ${globalTests[@]} ${imageTests[@]}; do
		[ "${testPaths[$testName]}" ] && continue

		if [ -d "$confDir/tests/$testName" ]; then
			# Test directory found relative to the conf file
			testPaths[$testName]="$confDir/tests/$testName"
		elif [ -d "$dir/tests/$testName" ]; then
			# Test directory found in the main tests/ directory
			testPaths[$testName]="$dir/tests/$testName"
		fi
	done
done

didFail=
for dockerImage in "$@"; do
	echo "testing $dockerImage"

	if ! docker inspect "$dockerImage" &> /dev/null; then
		echo $'\timage does not exist!'
		didFail=1
		continue
	fi

	repo="${dockerImage%:*}"
	tagVar="${dockerImage#*:}"
	#version="${tagVar%-*}"
	variant="${tagVar##*-}"

	testRepo="$repo"
	if [ -z "$keepNamespace" ]; then
		testRepo="${testRepo##*/}"
	fi
	[ -z "${testAlias[$repo]}" ] || testRepo="${testAlias[$repo]}"

	explicitVariant=
	if [ "${explicitTests[:$variant]}" ] \
	|| [ "${explicitTests[$repo:$variant]}" ] \
	|| [ "${explicitTests[$testRepo:$variant]}" ]
	then
		explicitVariant=1
	fi

	testCandidates=()
	if [ -z "$explicitVariant" ]; then
		testCandidates+=( "${globalTests[@]}" )
	fi
	testCandidates+=(
		${imageTests[:$variant]}
	)
	if [ -z "$explicitVariant" ]; then
		testCandidates+=(
			${imageTests[$testRepo]}
		)
	fi
	testCandidates+=(
		${imageTests[$testRepo:$variant]}
	)
	if [ "$testRepo" != "$repo" ]; then
		if [ -z "$explicitVariant" ]; then
			testCandidates+=(
				${imageTests[$repo]}
			)
		fi
		testCandidates+=(
			${imageTests[$repo:$variant]}
		)
	fi

	tests=()
	for t in "${testCandidates[@]}"; do
		if [ ${#argTests[@]} -gt 0 ] && [ -z "${argTests[$t]}" ]; then
			# skipping due to -t
			continue
		fi

		if [ -n "${globalExcludeTests[${testRepo}_$t]}" ] \
		|| [ -n "${globalExcludeTests[${testRepo}:${variant}_$t]}" ] \
		|| [ -n "${globalExcludeTests[:${variant}_$t]}" ] \
		|| [ -n "${globalExcludeTests[${repo}_$t]}" ] \
		|| [ -n "${globalExcludeTests[${repo}:${variant}_$t]}" ] \
		|| [ -n "${globalExcludeTests[:${variant}_$t]}" ]
		then
			# skipping due to exclude
			continue
		fi

		tests+=( "$t" )
	done

	currentTest=0
	totalTest="${#tests[@]}"
	for t in "${tests[@]}"; do
		(( currentTest+=1 ))
		echo -ne "\t'$t' [$currentTest/$totalTest]..."

		# run test against dockerImage here
		# find the script for the test
		scriptDir="${testPaths[$t]}"
		if [ -d "$scriptDir" ]; then
			script="$scriptDir/run.sh"
			if [ -x "$script" ] && [ ! -d "$script" ]; then
				if [ $dryRun ]; then
					if "$script" $dockerImage; then
						echo 'passed'
					else
						echo 'failed'
						didFail=1
					fi
				else
					if output="$("$script" $dockerImage)"; then
						if [ -f "$scriptDir/expected-std-out.txt" ] && ! d="$(echo "$output" | diff -u "$scriptDir/expected-std-out.txt" - 2>/dev/null)"; then
							echo 'failed; unexpected output:'
							echo "$d"
							didFail=1
						else
							echo 'passed'
						fi
					else
						echo 'failed'
						didFail=1
					fi
				fi
			else
				echo "skipping"
				echo >&2 "error: $script missing, not executable or is a directory"
				didFail=1
				continue
			fi
		else
			echo "skipping"
			echo >&2 "error: unable to locate test '$t'"
			didFail=1
			continue
		fi
	done
done

if [ "$didFail" ]; then
	exit 1
fi
