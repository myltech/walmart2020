#!/usr/bin/env bash
set -Eeuo pipefail

: "${BASHBREW_CACHE:=$HOME/.cache/bashbrew}"
export BASHBREW_CACHE BASHBREW_ARCH=

if [ ! -d "$BASHBREW_CACHE/git" ]; then
	# initialize the "bashbrew cache"
	bashbrew --arch amd64 from --uniq --apply-constraints hello-world:linux > /dev/null
fi

if [ "$#" -eq 0 ]; then
	set -- '--all'
fi

_is_naughty() {
	local from="$1"; shift

	case "$BASHBREW_ARCH=$from" in
		# a few images that no longer exist (and are thus not permissible)
		# https://techcommunity.microsoft.com/t5/Containers/Removing-the-latest-Tag-An-Update-on-MCR/ba-p/393045
		*=mcr.microsoft.com/windows/*:latest \
		) return 0 ;;
		# https://docs.microsoft.com/en-us/virtualization/windowscontainers/deploy-containers/base-image-lifecycle
		# "11/12/2019"
		*=mcr.microsoft.com/windows/*:1803* \
		) return 0 ;;
		# https://docs.microsoft.com/en-us/virtualization/windowscontainers/deploy-containers/base-image-lifecycle
		# "04/09/2019"
		*=mcr.microsoft.com/windows/*:1709* \
		) return 0 ;;
		# https://docs.microsoft.com/en-us/virtualization/windowscontainers/deploy-containers/base-image-lifecycle
		# "10/09/2018"
		*=mcr.microsoft.com/windows/nanoserver:sac2016 \
		) return 0 ;;

		# a few explicitly permissible exceptions to Santa's naughty list
		*=scratch \
		| amd64=docker.elastic.co/elasticsearch/elasticsearch:* \
		| amd64=docker.elastic.co/kibana/kibana:* \
		| amd64=docker.elastic.co/logstash/logstash:* \
		| arm64v8=docker.elastic.co/elasticsearch/elasticsearch:* \
		| arm64v8=docker.elastic.co/kibana/kibana:* \
		| arm64v8=docker.elastic.co/logstash/logstash:* \
		| windows-*=mcr.microsoft.com/windows/nanoserver:* \
		| windows-*=mcr.microsoft.com/windows/servercore:* \
		) return 1 ;;

		# "x/y" and not an approved exception
		*/*) return 0 ;;
	esac

	# must be some other official image AND support our current architecture
	local archSupported
	if archSupported="$(bashbrew cat --format '{{ .TagEntry.HasArchitecture arch | ternary arch "" }}' "$from")" && [ -n "$archSupported" ]; then
		return 1
	fi

	return 0
}

_arches() {
	bashbrew cat --format '
		{{- range .TagEntries -}}
			{{- .Architectures | join "\n" -}}
			{{- "\n" -}}
		{{- end -}}
	' "$@" | sort -u
}

_froms() {
	bashbrew cat --format '
		{{- range .TagEntries -}}
			{{- $.DockerFroms . | join "\n" -}}
			{{- "\n" -}}
		{{- end -}}
	' "$@" | sort -u
}

declare -A naughtyFromsArches=(
	#[img:tag=from:tag]='arch arch ...'
)
naughtyFroms=()
declare -A allNaughty=(
	#[img:tag]=1
)

tags="$(bashbrew --namespace '' list --uniq "$@" | sort -u)"
for img in $tags; do
	arches="$(_arches "$img")"
	hasNice= # do we have _any_ arches that aren't naughty? (so we can make the message better if not)
	for BASHBREW_ARCH in $arches; do
		export BASHBREW_ARCH

		froms="$(_froms "$img")"
		[ -n "$froms" ] # rough sanity check

		for from in $froms; do
			if _is_naughty "$from"; then
				if [ -z "${naughtyFromsArches["$img=$from"]:-}" ]; then
					naughtyFroms+=( "$img=$from" )
				else
					naughtyFromsArches["$img=$from"]+=', '
				fi
				naughtyFromsArches["$img=$from"]+="$BASHBREW_ARCH"
			else
				hasNice=1
			fi
		done
	done

	if [ -z "$hasNice" ]; then
		allNaughty["$img"]=1
	fi
done

for naughtyFrom in "${naughtyFroms[@]:-}"; do
	[ -n "$naughtyFrom" ] || continue # https://mywiki.wooledge.org/BashFAQ/112#BashFAQ.2F112.line-8 (empty array + "set -u" + bash 4.3 == sad day)
	img="${naughtyFrom%%=*}"
	from="${naughtyFrom#$img=}"
	if [ -n "${allNaughty["$img"]:-}" ]; then
		echo " - $img (FROM $from) -- completely unsupported base!"
	else
		arches="${naughtyFromsArches[$naughtyFrom]}"
		echo " - $img (FROM $from) [$arches]"
	fi
done
