@import "../lib/meshlines.ck"
@import "../sounds/bpm.ck"

class LineStruct {
    MeshLines @line;
    float vertPos, horizPos; // one is the line's world coord, the other is DELETE-1
    vec3 ctrl[0];            // 4 bezier control points
    vec3 color;              // per-line color
}

public class Lines extends GGen {
    0.01 => static float LINE_WIDTH;
    @(0.2, 0.2, 0.2) => static vec3 LINE_COLOR;

    -2 * 16 / 9 => static float MIN_X;
    2 * 16 / 9 => static float MAX_X;
    -2 => static float MIN_Y;
    2 => static float MAX_Y;
    -15 => static float MIN_Z;
    0 => static float MAX_Z;

    16 => static int MAX_PLAYER_NUM;
    -10000 => static float DELETE;
    -8. => static float z0;

    LineStruct allLines[MAX_PLAYER_NUM][0];

    OscOut @xmit;
    BPM bpm;

    fun @construct(OscOut @x, BPM @b) {
        x @=> xmit;
        b @=> bpm;
    }

    fun float gt2x(float gt) { return Math.map2(gt, 0., 1., MIN_X, MAX_X); }
    fun float gt2y(float gt) { return Math.map2(gt, 0., 1., MIN_Y, MAX_Y); }

    fun void spawnLines_randomRot(int num) {
        // spawn initially num of lines that are positioned randomly and rotate randomly
        for (0 => int i; i < num; i++) {
            Math.random2(0, 1) => int direction;
            Math.randomf() => float pos;
            @(Math.randomf(), Math.randomf(), Math.randomf()) => vec3 color;
            addLine(MAX_PLAYER_NUM - 1, direction, pos, color) @=> GGen @line_tf;
            line_tf.rotY(Math.random2f(-0.5, 0.5));
        }
    }

    fun GGen @addLine(int id, int direction, float pos, vec3 color) {
        <<< "addline" >>>;
        MeshLines line --> GGen line_tf --> this;

        LineStruct ls;
        line @=> ls.line;
        color => ls.color;
        line.width(LINE_WIDTH);
        line.posZ(z0);

        if (direction == 0) {
            line.posY(gt2y(pos));
            gt2y(pos) => ls.horizPos;
            DELETE - 1 => ls.vertPos;
        } else {
            line.posX(gt2x(pos));
            DELETE - 1 => ls.horizPos;
            gt2x(pos) => ls.vertPos;
        }

        // generate and store bezier control points for this line
        vec3 p0, p1, p2, p3;
        if (direction == 0) {
            Lib.random(@(5., 0, 0)) => p0;
            Lib.random(@(1.7, 0, 0)) => p1;
            Lib.random(@(-1.7, 0, 0)) => p2;
            Lib.random(@(-5., 0, 0)) => p3;
        } else {
            Lib.random(@(0., 5., 0)) => p0;
            Lib.random(@(0., 1.7, 0)) => p1;
            Lib.random(@(0., -1.7, 0)) => p2;
            Lib.random(@(0., -5., 0)) => p3;
        }
        ls.ctrl << p0 << p1 << p2 << p3;

        allLines[id] << ls;
        allLines[id][allLines[id].size() - 1] @=> LineStruct @lsRef;

        spork ~ drawLine(direction, lsRef);
        // TODO: currectly animate is going on forever
        spork ~ animateLine(lsRef);
        // spork ~ scrollLine(direction, line);
        spork ~ rotateLines();
        spork ~ colorizeLine(lsRef);

        updateSegs();
        return line_tf;
    }

    fun void cutLine(int id, int idx, int direction) {
        <<< "cutline" >>>;
        if (idx < 0 || idx >= allLines[id].size()) {
            <<< "\twarning: invalid idx", idx >>>;
            return;
        }

        allLines[id][idx] @=> LineStruct @ls;

        spork ~ cutAnimation(ls, direction);

        // allLines[id].erase(idx);
        if (direction == 0)
            DELETE - 1 => ls.horizPos;
        else
            DELETE - 1 => ls.vertPos;

        updateSegs();
    }

    fun void cutAnimation(LineStruct @ls, int direction) {
        // reconstruct the actual settled curve — this is the base for the split
        Lib.bezier(ls.ctrl[0], ls.ctrl[1], ls.ctrl[2], ls.ctrl[3], 200) @=> vec3 basePts[];

        // random split point; clamp so each half gets at least 2 points
        Math.randomf() => float splitT;
        (splitT * 200) $ int => int cutIdx;
        if (cutIdx < 2)
            2 => cutIdx;
        if (cutIdx > 198)
            198 => cutIdx;

        1.5::second => dur totalDur;
        0.18::second => dur snapDur; // tension-release snap window
        now => time start;
        200 => int N;

        // spawn two independent half-lines as children of this GGen
        MeshLines halfA --> this;
        MeshLines halfB --> this;
        halfA.width(ls.line.width());
        halfB.width(ls.line.width());
        halfA.posX(ls.line.posX());
        halfA.posY(ls.line.posY());
        halfB.posX(ls.line.posX());
        halfB.posY(ls.line.posY());

        // hide original immediately — the two halves take over visually
        ls.line.visibility(0.);

        while (now - start < totalDur) {
            GG.nextFrame() => now;
            (now - start) / totalDur => float t;

            // ---- phase 1: damped-spring snap (0 → snapDur) ----
            Math.min(1.0, (now - start) / snapDur) => float snapT;
            1.0 - Math.exp(-12.0 * snapT) => float recoil;
            Math.exp(-5.0 * snapT) * Math.sin(14.0 * snapT) * 0.18 => float bounce;
            (recoil + bounce) * 0.6 => float drift;

            // ---- phase 2: slow zero-g float after snap settles ----
            Math.max(0.0, t - 0.12) * 0.06 +=> drift;

            // ---- phase 3: ease-out dissolve (delayed, stays bright through snap) ----
            Math.max(0.0, (t - 0.35) / 0.65) => float fadeT;
            if (fadeT > 1.0)
                1.0 => fadeT;
            1.0 - fadeT * fadeT => float alpha;

            // ---- half A: right/top side (indices 0 .. cutIdx-1) ----
            vec3 ptsA[cutIdx];
            for (0 => int i; i < cutIdx; i++) {
                i $ float / (cutIdx - 1) => float distToCut;
                distToCut * drift => float mainDrift;
                Math.pow(distToCut, 2.5) * drift * 0.35 => float curl;
                Math.sin(i * 127.1 + cutIdx * 31.7) => float fray;

                if (direction == 0)
                    @(basePts[i].x + mainDrift, basePts[i].y + curl * fray, basePts[i].z) => ptsA[i];
                else
                    @(basePts[i].x + curl * fray, basePts[i].y + mainDrift, basePts[i].z) => ptsA[i];
            }
            ptsA => halfA.positions;

            // ---- half B: left/bottom side (indices cutIdx .. N-1) ----
            N - cutIdx => int lenB;
            vec3 ptsB[lenB];
            for (0 => int i; i < lenB; i++) {
                1.0 - (i $ float / (lenB - 1)) => float distToCut;
                distToCut * drift => float mainDrift;
                Math.pow(distToCut, 2.5) * drift * 0.35 => float curl;
                Math.sin((i + cutIdx) * 127.1 + cutIdx * 31.7) => float fray;

                basePts[i + cutIdx] => vec3 bp;
                if (direction == 0)
                    @(bp.x - mainDrift, bp.y + curl * fray, bp.z) => ptsB[i];
                else
                    @(bp.x + curl * fray, bp.y - mainDrift, bp.z) => ptsB[i];
            }
            ptsB => halfB.positions;

            // ---- color matches original's z-depth, faded by alpha ----
            ls.line.posZ() => float z;
            halfA.posZ(z);
            halfB.posZ(z);
            (z - MIN_Z) / (MAX_Z - MIN_Z) => float zScale;
            Math.max(0., zScale * alpha) => float a;
            @(ls.color.x, ls.color.y, ls.color.z, a) => halfA.color;
            @(ls.color.x, ls.color.y, ls.color.z, a) => halfB.color;
        }

        // permanently hide both halves
        halfA.visibility(0.);
        halfB.visibility(0.);
    }

    fun void drawLine(int direction, LineStruct @ls) {
        now => time start;
        0.5::second => dur transTime;
        // drawing animation: control points start spread far apart and converge to stored ctrl
        while (now - start < transTime) {
            GG.nextFrame() => now;
            (now - start) / transTime => float t;
            if (direction == 0) {
                Lib.bezier(ls.ctrl[0], ls.ctrl[1] + @(3.3 * (1 - t), 0, 0),
                           ls.ctrl[2] + @(6.6 * (1 - t), 0, 0), ls.ctrl[3] + @(10 * (1 - t), 0, 0),
                           200) => ls.line.positions;
            } else {
                Lib.bezier(ls.ctrl[0], ls.ctrl[1] + @(0, 3.3 * (1 - t), 0),
                           ls.ctrl[2] + @(0, 6.6 * (1 - t), 0), ls.ctrl[3] + @(0, 10 * (1 - t), 0),
                           200) => ls.line.positions;
            }
        }
    }

    fun void animateLine(LineStruct @ls) {
        now => time t0;
        1 => float speed;
        while (true) {
            GG.nextFrame() => now;
            (now - t0) / 1::second => float t;
            Math.sin(t * speed) => float inc;
            LINE_WIDTH + inc * 0.005 => ls.line.width;
            Math.random2(-1, 1) * 0.0005 => float rot;
            ls.line.rotX(ls.line.rotX() + rot);
            ls.line.rotY(ls.line.rotY() + rot);
            ls.line.rotZ(ls.line.rotZ() + rot);
        }
    }

    fun void scrollLine(int direction, MeshLines @line) {
        0.5 => float speed;
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

    fun void rotateLines() {
        while (true) {
            GG.nextFrame() => now;
            .001 * GG.dt() => this.rotateY;
        }
    }

    fun void colorizeLine(LineStruct @ls) {
        while (true) {
            GG.nextFrame() => now;
            ls.line.posZ() => float z;
            (z - MIN_Z) / (MAX_Z - MIN_Z) => float zScale;
            @(ls.color.x, ls.color.y, ls.color.z, zScale) => ls.line.color;
        }
    }

    fun void updatePositions(int id, int direction[], float pos[]) {
        for (int i; i < allLines[id].size(); i++) {
            if (direction[i] == 0)
                allLines[id][i].line.posY(gt2y(pos[i]));
            else
                allLines[id][i].line.posX(gt2x(pos[i]));
        }
    }
    fun dur[] computeSegments(int axis) {
        // axis 0 = vert (x for vertical lines), axis 1 = horiz (y for horizontal)
        float bounds[0];
        bounds << MIN_X;
        bounds << MAX_X;

        for (0 => int id; id < MAX_PLAYER_NUM; id++) {
            for (0 => int i; i < allLines[id].size(); i++) {
                axis ? allLines[id][i].horizPos : allLines[id][i].vertPos => float p;
                if (p > DELETE)
                    bounds << p;
            }
        }

        // insertion sort
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
        dur segments[bounds.size() - 1];
        for (0 => int i; i < segments.size(); i++)
            ((bounds[i + 1] - bounds[i]) / totalWidth) * bpm.quarterNote => segments[i];
        return segments;
    }

    fun void updateSegs() {
        <<< "updateSegs" >>>;
        computeSegments(0) @=> dur segXs[];
        computeSegments(1) @=> dur segYs[];
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
