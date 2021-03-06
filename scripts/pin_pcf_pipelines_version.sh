#!/bin/bash

set -eu
set -o pipefail

if [[ ! $(which yaml-patch) ]]; then
  echo "Did not find yaml-patch; are you sure it's in your PATH?"
  exit 1
fi

root="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

overwrite=""
dir="${root}/.."
has_fly_fmt="false"

while getopts v:w:d: option; do
 case "${option}" in
 v)
    version=${OPTARG};;
 w)
    overwrite=${OPTARG};;
 d)
    dir=${OPTARG};;
 esac
done

if [[ $(which fly) ]] && [[ $(fly -h 2>&1 | grep fmt) ]]; then
  has_fly_fmt="true"
fi

echo "Will pin pcf-pipelines to ${version}"

test_for_pcf_pipelines_git=$(cat <<-EOF
- op: test
  path: /resources/name=pcf-pipelines
  value:
    name: pcf-pipelines
    type: git
    source:
      uri: git@github.com:pivotal-cf/pcf-pipelines.git
      branch: master
      private_key: {{git_private_key}}
EOF
)

pin_pcf_pipelines=$(cat <<-EOF
- op: add
  path: /get=pcf-pipelines/version
  value:
    ref: ${version}
EOF
)

files=$(
  find \
    $dir \
    -type f \
    -name pipeline.yml |
  grep -v ci
)

for f in ${files[@]}; do
  if [[ $( cat $f | yaml-patch -o <(echo "$test_for_pcf_pipelines_git") 2>/dev/null ) ]]; then
    echo "Pinning ${f}"
    cat $f | yaml-patch -o <(echo "$pin_pcf_pipelines") > "${f}.pinned"

    if [[ "${overwrite}" != "" ]]; then
      filename=$f
    else
      filename=${f/.yml/}-pinned.yml
    fi

    mv "${f}.pinned" $filename

    if [[ "$has_fly_fmt" == "true" ]]; then
      fly fmt --write --config $filename
    fi
  else
    echo "Skipping $f"
  fi
done
