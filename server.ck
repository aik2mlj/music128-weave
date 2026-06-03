@import "sounds/noteProvider.ck"
@import "sounds/bpm.ck"
@import "sounds/chords.ck"
@import "sounds/scales.ck"
@import "lib/lib.ck"
@import "lib/gametrak.ck"
@import "lib/global.ck"
@import "sounds/thread.ck"
@import "visual/fireflies.ck"
@import "visual/lines.ck"

GWindow.title("weave");
// GWindow.windowed(1280, 960);
// GWindow.center();
GWindow.fullscreen();

GG.bloom(true);
GG.bloomPass().intensity(0.5);
GG.bloomPass().radius(0.7);
GG.bloomPass().levels(9);

// remove light
GG.scene().light() @=> GLight light;
0. => light.intensity;

// // set a camera as the main camera
GCamera cam => GG.scene().camera;

BPM bpm;
bpm.tempo(40);

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
// address that will send: /server/cycle, /server/segs

// Globals
Global.gt @=> GameTrak @gt;

/// ---------- VISUAL ---------- /////

0 => int randomRot;
0 => int scroll;


Lines lines(xmit, bpm) --> GG.scene();

// add fireflies
Fireflies fireflies --> GG.scene();

fun void camZoomIn(dur d) {
    // Camera zoom in at the beginning
    100 => float initPosZ => cam.posZ;
    0 => float targetPosZ;
    20 => float initPosY => cam.posY;
    0 => float targetPosY;
    now => time start;
    while (now - start < d) {
        GG.nextFrame() => now;
        (now - start) / d => float t;
        Lib.easeOutCubic(t) => float tEased;
        Math.map2(tEased, 0, 1, initPosZ, targetPosZ) => cam.posZ;
        Math.map2(tEased, 0, 1, initPosY, targetPosY) => cam.posY;
    }
}
spork ~ camZoomIn(10::second);

fun void camZoomOut(dur d) {
    // Camera zoom out at the end
    0 => float initPosZ => cam.posZ;
    200 => float targetPosZ;
    0 => float initPosY => cam.posY;
    20 => float targetPosY;
    now => time start;
    while (now - start < d) {
        GG.nextFrame() => now;
        (now - start) / d => float t;
        Lib.easeInCubic(t) => float tEased;
        Math.map2(tEased, 0, 1, initPosZ, targetPosZ) => cam.posZ;
        Math.map2(tEased, 0, 1, initPosY, targetPosY) => cam.posY;
    }
}

// fade a cloned world from invisible to full over duration d.
fun void fadeInWorld(Lines @w, dur d) {
    now => time start;
    while (now - start < d) {
        GG.nextFrame() => now;
        (now - start) / d => float t;
        Lib.easeInCubic(t) => float a;
        w.setWorldAlpha(a);
    }
    w.setWorldAlpha(1.);
}

// duplicate the world into a num^3 grid, with the original world in the middle.
// worlds are spawned gradually (cascading outward from the center) and each
// fades in, so the multiverse materializes along with the camera zoom-out.
fun void duplicateWorld(int num) {
    num / 2 => int half;
    30 => float distance;
    15::second => dur spawnSpan; // spread spawning across the zoom-out
    7::second => dur fadeDur;    // per-world fade-in time
    num * num * num - 1 => int total;
    if (total < 1)
        1 => total;
    spawnSpan / total => dur perWorld;

    // iterate rings outward (Chebyshev distance) so worlds cascade from center
    for (1 => int ring; ring <= half; ring++) {
        for (0 => int gx; gx < num; gx++) {
            for (0 => int gy; gy < num; gy++) {
                for (0 => int gz; gz < num; gz++) {
                    gx - half => int dx;
                    if (dx < 0)
                        -dx => dx;
                    gy - half => int dy;
                    if (dy < 0)
                        -dy => dy;
                    gz - half => int dz;
                    if (dz < 0)
                        -dz => dz;
                    dx => int r;
                    if (dy > r)
                        dy => r;
                    if (dz > r)
                        dz => r;
                    if (r != ring)
                        continue; // not in this ring yet

                    lines.clone() @=> Lines w;
                    w --> GG.scene();
                    (gx - half) $ float * distance => w.posX;
                    (gy - half) $ float * distance => w.posY;
                    (gz - half) $ float * distance => w.posZ;

                    w.setWorldAlpha(0.); // start invisible, then fade in
                    spork ~ fadeInWorld(w, fadeDur);
                    perWorld => now; // stagger spawns over the zoom-out
                }
            }
        }
    }
}

// prepopulate
// lines.spawnLines_randomRot(100);

/// ---------- CONTROL ---------- /////

Chords chords;
0 => int step;
0 => int STAGE;

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
                lines.addLine(id, direction, pos, color, scroll, randomRot);
            } else if (msg.address == "/client/linepos") {
                msg.getInt(0) => int id;
                msg.getInt(1) => int size;
                float pos[size];
                int direction[size];
                for (int i; i < size; i++) {
                    msg.getInt(2 + 2 * i) => direction[i];
                    msg.getFloat(2 + 2 * i + 1) => pos[i];
                }
                if (size > 0) {
                    // lines.updatePositions(id, direction, pos);
                }
            }
        }
    }
}
spork ~ clientListener();

fun void keyboardHandler() {
    while (true) {
        GG.nextFrame() => now;
        if (UI.isKeyPressed(UI_Key.UpArrow, false)) {
            // increase tempo
            <<< "tempo increased:", bpm.tempo() >>>;
            bpm.tempo(bpm.tempo() + 2);
            // TODO: optimize
            sendCycle();
            lines.updateSegs();
        } else if (UI.isKeyPressed(UI_Key.Space, false)) {
            <<< "STAGE changed" >>>;
            ++STAGE;
            if (STAGE == 1) {
            } else if (STAGE == 2) {
                // scrolling
                1 => scroll;
                0 => randomRot;
                lines.scrollingTheme();
            } else if (STAGE == 3) {
                // rotating
                1 => randomRot;
                0 => scroll;
                // change chord with huge pitch bend
                (step + 1) % 7 => step;
                // temporarily remove all the segments
                // lines.clearSegs();
                lines.rotatingTheme();
            } else if (STAGE == 4) {
                spork ~ camZoomOut(20::second);
                spork ~ duplicateWorld(7);
            }
        }
    }
}
spork ~ keyboardHandler();


fun void sendChord() {
    while (true) {
        10::ms => now;
        xmit.start("/server/chord");
        step => xmit.add;
        randomRot => xmit.add;
        xmit.send();
    }
}

spork ~ sendChord();


// server tells performers / clients instructions
fun void sendStage() {
    while (true) {
        10::ms => now;
        xmit.start("/server/stage");
        xmit.add(STAGE);
        xmit.send();
    }
}
spork ~ sendStage();

// ---------- CUTTING ---------- //

fun void cutSpeedHandler() {
    -0.011 => float cutVel;
    0.5::second => dur coldTime;
    time lastCutTime;
    while (true) {
        // when the negative velocity is big enough
        10::ms => now;
        if (gt.vel[2] < cutVel && now - lastCutTime > coldTime) {
            cutLine(0);
            now => lastCutTime;
            (step + 1) % 7 => step;
            <<< "cutting left tether" >>>;
        } else if (gt.vel[5] < cutVel && now - lastCutTime > coldTime) {
            cutLine(1);
            now => lastCutTime;
            (step + 1) % 7 => step;
            <<< "cutting right tether" >>>;
        }
        // <<< "v2:", gt.vel[2], "v5:", gt.vel[5] >>>;
    }
}
spork ~ cutSpeedHandler();

// class State {
//     0 => static int NONE;
//     1 => static int LEFT;
//     2 => static int RIGHT;
//     3 => static int CENTER;
// }
//
// State.NONE => int stateX;
// State.NONE => int stateY;
//
// // the state within this round of weaving.
// // 0 = none, 1 = left seen, 2 = center seen, 3 = right seen
// 0 => int roundStage;
//
// fun void cutStateHandler() {
//     while (true) {
//         // X, left tether
//         State.NONE => int newState;
//         if (gt.axis[0] < -0.05)
//             State.LEFT => newState;
//         else if (gt.axis[0] > 0.05)
//             State.RIGHT => newState;
//         else
//             State.CENTER => newState;
//
//         // only act on state transitions
//         if (newState != stateX) {
//             newState => stateX;
//
//             if (stateX == State.LEFT && roundStage == 0)
//                 1 => roundStage;
//             else if (stateX == State.CENTER && roundStage == 1)
//                 2 => roundStage;
//             else if (stateX == State.RIGHT && roundStage == 2)
//                 3 => roundStage;
//             else if (stateX == State.CENTER && roundStage == 3) {
//                 // if (gt.buttonHeldDown)
//                 cutLine(1);
//                 0 => roundStage;
//             }
//         }
//
//         // Y, right tether
//         State.NONE => newState;
//         if (gt.axis[4] < -0.05)
//             State.LEFT => newState;
//         else if (gt.axis[4] > 0.05)
//             State.RIGHT => newState;
//         else
//             State.CENTER => newState;
//
//         // only act on state transitions
//         if (newState != stateY) {
//             newState => stateY;
//
//             if (stateY == State.LEFT && roundStage == 0)
//                 1 => roundStage;
//             else if (stateY == State.CENTER && roundStage == 1)
//                 2 => roundStage;
//             else if (stateY == State.RIGHT && roundStage == 2)
//                 3 => roundStage;
//             else if (stateY == State.CENTER && roundStage == 3) {
//                 // if (gt.buttonHeldDown)
//                 cutLine(0);
//                 0 => roundStage;
//             }
//         }
//
//         10::ms => now;
//     }
// }
// spork ~ cutStateHandler();

fun void cutLine(int direction) {
    // randomly cut up to three lines
    lines.cutRandomLines(3, direction);
}

// seems unneeded
fun void sendCycle() {
    xmit.start("/server/cycle");
    xmit.add(bpm.quarterNote / second);
    xmit.send();
}


// main loop
while (true) {
    GG.nextFrame() => now;
}
