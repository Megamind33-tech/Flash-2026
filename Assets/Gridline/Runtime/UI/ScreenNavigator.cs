// Screen switching pattern forked from Unity Technologies' "Unity Royale" UI Toolkit runtime demo
// (TitleScreenManager, MIT licence, see Assets/Gridline/UI/FORK_NOTICE.md), generalised to named overlays.
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UIElements;

namespace Gridline.UI
{
    /// <summary>Shows/hides named screen roots with the "hidden" USS class and keeps a back stack for the Android back button.</summary>
    public class ScreenNavigator
    {
        public const string HiddenClass = "hidden";
        readonly VisualElement root;
        readonly Stack<VisualElement> open = new Stack<VisualElement>();

        public ScreenNavigator(VisualElement root) { this.root = root; }

        public bool HasOpenScreen { get { return open.Count > 0; } }

        public void Open(string name)
        {
            var screen = root.Q(name);
            if (screen == null || open.Contains(screen)) return;
            screen.RemoveFromClassList(HiddenClass);
            open.Push(screen);
        }

        public void Close(string name)
        {
            var screen = root.Q(name);
            if (screen == null) return;
            screen.AddToClassList(HiddenClass);
            var keep = new List<VisualElement>(open);
            keep.Remove(screen);
            open.Clear();
            for (int i = keep.Count - 1; i >= 0; i--) open.Push(keep[i]);
        }

        /// <summary>Closes the top-most screen. Returns false when nothing was open.</summary>
        public bool Back()
        {
            if (open.Count == 0) return false;
            open.Pop().AddToClassList(HiddenClass);
            return true;
        }

        public static void SetVisible(VisualElement e, bool visible)
        {
            if (e != null) e.EnableInClassList(HiddenClass, !visible);
        }

        /// <summary>Logs any element the controller expects but the UXML does not provide.</summary>
        public static bool Validate(VisualElement root, IEnumerable<string> names, string owner)
        {
            bool ok = true;
            foreach (var n in names)
            {
                if (root.Q(n) != null) continue;
                Debug.LogError("[GRIDLINE] " + owner + ": UXML element '" + n + "' not found");
                ok = false;
            }
            return ok;
        }
    }
}
