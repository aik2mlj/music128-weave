public class Lib {
    // bezier curve builder
    fun static vec3[] bezier(vec3 p0, vec3 p1, vec3 p2, vec3 p3, int npoints) {
        vec3 points[0];

        1.0 / npoints => float inc;
        for (float t; t <= 1; inc +=> t) {
            1 - t => float k;
            points << (k * k * k * p0 + 3 * k * k * t * p1 + 3 * k * t * t * p2 + t * t * t * p3);
        }

        return points;
    }

    // generates a random vec3 that slightly deviate from the base
    fun static vec3 random(vec3 base) {
        return @(base.x + Math.random2f(-0.1, 0.1), base.y + Math.random2f(-0.1, 0.1),
                 base.z + Math.random2f(-0.1, 0.1));
    }

    fun static float easeOutQuad(float t) { return 1.0 - (1.0 - t) * (1.0 - t); }

    fun static float easeOutCubic(float t) { return 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t); }

    fun static float smoothstep(float t) { return t * t * (3.0 - 2.0 * t); }
}
