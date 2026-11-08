#version 460 core
#include <flutter/runtime_effect.glsl>

// ImageFilter supplies the texture dimensions and the live backdrop.
uniform vec2 u_size;
uniform float u_logicalWidth;
uniform float u_radius;
uniform float u_refraction;
uniform float u_dispersion;
uniform float u_bevel;
uniform vec4 u_rect; // Global logical x, y, width, height of the glass.
uniform vec2 u_viewportSize;
uniform sampler2D u_backdrop;
out vec4 fragColor;

vec4 backdrop(vec2 pixel) {
  // Sample the filter snapshot directly. An additional GLES Y flip mirrors
  // the backdrop in the Android composed-filter path.
  vec2 uv = clamp(pixel / u_size, vec2(0.0), vec2(1.0));
  return texture(u_backdrop, uv);
}

void main() {
  vec2 pixel = FlutterFragCoord().xy;
  float scale = u_size.x / max(u_logicalWidth, 1.0);
  vec2 paneSize = u_size;
  vec2 paneOrigin = vec2(0.0);
  if (u_rect.z > 0.0 && u_rect.w > 0.0) {
    vec2 viewportScale = u_size / max(u_viewportSize, vec2(1.0));
    // Backdrop input can be a render-pass texture rather than a pane-sized
    // image. Map the lens into that texture instead of bending its outer edge.
    if (abs(viewportScale.x - viewportScale.y) < max(viewportScale.x, viewportScale.y) * .03) {
      scale = min(viewportScale.x, viewportScale.y);
      paneSize = u_rect.zw * scale;
      paneOrigin = u_rect.xy * scale;
    } else {
      // A tightly cropped input uses its own origin (with optional blur padding).
      scale = min(u_size.x / u_rect.z, u_size.y / u_rect.w);
      paneSize = u_rect.zw * scale;
      paneOrigin = (u_size - paneSize) * .5;
    }
  }
  vec2 halfSize = paneSize * 0.5;
  float radius = min(u_radius * scale, min(halfSize.x, halfSize.y));
  vec2 centered = pixel - paneOrigin - halfSize;
  vec2 q = abs(centered) - (halfSize - radius);
  vec2 exterior = max(q, vec2(0.0));
  float distanceToEdge = length(exterior) + min(max(q.x, q.y), 0.0) - radius;
  vec2 normal = length(exterior) > 0.001
      ? normalize(exterior) * sign(centered)
      : (q.x > q.y ? vec2(sign(centered.x), 0.0) : vec2(0.0, sign(centered.y)));

  // A rounded bevel refracts at the rim, leaving the face undistorted.
  float bevelWidth = min(max(u_bevel, 1.0) * scale,
      min(halfSize.x, halfSize.y) * .45);
  float edge = 1.0 - smoothstep(0.0, max(bevelWidth, 1.0), -distanceToEdge);
  float bend = edge * edge * u_refraction * scale;
  vec2 bent = pixel - normal * bend;
  float split = u_dispersion * scale * edge * edge;
  vec4 base = backdrop(bent);
  vec4 red = backdrop(bent - normal * split);
  vec4 blue = backdrop(bent + normal * split);
  vec3 refracted = min(vec3(red.r, base.g, blue.b), vec3(base.a));
  fragColor = vec4(refracted, base.a);
}
