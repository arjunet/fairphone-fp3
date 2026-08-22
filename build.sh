#!/bin/bash
set -xe

[ -d build ] || git clone https://github.com/arjunet/Modded-UBPORTS-build-tools build
./build/build.sh "$@"
