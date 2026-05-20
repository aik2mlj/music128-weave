@import "sounds/noteProvider.ck"
@import "sounds/bpm.ck"
@import "sounds/chords.ck"
@import "sounds/scales.ck"
@import "lib/gametrak.ck"
@import "lib/global.ck"
@import "lib/meshlines.ck"
@import "lib/lib.ck"
@import "sounds/thread.ck"

NoteProvider provider;
Chords chords;
Scales scales;

// Globals
Global.gt @=> GameTrak @gt;

// one person can weave up to six threads (one hemi)
6 => int CHANNELS;
0 => int CHAN_OFFSET;

0.01 => float LINE_WIDTH;
// random color for each client
@(Math.random2f(0.1, 0.9), Math.random2f(0.1, 0.9), Math.random2f(0.1, 0.9)) => vec3 color;

-2 * 16 / 9 => float MIN_X;
2 * 16 / 9 => float MAX_X;
-2 => float MIN_Y;
2 => float MAX_Y;
fun float gt2x(float gt) { return Math.map2(gt, 0., 1., MIN_X, MAX_X); }
fun float gt2y(float gt) { return Math.map2(gt, 0., 1., MIN_Y, MAX_Y); }

// instantiate sound threads
Thread threads[CHANNELS];
float allLinePos[0];
int allLineDir[0];


for (0 => int i; i < CHANNELS; ++i) {
    threads[i].connect2dac(i);
    if (i < 4) {
        threads[i].init(TriOsc osc);
    } else {
        threads[i].init(SawOsc osc);
    }
}

1::second => now;

// 0: left handle's x
// 1: left handle's y
// 2: left handle's z
// 3: right handle's x
// 4: right handle's y
// 5: right handle's z
//
// sync that is synced with server
float sync;

// OscIn from clients
// create our OSC receiver
OscIn oin;
// create our OSC message
OscMsg msg;
// use port 6449 (or whatever)
6449 => oin.port;
// create an address in the receiver, expect an int and a float
oin.addAddress("/server/sync");
oin.addAddress("/server/segs");

"localhost" => string hostname;
0 => int ID;
if (me.args()) {
    me.arg(0) => Std.atoi => ID;
    me.arg(1) => hostname;
}
// OscOut to server
// destination port number
6448 => int port;
// sender object
OscOut xmit;
// aim the transmitter at destination
xmit.dest(hostname, port);

fun void serverListener() {
    while (true) {
        oin => now;

        while (oin.recv(msg)) {
            // chout <= "received message: " <= msg.address <= IO.newline();
            if (msg.address == "/server/sync") {
                if (msg.typetag == "f") {
                    msg.getFloat(0) => sync;
                }
            } else if (msg.address == "/server/segs") {
                // reconstruct the array from however many args came in
                msg.getInt(0) => int numX;
                msg.getInt(1) => int numY;
                dur segXs[numX];
                dur segYs[numY];
                for (int n; n < numX; n++)
                    msg.getFloat(2 + n) * 1::samp => segXs[n];
                for (int n; n < numY; n++)
                    msg.getFloat(2 + numX + n) * 1::samp => segYs[n];
                <<< "received segs: ", segXs.size(), segYs.size() >>>;
                // <<< "segXs:" >>>;
                // for (int n; n < numX; ++n)
                //     <<< "\t", segXs[n] / 1::samp >>>;
                // <<< "segYs:" >>>;
                // for (int n; n < numY; ++n)
                //     <<< "\t", segYs[n] / 1::samp >>>;
                updateExistingRhythms(segXs, segYs);
            }
        }
    }
}
spork ~ serverListener();
/// ---------- RHYTHM ---------- /////

fun void updateExistingRhythms(dur segXs[], dur segYs[]) {
    <<< "updateExistingRhythms" >>>;
    for (0 => int i; i < CHANNELS; i++) {
        if (!threads[i].isOn())
            continue;

        if (threads[i].rhythmShred != null)
            threads[i].rhythmShred.exit();
        // TODO: check direction
        if (threads[i].direction == 0)
            spork ~ threads[i].rhythmicPause(segXs) @=> threads[i].rhythmShred;
        else
            spork ~ threads[i].rhythmicPause(segYs) @=> threads[i].rhythmShred;
    }
}

fun void addThread(int direction) {
    <<< "addthread" >>>;
    threads[threadNum++ % CHANNELS] @=> Thread thread;

    if (thread.isOn()) {
        thread.off();
    }

    float pos; // pos to be stored and thus can be reinterpreted during chord change
    int note;

    if (direction == 0) // horizontal
        gt.axis[2] => pos;
    else // vertical
        gt.axis[5] => pos;

    pos => thread.pos;
    direction => thread.direction;
    color => thread.color;

    allLinePos << pos;
    allLineDir << direction;

    provider.getNote(pos) => note;

    // convert it to freq, starting from C
    thread.freq(Std.mtof(48 + note));

    thread.on();
    sendAddLine(thread);

    // updateExistingRhythms();
}

fun void sendAddLine(Thread @thread) {
    // send an OSC message to the server
    // ID, direction, pos, color
    <<< "sendAddline" >>>;
    xmit.start("/client/addline");
    ID => xmit.add;
    thread.direction => xmit.add;
    thread.pos => xmit.add;
    thread.color.x => xmit.add;
    thread.color.y => xmit.add;
    thread.color.z => xmit.add;
    xmit.send();
}


/// ---------- CHORD ---------- /////
// for changing the entire chord/ scale scope

fun void chordChanger(int input[]) {
    provider.notes @=> int oldNotes[]; // save it！
    input @=> provider.notes;

    // sonically
    for (0 => int i; i < CHANNELS; i++) {
        if (threads[i].isOn()) {
            // update the frequency
            threads[i].freq(Std.mtof(48 + provider.getNote(threads[i].pos)));
        }
    }

    // visually, shift each line by its chord-tone delta
    for (0 => int i; i < allLinePos.size(); i++) {
        // get old slot position
        Math.round(allLinePos[i] * oldNotes.size()) $ int => int idx;

        // aka index 4 now should be index 3, if old chord has 5 notes, new has 4 notes
        if (idx >= input.size())
            input.size() - 1 => idx;

        if (idx >= oldNotes.size())
            oldNotes.size() - 1 => idx;


        input[idx] - oldNotes[idx] => int semitoneShift;
        // 12 semitones within one octave => compute the pos shift within this full range
        semitoneShift * 1.0 / (provider.octaves * 12) => float posShift;

        allLinePos[i] + posShift => float newPos;

        // clamp
        Math.max(0.0, Math.min(1.0, newPos)) => newPos;

        newPos => allLinePos[i];
    }
    sendLinePos(allLineDir, allLinePos);
}

fun void sendLinePos(int allLineDir[], float allLinePos[]) {
    xmit.start("/client/linepos");
    ID => xmit.add;
    allLinePos.size() => xmit.add;
    for (0 => int i; i < allLinePos.size(); ++i) {
        allLineDir[i] => xmit.add;
        allLinePos[i] => xmit.add;
    }
    xmit.send();
}


// for adding new chord on the context of existing chord(s)
fun void chordAdder(int input[]) { input @=> provider.notes; }


fun void chordSequencer() {
    0 => int step;
    while (true) {
        if (gt.buttonPressed) {
            if (step == 0)
                chordChanger(chords.b_maj9);
            else if (step == 1)
                chordChanger(chords.fsharp_maj9);
            else if (step == 2)
                chordChanger(chords.csharp_maj7);
            else if (step == 3)
                chordChanger(chords.aflat_sus2);
            else if (step == 4)
                chordChanger(chords.bflat_9sus4);
            else if (step == 5)
                chordChanger(chords.chordInverter(chords.bflat_9sus4, 2, 0));
            else if (step == 6)
                chordChanger(chords.chordInverter(chords.bflat_9sus4, 1, 0));

            // loop for now
            (step + 1) % 7 => step;
        }
        // <<< "step: ", step >>>;
        10::ms => now;
    }
}

spork ~ chordSequencer();

/// ---------- STATE ---------- /////
public class State {
    0 => static int NONE;
    1 => static int LEFT;
    2 => static int RIGHT;
    3 => static int CENTER;
}

State.NONE => int stateX;
State.NONE => int stateY;

// the state within this round of weaving.
// 0 = none, 1 = left seen, 2 = center seen, 3 = right seen
0 => int roundStage;
0 => int threadNum;


fun void stateHandler() {
    while (true) {
        // X
        State.NONE => int newState;
        if (gt.axis[0] < -0.05)
            State.LEFT => newState;
        else if (gt.axis[0] > 0.05)
            State.RIGHT => newState;
        else
            State.CENTER => newState;

        // only act on state transitions
        if (newState != stateX) {
            newState => stateX;

            if (stateX == State.LEFT && roundStage == 0)
                1 => roundStage;
            else if (stateX == State.CENTER && roundStage == 1)
                2 => roundStage;
            else if (stateX == State.RIGHT && roundStage == 2)
                3 => roundStage;
            else if (stateX == State.CENTER && roundStage == 3) {
                addThread(0);
                0 => roundStage;
            }
        }

        // Y
        State.NONE => newState;
        if (gt.axis[4] < -0.05)
            State.LEFT => newState;
        else if (gt.axis[4] > 0.05)
            State.RIGHT => newState;
        else
            State.CENTER => newState;

        // only act on state transitions
        if (newState != stateY) {
            newState => stateY;

            if (stateY == State.LEFT && roundStage == 0)
                1 => roundStage;
            else if (stateY == State.CENTER && roundStage == 1)
                2 => roundStage;
            else if (stateY == State.RIGHT && roundStage == 2)
                3 => roundStage;
            else if (stateY == State.CENTER && roundStage == 3) {
                addThread(1);
                0 => roundStage;
            }
        }

        10::ms => now;
    }
}
spork ~ stateHandler();

fun void keyboardHandler() {
    while (true) {
        GG.nextFrame() => now;
        if (UI.isKeyPressed(UI_Key.A, false)) {
            // fake a thread pos
            Math.randomf() => gt.axis[2];
            addThread(0);
        } else if (UI.isKeyPressed(UI_Key.S, false)) {
            // fake a thread pos
            Math.randomf() => gt.axis[5];
            addThread(1);
        } else if (UI.isKeyPressed(UI_Key.Space, false)) {
            1 => gt.buttonPressed;
            gt.buttonPress.broadcast();
            10::ms => now;
            0 => gt.buttonPressed;
        }
    }
}
spork ~ keyboardHandler();

fun void print() {
    while (true) {
        <<< "axes:", gt.axis[0], gt.axis[1], gt.axis[2], gt.axis[3], gt.axis[4], gt.axis[5] >>>;
        100::ms => now;
    }
}
// spork ~ print();


// main loop
while (true) {
    GG.nextFrame() => now;
}
