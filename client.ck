@import "sounds/noteProvider.ck"
@import "sounds/bpm.ck"
@import "sounds/chords.ck"
@import "sounds/scales.ck"
@import "lib/gametrak.ck"
@import "lib/global.ck"
@import "lib/meshlines.ck"
@import "lib/lib.ck"
@import "sounds/thread.ck"
@import "sounds/thread_cut.ck"

NoteProvider provider;
Chords chords;
Scales scales;

// Globals
Global.gt @=> GameTrak @gt;

// one person can weave up to six threads (one hemi)
12 => int CHANNELS;
0 => int CHAN_OFFSET;

0.01 => float LINE_WIDTH;
// random color for each client
@(Math.random2f(0.2, 0.9), Math.random2f(0.2, 0.9), Math.random2f(0.2, 0.9)) => vec3 color;

-2 * 16 / 9 => float MIN_X;
2 * 16 / 9 => float MAX_X;
-2 => float MIN_Y;
2 => float MAX_Y;
fun float gt2x(float gt) { return Math.map2(gt, 0., 1., MIN_X, MAX_X); }
fun float gt2y(float gt) { return Math.map2(gt, 0., 1., MIN_Y, MAX_Y); }

// instantiate sound threads
Thread threads[CHANNELS];
ThreadCut threadCut;
float allLinePos[0];
int allLineDir[0];
int allCuts[0];


for (0 => int i; i < CHANNELS; ++i) {
    threads[i].connect2dac(i);
}

1::second => now;


// cycle is synced with server
dur cycle;

// OscIn from clients
// create our OSC receiver
OscIn oin;
// create our OSC message
OscMsg msg;
// use port 6449 (or whatever)
6449 => oin.port;
// create an address in the receiver, expect an int and a float
oin.addAddress("/server/cycle");
oin.addAddress("/server/segs");
oin.addAddress("/server/chord");
oin.addAddress("/server/stage");

/// ---------- ID ---------- /////

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


@(0.820, 0.937, 0.980, 1) => vec4 textColor;
GText @currentInstruction;
null @=> currentInstruction;
GText @currentInstruction2;
null @=> currentInstruction2;

fun void addInstruction(string instruction) {
    if (currentInstruction != null)
        currentInstruction --< GG.scene();
    if (currentInstruction2 != null) {
        currentInstruction2 --< GG.scene();
        null @=> currentInstruction2;
    }
    GText text;
    text.size(0.2);
    text.text(instruction);
    text.color(textColor);
    text.pos(@(0, 0, 0));
    text --> GG.scene();
    text @=> currentInstruction;
}

// multiple line version
fun void addInstruction(string line1, string line2) {
    if (currentInstruction != null)
        currentInstruction --< GG.scene();
    if (currentInstruction2 != null)
        currentInstruction2 --< GG.scene();
    GText text1;
    text1.size(0.2);
    text1.text(line1);
    text1.color(textColor);
    text1.pos(@(0, 0.15, 0));
    text1 --> GG.scene();
    text1 @=> currentInstruction;

    GText text2;
    text2.size(0.2);
    text2.text(line2);
    text2.color(textColor);
    text2.pos(@(0, -0.15, 0));
    text2 --> GG.scene();
    text2 @=> currentInstruction2;
}

// initiate
if (ID == 0) {
    addInstruction("Slowly, intentionally", "Draw 5 horizontal threads");
} else if (ID >= 1 && ID <= 4) {
    addInstruction("Wait");
}


0 => int STEP;
0 => int STAGE;

fun void serverListener() {
    while (true) {
        oin => now;

        while (oin.recv(msg)) {
            // chout <= "received message: " <= msg.address <= IO.newline();
            if (msg.address == "/server/cycle") {
                if (msg.typetag == "f") {
                    if (msg.getFloat(0)::second != cycle) {
                        msg.getFloat(0)::second => cycle;
                        // update cycle
                        <<< "cycle updated:", cycle / second, "s" >>>;
                    }
                }
            } else if (msg.address == "/server/stage") {
                msg.getInt(0) => int stage;
                // new not equal to old
                if (stage != STAGE) {
                    if (stage == 1) {
                        if (ID == 0) {
                            addInstruction("Again Slowly, intentionally",
                                           "Draw 5 horizontal threads");
                        } else if (ID == 1) {
                            addInstruction("Wait til player 0 is done",
                                           "Then slowly, intentionally draw 5 vertical threads");
                        } else {
                            addInstruction("Wait");
                        }
                    }

                    else if (stage == 2) {
                        if (ID == 0 || ID == 2 || ID == 4) {
                            addInstruction("At a moderate speed", "Draw horizontal threads");
                        } else {
                            addInstruction("At a moderate speed", "Draw vertical threads");
                        }
                    }
                    stage => STAGE;
                }


            } else if (msg.address == "/server/chord") {
                msg.getInt(0) => int step;
                if (step != STEP) {
                    msg.getInt(1) => int randomRot;
                    // randomRot == pitchBend
                    if (step == 0)
                        chordChanger(chords.b_maj9, randomRot);
                    else if (step == 1)
                        chordChanger(chords.fsharp_maj9, randomRot);
                    else if (step == 2)
                        chordChanger(chords.csharp_maj7, randomRot);
                    else if (step == 3)
                        chordChanger(chords.aflat_sus2, randomRot);
                    else if (step == 4)
                        chordChanger(chords.bflat_9sus4, randomRot);
                    else if (step == 5)
                        chordChanger(chords.chordInverter(chords.bflat_9sus4, 2, 0), randomRot);
                    else if (step == 6)
                        chordChanger(chords.chordInverter(chords.bflat_9sus4, 1, 0), randomRot);
                    step => STEP;
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


// fun void cutThread(int direction) {
//     if (direction == 0) {
//         for (0 => int i; i < CHANNELS; i++) {
//             if (threads[i].isOn() && threads[i].direction == 0) {
//                 threads[i].off();
//             }
//         }
//     } else if (direction == 1) {
//         for (0 => int i; i < CHANNELS; i++) {
//             if (threads[i].isOn() && threads[i].direction == 1) {
//                 threads[i].off();
//             }
//         }
//     }
// }


// in client.ck, after the 1::second => now; line


fun void cutThread(int direction) {

    int targetNote;
    if (direction == 0)
        provider.getNote(gt.axis[5]) => targetNote;
    else if (direction == 1)
        provider.getNote(gt.axis[2]) => targetNote;

    1000 => int minDiff;
    -1 => int minN;
    // get the thread that is closest to the target note
    for (0 => int i; i < CHANNELS; i++) {
        if (threads[i].isOn() && threads[i].direction == direction) {
            if (Math.abs(provider.getNote(threads[i].pos) - targetNote) < minDiff) {
                Math.abs(provider.getNote(threads[i].pos) - targetNote) => minDiff;
                i => minN;
            }
        }
    }
    if (minN >= 0) { // if found
        threads[minN].off();
        threadCut.cut(targetNote);
        1 => allCuts[threads[minN].idx];
        // send to server which line to cut
        sendCutLine(threads[minN].idx, direction);
    } else { // if did not find
        1000 => minDiff;
        -1 => minN;
        // then find the closest line from allLinePos
        for (0 => int i; i < allLinePos.size(); ++i) {
            if (allCuts[i] == 0 && allLineDir[i] == direction) {
                allLinePos[i] => float pos;
                if (Math.abs(provider.getNote(pos) - targetNote) < minDiff) {
                    Math.abs(provider.getNote(pos) - targetNote) => minDiff;
                    i => minN;
                }
            }
        }
        if (minN >= 0) {
            1 => allCuts[minN];
            threadCut.cut(targetNote);
            // send to server which line to cut
            sendCutLine(minN, direction);
        }
    }
}

fun void sendCutLine(int idx, int direction) {
    xmit.start("/client/cutline");
    ID => xmit.add;
    idx => xmit.add;
    direction => xmit.add;
    xmit.send();
}

fun void addThread(int direction) { addThread(direction, 0); }

fun void addThread(int direction, int prepopulate) {
    <<< "addthread" >>>;
    threads[threadNum++ % CHANNELS] @=> Thread thread;

    if (thread.isOn()) {
        thread.off();
    }

    float pos; // pos to be stored and thus can be reinterpreted during chord change
    int note;

    // gt axis[2] and [5] are for pitch right now

    if (direction == 0) { // horizontal
        (gt.axis[1] + 1) / 2 => pos;
        thread.init(TriOsc osc);
    } else { // vertical
        (gt.axis[4] + 1) / 2 => pos;
        thread.init(SawOsc osc);
    }

    pos => thread.pos;
    direction => thread.direction;
    if (prepopulate) {
        // grey color
        Math.random2f(0.3, 2) * @(0.1, 0.1, 0.1) => thread.color;
    } else {
        color => thread.color;
    }
    threadNum - 1 => thread.idx;

    allLinePos << pos;
    allLineDir << direction;
    allCuts << 0;

    provider.getNote(pos) => note;

    // convert it to freq, starting from C
    // thread.freq(Std.mtof(48 + note));

    thread.on();
    thread.set_target_pitch(0.5, note);

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

fun void chordChanger(int input[], int pitchBend) {
    provider.notes @=> int oldNotes[]; // save it！
    input @=> provider.notes;

    // sonically
    for (0 => int i; i < CHANNELS; i++) {
        if (threads[i].isOn()) {
            // update the frequency
            provider.getNote(threads[i].pos) => int note;
            // threads[i].freq(Std.mtof(48 + note));

            if (pitchBend) {
                threads[i].set_target_pitch(note);
            } else {
                threads[i].set_target_pitch(0.5, note);
            }
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


// fun void chordSequencer() {
//     0 => int step;
//     while (true) {
//         if (gt.buttonPressed) {
//             if (step == 0)
//                 chordChanger(chords.b_maj9);
//             else if (step == 1)
//                 chordChanger(chords.fsharp_maj9);
//             else if (step == 2)
//                 chordChanger(chords.csharp_maj7);
//             else if (step == 3)
//                 chordChanger(chords.aflat_sus2);
//             else if (step == 4)
//                 chordChanger(chords.bflat_9sus4);
//             else if (step == 5)
//                 chordChanger(chords.chordInverter(chords.bflat_9sus4, 2, 0));
//             else if (step == 6)
//                 chordChanger(chords.chordInverter(chords.bflat_9sus4, 1, 0));
//
//             // loop for now
//             (step + 1) % 7 => step;
//
//             <<< "chord changed: ", step >>>;
//         }
//         10::ms => now;
//     }
// }
// spork ~ chordSequencer();


// 0: left handle's x
// 1: left handle's y
// 2: left handle's z
// 3: right handle's x
// 4: right handle's y
// 5: right handle's z


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


// need to sendAddLine
fun void drawHandler() {

    0.002 => float DEADZONE;

    int hSlot;
    int vSlot;

    int wasMovingH;
    int wasMovingV;


    while (true) {
        1::ms => now;

        // Horizontal thread (axis[2])
        // which includes it being deltaH is positive
        if (gt.vel[2] > DEADZONE && !wasMovingH && !gt.buttonHeldDown) {
            1 => wasMovingH;
            threadNum % CHANNELS => hSlot; // record slot for turning off again
            addThread(0);
        } else if (gt.vel[2] <= 0 && wasMovingH) {
            0 => wasMovingH;
        }

        if (gt.vel[5] > DEADZONE && !wasMovingV && !gt.buttonHeldDown) {
            1 => wasMovingV;
            threadNum % CHANNELS => vSlot;
            addThread(1);
        } else if (gt.vel[5] <= 0 && wasMovingV) {
            0 => wasMovingV;
        }
    }
}


spork ~ drawHandler();

// for tracking the motion
fun void stateHandler() {
    while (true) {
        // X, left tether
        State.NONE => int newState;
        if (gt.axis[0] < -0.05)
            State.LEFT => newState;
        else if (gt.axis[0] > 0.05)
            State.RIGHT => newState;
        else
            State.CENTER => newState;


        // gt.axis[2]

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
                if (gt.buttonHeldDown)
                    cutThread(1);
                0 => roundStage;
            }
        }


        // Y, right tether
        State.NONE => newState;
        if (gt.axis[4] < -0.05)
            State.LEFT => newState;
        else if (gt.axis[4] > 0.05)
            State.RIGHT => newState;
        else
            State.CENTER => newState;


        // gt.axis[5]

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
                if (gt.buttonHeldDown)
                    cutThread(0);
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
            Math.randomf() * 2 - 1 => gt.axis[1];
            addThread(0);
        } else if (UI.isKeyPressed(UI_Key.S, false)) {
            // fake a thread pos
            Math.randomf() * 2 - 1 => gt.axis[4];
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


fun void prePopulate(int numLines) {
    for (0 => int i; i < numLines; i++) {
        Math.randomf() * 2 - 1 => gt.axis[1];
        Math.randomf() * 2 - 1 => gt.axis[4];
        addThread(Math.random2(0, 1), 1);
        10::ms => now;
    }
}

// each prepopulates 5 horizontal for now
// prePopulate(10);


// main loop
while (true) {
    GG.nextFrame() => now;
}
