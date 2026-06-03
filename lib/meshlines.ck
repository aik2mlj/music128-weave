/*-----------------------------------------------------------------------------
name: meshlines.ck
desc: 3D screen-space projected lines. Supports colors, per-vertex widths,
dashed lines, alpha-map brushstroke textures, animation, and more.
This implementation is inspired by THREE.MeshLine, with the addition of
significant performance improvements, bug fixes, and API changes.

For testing alpha-mapping, download the brushstroke texture from:
https://chuck.stanford.edu/chugl/examples/data/textures/brush-texture.png
and uncomment the relevant lines below.

Some remarks:
- this line renderer performs best on vertex data that is relatively dense
and smooth, e.g. as one would get with bezier curves or some other spline.
- prefer using GLines for lines that have sharp corners and whose vertices
are coplanar.
- if sizeAttenuation == true, the line will appear smaller the farther
it is, and .width corresponds to world-space width.
- if sizeAttenuation == false, the line will have constant size, and
.width corresponds to width in pixels.
- looping is janky when it breaks continuity or suddenly jumps a large
distance. in those cases prefer creating the loop yourself via adding
more points.

references:
- https://mattdesl.svbtle.com/drawing-lines-is-hard
- https://github.com/spite/THREE.MeshLine?tab=readme-ov-file
- https://threlte.xyz/docs/reference/extras/meshline-material

possible improvements:
- add depth tinting, like in noclip's gfx/helpers/DebugDraw

author: Andrew Zhu Aday (https://ccrma.stanford.edu/~azaday/)
  date: December 2025
//---------------------------------------------------------------------------*/

// scene setup
new GOrbitCamera => GG.scene().camera;
GG.scene().backgroundColor(.8 * Color.WHITE);

// generates a random vec3
fun vec3 random() {
    return @(Math.random2f(-10, 10), Math.random2f(-10, 10), Math.random2f(-10, 10));
}

// color palette
[Color.hex(0xed6a5a), Color.hex(0xf4f1bb), Color.hex(0x9bc1bc), Color.hex(0x5ca4a9),
 Color.hex(0xe6ebe0), Color.hex(0xf0b67f), Color.hex(0xfe5f55), Color.hex(0xd6d1b1),
 Color.hex(0xc7efcf), Color.hex(0xeef5db), Color.hex(0x50514f), Color.hex(0xf25f5c),
 Color.hex(0xffe066), Color.hex(0x247ba0), Color.hex(0x70c1b3)] @=> vec3 random_colors[];
fun vec3 randomColor() { return random_colors[Math.random2(0, random_colors.size() - 1)]; }


GGen line_transform --> GG.scene();
MeshLines lines[0];
// function to create and store a MeshLines object
fun void addLine() {
    MeshLines line --> line_transform;

    random() => vec3 p0;
    random() => vec3 p1;
    random() => vec3 p2;
    random() => vec3 p3;

    bezier(p0, p1, p2, p3, 200) => line.positions;
    [0.0, 1, 0] => line.widths; // taper the line from start to end
    [randomColor(), randomColor(), randomColor()] => line.colors;

    lines << line;
}

// add the lines to our scene
repeat(50) addLine();

// disable gamma correction and tonemapping
GG.outputPass().gamma(0);
GG.outputPass().tonemap(0);

// UI Params
UI_Float width(lines[0].width());
UI_Bool attenuate_size(lines[0].sizeAttenuation());
UI_Float scale_down(lines[0].scaleDown());
UI_Float dash_offset(lines[0].dashOffset());
UI_Float dash_len(1.0);
UI_Float dash_ratio(lines[0].dashRatio());
UI_Float4 color(lines[0].color());
UI_Float visibility(lines[0].visibility());

["None", "Segment", "Blend", "Cycle"] @=> string color_modes[];
UI_Int color_mode_idx(lines[0].colorMode());
UI_Bool loop(lines[0].loop());

["None", "Blend", "Cycle"] @=> string width_modes[];
UI_Int width_mode(lines[0].widthMode());

UI_Bool animate(true);

// uncomment this and all lines with `alpha_map` to test applying a brush texture!
// (first you need to get a brush texture)
Texture.load(me.dir() + "./brush-texture.png") @=> Texture brush_texture;
UI_Bool alpha_map(false);

// render loop
while (1) {
    GG.nextFrame() => now;
    .1 * GG.dt() => line_transform.rotateY;

    // build UI widgets
    UI.slider("width", width, 0, 1);
    UI.checkbox("animate", animate);
    if (!animate.val()) {
        UI.slider("dash offset", dash_offset, 0, 20);
    }
    UI.slider("dash len", dash_len, 0, 1);
    UI.slider("dash ratio", dash_ratio, 0, 1);
    UI.colorEdit("color", color);
    UI.slider("visibility", visibility, -2, 2);
    UI.listBox("color mode", color_mode_idx, color_modes);
    UI.listBox("width mode", width_mode, width_modes);
    UI.checkbox("attenuate size", attenuate_size);
    UI.slider("scale down", scale_down, 0, .1);
    UI.checkbox("loop", loop);
    UI.checkbox("brush texture", alpha_map);

    // update all lines
    for (auto line : lines) {
        line.width(width.val());
        line.sizeAttenuation(attenuate_size.val());
        line.scaleDown(scale_down.val());
        line.color(color.val());
        line.visibility(visibility.val());
        line.colorMode(color_mode_idx.val());
        line.widthMode(width_mode.val());
        line.loop(loop.val());

        line.dashLength(dash_len.val());
        line.dashRatio(dash_ratio.val());
        // animate via dash offset
        if (animate.val()) {
            line.dashOffset(.2 * (now / second));
        } else {
            line.dashOffset(dash_offset.val());
        }

        if (alpha_map.val()) {
            line.alphaMap(brush_texture);
        } else {
            line.alphaMap(MeshLines.white_pixel);
        }
    }
}

// bezier curve builder
fun vec3[] bezier(vec3 p0, vec3 p1, vec3 p2, vec3 p3, // control points
                  int npoints) {
    vec3 points[0];

    1.0 / npoints => float inc;
    for (float t; t <= 1; inc +=> t) {
        1 - t => float k;
        points << (k * k * k * p0 + 3 * k * k * t * p1 + 3 * k * t * t * p2 + t * t * t * p3);
    }

    return points;
}

// implementation
public class MeshLines extends GMesh {
    // material shader, shared by all MeshLines instances
    static ShaderDesc shader_desc;
    static Shader @shader;

    // internal shader enums (don't touch!)
    0 => static int BIND_ATTRIB_POSITIONS;
    1 => static int BIND_ATTRIB_COLORS;
    2 => static int BIND_ATTRIB_WIDTH;
    3 => static int BIND_COLOR;
    4 => static int BIND_COLOR_MODE;
    5 => static int BIND_WIDTH;
    6 => static int BIND_SIZE_ATTENUATION;
    7 => static int BIND_SCALE_DOWN;
    8 => static int BIND_DASH;
    9 => static int BIND_VISIBILITY;
    10 => static int BIND_LOOP;
    11 => static int BIND_WIDTH_MODE;
    12 => static int BIND_ALPHA_MAP;
    13 => static int BIND_SAMPLER;
    14 => static int BIND_ALPHA_CUTOFF;
    15 => static int BIND_TEXTURE_SCALE;

    // color mode enum
    0 => static int COLOR_MODE_NONE; // ignore the a_color array entirely
    1 => static int
              COLOR_MODE_SEGMENT; // distribute a_colors evenly over entire line, with no blending
    2 => static int
              COLOR_MODE_BLEND; // distribute a_colors evenly over entire line, with linear blending
    3 => static int COLOR_MODE_CYCLE; // a_color[idx % a_color.size] cycle color every line segment

    // width mode enum
    0 => static int WIDTH_MODE_NONE;  // ignore the widths array entirely
    1 => static int WIDTH_MODE_BLEND; // distribute widths over entire line, with linear blending
    2 => static int WIDTH_MODE_CYCLE; // cycle width every line segment

    // default binding values
    static float empty_float_arr[4];
    [1.0, 1, 1, 1] @=> static float white_float_arr[];
    static Texture @white_pixel;
    if (white_pixel == null) {
        Texture tex @=> white_pixel;
        tex.write(white_float_arr);
    }

    // local params
    Material line_material;
    Geometry line_geo; // just used to set vertex count
    int n_positions;   // #line vertices

    // constructor
    fun MeshLines() {
        // create shader if not already created
        if (shader == null) {
            me.dir() + "meshlines.wgsl" => shader_desc.vertexPath;
            me.dir() + "meshlines.wgsl" => shader_desc.fragmentPath;
            null @=> shader_desc.vertexLayout;
            new Shader(shader_desc) @=> shader;
        }

        // init material shader
        line_material.shader(shader);
        line_material.topology(Material.Topology_TriangleStrip);

        // init storage buffers
        line_material.storageBuffer(BIND_ATTRIB_POSITIONS, empty_float_arr);
        line_material.storageBuffer(BIND_ATTRIB_COLORS, white_float_arr);
        line_material.storageBuffer(BIND_ATTRIB_WIDTH, white_float_arr);

        // prep geo
        line_geo.vertexCount(0);

        // set geo and mat on GMesh
        line_geo => this.geo;
        line_material => this.mat;

        // init uniforms
        width(.1);
        sizeAttenuation(true);
        scaleDown(0.0);
        _dash(@(0, 0, .5));
        color(Color.WHITE);
        visibility(1.0);
        colorMode(COLOR_MODE_BLEND);
        loop(false);
        widthMode(WIDTH_MODE_BLEND);
        alphaMap(white_pixel);
        sampler(TextureSampler.linear());
        alphaCutoff(0);
        textureScale(@(1, 1));
    }

    // independent clone: fresh material + geometry with all uniforms copied.
    // positions are NOT copied (they live in an unreadable storage buffer) —
    // the caller is expected to set them (e.g. rebuilt from bezier ctrl points).
    fun MeshLines clone() {
        MeshLines l;
        l.width(width());
        l.color(color());
        l.visibility(visibility());
        l.colorMode(colorMode());
        l.widthMode(widthMode());
        l.loop(loop());
        l.sizeAttenuation(sizeAttenuation());
        l.scaleDown(scaleDown());
        return l;
    }

    // == PUBLIC API =======================================================
    fun void positions(vec3 p[]) {
        if (p == null || p.size() < 2) {
            line_material.storageBuffer(BIND_ATTRIB_POSITIONS, empty_float_arr);
            0 => n_positions;
        } else {
            line_material.storageBuffer(BIND_ATTRIB_POSITIONS, p);
            p.size() => n_positions;
        }
        _updateVertexCount();
    }

    fun void colors(vec3 colors[]) {
        if (colors == null || colors.size() == 0) {
            line_material.storageBuffer(BIND_ATTRIB_COLORS, white_float_arr);
        } else {
            vec4 co[0];
            for (auto c : colors)
                co << @(c.r, c.g, c.b, 1.0);
            line_material.storageBuffer(BIND_ATTRIB_COLORS, co);
        }
    }

    fun void colors(vec4 colors[]) {
        if (colors == null || colors.size() == 0) {
            line_material.storageBuffer(BIND_ATTRIB_COLORS, white_float_arr);
        } else {
            line_material.storageBuffer(BIND_ATTRIB_COLORS, colors);
        }
    }

    fun void widths(float w[]) {
        if (w == null || w.size() == 0) {
            line_material.storageBuffer(BIND_ATTRIB_WIDTH, white_float_arr);
        } else {
            line_material.storageBuffer(BIND_ATTRIB_WIDTH, w);
        }
    }

    fun vec4 color() { return line_material.uniformFloat4(BIND_COLOR); }
    fun void color(vec3 v) { line_material.uniformFloat4(BIND_COLOR, @(v.r, v.g, v.b, 1.0)); }
    fun void color(vec4 v) { line_material.uniformFloat4(BIND_COLOR, v); }

    fun void colorMode(int i) { line_material.uniformInt(BIND_COLOR_MODE, i); }
    fun int colorMode() { return line_material.uniformInt(BIND_COLOR_MODE); }

    fun float dashOffset() { return line_material.uniformFloat3(BIND_DASH).x; }
    fun void dashOffset(float f) {
        _dash() => vec3 d;
        f => d.x;
        line_material.uniformFloat3(BIND_DASH, d);
    }

    // set the length of each dashed segment as a fractional ratio of the entire line
    // range: [0, 1]
    fun float dashLength() { return line_material.uniformFloat3(BIND_DASH).y; }
    fun void dashLength(float f) {
        _dash() => vec3 d;
        f => d.y;
        line_material.uniformFloat3(BIND_DASH, d);
    }

    fun float dashRatio() { return line_material.uniformFloat3(BIND_DASH).z; }
    fun void dashRatio(float f) {
        _dash() => vec3 d;
        f => d.z;
        line_material.uniformFloat3(BIND_DASH, d);
    }

    fun float scaleDown() { return line_material.uniformFloat(BIND_SCALE_DOWN); }
    fun void scaleDown(float f) { line_material.uniformFloat(BIND_SCALE_DOWN, f); }

    fun int sizeAttenuation() { return line_material.uniformInt(BIND_SIZE_ATTENUATION); }
    fun void sizeAttenuation(int attenuate) {
        line_material.uniformInt(BIND_SIZE_ATTENUATION, attenuate ? true : false);
    }

    // set the width in worldspace units
    fun void width(float w) { line_material.uniformFloat(BIND_WIDTH, w); }
    fun float width() { return line_material.uniformFloat(BIND_WIDTH); }

    fun void widthMode(int m) { line_material.uniformInt(BIND_WIDTH_MODE, m); }
    fun int widthMode() { return line_material.uniformInt(BIND_WIDTH_MODE); }

    // percentage of line that is shown
    fun void visibility(float w) { line_material.uniformFloat(BIND_VISIBILITY, w); }
    fun float visibility() { return line_material.uniformFloat(BIND_VISIBILITY); }

    fun void loop(int b) {
        line_material.uniformInt(BIND_LOOP, b);
        _updateVertexCount();
    }
    fun int loop() { return line_material.uniformInt(BIND_LOOP); }

    fun void alphaMap(Texture t) { line_material.texture(BIND_ALPHA_MAP, t); }
    fun Texture alphaMap() { return line_material.texture(BIND_ALPHA_MAP); }

    fun void sampler(TextureSampler s) { line_material.sampler(BIND_SAMPLER, s); }
    fun TextureSampler sampler() { return line_material.sampler(BIND_SAMPLER); }

    fun void alphaCutoff(float c) { line_material.uniformFloat(BIND_ALPHA_CUTOFF, c); }
    fun float alphaCutoff() { return line_material.uniformFloat(BIND_ALPHA_CUTOFF); }

    fun void textureScale(vec2 s) { line_material.uniformFloat2(BIND_TEXTURE_SCALE, s); }
    fun vec2 textureScale() { return line_material.uniformFloat2(BIND_TEXTURE_SCALE); }
    // == END PUBLIC API =======================================================

    // == PRIVATE API ==========================================================
    fun vec3 _dash() { return line_material.uniformFloat3(BIND_DASH); }
    fun void _dash(vec3 v) { line_material.uniformFloat3(BIND_DASH, v); }

    fun void _updateVertexCount() {
        if (loop())
            line_geo.vertexCount((n_positions + 1) * 2);
        else
            line_geo.vertexCount(n_positions * 2);
    }
}
