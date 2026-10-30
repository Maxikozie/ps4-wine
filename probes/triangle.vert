#version 450
// Milestone b triangle: the orbis-porting-kit example's on-screen positions, no vertex buffer.
// The centre of the screen (NDC 0,0) lies inside it, which is the pixel check.sh b reads.
//
// Copyright (C) 2026 the ps4-wine authors. SPDX-License-Identifier: GPL-3.0-or-later
const vec2 kPos[3] = vec2[3](vec2(0.0, -0.6), vec2(0.6, 0.6), vec2(-0.6, 0.6));

void main() {
    gl_Position = vec4(kPos[gl_VertexIndex], 0.0, 1.0);
}
