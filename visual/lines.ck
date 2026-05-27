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
    -10000 => static float DELETE;
    MeshLines @allLines[MAX_PLAYER_NUM][0];
    float vertPositions[MAX_PLAYER_NUM][0];  // world-space x of for vertical lines
    float horizPositions[MAX_PLAYER_NUM][0]; // for horizontal lines
    vec3 lineCtrl[MAX_PLAYER_NUM][0];        // 4 bezier ctrl pts per line (base = 4*idx)

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
            horizPositions[id] << gt2y(pos);
            vertPositions[id] << DELETE - 1;
        } else {
            line.posX(gt2x(pos));
            horizPositions[id] << DELETE - 1;
            vertPositions[id] << gt2x(pos);
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
        lineCtrl[id] << p0 << p1 << p2 << p3;

        spork ~ drawLine(direction, line, p0, p1, p2, p3);
        // TODO: currectly animate is going on forever
        spork ~ animateWidth(line);
        spork ~ scrollLine(direction, line);
        spork ~ colorizeLine(line);

        updateSegs();
    }

    fun void cutLine(int id, int idx, int direction) {
        <<< "cutline" >>>;
        if (idx < 0 || idx >= allLines[id].size()) {
            <<< "\twarning: invalid idx", idx >>>;
            return;
        }

        // fancy cut animation: split at random position, drift apart, fade away
        4 * idx => int base;
        spork ~ cutAnimation(allLines[id][idx], direction, lineCtrl[id][base],
                            lineCtrl[id][base + 1], lineCtrl[id][base + 2], lineCtrl[id][base + 3]);

        // allLines[id].erase(idx);
        if (direction == 0) {
            DELETE - 1 => horizPositions[id][idx];
        } else {
            DELETE - 1 => vertPositions[id][idx];
        }

        updateSegs();
    }

    fun void cutAnimation(MeshLines @line, int direction, vec3 p0, vec3 p1, vec3 p2, vec3 p3) {
        // reconstruct the actual settled curve — this is the base for the split
        Lib.bezier(p0, p1, p2, p3, 200) @=> vec3 basePts[];

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
        halfA.width(line.width());
        halfB.width(line.width());
        halfA.posX(line.posX());
        halfA.posY(line.posY());
        halfB.posX(line.posX());
        halfB.posY(line.posY());

        // hide original immediately — the two halves take over visually
        line.visibility(0.);

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
                // distance from anchored end (0) to cut end (1)
                i $ float / (cutIdx - 1) => float distToCut;
                distToCut * drift => float mainDrift;

                // curl: perpendicular fray, strongest right at the cut end
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
                // distance from cut end (1) to anchored end (0)
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
            line.posZ() => float z;
            halfA.posZ(z);
            halfB.posZ(z);
            (z - MIN_Z) / (MAX_Z - MIN_Z) => float zScale;
            Math.max(0., zScale * alpha) => float a;
            @(color.x, color.y, color.z, a) => halfA.color;
            @(color.x, color.y, color.z, a) => halfB.color;
        }

        // permanently hide both halves
        halfA.visibility(0.);
        halfB.visibility(0.);
    }

    fun void drawLine(int direction, MeshLines @line, vec3 p0, vec3 p1, vec3 p2, vec3 p3) {
        now => time start;
        0.5::second => dur transTime;
        // drawing animation: control points start spread far apart and converge to p0..p3
        while (now - start < transTime) {
            GG.nextFrame() => now;
            (now - start) / transTime => float t;
            if (direction == 0) {
                Lib.bezier(p0, p1 + @(3.3 * (1 - t), 0, 0), p2 + @(6.6 * (1 - t), 0, 0),
                           p3 + @(10 * (1 - t), 0, 0), 200) => line.positions;
            } else {
                Lib.bezier(p0, p1 + @(0, 3.3 * (1 - t), 0), p2 + @(0, 6.6 * (1 - t), 0),
                           p3 + @(0, 10 * (1 - t), 0), 200) => line.positions;
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
    fun dur[] computeSegments(float positions[][]) {
        float bounds[0]; // line locations including the outbounds

        bounds << MIN_X;
        bounds << MAX_X;

        for (0 => int i; i < positions.size(); ++i) {
            for (0 => int j; j < positions[i].size(); ++j)
                if (positions[i][j] > DELETE)
                    bounds << positions[i][j];
        }

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
        dur segments[bounds.size() - 1];
        // find the dur of each segment
        for (0 => int i; i < segments.size(); i++)
            ((bounds[i + 1] - bounds[i]) / totalWidth) * bpm.quarterNote => segments[i];
        return segments;
    }

    fun void updateSegs() {
        <<< "updateSegs" >>>;
        computeSegments(vertPositions) @=> dur segXs[];
        computeSegments(horizPositions) @=> dur segYs[];

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
