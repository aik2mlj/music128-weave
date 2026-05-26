public class GameTrak {
    // HID objects
    Hid trak;
    HidMsg msg;

    float deadzone;

    // timestamps
    time lastTime;
    time currTime;

    // previous axis data
    float lastAxis[6];
    // current axis data
    float axis[6];
    // previous velocity
    float lastVel[6];
    // current velocity
    float vel[6];

    // if button pressed on last frame (internally used)
    int lastButtonPressed;
    // if button pressed on current frame
    int buttonPressed;
    // if button down
    int buttonDown;
    // if button up
    int buttonUp;


    // check if the button is continuously held down
    int buttonHeldDown;

    // Button press event
    Event buttonPress;

    fun GameTrak(int device) { GameTrak(device, .032); }

    fun GameTrak(int device, float deadzone) {
        if (!trak.openJoystick(device))
            me.exit();
        <<< "joystick '" + trak.name() + "' ready", "" >>>;
        deadzone => this.deadzone;
        spork ~ update();
    }

    // spork this
    fun void update() {
        while (true) {
            // wait on HidIn as event
            trak => now;

            // messages received
            while (trak.recv(msg)) {
                // joystick axis motion
                if (msg.isAxisMotion()) {
                    // check which
                    if (msg.which >= 0 && msg.which < 6) {
                        // check if fresh
                        if (now > currTime) {
                            // time stamp
                            currTime => lastTime;
                            // set
                            now => currTime;
                        }
                        vel[msg.which] => lastVel[msg.which];
                        // find current velocity
                        axis[msg.which] - lastAxis[msg.which] => vel[msg.which];
                        // save last
                        axis[msg.which] => lastAxis[msg.which];
                        // the z axes map to [0,1], others map to [-1,1]
                        if (msg.which != 2 && msg.which != 5) {
                            msg.axisPosition => axis[msg.which];
                        } else {
                            1 - ((msg.axisPosition + 1) / 2) - deadzone => axis[msg.which];
                            if (axis[msg.which] < 0)
                                0 => axis[msg.which];
                        }
                    }
                }

                msg.isButtonDown() => buttonDown;
                msg.isButtonUp() => buttonUp;

                !lastButtonPressed &&buttonDown => buttonPressed;
                buttonPressed => lastButtonPressed;

                if (buttonPressed)
                    buttonPress.broadcast();

                // alternative: only update button state on button events
                if (msg.isButtonDown()) {
                    1 => buttonHeldDown;
                } else if (msg.isButtonUp()) {
                    0 => buttonHeldDown;
                }
            }
        }
    }
}
