@import "sounds/noteProvider.ck"
@import "sounds/bpm.ck"
@import "sounds/chords.ck"
@import "sounds/scales.ck"
@import "lib/meshlines.ck"
@import "lib/lib.ck"
@import "sounds/thread.ck"

GWindow.title("weave");
// GWindow.windowed(1280, 960);
// GWindow.center();
GWindow.fullscreen();

GG.bloom(true);
GG.bloomPass().intensity(0.5);
GG.bloomPass().radius(0.7);
GG.bloomPass().levels(9);

// // set an orbit camera as the main camera
GOrbitCamera cam => GG.scene().camera;
// // position the camera
cam.posZ(5);
// cam.orthographic();

BPM bpm;
bpm.tempo(80);
bpm.quarterNote => dur sync;
2 * sync => dur cycle;

0.01 => float LINE_WIDTH;
@(0.2, 0.2, 0.2) => vec3 LINE_COLOR;

-2 * 16 / 9 => float MIN_X;
2 * 16 / 9 => float MAX_X;
-2 => float MIN_Y;
2 => float MAX_Y;
fun float gt2x(float gt) { return Math.map2(gt, 0., 1., MIN_X, MAX_X); }
fun float gt2y(float gt) { return Math.map2(gt, 0., 1., MIN_Y, MAX_Y); }

// OscIn from clients
// create our OSC receiver
OscIn oin;
// create our OSC message
OscMsg msg;
// use port 6449 (or whatever)
6448 => oin.port;
// create an address in the receiver, expect an int and a float
oin.addAddress("/client/addline");
oin.addAddress("/client/linepos");

// OscOut multicast
// multicast address sends to all machines on local network
"255.255.255.255" => string hostname;
// "localhost" => string hostname;
if (me.args()) {
    me.arg(0) => hostname;
}
// destination port number
6449 => int port;
// sender object
OscOut xmit;
// aim the transmitter at destination
xmit.dest(hostname, port);
// address that will send: /server/sync, /server/segs

/// ---------- VISUAL ---------- /////

// tracking lines
MeshLines @allLines[16][0];

// TODO: thread changes to an address sent from client
fun addLine(int id, int direction, float pos, vec3 color) {
    <<< "addline" >>>;
    MeshLines line --> GG.scene();

    allLines[id] << line;

    line.color(color);
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
    spork ~ animate(line);

    updateSegs();
}

fun void drawLine(int direction, MeshLines @line) {
    now => time start;
    0.5::second => dur transTime;
    Lib.random(@(1.7, 0, 0)) => vec3 px1;
    Lib.random(@(-1.7, 0, 0)) => vec3 px2;
    Lib.random(@(0., 1.7, 0)) => vec3 py1;
    Lib.random(@(0., -1.7, 0)) => vec3 py2;
    while (now - start < transTime) {
        GG.nextFrame() => now;
        (now - start) / transTime => float t;
        if (direction == 0) {
            Lib.bezier(@(5, 0, 0), px1 + @(3.3 * (1 - t), 0, 0), px2 + @(6.6 * (1 - t), 0, 0),
                       @(-5 + 10 * (1 - t), 0, 0), 200) => line.positions;
        } else {
            Lib.bezier(@(0, 5, 0), py1 + @(0, 3.3 * (1 - t), 0), py2 + @(0, 6.6 * (1 - t), 0),
                       @(0, -5 + 10 * (1 - t), 0), 200) => line.positions;
        }
    }
}

fun void animate(MeshLines @line) {
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

/// ---------- RHYTHM ---------- /////

float vertPositions[0];  // world-space x of for vertical lines
float horizPositions[0]; // for horizontal lines
0 => int vertCount;
0 => int horizCount;

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
        ((bounds[i + 1] - bounds[i]) / totalWidth) * cycle => segments[i];
    return segments;
}

// TODO: change to sending osc to the corresponding client to start.
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

fun void clientListener() {
    while (true) {
        oin => now;

        while (oin.recv(msg)) {
            // chout <= "received message: " <= msg.address <= IO.newline();
            if (msg.address == "/client/addline") {
                msg.getInt(0) => int id;
                msg.getInt(1) => int direction;
                msg.getFloat(2) => float pos;
                msg.getFloat(3) => float cx;
                msg.getFloat(4) => float cy;
                msg.getFloat(5) => float cz;
                @(cx, cy, cz) => vec3 color;
                addLine(id, direction, pos, color);
            } else if (msg.address == "/client/linepos") {
                msg.getInt(0) => int id;
                msg.getInt(1) => int size;
                float pos[size];
                float direction[size];
                for (int i; i < size; i++) {
                    msg.getInt(2 + 2 * i) => direction[i];
                    msg.getFloat(2 + 2 * i + 1) => pos[i];
                }
                // update line positions
                // sanity check
                if (size != allLines[id].size())
                    <<< "error: size mismatch in linepos" >>>;
                if (size > 0) {
                    for (int i; i < allLines[id].size(); i++) {
                        if (direction[i] == 0)
                            allLines[id][i].posY(gt2y(pos[i]));
                        else
                            allLines[id][i].posX(gt2x(pos[i]));
                    }
                }
            }
        }
    }
}
spork ~ clientListener();

// main loop
while (true) {
    GG.nextFrame() => now;
}
