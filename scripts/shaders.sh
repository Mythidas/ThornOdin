#!/usr/bin/env bash

glslc -fshader-stage=vertex ./res/shader.vert -o ./res/shader.vert.spv
glslc -fshader-stage=fragment ./res/shader.frag -o ./res/shader.frag.spv
