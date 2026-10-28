#!/usr/bin/env bash

odin check thorn/src -vet -strict-style -warnings-as-errors -collection:extern=./extern -collection:thorn=./thorn/src
odin test thorn/test --all-packages -collection:extern=./extern -collection:thorn=./thorn/src
