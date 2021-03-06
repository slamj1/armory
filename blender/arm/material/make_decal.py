import arm.material.cycles as cycles
import arm.material.mat_state as mat_state
import arm.material.mat_utils as mat_utils
import arm.utils

def make(context_id):
    con_decal = mat_state.data.add_context({ 'name': context_id, 'depth_write': False, 'compare_mode': 'less', 'cull_mode': 'clockwise',
        'blend_source': 'source_alpha',
        'blend_destination': 'inverse_source_alpha',
        'blend_operation': 'add',
        'color_write_alpha': False
    })

    vert = con_decal.make_vert()
    frag = con_decal.make_frag()
    geom = None
    tesc = None
    tese = None

    vert.add_uniform('mat4 WVP', '_worldViewProjectionMatrix')
    vert.add_uniform('mat3 N', '_normalMatrix')
    vert.add_out('vec4 wvpposition')
    vert.add_out('vec3 wnormal')

    vert.write('wnormal = N * vec3(0.0, 0.0, 1.0);')
    vert.write('wvpposition = WVP * vec4(pos, 1.0);')
    vert.write('gl_Position = wvpposition;')
    
    frag.add_include('../../Shaders/compiled.glsl')
    frag.add_include('../../Shaders/std/gbuffer.glsl')
    frag.ins = vert.outs
    frag.add_uniform('sampler2D gbufferD')
    frag.add_uniform('mat4 invVP', '_inverseViewProjectionMatrix')
    frag.add_uniform('mat4 invW', '_inverseWorldMatrix')
    frag.add_uniform('vec3 eye', '_cameraPosition')
    frag.add_out('vec4[2] fragColor')

    frag.write_main_header('    vec3 n = normalize(wnormal);')

    frag.write_main_header('    vec2 screenPosition = wvpposition.xy / wvpposition.w;')
    frag.write_main_header('    vec2 depthCoord = screenPosition * 0.5 + 0.5;')
    frag.write_main_header('    float depth = texture(gbufferD, depthCoord).r * 2.0 - 1.0;')
    
    frag.write_main_header('    vec3 wpos = getPos2(invVP, depth, depthCoord);')
    frag.write_main_header('    vec4 mpos = invW * vec4(wpos, 1.0);')
    frag.write_main_header('    if (abs(mpos.x) > 1.0) discard;')
    frag.write_main_header('    if (abs(mpos.y) > 1.0) discard;')
    frag.write_main_header('    if (abs(mpos.z) > 1.0) discard;')
    
    frag.write_main_header('    vec3 vVec = normalize(eye - wpos);')
    frag.write_main_header('    vec2 texCoord = mpos.xy * 0.5 + 0.5;')

    frag.write('vec3 basecol;')
    frag.write('float roughness;')
    frag.write('float metallic;')
    frag.write('float occlusion;')
    cycles.parse(mat_state.nodes, con_decal, vert, frag, geom, tesc, tese, parse_opacity=False)

    frag.write('n /= (abs(n.x) + abs(n.y) + abs(n.z));')
    frag.write('n.xy = n.z >= 0.0 ? n.xy : octahedronWrap(n.xy);')
    
    if cycles.basecol_texname == '':
        frag.write('const float alpha = 1.0;')
    else:
        frag.write('const float alpha = {0}.a;'.format(cycles.basecol_texname))

    frag.write('fragColor[0] = vec4(n.xy, packFloat(metallic, roughness), alpha);')
    frag.write('fragColor[1] = vec4(basecol.rgb, alpha);')

    return con_decal
