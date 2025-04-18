#!/usr/bin/env bash

# A simple script that reads from rumble data, gets extra info
# about the latest scanned image (size and build time), then
# uses this data to create the image-comparison-*.html files

set -ex

function epoch {
    ts="$(echo "${1}" | cut -d. -f1 | sed 's|Z||')"
    python3 -c "import os; os.environ['TZ'] = 'UTC'; from datetime import datetime as dt; t = dt.strptime('${ts}', '%Y-%m-%dT%H:%M:%S'); print(int((t - dt(1970, 1, 1)).total_seconds() * 1000))"
}

function epoch_now {
    python3 -c "import os; os.environ['TZ'] = 'UTC'; from datetime import datetime as dt; t = dt.now(); print(int((t - dt(1970, 1, 1)).total_seconds() * 1000))"
}

# Inspired by https://gist.github.com/imjasonh/ce437a40160acab17030d024d4680fd2
function image_size {
    size="$(crane manifest $1 --platform ${2:-linux/amd64} | jq '.config.size + ([.layers[].size] | add)' | numfmt --to=iec)"
    echo "${size}" | sed 's|K| KB|' | sed 's|M| MB|' | sed 's|G| GB|' | sed 's|T| TB|'
}

function num_cves {
    # docker run --rm cgr.dev/chainguard/grype $1 -o json 2>/dev/null | jq '.matches | length'
    docker run --rm mcr.microsoft.com/oss/v2/aquasecurity/trivy:v0.58.2 image $1 -q -f json 2>/dev/null | jq '(.Results[0].Vulnerabilities | length) as $os_vulns | (.Results[1].Vulnerabilities | length) as $lang_vulns | $os_vulns + $lang_vulns'
}

function main {
    for combo in \
    "kube-state-metrics|kube-state-metrics|mcr.microsoft.com/oss/v2/kubernetes/kube-state-metrics:v2.14.0|registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.14.0" \
    "kube-proxy|kube-proxy|mcr.microsoft.com/oss/v2/kubernetes/kube-proxy:v1.29.13|registry.k8s.io/kube-proxy:v1.29.13" \
    "coredns|coredns|mcr.microsoft.com/oss/v2/kubernetes/coredns:v1.11.3|registry.k8s.io/coredns/coredns:v1.11.3"; do

        image_key="$(echo "${combo}" | cut -d\| -f1)"
        image_name="$(echo "${combo}" | cut -d\| -f2)"

        ours_ref="$(echo "${combo}" | cut -d\| -f3)"
        ours_cves_num="$(num_cves "${ours_ref}")"

        theirs_ref="$(echo "${combo}" | cut -d\| -f4)"
        theirs_cves_num="$(num_cves "${theirs_ref}")"

        ours_size="$(image_size "${ours_ref}")"

        theirs_size="$(image_size "${theirs_ref}")"
        theirs_crane_resp="$(crane config "${theirs_ref}")"

        ours_size_num="$(echo "${ours_size}" | awk '{print $1}')"
        ours_size_unit="$(echo "${ours_size}" | awk '{print $2}')"
        theirs_size_num="$(echo "${theirs_size}" | awk '{print $1}')"
        theirs_size_unit="$(echo "${theirs_size}" | awk '{print $2}')"

        generated_at_timestamp="$(epoch_now)"

        cat comparison.template.html | \
        sed "s|{{imageName}}|${image_name}|g" | \
        sed "s|{{oursCvesNum}}|${ours_cves_num}|g" | \
        sed "s|{{oursSizeNum}}|${ours_size_num}|g" | \
        sed "s|{{oursSizeUnit}}|${ours_size_unit}|g" | \
        sed "s|{{theirsCvesNum}}|${theirs_cves_num}|g" | \
        sed "s|{{theirsSizeNum}}|${theirs_size_num}|g" | \
        sed "s|{{theirsSizeUnit}}|${theirs_size_unit}|g" > \
        "comparison-${image_key}.html"
    done
}

main
