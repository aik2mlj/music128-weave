public class NoteProvider {
    // to provide a placeholder
    [0, 3, 7] @=> static int notes[];
    0 => static int position;

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
