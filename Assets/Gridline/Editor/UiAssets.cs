using UnityEditor;
using UnityEngine;
using UnityEngine.UIElements;

namespace Gridline.EditorTools
{
    /// <summary>Creates the UI Toolkit runtime assets (PanelSettings) and attaches UIDocuments to generated scenes.</summary>
    public static class UiAssets
    {
        public const string Theme = "Assets/Gridline/UI/Styles/GridlineTheme.tss";
        public const string MenuUxml = "Assets/Gridline/UI/Uxml/MainMenu.uxml";
        public const string HudUxml = "Assets/Gridline/UI/Uxml/RaceHud.uxml";
        const string PanelPath = GridlinePaths.Settings + "/GridlinePanel.asset";

        public static PanelSettings Panel()
        {
            GridlinePaths.EnsureFolder(GridlinePaths.Settings);
            var panel = AssetDatabase.LoadAssetAtPath<PanelSettings>(PanelPath);
            if (panel == null)
            {
                panel = ScriptableObject.CreateInstance<PanelSettings>();
                AssetDatabase.CreateAsset(panel, PanelPath);
            }
            panel.themeStyleSheet = AssetDatabase.LoadAssetAtPath<ThemeStyleSheet>(Theme);
            if (panel.themeStyleSheet == null) Debug.LogError("[GRIDLINE] Theme style sheet missing: " + Theme);
            panel.scaleMode = PanelScaleMode.ScaleWithScreenSize;
            panel.referenceResolution = new Vector2Int(1920, 1080);
            panel.screenMatchMode = PanelScreenMatchMode.MatchWidthOrHeight;
            panel.match = 0.5f;
            EditorUtility.SetDirty(panel);
            return panel;
        }

        public static UIDocument AddDocument(GameObject go, string uxmlPath)
        {
            var doc = go.AddComponent<UIDocument>();
            doc.panelSettings = Panel();
            doc.visualTreeAsset = AssetDatabase.LoadAssetAtPath<VisualTreeAsset>(uxmlPath);
            if (doc.visualTreeAsset == null) Debug.LogError("[GRIDLINE] UXML missing: " + uxmlPath);
            return doc;
        }
    }
}
