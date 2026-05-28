@import "sounds/noteProvider.ck"
@import "sounds/bpm.ck"
@import "sounds/chords.ck"
@import "sounds/scales.ck"
@import "lib/lib.ck"
@import "lib/gametrak.ck"
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

// // set an orbit camera as the main camera
GOrbitCamera cam => GG.scene().camera;
// // position the camera
0.00001 => cam.posZ;
// cam.orthographic();

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
oin.addAddress("/client/cutline");

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

/// ---------- VISUAL ---------- /////

0 => int THEME;
0 => int randomRot;
0 => int scroll;

Lines lines(xmit, bpm) --> GG.scene();

// prepopulate
// lines.spawnLines_randomRot(100);

/// ---------- CONTROL ---------- /////

Chords chords;
GameTrak gt(0);

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
                lines.addLine(id, direction, pos, color, scroll);
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
                    lines.updatePositions(id, direction, pos);
                }
            } else if (msg.address == "/client/cutline") {
                msg.getInt(0) => int id;
                msg.getInt(1) => int idx;
                msg.getInt(2) => int direction;
                lines.cutLine(id, idx, direction);
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
        } else if (UI.isKeyPressed(UI_Key.Enter, false)) {
            // switch to the second theme
            <<< "theme changed" >>>;
            ++THEME;
            if (THEME == 1) {
                // scrolling
                1 => scroll;
                0 => randomRot;
                lines.scrollingTheme();
                // add fireflies
                Fireflies fireflies --> GG.scene();
            } else if (THEME == 2) {
                // rotating
                1 => randomRot;
                0 => scroll;
                lines.rotatingTheme();
            }
        }
    }
}
spork ~ keyboardHandler();

// seems unneeded
fun void sendCycle() {
    xmit.start("/server/cycle");
    xmit.add(bpm.quarterNote / second);
    xmit.send();
}


0 => int step;
fun void chordSequencer() {

    while (true) {
        gt.buttonPress => now;
        (step + 1) % 7 => step;
        <<< "chord step broadcast:", step >>>;
    }
}
spork ~ chordSequencer();

// main loop
while (true) {
    GG.nextFrame() => now;
    // continuous send
    xmit.start("/server/chord");
    step => xmit.add;
    xmit.send();
}
