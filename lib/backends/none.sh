#!/usr/bin/env bash
# lib/backends/none.sh — meta-components.
#
# A meta-component installs nothing itself; it exists purely as a node in the
# dependency graph so profiles can depend on a coherent group (e.g. "cli-utils"
# pulling in a dozen apt packages that each stand alone).
# shellcheck shell=bash

backend_none_install() { log_debug "${1}: meta-component, nothing to install"; }
backend_none_remove() { return 0; }
backend_none_update() { return 0; }
backend_none_version() { printf 'meta'; }
