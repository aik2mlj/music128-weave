public class NoteProvider {
    // to provide a placeholder
    [0, 3, 7] @=> static int notes[];
    3 => static int octaves;
    0 => static int position;

    fun int size() { return octaves * notes.size(); }

    fun int getNote(float x) {
        // x in [0, 1)
        // return the closest note for a given x
        Math.round(x * size()) $ int => int idx;
        if (idx >= size())
            size() - 1 => idx;
        if (idx < 0)
            0 => idx;
        notes[idx % notes.size()] + (idx / notes.size()) * 12 => int base;
        return base;
    }

    // converts a frequency in Hz to a MIDI note number
    fun float freqToMidi(float hz) { return 69.0 + 12.0 * Math.log2(hz / 440.0); }

    ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"] @=> string chroma[];

    // returns a friendly note name for a given frequency
    fun string freqToNoteName(float hz) {
        freqToMidi(hz) => float midi;
        Math.round(midi) $ int => int note;
        chroma[note % 12] + (note / 12 - 1) => string name;
        return name;
    }
}
