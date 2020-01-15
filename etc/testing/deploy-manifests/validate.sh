#!/bin/bash

set -e

here="$(dirname "${0}")"
dest_dir="test"
rm -rf "${here}/${dest_dir}" || true
mkdir -p "${here}/${dest_dir}"

is_regenerate=""
if [[ "${#@}" -eq 1 ]]; then
  if [[ "${1}" == "--regenerate" ]]; then
	  is_regenerate="true"
    dest_dir="golden"
  else
    echo "Unrecognized flag ${1}" >/dev/stderr
    echo "Must be --regenerate" >/dev/stderr
    exit 1
  fi
fi

# Generate a deployment manifest for many different targets using the local
# build of 'pachctl'
custom_args=(
--secure
--dynamic-etcd-nodes 3
--etcd-storage-class storage-class
--namespace pachyderm
--no-expose-docker-socket
--object-store=s3
  pach-volume       # <volumes>
  50                # <size of volumes (in GB)>
  pach-bucket       # <bucket>
  storage-id        # <id>
  storage-secret    # <secret>
  storage.endpoint  # <endpoint>
)
google_args=(
--dynamic-etcd-nodes 3
  pach-bucket # <bucket-name>
  50          # <disk-size>
)
amazon_args=(
--dynamic-etcd-nodes 3
--credentials "AWSIDAWSIDAWSIDAWSID,awssecret+awssecret+awssecret+awssecret+"
  pach-bucket # <bucket-name>
  us-west-1   # <region>
  50          # <disk-size>
)
microsoft_args=(
--dynamic-etcd-nodes 3
  pach-container           # <container>
  pach-account             # <account-name>
  cGFjaC1hY2NvdW50LWtleQ== # <account-key> (base64-encoded "pach-account-key")
  50                       # <disk-size>
)

pach_config="${here}/${dest_dir}/pachconfig"
# Use a test-specific pach config to avoid local settings from changing the
# output
export PACH_CONFIG="${pach_config}"
for platform in custom google amazon microsoft; do
  for fmt in json yaml; do
    output="${here}/${dest_dir}/${platform}-deploy-manifest.${fmt}"
    eval "args=( \"\${${platform}_args[@]}\" )"
    # Generate kubernetes manifest:
    # - strip additional version info so that pachctl builds from the same
    #   version all work
    # - Use an empty pach config so that e.g. metrics don't change the output
    pachctl deploy "${platform}" "${args[@]}" -o "${fmt}" --dry-run \
      | sed 's/\([0-9]\{1,4\}\.[0-9]\{1,4\}\.[0-9]\{1,4\}\)-[0-9a-f]\{40\}/\1/g' >"${output}"
    rm -f "${pach_config}" # remove cfg from next run (or diff dir, or golden/)
    if [[ ! "${is_regenerate}" ]]; then
      # Check manifests with kubeval
      kubeval "${output}"
    fi
  done
done

if [[ "${is_regenerate}" ]]; then
  exit 0
fi

# Compare manifests to golden files (in addition to kubeval, to see changes
# in storage secrets and such)
#
# TODO(msteffen): if we ever consider removing this because it generates too
# many spurious test failures, then I highly recomment we keep the 'kubeval'
# validation above, as it should accept any valid kubernetes manifest, and
# would've caught at least one serialization bug that completely broke 'pachctl
# deploy' in v1.9.8
echo ""
echo "Diffing 'pachctl deploy' output with known-good golden manifests."
echo "If this fails but should pass, run:"
echo "  validate.sh --regenerate"
echo "    or"
echo "  make regenerate-test-deploy-manifests"
echo "  (at the top level of the Pachyderm repo)"
echo "to replace the golden deployment manifests with current output."
echo "This is necessary if you have deliberately changed 'pachctl deploy'"
echo ""
DIFF_CMD="${DIFF_CMD:-diff --unified=6}"
if ! ${DIFF_CMD} "${here}/${dest_dir}" "${here}/golden"; then
  echo ""
  echo "Error: deployment manifest has changed."
  exit 1
else
  echo "No differences found"
fi
