using Gridline.Core;
using RVP;
using UnityEngine;

namespace Gridline.Input
{
    /// <summary>
    /// Mobile-first driver input: on-screen touch controls or device tilt, plus an optional Bluetooth gamepad.
    /// There are deliberately no keyboard bindings; the gamepad uses GRIDLINE's joystick-only GLPad* axes.
    /// </summary>
    [RequireComponent(typeof(VehicleParent))]
    public class PlayerCarInput : MonoBehaviour
    {
        public TouchControls touch;
        public GameSettings settings;
        public bool Driving { get; set; }

        [Tooltip("Steering slew rate in full-lock per second at sensitivity 1")]
        public float steerRate = 2.6f;
        public float returnRate = 4.5f;
        public float tiltRange = 0.45f;
        public float tiltDeadzone = 0.04f;

        VehicleParent vp;
        float steer, throttle, brake;
        bool padUpHeld, padDownHeld;

        void Awake() { vp = GetComponent<VehicleParent>(); }

        void Update()
        {
            float sensitivity = settings != null ? settings.steeringSensitivity : 1f;
            float pad = Axis("GLPadSteer");
            float target;
            bool analogue = true;
            if (Mathf.Abs(pad) > 0.05f) target = pad;
            else if (settings != null && settings.steeringMode == SteeringMode.Tilt) target = TiltSteer() * sensitivity;
            else
            {
                target = touch != null ? touch.Steer : 0f;
                analogue = false;
            }

            target = Mathf.Clamp(target, -1f, 1f);
            if (analogue) steer = target;
            else
            {
                // Digital touch buttons ramp in and snap back so steering feels progressive on glass.
                float rate = (Mathf.Abs(target) < 0.01f || Mathf.Sign(target) != Mathf.Sign(steer) ? returnRate : steerRate) * sensitivity;
                steer = Mathf.MoveTowards(steer, target, rate * Time.deltaTime);
            }

            throttle = Mathf.Clamp01(Mathf.Max(touch != null ? touch.Throttle : 0f, Axis("GLPadThrottle")));
            brake = Mathf.Clamp01(Mathf.Max(touch != null ? touch.Brake : 0f, Axis("GLPadBrake")));

            bool padUp = Axis("GLPadUpshift") > 0.5f, padDown = Axis("GLPadDownshift") > 0.5f;
            if (Driving && settings != null && settings.transmission == TransmissionMode.Manual)
            {
                if ((touch != null && touch.UpshiftPressed) || (padUp && !padUpHeld)) vp.PressUpshift();
                if ((touch != null && touch.DownshiftPressed) || (padDown && !padDownHeld)) vp.PressDownshift();
            }
            padUpHeld = padUp;
            padDownHeld = padDown;
        }

        float TiltSteer()
        {
            // Input.acceleration is in the device's natural (portrait) frame; map it to the landscape screen's right axis.
            Vector3 a = UnityEngine.Input.acceleration;
            float raw = Screen.orientation == ScreenOrientation.LandscapeRight ? a.y : -a.y;
            if (Mathf.Abs(raw) < tiltDeadzone) return 0f;
            return Mathf.Clamp((raw - Mathf.Sign(raw) * tiltDeadzone) / tiltRange, -1f, 1f);
        }

        void FixedUpdate()
        {
            if (!Driving)
            {
                vp.SetAccel(0f);
                vp.SetBrake(0f);
                vp.SetSteer(0f);
                vp.SetEbrake(1f);
                return;
            }
            vp.SetAccel(throttle);
            vp.SetBrake(brake);
            vp.SetSteer(steer);
            vp.SetEbrake(0f);
        }

        static float Axis(string name)
        {
            try { return UnityEngine.Input.GetAxisRaw(name); }
            catch (System.ArgumentException) { return 0f; }
        }
    }
}
