public class Fireflies extends GGen {
    @(255, 230, 109) / 255.0 => vec3 FIREFLY_COLOR;
    // many fireflies out there
    600 => int FIREFLY_NUM;
    -30 => float minX;
    -30 => float minZ;
    30 => float maxX => float maxZ;
    1 => float maxY;
    -10 => float minY;

    SphereGeometry sphere_geo_many(0.02, 32, 16, 0., 2 * Math.pi, 0., Math.pi);
    FlatMaterial mat_many[FIREFLY_NUM];
    GMesh fireflies[FIREFLY_NUM];
    float init_time[FIREFLY_NUM];   // the initial time offset for each firefly
    float fade_freq[FIREFLY_NUM];   // fade in/out frequency of each firefly
    float intensities[FIREFLY_NUM]; // randomized brightness of each firefly

    float vx[FIREFLY_NUM];
    float vy[FIREFLY_NUM];
    float vz[FIREFLY_NUM];

    fun @construct() {
        for (int i; i < FIREFLY_NUM; i++) {
            Math.random2f(0.1, 3.) => fade_freq[i];
            Math.random2f(0., 2.) => init_time[i];
            Math.random2f(0.1, 0.5) => intensities[i];
        }
        for (auto x : mat_many) {
            x.color(FIREFLY_COLOR * Math.random2f(0., 0.3));
        }
        for (int i; i < FIREFLY_NUM; i++) {
            GMesh sphere(sphere_geo_many, mat_many[i]) @=> fireflies[i];
            fireflies[i] --> this;
            @(Math.random2f(minX, maxX), Math.random2f(minY, maxY), Math.random2f(minZ, maxZ)) => fireflies[i].translate;
        }
        spork ~ fade_in_out();
        spork ~ drifting();
    }

    fun void fade_in_out() {
        // fireflies: fade in/out randomly
        now => time init_t;
        while (true) {
            GG.nextFrame() => now;
            (now - init_t) / 1::second => float t;
            for (int i; i < FIREFLY_NUM; i++) {
                FIREFLY_COLOR * intensities[i] *
                    Math.fabs(Math.sin(fade_freq[i] * t + init_time[i])) => mat_many[i].color;
            }
        }
    }

    fun void drifting() {
        // fireflies drifting randomly with velocity randomization
        0.001 => float acc_range;
        2 => float edge_buf;
        1 => float vz_mag; // the magifier of firefies' velocity at z axis
        0 => float vx_mag; // the magifier of firefies' velocity at x axis
        while (true) {
            GG.nextFrame() => now;

            if (UI.isKeyPressed(UI_Key.W)) {
                0.1 +=> vz_mag;
            } else if (UI.isKeyPressed(UI_Key.S)) {
                0.1 -=> vz_mag;
            }

            if (UI.isKeyPressed(UI_Key.A)) {
                0.01 +=> vx_mag;
            } else if (UI.isKeyPressed(UI_Key.D)) {
                0.01 -=> vx_mag;
            }

            for (int i; i < FIREFLY_NUM; i++) {
                Math.random2f(-acc_range, acc_range) +=> vx[i];
                Math.random2f(-acc_range, acc_range) +=> vy[i];
                Math.random2f(-acc_range, acc_range) +=> vz[i];

                fireflies[i].pos() => vec3 pos;

                // soft boundary
                // if (pos.x < minX + edge_buf || pos.x > maxX - edge_buf)
                //     0.9 *=> vx[i];
                // if (pos.y < minY + edge_buf || pos.y > maxY - edge_buf)
                //     0.9 *=> vy[i];
                // if (pos.z < minZ + edge_buf || pos.z > maxZ - edge_buf)
                //     0.9 *=> vz[i];
                // soft center
                if (Math.fabs(pos.x) < edge_buf || Math.fabs(pos.x) - 5 < edge_buf ||
                    Math.fabs(pos.x) + 5 < edge_buf)
                    0.99 *=> vx[i];
                if (Math.fabs(pos.y) < edge_buf)
                    0.99 *=> vy[i];
                if (Math.fabs(pos.z) < edge_buf * 5)
                    0.99 *=> vz[i];
                // boundary reflection
                if (pos.x < minX || pos.x > maxX)
                    -0.99 *=> vx[i];
                if (pos.y < minY || pos.y > maxY)
                    -0.99 *=> vy[i];
                // if (pos.z < minZ || pos.z > maxZ) -0.99 *=> vz[i];
                // wrapping
                if (pos.x < minX)
                    maxX => pos.x;
                else if (pos.x > maxX)
                    minX => pos.x;
                // if (pos.y < minY)
                //     maxY => pos.y;
                // else if (pos.y > maxY)
                //     minY => pos.y;
                if (pos.z < minZ)
                    maxZ => pos.z;
                else if (pos.z > maxZ)
                    minZ => pos.z;

                // update the postions
                // the fireflies are flying towards you, thus +GG.dt() for z axis
                @(vx[i] + GG.dt() * vx_mag + pos.x, vy[i] + pos.y,
                  vz[i] + GG.dt() * vz_mag + pos.z) => fireflies[i].pos;
            }
        }
    }
}
