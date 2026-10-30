#version 450
// Flat pure green: check.sh b expects 0,255,0 at the frame centre on a black clear. Green is the
// one channel that RGBA/BGRA confusion cannot change.
//
// Copyright (C) 2026 the ps4-wine authors. SPDX-License-Identifier: GPL-3.0-or-later
layout(location = 0) out vec4 oColour;

void main() {
    oColour = vec4(0.0, 1.0, 0.0, 1.0);
}
