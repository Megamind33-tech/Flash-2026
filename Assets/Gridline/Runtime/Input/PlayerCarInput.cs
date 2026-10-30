using Gridline.Core;
using RVP;
using UnityEngine;

namespace Gridline.Input
{
    /// <summary>Merges touch, tilt, keyboard and gamepad into RVP vehicle input, applying the player's sensitivity setting.</summary>
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

        void Awake() { vp = GetComponent<VehicleParent>(); }

        void Update()
        {
            float sensitivity = settings != null ? settings.steeringSensitivity : 1f;
            float target = 0f;
            bool analogue = false;

            float axis = SafeAxis("Horizontal");
            if (Mathf.Abs(axis) > 0.05f)
            {
                target = axis;
                analogue = true;
            }
            else if (settings != null && settings.steeringMode == SteeringMode.Tilt)
            {
                target = TiltSteer() * sensitivity;
                analogue = true;
            }
            else if (touch != null)
            {
                target = touch.Steer;
            }

            target = Mathf.Clamp(target, -1f, 1f);
            if (analogue) steer = target;
            else
            {
                float rate = (Mathf.Abs(target) < 0.01f || Mathf.Sign(target) != Mathf.Sign(steer) ? returnRate : steerRate) * sensitivity;
                steer = Mathf.MoveTowards(steer, target, rate * Time.deltaTime);
            }

            throttle = Mathf.Clamp01(Mathf.Max(touch != null ? touch.Throttle : 0f, SafeAxis("Accel")));
            brake = Mathf.Clamp01(Mathf.Max(touch != null ? touch.Brake : 0f, SafeAxis("Brake")));

            if (Driving && settings != null && settings.transmission == TransmissionMode.Manual)
            {
                if ((touch != null && touch.UpshiftPressed) || SafeButtonDown("Upshift")) vp.PressUpshift();
                if ((touch != null && touch.DownshiftPressed) || SafeButtonDown("Downshift")) vp.PressDownshift();
            }
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

        static float SafeAxis(string name)
        {
            try { return UnityEngine.Input.GetAxis(name); }
            catch (System.ArgumentException) { return 0f; }
        }

        static bool SafeButtonDown(string name)
        {
            try { return UnityEngine.Input.GetButtonDown(name); }
            catch (System.ArgumentException) { return false; }
        }
    }
}
