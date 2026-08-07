#!/usr/bin/env bash
# kind-load.sh — build, pull, and load images into the kind cluster

set -euo pipefail

err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

usage() {
  echo "Usage: $0 <cilium|apps> [--verbose]" >&2
  exit 2
}

load_cilium() {
  # ── 1. Validate override images exist in Docker (fail fast) ──
  if [ -n "${CILIUM_AGENT_IMAGE}" ]; then
    if ! docker image inspect "${CILIUM_AGENT_IMAGE}" >/dev/null 2>&1; then
      echo "ERROR: CILIUM_AGENT_IMAGE '${CILIUM_AGENT_IMAGE}' not found in Docker daemon" >&2
      echo "  Available cilium images:" >&2
      docker images --filter "reference=*cilium*" --format "    {{.Repository}}:{{.Tag}}" >&2
      exit 1
    fi
    echo "  ✓ CILIUM_AGENT_IMAGE: ${CILIUM_AGENT_IMAGE}"
  fi
  if [ -n "${CILIUM_OPERATOR_IMAGE}" ]; then
    if ! docker image inspect "${CILIUM_OPERATOR_IMAGE}" >/dev/null 2>&1; then
      echo "ERROR: CILIUM_OPERATOR_IMAGE '${CILIUM_OPERATOR_IMAGE}' not found in Docker daemon" >&2
      echo "  Available operator images:" >&2
      docker images --filter "reference=*operator*" --format "    {{.Repository}}:{{.Tag}}" >&2
      exit 1
    fi
    echo "  ✓ CILIUM_OPERATOR_IMAGE: ${CILIUM_OPERATOR_IMAGE}"
  fi

  # ── 2. Discover images via helm images get ──
  # Pass the same --set overrides used by cilium:install so the chart
  # resolves to the ACTUAL images that will run. Without this, the chart
  # returns its default agent/operator refs and docker pull clobbers any
  # locally-built image that shares the same tag.
  helm_get_args=()
  if [ -n "${CILIUM_CHART_DIR}" ]; then
    helm_get_args+=("${CILIUM_CHART_DIR}")
  else
    helm_get_args+=(cilium/cilium --version "${CILIUM_VERSION}")
  fi
  helm_get_args+=(--values config/values.cilium.yaml)
  if [ -n "${CILIUM_AGENT_IMAGE}" ]; then
    helm_get_args+=(--set "image.override=${CILIUM_AGENT_IMAGE}")
  fi
  if [ -n "${CILIUM_OPERATOR_IMAGE}" ]; then
    helm_get_args+=(--set "operator.image.override=${CILIUM_OPERATOR_IMAGE}")
  fi

  images=()
  while IFS= read -r img; do
    images+=("${img}")
  done < <(helm images get "${helm_get_args[@]}" 2>/dev/null |
    sed 's/@sha256:.*//' |
    sort -u)

  # ── 3. Pull remote images; skip those already in Docker daemon ──
  # Locally-built override images are already present and must NOT be
  # pulled — docker pull would either clobber them with an upstream
  # image or fail for local-only tags like localhost:5000/….
  for img in "${images[@]}"; do
    if docker image inspect "${img}" >/dev/null 2>&1; then
      echo "  ⊙ ${img} (local — skip pull)"
    elif [ "${verbose}" = true ]; then
      docker pull "${img}" || err "WARN: pull failed for ${img}"
    else
      docker pull --quiet "${img}" || err "WARN: pull failed for ${img}"
    fi
  done

  # ── 4. Verify all images are available locally ──
  ready=()
  missing=()
  for img in "${images[@]}"; do
    if docker image inspect "${img}" >/dev/null 2>&1; then
      ready+=("${img}")
    else
      missing+=("${img}")
    fi
  done
  if [ "${missing[*]:-}" != "" ]; then
    echo "WARNING: image(s) not available locally (skipping):" >&2
    printf '  \u2717 %s\n' "${missing[@]}" >&2
  fi
  if [ "${ready[*]:-}" = "" ]; then
    echo "ERROR: No images available to load into kind" >&2
    exit 1
  fi

  # ── 5. Load verified images into kind ──
  if [ "${verbose}" = true ]; then
    kind load docker-image "${ready[@]}" --name "${KIND_CLUSTER_NAME}"
  else
    kind load --quiet docker-image "${ready[@]}" --name "${KIND_CLUSTER_NAME}"
  fi
}

load_apps() {
  if [ "${verbose}" = true ]; then
    docker build -t "backend-grpc:${BACKEND_GRPC_VERSION}" apps/backend-grpc/image
  else
    docker build --quiet -t "backend-grpc:${BACKEND_GRPC_VERSION}" apps/backend-grpc/image
  fi
  if ! docker image inspect "backend-grpc:${BACKEND_GRPC_VERSION}" >/dev/null 2>&1; then
    echo "ERROR: backend-grpc:${BACKEND_GRPC_VERSION} build failed — image not found in Docker daemon" >&2
    exit 1
  fi

  if [ "${verbose}" = true ]; then
    docker build -t "coraza-waf-extproc:${CORAZA_WAF_EXTPROC_VERSION}" apps/coraza-waf-extproc/image
  else
    docker build --quiet -t "coraza-waf-extproc:${CORAZA_WAF_EXTPROC_VERSION}" apps/coraza-waf-extproc/image
  fi
  if ! docker image inspect "coraza-waf-extproc:${CORAZA_WAF_EXTPROC_VERSION}" >/dev/null 2>&1; then
    echo "ERROR: coraza-waf-extproc:${CORAZA_WAF_EXTPROC_VERSION} build failed — image not found in Docker daemon" >&2
    exit 1
  fi

  if [ "${verbose}" = true ]; then
    docker build -t "external-authz:${EXTERNAL_AUTHZ_VERSION}" apps/external-authz/image
  else
    docker build --quiet -t "external-authz:${EXTERNAL_AUTHZ_VERSION}" apps/external-authz/image
  fi
  if ! docker image inspect "external-authz:${EXTERNAL_AUTHZ_VERSION}" >/dev/null 2>&1; then
    echo "ERROR: external-authz:${EXTERNAL_AUTHZ_VERSION} build failed — image not found in Docker daemon" >&2
    exit 1
  fi

  remote_images=(
    "nicolaka/netshoot:${NETSHOOT_VERSION}"
    "mccutchen/go-httpbin:${HTTPBIN_VERSION}"
    "envoyproxy/envoy:v${ENVOY_VERSION}"
  )

  for img in "${remote_images[@]}"; do
    if [ "${verbose}" = true ]; then
      docker pull "${img}" || err "WARN: pull failed for ${img}, using local image"
    else
      docker pull --quiet "${img}" || err "WARN: pull failed for ${img}, using local image"
    fi
  done

  all_images=(
    "backend-grpc:${BACKEND_GRPC_VERSION}"
    "coraza-waf-extproc:${CORAZA_WAF_EXTPROC_VERSION}"
    "external-authz:${EXTERNAL_AUTHZ_VERSION}"
    "${remote_images[@]}"
  )
  if [ "${verbose}" = true ]; then
    kind load docker-image "${all_images[@]}" --name "${KIND_CLUSTER_NAME}"
  else
    kind load docker-image --quiet "${all_images[@]}" --name "${KIND_CLUSTER_NAME}"
  fi

  # Verify images are actually present on at least one worker node
  worker_node="${KIND_CLUSTER_NAME}-worker"
  echo "--- Image load verification ---"
  load_ok=true
  for img in "${all_images[@]}"; do
    if docker exec "${worker_node}" crictl images -o json 2>/dev/null | grep -q "${img}"; then
      echo "  ✅ ${img}"
    else
      echo "  ❌ ${img} — NOT FOUND on ${worker_node}" >&2
      load_ok=false
    fi
  done
  if [ "${load_ok}" != true ]; then
    echo "ERROR: one or more images failed to load — pods will get ErrImagePull" >&2
    exit 1
  fi
}

main() {
  local loader=""
  verbose=false

  for arg in "$@"; do
    case "${arg}" in
    cilium | apps)
      if [ -n "${loader}" ]; then
        usage
      fi
      loader="${arg}"
      ;;
    --verbose)
      verbose=true
      ;;
    *)
      usage
      ;;
    esac
  done

  if [ -z "${loader}" ]; then
    usage
  fi

  "load_${loader}"
}

main "$@"
