#!/usr/bin/env bash
# ==============================================================================
# agent-harness: core/scripts/stack-config.sh
# Configuration resolution report and structural validation
# ==============================================================================
#
# The validator walks schema.json against the resolved configuration rather than
# restating the schema in shell, so the schema stays the single description of what a
# configuration may contain. It is a structural check, not a JSON Schema implementation,
# and it says so: "validated" must not be read as "conforms to schema.json".

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/config.sh"

usage() {
    cat <<USAGE_EOF
Usage:
  harness config validate    Report the resolved configuration and every structural problem
USAGE_EOF
}

ACTION="${1:-validate}"
shift || true

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        *) log_error "Unknown config option: $1"; usage; exit 1 ;;
    esac
done

case "${ACTION}" in
    validate) ;;
    -h|--help|help) usage; exit 0 ;;
    *) log_error "Unknown config action: ${ACTION}"; usage; exit 1 ;;
esac

CONFIG_FILE="$(resolve_config_file)"
SCHEMA_FILE="$(get_harness_root)/schema.json"
PROFILE_LINE="$(get_active_profile_with_reason)"
ACTIVE_PROFILE="${PROFILE_LINE%%$'\t'*}"
PROFILE_REASON="${PROFILE_LINE#*$'\t'}"

if [ -n "${CONFIG_FILE}" ]; then
    log_info "Configuration file: ${CONFIG_FILE}"
else
    log_info "Configuration file: none (the built-in defaults apply)"
fi
log_info "Active profile: ${ACTIVE_PROFILE} (resolved by ${PROFILE_REASON})"

ERRORS_FOUND=0
WARNINGS_FOUND=0
UNCHECKED=()

if ! command -v jq >/dev/null 2>&1; then
    log_error "Structural validation requires jq, which is not available."
    exit 1
fi

if [ -z "${CONFIG_FILE}" ]; then
    UNCHECKED+=("every structural check: there is no configuration file to validate")
elif ! jq empty "${CONFIG_FILE}" >/dev/null 2>&1; then
    log_error "${CONFIG_FILE} is not valid JSON."
    ERRORS_FOUND=$((ERRORS_FOUND + 1))
    UNCHECKED+=("every structural check: the file could not be parsed")
elif [ ! -f "${SCHEMA_FILE}" ]; then
    log_error "Cannot validate: ${SCHEMA_FILE} is missing."
    exit 1
else
    # Walks the schema and the configuration together, emitting one
    # "<level>\t<dotted path>\t<message>" line per problem.
    FINDINGS="$(jq -r -n --slurpfile schema "${SCHEMA_FILE}" --slurpfile config "${CONFIG_FILE}" '
        def typeone($t; $v):
            if $t == "object" then ($v | type) == "object"
            elif $t == "array" then ($v | type) == "array"
            elif $t == "string" then ($v | type) == "string"
            elif $t == "boolean" then ($v | type) == "boolean"
            elif $t == "number" then ($v | type) == "number"
            elif $t == "integer" then (($v | type) == "number" and ($v | floor) == $v)
            else true
            end;

        # A schema type may be a list of alternatives. The qa command keys accept a string
        # or false -- the documented way to record that a project has no such gate -- and
        # before this the validator rejected the very value stack-qa.sh honours.
        def typematch($t; $v):
            if ($t | type) == "array" then ([$t[] | typeone(.; $v)] | any)
            else typeone($t; $v)
            end;

        def typename($t):
            if ($t | type) == "array" then ($t | join(" or ")) else $t end;

        def checknode($sch; $val; $path):
            if $sch == null then []
            elif ($sch.type != null) and ((typematch($sch.type; $val)) | not) then
                [{ level: "error", path: $path, message: "expected \(typename($sch.type)), found \($val | type)" }]
            elif $sch.type == "object" then
                [ (($sch.required // [])[]) as $key
                  | select(($val | has($key)) | not)
                  | { level: "error", path: ($path + [$key]), message: "missing required key" } ]
                + ( [ ($val | keys[]) as $key
                      | if (($sch.properties // {}) | has($key)) then
                            checknode($sch.properties[$key]; $val[$key]; ($path + [$key]))
                        elif (($sch.additionalProperties | type) == "object") then
                            checknode($sch.additionalProperties; $val[$key]; ($path + [$key]))
                        elif ($sch.additionalProperties == false) then
                            [{ level: "error", path: ($path + [$key]), message: "unknown key: the schema forbids additional keys here" }]
                        else
                            [{ level: "warning", path: ($path + [$key]), message: "unknown key: not described by schema.json" }]
                        end ]
                    | add // [] )
            elif $sch.type == "array" then
                ( [ ($val | to_entries[]) | checknode($sch.items; .value; ($path + [(.key | tostring)])) ] | add // [] )
            else
                ( if ($sch.enum != null) and (($sch.enum | index($val)) == null)
                  then [{ level: "error", path: $path, message: "must be one of: \($sch.enum | join(", "))" }]
                  else [] end )
                + ( if ($sch.minimum != null) and ($val < $sch.minimum)
                    then [{ level: "error", path: $path, message: "must be at least \($sch.minimum)" }]
                    else [] end )
            end;

        ($schema[0]) as $s
        | ($config[0]) as $c
        | ( checknode($s; $c; [])
            + ( if ($c.project.defaultProfile? != null) and ((($c.profiles // {}) | has($c.project.defaultProfile)) | not)
                then [{ level: "error", path: ["project", "defaultProfile"], message: "names no profile in this configuration: \($c.project.defaultProfile)" }]
                else [] end )
            + ( if (($c.profiles? | type) == "object") and (($c.profiles | length) == 0)
                then [{ level: "warning", path: ["profiles"], message: "is empty, so every command falls back to the built-in defaults" }]
                else [] end ) )
        | .[]
        | "\(.level)\t\(.path | join("."))\t\(.message)"
    ' 2>/dev/null)" || FINDINGS="__FAILED__"

    if [ "${FINDINGS}" = "__FAILED__" ]; then
        log_error "Structural validation could not complete against ${SCHEMA_FILE}."
        exit 1
    fi

    while IFS=$'\t' read -r level path message; do
        [ -n "${level}" ] || continue
        case "${level}" in
            error)
                log_error "${path}: ${message}"
                ERRORS_FOUND=$((ERRORS_FOUND + 1))
                ;;
            *)
                log_warn "${path}: ${message}"
                WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
                ;;
        esac
    done <<< "${FINDINGS}"

    # A targetRepoPath that does not resolve is a warning rather than an error: one
    # configuration is often shared across machines that do not all carry every
    # repository. It is reported because get_target_repo silently falls back to the
    # current directory, and silence is what made that surprising.
    while IFS= read -r configured; do
        [ -n "${configured}" ] || continue
        expanded="$(expand_config_path "${configured#*$'\t'}")"
        if [ ! -d "${expanded}" ]; then
            log_warn "profiles.${configured%%$'\t'*}.targetRepoPath: '${expanded}' does not exist, so commands run against the current directory instead."
            WARNINGS_FOUND=$((WARNINGS_FOUND + 1))
        fi
    done < <(jq -r '.profiles // {} | to_entries[] | select(.value.targetRepoPath != null) | "\(.key)\t\(.value.targetRepoPath)"' "${CONFIG_FILE}" 2>/dev/null)

    UNCHECKED+=("JSON Schema conformance: this is a structural walk of schema.json, not a schema engine, so pattern, format, dependency, and composition keywords are not applied")
    UNCHECKED+=("command strings: qa and ci commands are not executed or parsed here, only type-checked")
fi

echo ""
for note in "${UNCHECKED[@]}"; do
    log_info "Not checked — ${note}"
done

echo ""
if [ "${ERRORS_FOUND}" -ne 0 ]; then
    log_error "Configuration has ${ERRORS_FOUND} error(s) and ${WARNINGS_FOUND} warning(s)."
    exit 1
fi
if [ "${WARNINGS_FOUND}" -ne 0 ]; then
    log_warn "Configuration is structurally valid with ${WARNINGS_FOUND} warning(s)."
    exit 0
fi
log_success "Configuration is structurally valid."
