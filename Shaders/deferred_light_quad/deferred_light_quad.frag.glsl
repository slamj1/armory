#version 450

#ifdef GL_ES
precision mediump float;
#endif

#include "../compiled.glsl"
#include "../std/brdf.glsl"
#include "../std/math.glsl"
#ifndef _NoShadows
	#ifdef _PCSS
	#include "../std/shadows_pcss.glsl"
	#else
	#include "../std/shadows.glsl"
	#endif
#endif
#ifdef _SSS
#include "../std/sss.glsl"
#endif
#include "../std/gbuffer.glsl"

uniform sampler2D gbufferD;
uniform sampler2D gbuffer0;
uniform sampler2D gbuffer1;

#ifndef _NoShadows
	//!uniform sampler2D shadowMap;
	#ifdef _PCSS
	//!uniform sampler2D snoise;
	//!uniform float lampSizeUV;
	#endif
#endif

uniform mat4 LWVP;
uniform vec3 lightColor;
uniform vec3 l; // lightDir
uniform int lightShadow;
uniform float shadowsBias;
uniform vec3 eye;
uniform vec3 eyeLook;
#ifdef _SSRS
	uniform mat4 VP;
#endif

#ifdef _LampColTex
	uniform sampler2D texlampcolor;
#endif

in vec2 texCoord;
in vec3 viewRay;
out vec4 fragColor;

#ifndef _NoShadows
float shadowTest(const vec3 lPos) {
	
	#ifdef _Clampstc
	// Filtering out of bounds, remove
	// const vec2 border = vec2(1.0 / shadowmapSize[0], 1.0 / shadowmapSize[1]) * 2.0;
	// lPos.xy = clamp(lPos.xy, border[0], 1.0 - border[1]);
	if (lPos.x < 0.0) return 1.0;
	if (lPos.y < 0.0) return 1.0;
	if (lPos.x > 1.0) return 1.0;
	if (lPos.y > 1.0) return 1.0;
	#endif

	#ifdef _PCSS
	return PCSS(lPos.xy, lPos.z - shadowsBias);
	#else
	return PCF(lPos.xy, lPos.z - shadowsBias);
	#endif
}
#endif

#ifdef _SSRS
vec2 getProjectedCoord(vec3 hitCoord) {
	vec4 projectedCoord = VP * vec4(hitCoord, 1.0);
	projectedCoord.xy /= projectedCoord.w;
	projectedCoord.xy = projectedCoord.xy * 0.5 + 0.5;
	return projectedCoord.xy;
}
float getDeltaDepth(vec3 hitCoord) {
	vec2 texCoord = getProjectedCoord(hitCoord);
	float depth = texture(gbufferD, texCoord).r * 2.0 - 1.0;
	// TODO: store_depth
	// vec4 g0 = texture(gbuffer0, texCoord);
	// float depth = (1.0 - g0.a) * 2.0 - 1.0;
	vec3 wpos = getPos(eye, eyeLook, viewRay, depth);
	float d1 = length(eye - wpos);
	float d2 = length(eye - hitCoord);
	return d1 - d2;
}
float traceShadow(vec3 dir, vec3 hitCoord) {
	dir *= ssrsRayStep;
	// for (int i = 0; i < maxSteps; i++) {
		hitCoord += dir;
		if (getDeltaDepth(hitCoord) > 0.0) return 0.0;
		hitCoord += dir;
		if (getDeltaDepth(hitCoord) > 0.0) return 0.0;
		hitCoord += dir;
		if (getDeltaDepth(hitCoord) > 0.0) return 0.0;
		hitCoord += dir;
		if (getDeltaDepth(hitCoord) > 0.0) return 0.0;
	//}
	return 1.0;
}
#endif

void main() {
	vec4 g0 = texture(gbuffer0, texCoord); // Normal.xy, metallic/roughness, occlusion
	vec4 g1 = texture(gbuffer1, texCoord); // Basecolor.rgb, 
	float depth = texture(gbufferD, texCoord).r * 2.0 - 1.0; // 0 - 1 => -1 - 1
	// TODO: store_depth
	// float depth = (1.0 - g0.a) * 2.0 - 1.0;

	vec3 n;
	n.z = 1.0 - abs(g0.x) - abs(g0.y);
	n.xy = n.z >= 0.0 ? g0.xy : octahedronWrap(g0.xy);
	n = normalize(n);

	vec3 p = getPos(eye, eyeLook, viewRay, depth);
	vec2 metrough = unpackFloat(g0.b);
	
	vec3 v = normalize(eye - p);
	float dotNV = dot(n, v);
	
	vec3 albedo = surfaceAlbedo(g1.rgb, metrough.x); // g1.rgb - basecolor
	vec3 f0 = surfaceF0(g1.rgb, metrough.x);
	
	float visibility = 1.0;
#ifndef _NoShadows
	if (lightShadow == 1) {
		vec4 lampPos = LWVP * vec4(p, 1.0);
		if (lampPos.w > 0.0) {
			visibility = shadowTest(lampPos.xyz / lampPos.w);
		}
	}
#endif

	// Per-light
	// vec3 l = lightDir; // lightType == 0 // Sun
	vec3 h = normalize(v + l);
	float dotNH = dot(n, h);
	float dotVH = dot(v, h);
	float dotNL = dot(n, l);
	// float dotLV = dot(l, v);
	// float dotLH = dot(l, h);

#ifdef _Cycles
	fragColor.rgb = orenNayarDiffuseBRDF(albedo, metrough.y, dotNV, dotNL, dotVH) + specularBRDF(f0, metrough.y, dotNL, dotNH, dotNV, dotVH);
#else
	fragColor.rgb = lambertDiffuseBRDF(albedo, dotNL) + specularBRDF(f0, metrough.y, dotNL, dotNH, dotNV, dotVH);
#endif
	
	// Aniso spec
	// #ifdef _Aniso
	// float shinyParallel = metrough.y;
	// float shinyPerpendicular = 0.08;
	// vec3 fiberDirection = vec3(0.0, 1.0, 8.0);
	// fragColor.rgb = diffuseBRDF(albedo, metrough.y, dotNV, dotNL, dotVH, dotLV) + wardSpecular(n, h, dotNL, dotNV, dotNH, fiberDirection, shinyParallel, shinyPerpendicular);
	// #endif

	fragColor.rgb *= lightColor;

#ifdef _LampColTex
	// fragColor.rgb *= texture(texlampcolor, envMapEquirect(l)).rgb;
	fragColor.rgb *= pow(texture(texlampcolor, l.xy).rgb, vec3(2.2));
#endif
	
#ifdef _SSS
	if (floor(g1.a) == 2) {
		fragColor.rgb += fragColor.rgb * SSSSTransmittance(1.0, 0.005, p, n, l, shadowMap, LWVP);
	}
#endif

#ifdef _SSRS
	float tvis = traceShadow(-l, p);
	// vec2 coords = getProjectedCoord(hitCoord);
	// vec2 deltaCoords = abs(vec2(0.5, 0.5) - coords.xy);
	// float screenEdgeFactor = clamp(1.0 - (deltaCoords.x + deltaCoords.y), 0.0, 1.0);
	// tvis *= screenEdgeFactor;
	visibility *= tvis;
#endif

	fragColor.rgb *= visibility;
}
