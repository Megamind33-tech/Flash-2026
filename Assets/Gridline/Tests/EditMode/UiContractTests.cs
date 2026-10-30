using Gridline.UI;
using NUnit.Framework;
using UnityEditor;
using UnityEngine.UIElements;

namespace Gridline.Tests
{
    /// <summary>Catches drift between UXML element names and the controllers that bind them.</summary>
    public class UiContractTests
    {
        static void AssertContract(string uxmlPath, string[] names)
        {
            var tree = AssetDatabase.LoadAssetAtPath<VisualTreeAsset>(uxmlPath);
            Assert.IsNotNull(tree, "UXML not imported: " + uxmlPath);
            var root = tree.CloneTree();
            foreach (var n in names) Assert.IsNotNull(root.Q(n), uxmlPath + " is missing element '" + n + "'");
        }

        [Test]
        public void MainMenuUxmlProvidesEveryBoundElement()
        {
            AssertContract("Assets/Gridline/UI/Uxml/MainMenu.uxml", MainMenuController.RequiredElements);
        }

        [Test]
        public void RaceHudUxmlProvidesEveryBoundElement()
        {
            AssertContract("Assets/Gridline/UI/Uxml/RaceHud.uxml", RaceHudController.RequiredElements);
        }

        [Test]
        public void ThemeAndStylesheetImport()
        {
            Assert.IsNotNull(AssetDatabase.LoadAssetAtPath<ThemeStyleSheet>("Assets/Gridline/UI/Styles/GridlineTheme.tss"));
            Assert.IsNotNull(AssetDatabase.LoadAssetAtPath<StyleSheet>("Assets/Gridline/UI/Styles/Gridline.uss"));
        }
    }
}
