using UnityEngine;
using UnityEngine.UIElements;

namespace Gridline.Input
{
    /// <summary>
    /// On-screen driving controls defined in RaceHud.uxml. Raw multi-touch is hit-tested against the pad elements
    /// (rather than UI click events) so holds, slides between pads and simultaneous steer + pedal all work.
    /// </summary>
    public class TouchControls : MonoBehaviour
    {
        public const string PressedClass = "pad--pressed";

        public float Steer { get; private set; }
        public float Throttle { get; private set; }
        public float Brake { get; private set; }
        public bool UpshiftPressed { get; private set; }
        public bool DownshiftPressed { get; private set; }

        VisualElement container, left, right, brake, throttle, up, down;
        bool upHeld, downHeld, visible = true;

        public void Bind(VisualElement root, bool showSteering, bool showShifter)
        {
            container = root.Q("controls");
            left = root.Q("pad-left");
            right = root.Q("pad-right");
            brake = root.Q("pad-brake");
            throttle = root.Q("pad-throttle");
            up = root.Q("pad-up");
            down = root.Q("pad-down");
            Gridline.UI.ScreenNavigator.SetVisible(left, showSteering);
            Gridline.UI.ScreenNavigator.SetVisible(right, showSteering);
            Gridline.UI.ScreenNavigator.SetVisible(up, showShifter);
            Gridline.UI.ScreenNavigator.SetVisible(down, showShifter);
        }

        public void SetVisible(bool show)
        {
            visible = show;
            Gridline.UI.ScreenNavigator.SetVisible(container, show);
            if (!show) Steer = Throttle = Brake = 0f;
        }

        void Update()
        {
            if (container == null || container.panel == null || !visible) return;
            bool l = false, r = false, t = false, b = false, u = false, d = false;
            for (int i = 0; i < UnityEngine.Input.touchCount; i++)
            {
                var touch = UnityEngine.Input.GetTouch(i);
                if (touch.phase == TouchPhase.Ended || touch.phase == TouchPhase.Canceled) continue;
                Test(touch.position, ref l, ref r, ref t, ref b, ref u, ref d);
            }
#if UNITY_EDITOR
            // Editor convenience only: the shipped game is touch/tilt/gamepad.
            if (UnityEngine.Input.touchCount == 0 && UnityEngine.Input.GetMouseButton(0))
                Test(UnityEngine.Input.mousePosition, ref l, ref r, ref t, ref b, ref u, ref d);
#endif
            Steer = (r ? 1f : 0f) - (l ? 1f : 0f);
            Throttle = t ? 1f : 0f;
            Brake = b ? 1f : 0f;
            UpshiftPressed = u && !upHeld;
            DownshiftPressed = d && !downHeld;
            upHeld = u;
            downHeld = d;
            Mark(left, l);
            Mark(right, r);
            Mark(throttle, t);
            Mark(brake, b);
            Mark(up, u);
            Mark(down, d);
        }

        void Test(Vector2 screen, ref bool l, ref bool r, ref bool t, ref bool b, ref bool u, ref bool d)
        {
            Vector2 p = RuntimePanelUtils.ScreenToPanel(container.panel, new Vector2(screen.x, Screen.height - screen.y));
            l |= Hit(left, p);
            r |= Hit(right, p);
            t |= Hit(throttle, p);
            b |= Hit(brake, p);
            u |= Hit(up, p);
            d |= Hit(down, p);
        }

        static bool Hit(VisualElement e, Vector2 p)
        {
            return e != null && e.resolvedStyle.display != DisplayStyle.None && !e.ClassListContains(Gridline.UI.ScreenNavigator.HiddenClass) && e.worldBound.Contains(p);
        }

        static void Mark(VisualElement e, bool on)
        {
            if (e != null) e.EnableInClassList(PressedClass, on);
        }
    }
}
