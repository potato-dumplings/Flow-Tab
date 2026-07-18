#!/usr/bin/env bash
set -euo pipefail

LC_ALL=C /usr/bin/perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC \
  -e 'printf "%.0f\n", clock_gettime(CLOCK_MONOTONIC) * 1000000000'
