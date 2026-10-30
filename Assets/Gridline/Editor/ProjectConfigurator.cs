using System;
using System.Reflection;
using UnityEditor;
using UnityEditor.Build;
using UnityEngine;
using UnityEngine.Rendering;

namespace Gridline.EditorTools
{
    /// <summary>
    /// Idempotent, headless project configuration: URP pipeline + three quality tiers, Android player settings,
    /// legacy input handling. Everything is applied from code so a clean checkout builds without manual editor steps.
    /// URP types are resolved by name so this assembly does not need a compile-time URP reference.
    /// </summary>
    public static class ProjectConfigurator
    {
        public const string CompanyName = "Gridline Studio";
        public const string ProductName = "GRIDLINE";
        public const string ApplicationId = "com.gridline.racingleague";

        const string UrpAssetType = "UnityEngine.Rendering.Universal.UniversalRenderPipelineAsset, Unity.RenderPipelines.Universal.Runtime";
        const string UrpRendererType = "UnityEngine.Rendering.Universal.RendererType, Unity.RenderPipelines.Universal.Runtime";
        const string UrpRendererDataType = "UnityEngine.Rendering.Universal.UniversalRendererData, Unity.RenderPipelines.Universal.Runtime";

        public static readonly string[] QualityNames = { "Low", "Medium", "High" };

        [MenuItem("GRIDLINE/Configure Project")]
        public static void Apply()
        {
            GridlinePaths.EnsureFolder(GridlinePaths.Settings);
            var assets = CreatePipelineAssets();
            ConfigureQuality(assets);
            ConfigurePlayer();
            AssetDatabase.SaveAssets();
            Debug.Log("[GRIDLINE] Project configured: URP tiers=" + assets.Length + ", app id " + ApplicationId);
        }

        static RenderPipelineAsset[] CreatePipelineAssets()
        {
            Type assetType = Type.GetType(UrpAssetType, true);
            string rendererPath = GridlinePaths.Settings + "/GridlineURP_Renderer.asset";
            var renderer = AssetDatabase.LoadAssetAtPath<ScriptableObject>(rendererPath);
            if (renderer == null) renderer = CreateRendererData(rendererPath);

            // Tier tuning: render scale, MSAA samples, shadow distance, shadow map size, soft shadows, HDR.
            var tiers = new[]
            {
                new Tier("Low", 0.75f, 1, 0f, 512, false, false),
                new Tier("Medium", 0.9f, 2, 60f, 1024, false, false),
                new Tier("High", 1.0f, 4, 90f, 2048, true, true),
            };
            var result = new RenderPipelineAsset[tiers.Length];
            for (int i = 0; i < tiers.Length; i++)
            {
                string path = GridlinePaths.Settings + "/GridlineURP_" + tiers[i].Name + ".asset";
                var asset = AssetDatabase.LoadAssetAtPath<RenderPipelineAsset>(path);
                if (asset == null)
                {
                    MethodInfo create = assetType.GetMethod("Create", BindingFlags.Public | BindingFlags.Static);
                    asset = (RenderPipelineAsset)create.Invoke(null, new object[] { renderer });
                    AssetDatabase.CreateAsset(asset, path);
                }
                var so = new SerializedObject(asset);
                Set(so, "m_RenderScale", tiers[i].RenderScale);
                SetInt(so, "m_MSAA", tiers[i].Msaa);
                SetBool(so, "m_MainLightShadowsSupported", tiers[i].ShadowDistance > 0f);
                SetBool(so, "m_AnyShadowsSupported", tiers[i].ShadowDistance > 0f);
                Set(so, "m_ShadowDistance", Mathf.Max(1f, tiers[i].ShadowDistance));
                SetInt(so, "m_MainLightShadowmapResolution", tiers[i].ShadowMap);
                SetInt(so, "m_ShadowCascadeCount", 1);
                SetBool(so, "m_SoftShadowsSupported", tiers[i].SoftShadows);
                SetBool(so, "m_SupportsHDR", tiers[i].Hdr);
                SetBool(so, "m_RequireDepthTexture", false);
                SetBool(so, "m_RequireOpaqueTexture", false);
                SetBool(so, "m_AdditionalLightShadowsSupported", false);
                SetInt(so, "m_AdditionalLightsPerObjectLimit", 2);
                SetBool(so, "m_UseSRPBatcher", true);
                so.ApplyModifiedPropertiesWithoutUndo();
                EditorUtility.SetDirty(asset);
                result[i] = asset;
            }
            return result;
        }

        static ScriptableObject CreateRendererData(string path)
        {
            Type assetType = Type.GetType(UrpAssetType, true);
            Type rendererEnum = Type.GetType(UrpRendererType, true);
            // URP's own factory also assigns default post-process data and shader resources.
            MethodInfo factory = assetType.GetMethod("CreateRendererAsset", BindingFlags.NonPublic | BindingFlags.Static);
            if (factory != null)
            {
                object universal = Enum.Parse(rendererEnum, "UniversalRenderer");
                return (ScriptableObject)factory.Invoke(null, new object[] { path, universal, false, "Renderer" });
            }
            Debug.LogWarning("[GRIDLINE] URP CreateRendererAsset not found; creating bare UniversalRendererData");
            var data = ScriptableObject.CreateInstance(Type.GetType(UrpRendererDataType, true));
            AssetDatabase.CreateAsset(data, path);
            return data;
        }

        static void ConfigureQuality(RenderPipelineAsset[] assets)
        {
            GraphicsSettings.defaultRenderPipeline = assets[1];
            var qualityAsset = AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/QualitySettings.asset")[0];
            var so = new SerializedObject(qualityAsset);
            var levels = so.FindProperty("m_QualitySettings");
            while (levels.arraySize < QualityNames.Length) levels.InsertArrayElementAtIndex(levels.arraySize);
            while (levels.arraySize > QualityNames.Length) levels.DeleteArrayElementAtIndex(levels.arraySize - 1);
            for (int i = 0; i < QualityNames.Length; i++)
            {
                var level = levels.GetArrayElementAtIndex(i);
                level.FindPropertyRelative("name").stringValue = QualityNames[i];
                var rp = level.FindPropertyRelative("customRenderPipeline");
                if (rp != null) rp.objectReferenceValue = assets[i];
                SetRelInt(level, "vSyncCount", 0);
                SetRelInt(level, "antiAliasing", 0);
                SetRelInt(level, "pixelLightCount", 1);
                SetRelFloat(level, "lodBias", i == 0 ? 0.7f : i == 1 ? 1f : 1.5f);
                SetRelInt(level, "anisotropicTextures", i == 0 ? 0 : 1);
                SetRelInt(level, "globalTextureMipmapLimit", i == 0 ? 1 : 0);
                SetRelInt(level, "skinWeights", 2);
                SetRelInt(level, "softParticles", 0);
                SetRelInt(level, "realtimeReflectionProbes", 1);
                SetRelInt(level, "particleRaycastBudget", i == 0 ? 64 : 256);
            }
            var current = so.FindProperty("m_CurrentQuality");
            if (current != null) current.intValue = 1;
            so.ApplyModifiedPropertiesWithoutUndo();
            QualitySettings.SetQualityLevel(1, false);
            AssetDatabase.SaveAssets();
        }

        static void ConfigurePlayer()
        {
            var android = NamedBuildTarget.Android;
            PlayerSettings.companyName = CompanyName;
            PlayerSettings.productName = ProductName;
            PlayerSettings.SetApplicationIdentifier(android, ApplicationId);
            PlayerSettings.SetScriptingBackend(android, ScriptingImplementation.IL2CPP);
            PlayerSettings.SetManagedStrippingLevel(android, ManagedStrippingLevel.Low);
            PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARM64;
            PlayerSettings.Android.minSdkVersion = AndroidSdkVersions.AndroidApiLevel26;
            PlayerSettings.Android.targetSdkVersion = AndroidSdkVersions.AndroidApiLevelAuto;
            PlayerSettings.colorSpace = ColorSpace.Linear;
            PlayerSettings.defaultInterfaceOrientation = UIOrientation.AutoRotation;
            PlayerSettings.allowedAutorotateToLandscapeLeft = true;
            PlayerSettings.allowedAutorotateToLandscapeRight = true;
            PlayerSettings.allowedAutorotateToPortrait = false;
            PlayerSettings.allowedAutorotateToPortraitUpsideDown = false;
            PlayerSettings.enableFrameTimingStats = true;
            PlayerSettings.runInBackground = false;
            EditorUserBuildSettings.androidBuildSubtarget = MobileTextureSubtarget.ASTC;

            // GRIDLINE and RVP use the legacy Input Manager (touch, accelerometer, axes). 0 = Input Manager, 2 = Both.
            var player = AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/ProjectSettings.asset");
            if (player.Length > 0)
            {
                var so = new SerializedObject(player[0]);
                var handler = so.FindProperty("activeInputHandler");
                if (handler != null && handler.intValue == 1)
                {
                    handler.intValue = 0;
                    so.ApplyModifiedPropertiesWithoutUndo();
                    Debug.Log("[GRIDLINE] activeInputHandler switched to Input Manager");
                }
            }
        }

        static void Set(SerializedObject so, string name, float v) { var p = so.FindProperty(name); if (p != null) p.floatValue = v; else Missing(name); }
        static void SetInt(SerializedObject so, string name, int v) { var p = so.FindProperty(name); if (p != null) p.intValue = v; else Missing(name); }
        static void SetBool(SerializedObject so, string name, bool v) { var p = so.FindProperty(name); if (p != null) p.boolValue = v; else Missing(name); }
        static void SetRelInt(SerializedProperty sp, string name, int v) { var p = sp.FindPropertyRelative(name); if (p != null) p.intValue = v; }
        static void SetRelFloat(SerializedProperty sp, string name, float v) { var p = sp.FindPropertyRelative(name); if (p != null) p.floatValue = v; }
        static void Missing(string name) { Debug.LogWarning("[GRIDLINE] URP field not found: " + name); }

        readonly struct Tier
        {
            public readonly string Name;
            public readonly float RenderScale;
            public readonly int Msaa;
            public readonly float ShadowDistance;
            public readonly int ShadowMap;
            public readonly bool SoftShadows;
            public readonly bool Hdr;

            public Tier(string name, float renderScale, int msaa, float shadowDistance, int shadowMap, bool softShadows, bool hdr)
            {
                Name = name;
                RenderScale = renderScale;
                Msaa = msaa;
                ShadowDistance = shadowDistance;
                ShadowMap = shadowMap;
                SoftShadows = softShadows;
                Hdr = hdr;
            }
        }
    }
}
