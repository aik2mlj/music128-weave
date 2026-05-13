@import "noteProvider.ck"
@import "bpm.ck"
@import "chords.ck"
@import "scales.ck"
@import "../lib/gametrak.ck"
@import "../lib/global.ck"

GWindow.title("weave");
GWindow.windowed(1280, 960);
GWindow.center();
// GWindow.fullscreen();

NoteProvider provider;
BPM bpm;
Chords chords;
Scales scales;

// Globals
Global.gt @=> GameTrak @gt;

scales.majorScale @=> provider.notes;

// one person can weave up to six threads (one hemi)
6 => int CHANNELS;
0 => int CHAN_OFFSET;
TriOsc thread[CHANNELS];
LPF threadLPF[CHANNELS];
ADSR env[CHANNELS];
NRev threadRev[CHANNELS];

// set parameters — nothing patched to dac yet
for (int i; i < CHANNELS; i++) {
    thread[i].gain(0.05); // a low gain
    threadLPF[i].set(800, 1);
    threadRev[i].gain(0.5);
    threadRev[i].mix(0.1);
    (30::ms, 500::ms, 0, 400::ms) => env[i].set;
}

1::second => now;

// 0: left handle's x
// 1: left handle's y
// 2: left handle's z
// 3: right handle's x
// 4: right handle's y
// 5: right handle's z


public class State {
    0 => static int NONE;
    1 => static int LEFT;
    2 => static int RIGHT;
    3 => static int CENTER;
}

State.NONE => int state;

// the state within this round of weaving.
// 0 = none, 1 = left seen, 2 = center seen, 3 = right seen
0 => int roundStage;
0 => int threadNum;


fun addLine() {
    GLines line --> GG.scene();
    line.color(Color.WHITE);
    line.width(0.01);

    vec2 pts[2];
    @(-5.0, 0.0) => pts[0];
    @(0.0, 0.0) => pts[1];
    line.positions(pts);
    line.posY(gt.axis[2]); // fix it there

    while (true) {
        GG.nextFrame() => now;
    }
}

fun void easeIn(int num) {
    while (true) {
        // check left tether x -- slowly weave in the sound
        Math.max(0.0, -gt.axis[0]) / 2.0 => float newGain;
        // only update toward louder
        if (newGain > thread[num].gain()) {
            newGain => thread[num].gain;
            <<< "check gain level ", thread[num].gain(), " num: ", num >>>;
        }
        10::ms => now;
    }
}

fun void addThread() {
    if (threadNum < CHANNELS) {
        thread[threadNum] => threadLPF[threadNum] => threadRev[threadNum] => dac;


        // figure out the interval length
        Math.floor((gt.axis[2]) * provider.notes.size()) $ int => int idx;
        // watch boundary
        if (idx >= provider.notes.size())
            provider.notes.size() - 1 => idx;
        // convert it to freq, starting from C
        Std.mtof(60 + provider.notes[idx]) => float freq;
        thread[threadNum].freq(freq);

        spork ~ easeIn(threadNum);
        spork ~ addLine();
        threadNum++;
        <<< "thread added:", threadNum >>>;
    }
}

fun void stateHandler() {
    while (true) {
        State.NONE => int newState;

        if (gt.axis[0] < -0.05)
            State.LEFT => newState;
        else if (gt.axis[0] > 0.05)
            State.RIGHT => newState;
        else
            State.CENTER => newState;

        // only act on state transitions
        if (newState != state) {
            newState => state;

            if (state == State.LEFT && roundStage == 0)
                1 => roundStage;
            else if (state == State.CENTER && roundStage == 1)
                2 => roundStage;
            else if (state == State.RIGHT && roundStage == 2)
                3 => roundStage;
            else if (state == State.CENTER && roundStage == 3) {
                addThread();
                0 => roundStage;
            }
        }

        10::ms => now;
    }
}
spork ~ stateHandler();


fun void print() {
    while (true) {
        <<< "axes:", gt.axis[0], gt.axis[1], gt.axis[2], gt.axis[3], gt.axis[4], gt.axis[5] >>>;
        100::ms => now;
    }
}
spork ~ print();


// main loop
while (true) {
    GG.nextFrame() => now;
}
