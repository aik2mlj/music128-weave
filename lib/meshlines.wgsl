#include FRAME_UNIFORMS
#include DRAW_UNIFORMS

struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) v_dash_counter: f32, // ratio of vertex along line segment, from [0,1]. vertex N/2 has value .5
    @location(1) v_visibility_counter: f32, // ratio of vertex along line segment, from [0,1]. vertex N/2 has value .5
    @location(2) v_color: vec4f,
    @location(3) v_uv: vec2f,
};


const COLOR_MODE_NONE = 0; // ignore the a_color array entirely
const COLOR_MODE_SEGMENT = 1; // distribute a_colors evenly over entire line, with no blending
const COLOR_MODE_BLEND = 2; // distribute a_colors evenly over entire line, with linear blending
const COLOR_MODE_CYCLE = 3; // a_color[idx % a_color.size] cycle color every line/vertex segment

const WIDTH_MODE_NONE = 0; // ignore width attribute
const WIDTH_MODE_BLEND = 1; // distribute a_widths evenly over line with linear blending
const WIDTH_MODE_CYCLE = 2; // cycle width for every line/vertex segment

@group(1) @binding(0) var<storage> a_position : array<f32>;  // f32 instead of vec3f because of bullshit byte alignment 
@group(1) @binding(1) var<storage> a_color : array<vec4f>; 
@group(1) @binding(2) var<storage> a_width : array<f32>;  // per-vertex width modifier

@group(1) @binding(3) var<uniform> u_color : vec4f;
@group(1) @binding(4) var<uniform> u_color_mode : i32;
@group(1) @binding(5) var<uniform> u_thickness : f32;
@group(1) @binding(6) var<uniform> u_size_attenuation : i32;
@group(1) @binding(7) var<uniform> u_scale_down : f32;
@group(1) @binding(8) var<uniform> u_dash : vec3f; // @(offset, len, ratio)
@group(1) @binding(9) var<uniform> u_visibility : f32; // % of line that is shown
@group(1) @binding(10) var<uniform> u_loop : i32;
@group(1) @binding(11) var<uniform> u_width_mode : i32;

// alpha params
@group(1) @binding(12) var alpha_map: texture_2d<f32>;
@group(1) @binding(13) var texture_sampler: sampler;
@group(1) @binding(14) var<uniform> u_alpha_cutoff : f32;
@group(1) @binding(15) var<uniform> u_texture_scale : vec2f;

fn intoScreen(i: vec4f) -> vec2f {
    return vec2f(u_frame.resolution.xy) * (0.5 * i.xy / i.w + 0.5);
}

@vertex
fn vs_main(
    @builtin(instance_index) instance_idx : u32,    // carry over from everything being indexed...
    @builtin(vertex_index) vertex_idx : u32,        // used to determine which polygon we are drawing
) -> VertexOutput {
    var out : VertexOutput;
    var u_Draw : DrawUniforms = u_draw_instances[instance_idx];
    let proj_view_model = u_frame.projection * u_frame.view * u_Draw.model;
    let resolution = vec2f(u_frame.resolution.xy);

    // @TODO make param
    let line_num_vertices = i32(arrayLength(&a_position) / 3);
    let line_num_colors = i32(arrayLength(&a_color));
    let line_num_widths = i32(arrayLength(&a_width));
    let orientation = f32((i32(vertex_idx) % 2) * 2 - 1); // -1 if vertex_idx is even, else 1

    // compute which 
    let segment_idx = i32(vertex_idx) / 2;
    var curr_idx : i32 = 0;
    var prev_idx : i32 = 0;
    var next_idx : i32 = 0;
    if (u_loop > 0) {
        curr_idx = (i32(vertex_idx) / 2) % line_num_vertices;
        prev_idx = select(curr_idx - 1, line_num_vertices - 1, curr_idx == 0);
        next_idx = select(curr_idx + 1, 0, curr_idx == line_num_vertices - 1);
    } else {
        curr_idx = i32(vertex_idx) / 2;
        prev_idx = max(curr_idx - 1, 0);
        next_idx = min(curr_idx + 1, line_num_vertices - 1);
    }

    var actual_thickness = u_thickness;
    if (line_num_widths > 0) {
        if (u_width_mode == WIDTH_MODE_BLEND) {
            let width_idx = (f32(curr_idx) / f32(line_num_vertices-1) * f32(line_num_widths-1));
            actual_thickness *= mix(
                a_width[i32(width_idx) % line_num_widths], 
                a_width[(i32(width_idx) + 1) % line_num_widths], 
                fract(width_idx)
            );
        }
        else if (u_width_mode == WIDTH_MODE_CYCLE) {
            actual_thickness *= a_width[segment_idx % line_num_widths];
        }
    }


    let curr_pos = vec3f(
        a_position[curr_idx * 3 + 0],
        a_position[curr_idx * 3 + 1],
        a_position[curr_idx * 3 + 2],
    );
    let curr_proj = proj_view_model * vec4f(curr_pos, 1.0);
    let curr_normed = curr_proj / curr_proj.w;
    let curr_screen = intoScreen(curr_normed);

    let next_pos = vec3f(
        a_position[next_idx * 3 + 0],
        a_position[next_idx * 3 + 1],
        a_position[next_idx * 3 + 2],
    );
    let next_proj = proj_view_model * vec4f(next_pos, 1.0);
    let next_normed = next_proj / next_proj.w;
    let next_screen = intoScreen(next_normed);

    let prev_pos = vec3f(
        a_position[prev_idx * 3 + 0],
        a_position[prev_idx * 3 + 1],
        a_position[prev_idx * 3 + 2],
    );
    let prev_proj = proj_view_model * vec4f(prev_pos, 1.0);
    let prev_normed = prev_proj / prev_proj.w;
    let prev_screen = intoScreen(prev_normed);

    var dir: vec2f = vec2f(0.0);
    if (all(prev_screen == curr_screen)) { // first point
        dir = normalize(next_screen - curr_screen);
    } 
    else if (all(next_screen == curr_screen)) { // last point
        dir = normalize(curr_screen - prev_screen);
    } else { // middle point
        let inDir = curr_screen - prev_screen;
        let  outDir = next_screen - curr_screen;
        let  fullDir = next_screen - prev_screen;

        if(length(fullDir) > 0.0) {
            dir = normalize(fullDir);
        } else if(length(inDir) > 0.0){
            dir = normalize(inDir);
        } else {
            dir = normalize(outDir);
        }

        // old approach
        // let dir1 = normalize( curr_screen - prev_screen );
        // let dir2 = normalize( next_screen - prev_screen );
        // dir = normalize( dir1 + dir2 );
        // vec2 perp = vec2( -dir1.y, dir1.x );
        // vec2 miter = vec2( -dir.y, dir.x );
        //w = clamp( w / dot( miter, perp ), 0., 4. * lineWidth * width );
    }

    var normal = vec2(-dir.y, dir.x);

    if(u_size_attenuation > 0) {
        normal /= curr_proj.w;
        normal *= min(resolution.x, resolution.y);
    }

    if (u_scale_down > 0.0) {
        let dist = length(next_normed - prev_normed);
        normal *= smoothstep(0.0, u_scale_down, dist);
    }

    let offsetInScreen = actual_thickness * normal * orientation * 0.5;
    let withOffsetScreen = curr_screen + offsetInScreen;
    let withOffsetNormed = vec3f((2.0 * withOffsetScreen/vec2f(u_frame.resolution.xy) - 1.0), curr_normed.z);

    let counter = f32(segment_idx) / f32(line_num_vertices);
    var color = u_color;
    if (line_num_colors > 0 && u_color_mode > 0) {
        if (u_color_mode == COLOR_MODE_CYCLE) {
            color *= a_color[segment_idx % line_num_colors];
        }
        else if (u_color_mode == COLOR_MODE_SEGMENT) {
            color *= a_color[min(i32(counter * f32(line_num_colors)), line_num_colors -1)];
        }
        else if (u_color_mode == COLOR_MODE_BLEND) {
            let color_idx = (f32(curr_idx) / f32(line_num_vertices-1) * f32(line_num_colors-1));
            color *= mix(
                a_color[i32(color_idx) % line_num_colors], 
                a_color[(i32(color_idx) + 1) % line_num_colors], 
                fract(color_idx)
            );
        }
    }

    out.position = curr_proj.w * vec4f(withOffsetNormed, 1.0);
    out.v_dash_counter = f32(curr_idx) / f32(line_num_vertices); // this works better with dash + loop
    out.v_visibility_counter = counter;
    out.v_color = color;
    if (u_loop > 0) {
        out.v_uv.x = f32(segment_idx) / f32(line_num_vertices);
    } else {
        out.v_uv.x = f32(curr_idx) / f32(line_num_vertices - 1);
    }
    out.v_uv.y = select(0.0, 1.0, orientation > 0);

    return out;
}

@fragment
fn fs_main(in : VertexOutput) -> @location(0) vec4f {
    let dashOffset = u_dash.x;
    let dashArray = u_dash.y;
    let dashRatio = u_dash.z;

    var dash_discard = false;
    if (dashArray > 0.0 && dashRatio > 0.0) {
        dash_discard = (modf((in.v_dash_counter + dashOffset) / dashArray).fract - (dashRatio)) < 0.0;
    }

    var color = in.v_color;
    color.a *= step(in.v_visibility_counter, u_visibility);
    color.a *= textureSample(alpha_map, texture_sampler, in.v_uv * u_texture_scale).r; // @TODO mult by alpha scale

    if (dash_discard || color.a <= u_alpha_cutoff) {
        discard;
    }

    return color;
}
