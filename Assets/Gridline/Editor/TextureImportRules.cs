using UnityEditor;
using UnityEngine;

namespace Gridline.EditorTools
{
    /// <summary>Mobile import rules: normal-map/linear detection by suffix, size caps and ASTC on Android.</summary>
    public class TextureImportRules : AssetPostprocessor
    {
        void OnPreprocessTexture()
        {
            bool gridline = assetPath.StartsWith("Assets/Gridline/");
            bool rvp = assetPath.StartsWith(GridlinePaths.RvpRoot + "/Textures/");
            if (!gridline && !rvp) return;
            var importer = (TextureImporter)assetImporter;
            string lower = assetPath.ToLowerInvariant();
            bool normal = lower.Contains("_normal") || lower.Contains("_bump");
            if (gridline)
            {
                if (normal) importer.textureType = TextureImporterType.NormalMap;
                if (lower.Contains("_ms.")) importer.sRGBTexture = false;
                importer.mipmapEnabled = true;
                importer.anisoLevel = 4;
            }
            const int max = 1024;
            importer.maxTextureSize = Mathf.Min(importer.maxTextureSize, 2048);
            var android = importer.GetPlatformTextureSettings("Android");
            android.overridden = true;
            android.maxTextureSize = max;
            android.format = normal ? TextureImporterFormat.ASTC_4x4 : TextureImporterFormat.ASTC_6x6;
            android.compressionQuality = 50;
            importer.SetPlatformTextureSettings(android);
        }
    }
}
