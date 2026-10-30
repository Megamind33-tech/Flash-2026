using Gridline.UI;
using UnityEngine;
using UnityEngine.UI;

namespace Gridline.Input
{
    /// <summary>
    /// On-screen driving controls. Polls raw touches (multi-touch: steer with the left thumb, pedals with the right)
    /// instead of uGUI events so holds and slides between buttons work reliably on small screens.
    /// </summary>
    public class TouchControls : MonoBehaviour
    {
        public float Steer { get; private set; }
        public float Throttle { get; private set; }
        public float Brake { get; private set; }
        public bool UpshiftPressed { get; private set; }
        public bool DownshiftPressed { get; private set; }

        RectTransform left, right, throttle, brake, upshift, downshift;
        Image leftImg, rightImg, throttleImg, brakeImg;
        bool upHeld, downHeld;
        Canvas canvas;
        static readonly Color Idle = new Color(1f, 1f, 1f, 0.16f);
        static readonly Color Active = new Color(0.95f, 0.66f, 0f, 0.55f);

        public void Build(bool showSteering, bool showShifter)
        {
            canvas = UiFactory.CreateCanvas("TouchControls", 10);
            canvas.transform.SetParent(transform, false);
            var root = canvas.transform;
            left = Control(root, "SteerLeft", new Vector2(0, 0), new Vector2(0, 0), new Vector2(60, 60), new Vector2(250, 250), "◄", out leftImg);
            right = Control(root, "SteerRight", new Vector2(0, 0), new Vector2(0, 0), new Vector2(340, 60), new Vector2(250, 250), "►", out rightImg);
            brake = Control(root, "Brake", new Vector2(1, 0), new Vector2(1, 0), new Vector2(-370, 60), new Vector2(220, 260), "BRAKE", out brakeImg);
            throttle = Control(root, "Throttle", new Vector2(1, 0), new Vector2(1, 0), new Vector2(-60, 60), new Vector2(260, 340), "GAS", out throttleImg);
            left.gameObject.SetActive(showSteering);
            right.gameObject.SetActive(showSteering);
            if (showShifter)
            {
                upshift = Control(root, "Upshift", new Vector2(1, 0), new Vector2(1, 0), new Vector2(-60, 430), new Vector2(150, 120), "+", out _);
                downshift = Control(root, "Downshift", new Vector2(1, 0), new Vector2(1, 0), new Vector2(-230, 430), new Vector2(150, 120), "−", out _);
            }
        }

        static RectTransform Control(Transform root, string name, Vector2 anchor, Vector2 pivot, Vector2 pos, Vector2 size, string label, out Image img)
        {
            // Pivot sits on the anchor corner so positions read as margins from that screen corner.
            var rt = UiFactory.Box(root, name, anchor, new Vector2(anchor.x, 0f), pos, size);
            img = UiFactory.Panel(rt, Idle);
            img.raycastTarget = false;
            UiFactory.Label(rt, "Label", label, 44, TextAnchor.MiddleCenter, new Color(1f, 1f, 1f, 0.85f), FontStyle.Bold);
            return rt;
        }

        void Update()
        {
            bool l = false, r = false, t = false, b = false, up = false, down = false;
            for (int i = 0; i < UnityEngine.Input.touchCount; i++)
            {
                var touch = UnityEngine.Input.GetTouch(i);
                if (touch.phase == TouchPhase.Ended || touch.phase == TouchPhase.Canceled) continue;
                Test(touch.position, ref l, ref r, ref t, ref b, ref up, ref down);
            }
            if (UnityEngine.Input.touchCount == 0 && UnityEngine.Input.GetMouseButton(0))
                Test(UnityEngine.Input.mousePosition, ref l, ref r, ref t, ref b, ref up, ref down);

            Steer = (r ? 1f : 0f) - (l ? 1f : 0f);
            Throttle = t ? 1f : 0f;
            Brake = b ? 1f : 0f;
            UpshiftPressed = up && !upHeld;
            DownshiftPressed = down && !downHeld;
            upHeld = up;
            downHeld = down;

            if (leftImg != null) leftImg.color = l ? Active : Idle;
            if (rightImg != null) rightImg.color = r ? Active : Idle;
            if (throttleImg != null) throttleImg.color = t ? Active : Idle;
            if (brakeImg != null) brakeImg.color = b ? Active : Idle;
        }

        void Test(Vector2 p, ref bool l, ref bool r, ref bool t, ref bool b, ref bool up, ref bool down)
        {
            l |= Hit(left, p);
            r |= Hit(right, p);
            t |= Hit(throttle, p);
            b |= Hit(brake, p);
            up |= Hit(upshift, p);
            down |= Hit(downshift, p);
        }

        static bool Hit(RectTransform rt, Vector2 p)
        {
            return rt != null && rt.gameObject.activeInHierarchy && RectTransformUtility.RectangleContainsScreenPoint(rt, p, null);
        }

        public void SetVisible(bool visible)
        {
            if (canvas != null) canvas.enabled = visible;
        }
    }
}
