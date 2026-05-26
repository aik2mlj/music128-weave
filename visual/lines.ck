@import "../lib/meshlines.ck"
@import "../sounds/bpm.ck"

public class Lines extends GGen {
    0.01 => static float LINE_WIDTH;
    @(0.2, 0.2, 0.2) => static vec3 LINE_COLOR;

    -2 * 16 / 9 => static float MIN_X;
    2 * 16 / 9 => static float MAX_X;
    -2 => static float MIN_Y;
    2 => static float MAX_Y;
    -10 => static float MIN_Z;
    5 => static float MAX_Z;

    16 => static int MAX_PLAYER_NUM;
    MeshLines @allLines[MAX_PLAYER_NUM][0];
    float vertPositions[0];  // world-space x of for vertical lines
    float horizPositions[0]; // for horizontal lines
    0 => int vertCount;
    0 => int horizCount;

    vec3 color;

    OscOut @xmit;
    BPM bpm;

    fun @construct(OscOut @x, BPM @b) {
        x @=> xmit;
        b @=> bpm;
    }

    fun float gt2x(float gt) { return Math.map2(gt, 0., 1., MIN_X, MAX_X); }
    fun float gt2y(float gt) { return Math.map2(gt, 0., 1., MIN_Y, MAX_Y); }

    fun addLine(int id, int direction, float pos, vec3 color) {
        <<< "addline" >>>;
        MeshLines line --> this;

        allLines[id] << line;

        color => this.color;
        line.width(LINE_WIDTH);

        if (direction == 0) {
            line.posY(gt2y(pos));
            horizCount++;
            horizPositions << gt2y(pos);
        } else {
            line.posX(gt2x(pos));
            vertCount++;
            vertPositions << gt2x(pos);
        }

        spork ~ drawLine(direction, line);
        // TODO: currectly animate is going on forever
        spork ~ animateWidth(line);
        spork ~ scrollLine(direction, line);
        spork ~ colorizeLine(line);

        updateSegs();
    }

    fun void drawLine(int direction, MeshLines @line) {
        now => time start;
        0.5::second => dur transTime;
        Lib.random(@(5., 0, 0)) => vec3 px0;
        Lib.random(@(1.7, 0, 0)) => vec3 px1;
        Lib.random(@(-1.7, 0, 0)) => vec3 px2;
        Lib.random(@(-5., 0, 0)) => vec3 px3;
        Lib.random(@(0., 5., 0)) => vec3 py0;
        Lib.random(@(0., 1.7, 0)) => vec3 py1;
        Lib.random(@(0., -1.7, 0)) => vec3 py2;
        Lib.random(@(0., -5, 0)) => vec3 py3;
        // drawing animation
        while (now - start < transTime) {
            GG.nextFrame() => now;
            (now - start) / transTime => float t;
            if (direction == 0) {
                Lib.bezier(px0, px1 + @(3.3 * (1 - t), 0, 0), px2 + @(6.6 * (1 - t), 0, 0),
                           px3 + @(10 * (1 - t), 0, 0), 200) => line.positions;
            } else {
                Lib.bezier(py0, py1 + @(0, 3.3 * (1 - t), 0), py2 + @(0, 6.6 * (1 - t), 0),
                           py3 + @(0, 10 * (1 - t), 0), 200) => line.positions;
            }
        }
    }

    fun void animateWidth(MeshLines @line) {
        now => time t0;
        // (2 * Math.PI) / (10 * (beatLen / 1::second)) => float speed;
        1 => float speed;
        0.2 => float dcolor;
        while (true) {
            GG.nextFrame() => now;
            (now - t0) / 1::second => float t;
            Math.sin(t * speed) => float inc;
            LINE_WIDTH + inc * 0.005 => line.width;
            // @(LINE_COLOR.x + (inc + Math.randomf()) * dcolor,
            //   LINE_COLOR.y + (inc + Math.randomf()) * dcolor,
            //   LINE_COLOR.z + (inc + Math.randomf()) * dcolor) => line.color;
        }
    }

    fun void scrollLine(int direction, MeshLines @line) {
        0.5 => float speed;
        -5. => float z0;
        line.posZ(z0);
        // scrolling
        now => time start;
        while (true) {
            GG.nextFrame() => now;
            (now - start) / 1::second => float t;
            // scroll posZ within MIN_Z and MAX_Z, wrap around
            (z0 + speed * t - MIN_Z) % (MAX_Z - MIN_Z) + MIN_Z => float z;
            line.posZ(z);
        }
    }

    fun void colorizeLine(MeshLines @line) {
        while (true) {
            GG.nextFrame() => now;
            line.posZ() => float z;
            // color the line: the closer to MIN_Z the darker
            // the closer to MAX_Z the brighter
            (z - MIN_Z) / (MAX_Z - MIN_Z) => float zScale;
            @(color.x, color.y, color.z, zScale) => line.color;
        }
    }

    fun void updatePositions(int id, int direction[], float pos[]) {
        for (int i; i < allLines[id].size(); i++) {
            if (direction[i] == 0)
                allLines[id][i].posY(gt2y(pos[i]));
            else
                allLines[id][i].posX(gt2x(pos[i]));
        }
    }
    fun dur[] computeSegments(float positions[], int count) {
        float bounds[count + 2]; // line locations including the outbounds

        MIN_X => bounds[0];
        MAX_X => bounds[count + 1];

        for (0 => int i; i < count; i++)
            positions[i] => bounds[i + 1];

        // insertion sort line locations
        for (1 => int i; i < bounds.size(); i++) {
            bounds[i] => float key;
            i - 1 => int j;
            while (j >= 0 && bounds[j] > key) {
                bounds[j] => bounds[j + 1];
                j--;
            }
            key => bounds[j + 1];
        }

        MAX_X - MIN_X => float totalWidth;
        dur segments[count + 1];
        // find the dur of each segment
        for (0 => int i; i < segments.size(); i++)
            ((bounds[i + 1] - bounds[i]) / totalWidth) * bpm.quarterNote => segments[i];
        return segments;
    }

    fun void updateSegs() {
        <<< "updateSegs" >>>;
        computeSegments(vertPositions, vertCount) @=> dur segXs[];
        computeSegments(horizPositions, horizCount) @=> dur segYs[];

        // send osc
        sendRhythmSegs(segXs, segYs);
    }

    fun void sendRhythmSegs(dur segXs[], dur segYs[]) {
        <<< "Sending rhythm segments", segXs.size(), segYs.size() >>>;
        // <<< "segXs:" >>>;
        // for (int n; n < segXs.size(); ++n)
        //     <<< "\t", segXs[n] / 1::samp >>>;
        // <<< "segYs:" >>>;
        // for (int n; n < segYs.size(); ++n)
        //     <<< "\t", segYs[n] / 1::samp >>>;
        xmit.start("/server/segs");
        segXs.size() => xmit.add; // number of elements
        segYs.size() => xmit.add; // number of elements
        for (int i; i < segXs.size(); i++)
            segXs[i] / 1::samp => xmit.add; // add each float
        for (int i; i < segYs.size(); i++)
            segYs[i] / 1::samp => xmit.add; // add each float
        xmit.send();
    }
}
