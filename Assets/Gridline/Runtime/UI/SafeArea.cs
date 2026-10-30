using UnityEngine;
using UnityEngine.UIElements;

namespace Gridline.UI
{
    /// <summary>Insets a UI Toolkit root by the device safe area (notches, rounded corners, gesture bars).</summary>
    public static class SafeArea
    {
        public static void Apply(VisualElement root)
        {
            if (root.panel == null)
            {
                root.RegisterCallback<AttachToPanelEvent>(_ => Apply(root));
                return;
            }
            Rect sa = Screen.safeArea;
            Vector2 topLeft = RuntimePanelUtils.ScreenToPanel(root.panel, new Vector2(sa.xMin, Screen.height - sa.yMax));
            Vector2 bottomRight = RuntimePanelUtils.ScreenToPanel(root.panel, new Vector2(Screen.width - sa.xMax, sa.yMin));
            root.style.marginLeft = topLeft.x;
            root.style.marginTop = topLeft.y;
            root.style.marginRight = bottomRight.x;
            root.style.marginBottom = bottomRight.y;
        }
    }
}
