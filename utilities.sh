#!/bin/sh

set -e

_fail() {
  echo $@ >&2
  exit 1
}

