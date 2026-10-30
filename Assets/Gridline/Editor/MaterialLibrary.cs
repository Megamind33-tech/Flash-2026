using System.Collections.Generic;
using UnityEditor;
using UnityEngine;

namespace Gridline.EditorTools
{
    /// <summary>
    /// Converts the vendored RVP Built-in materials to URP in place, and creates GRIDLINE's own URP materials
    /// (surfaces, liveries, trackside). All idempotent.
    /// </summary>
    public static class MaterialLibrary
    {
        public const string LitShader = "Universal Render Pipeline/Lit";
        public const string ParticlesUnlitShader = "Universal Render Pipeline/Particles/Unlit";

        public static readonly string[] LiveryNames = { "player_white", "halden_blue", "corsair_red", "vantor_gold", "northline_green" };

        [MenuItem("GRIDLINE/Upgrade RVP Materials To URP")]
        public static void UpgradeRvpMaterials()
        {
            var lit = Shader.Find(LitShader);
            var particles = Shader.Find(ParticlesUnlitShader);
            if (lit == null || particles == null)
            {
                Debug.LogError("[GRIDLINE] URP shaders not found; is the URP package installed?");
                return;
            }
            int converted = 0;
            foreach (string guid in AssetDatabase.FindAssets("t:Material", new[] { GridlinePaths.RvpRoot }))
            {
                string path = AssetDatabase.GUIDToAssetPath(guid);
                var m = AssetDatabase.LoadAssetAtPath<Material>(path);
                if (m == null || m.shader == null || m.shader.name.StartsWith("Universal Render Pipeline")) continue;
                string from = m.shader.name;
                if (from.Contains("Particles")) ConvertParticle(m, particles, from.Contains("Additive"));
                else ConvertLit(m, lit);
                EditorUtility.SetDirty(m);
                converted++;
                Debug.Log("[GRIDLINE] Material " + path + ": " + from + " -> " + m.shader.name);
            }
            AssetDatabase.SaveAssets();
            Debug.Log("[GRIDLINE] RVP materials converted: " + converted);
        }

        static void ConvertLit(Material m, Shader lit)
        {
            // Read Built-in Standard properties before the shader swap drops them from the active property set.
            Texture main = Tex(m, "_MainTex");
            Color color = m.HasProperty("_Color") ? m.GetColor("_Color") : Color.white;
            Texture bump = Tex(m, "_BumpMap");
            float bumpScale = m.HasProperty("_BumpScale") ? m.GetFloat("_BumpScale") : 1f;
            Texture metalMap = Tex(m, "_MetallicGlossMap");
            float metallic = m.HasProperty("_Metallic") ? m.GetFloat("_Metallic") : 0f;
            float gloss = m.HasProperty("_Glossiness") ? m.GetFloat("_Glossiness") : 0.5f;
            float glossScale = m.HasProperty("_GlossMapScale") ? m.GetFloat("_GlossMapScale") : 1f;
            Texture occlusion = Tex(m, "_OcclusionMap");
            Texture emissionMap = Tex(m, "_EmissionMap");
            Color emission = m.HasProperty("_EmissionColor") ? m.GetColor("_EmissionColor") : Color.black;
            bool emissive = m.IsKeywordEnabled("_EMISSION");
            float mode = m.HasProperty("_Mode") ? m.GetFloat("_Mode") : 0f;
            Vector2 tiling = m.HasProperty("_MainTex") ? m.GetTextureScale("_MainTex") : Vector2.one;
            Vector2 offset = m.HasProperty("_MainTex") ? m.GetTextureOffset("_MainTex") : Vector2.zero;

            m.shader = lit;
            m.shaderKeywords = new string[0];
            m.SetTexture("_BaseMap", main);
            m.SetTextureScale("_BaseMap", tiling);
            m.SetTextureOffset("_BaseMap", offset);
            m.SetColor("_BaseColor", color);
            if (bump != null)
            {
                m.SetTexture("_BumpMap", bump);
                m.SetFloat("_BumpScale", bumpScale);
                m.EnableKeyword("_NORMALMAP");
            }
            m.SetFloat("_Metallic", metallic);
            if (metalMap != null)
            {
                m.SetTexture("_MetallicGlossMap", metalMap);
                m.SetFloat("_Smoothness", glossScale);
                m.EnableKeyword("_METALLICSPECGLOSSMAP");
            }
            else
            {
                m.SetFloat("_Smoothness", gloss);
            }
            if (occlusion != null)
            {
                m.SetTexture("_OcclusionMap", occlusion);
                m.EnableKeyword("_OCCLUSIONMAP");
            }
            if (emissive || emissionMap != null)
            {
                m.SetTexture("_EmissionMap", emissionMap);
                m.SetColor("_EmissionColor", emission);
                m.EnableKeyword("_EMISSION");
                m.globalIlluminationFlags = MaterialGlobalIlluminationFlags.None;
            }
            // Built-in render modes: 0 opaque, 1 cutout, 2 fade, 3 transparent.
            if (mode >= 2f) MakeTransparent(m, mode >= 3f);
            else if (mode >= 1f) MakeCutout(m);
            else MakeOpaque(m);
        }

        static void ConvertParticle(Material m, Shader particles, bool additive)
        {
            Texture main = Tex(m, "_MainTex");
            Color tint = m.HasProperty("_TintColor") ? m.GetColor("_TintColor") * 2f : (m.HasProperty("_Color") ? m.GetColor("_Color") : Color.white);
            m.shader = particles;
            m.shaderKeywords = new string[0];
            m.SetTexture("_BaseMap", main);
            m.SetColor("_BaseColor", tint);
            m.SetFloat("_Surface", 1f);
            m.SetFloat("_Blend", additive ? 2f : 0f); // URP blend: 0 alpha, 1 premultiply, 2 additive, 3 multiply
            m.SetFloat("_SrcBlend", additive ? (float)UnityEngine.Rendering.BlendMode.SrcAlpha : (float)UnityEngine.Rendering.BlendMode.SrcAlpha);
            m.SetFloat("_DstBlend", additive ? (float)UnityEngine.Rendering.BlendMode.One : (float)UnityEngine.Rendering.BlendMode.OneMinusSrcAlpha);
            m.SetFloat("_ZWrite", 0f);
            m.EnableKeyword("_SURFACE_TYPE_TRANSPARENT");
            m.renderQueue = (int)UnityEngine.Rendering.RenderQueue.Transparent;
            m.SetOverrideTag("RenderType", "Transparent");
        }

        public static void MakeOpaque(Material m)
        {
            m.SetFloat("_Surface", 0f);
            m.SetFloat("_AlphaClip", 0f);
            m.SetFloat("_SrcBlend", (float)UnityEngine.Rendering.BlendMode.One);
            m.SetFloat("_DstBlend", (float)UnityEngine.Rendering.BlendMode.Zero);
            m.SetFloat("_ZWrite", 1f);
            m.renderQueue = (int)UnityEngine.Rendering.RenderQueue.Geometry;
            m.SetOverrideTag("RenderType", "Opaque");
        }

        static void MakeCutout(Material m)
        {
            MakeOpaque(m);
            m.SetFloat("_AlphaClip", 1f);
            m.SetFloat("_Cutoff", 0.5f);
            m.EnableKeyword("_ALPHATEST_ON");
            m.renderQueue = (int)UnityEngine.Rendering.RenderQueue.AlphaTest;
            m.SetOverrideTag("RenderType", "TransparentCutout");
        }

        static void MakeTransparent(Material m, bool preserveSpecular)
        {
            m.SetFloat("_Surface", 1f);
            m.SetFloat("_Blend", preserveSpecular ? 1f : 0f);
            m.SetFloat("_SrcBlend", preserveSpecular ? (float)UnityEngine.Rendering.BlendMode.One : (float)UnityEngine.Rendering.BlendMode.SrcAlpha);
            m.SetFloat("_DstBlend", (float)UnityEngine.Rendering.BlendMode.OneMinusSrcAlpha);
            m.SetFloat("_ZWrite", 0f);
            m.EnableKeyword("_SURFACE_TYPE_TRANSPARENT");
            if (preserveSpecular) m.EnableKeyword("_ALPHAPREMULTIPLY_ON");
            m.renderQueue = (int)UnityEngine.Rendering.RenderQueue.Transparent;
            m.SetOverrideTag("RenderType", "Transparent");
        }

        static Texture Tex(Material m, string prop) { return m.HasProperty(prop) ? m.GetTexture(prop) : null; }

        // ---------------- GRIDLINE materials ----------------

        public static Material[] Liveries()
        {
            GridlinePaths.EnsureFolder(GridlinePaths.Materials);
            var body = AssetDatabase.LoadAssetAtPath<Material>(GridlinePaths.RvpBodyMaterial);
            var result = new List<Material>();
            foreach (var name in LiveryNames)
            {
                string path = GridlinePaths.Materials + "/Body_Livery_" + name + ".mat";
                var m = AssetDatabase.LoadAssetAtPath<Material>(path);
                if (m == null)
                {
                    m = body != null ? new Material(body) : new Material(Shader.Find(LitShader));
                    AssetDatabase.CreateAsset(m, path);
                }
                else if (body != null)
                {
                    m.CopyPropertiesFromMaterial(body);
                    m.shader = body.shader;
                }
                m.SetTexture("_BaseMap", AssetDatabase.LoadAssetAtPath<Texture2D>(GridlinePaths.LiveryTextures + "/body_" + name + ".png"));
                m.SetColor("_BaseColor", Color.white);
                // Clear-coat look: glossier than the stock body.
                if (m.HasProperty("_Smoothness")) m.SetFloat("_Smoothness", Mathf.Max(m.GetFloat("_Smoothness"), 0.78f));
                EditorUtility.SetDirty(m);
                result.Add(m);
            }
            return result.ToArray();
        }

        public static Material Surface(string name, float tileMetres, float smoothnessScale, Color tint)
        {
            string path = GridlinePaths.Materials + "/Surface_" + name + ".mat";
            var m = GetOrCreate(path);
            m.SetTexture("_BaseMap", AssetDatabase.LoadAssetAtPath<Texture2D>(GridlinePaths.SurfaceTextures + "/" + name + "_albedo.jpg"));
            m.SetColor("_BaseColor", tint);
            var normal = AssetDatabase.LoadAssetAtPath<Texture2D>(GridlinePaths.SurfaceTextures + "/" + name + "_normal.jpg");
            if (normal != null)
            {
                m.SetTexture("_BumpMap", normal);
                m.EnableKeyword("_NORMALMAP");
            }
            var ms = AssetDatabase.LoadAssetAtPath<Texture2D>(GridlinePaths.SurfaceTextures + "/" + name + "_ms.png");
            if (ms != null)
            {
                m.SetTexture("_MetallicGlossMap", ms);
                m.EnableKeyword("_METALLICSPECGLOSSMAP");
            }
            m.SetFloat("_Smoothness", smoothnessScale);
            m.SetFloat("_Metallic", 0f);
            // Meshes carry UVs in metres; tiling converts to texture repeats.
            m.SetTextureScale("_BaseMap", Vector2.one / tileMetres);
            EditorUtility.SetDirty(m);
            return m;
        }

        public static Material Solid(string name, Color color, float metallic, float smoothness, Color emission = default)
        {
            var m = GetOrCreate(GridlinePaths.Materials + "/" + name + ".mat");
            m.SetColor("_BaseColor", color);
            m.SetFloat("_Metallic", metallic);
            m.SetFloat("_Smoothness", smoothness);
            if (emission.maxColorComponent > 0f)
            {
                m.SetColor("_EmissionColor", emission);
                m.EnableKeyword("_EMISSION");
                m.globalIlluminationFlags = MaterialGlobalIlluminationFlags.None;
            }
            EditorUtility.SetDirty(m);
            return m;
        }

        public static Material Textured(string name, Texture2D tex, Color tint, float smoothness)
        {
            var m = GetOrCreate(GridlinePaths.Materials + "/" + name + ".mat");
            m.SetTexture("_BaseMap", tex);
            m.SetColor("_BaseColor", tint);
            m.SetFloat("_Smoothness", smoothness);
            EditorUtility.SetDirty(m);
            return m;
        }

        public static Material Skybox()
        {
            string path = GridlinePaths.Materials + "/Sky_Procedural.mat";
            var m = AssetDatabase.LoadAssetAtPath<Material>(path);
            if (m == null)
            {
                m = new Material(Shader.Find("Skybox/Procedural"));
                AssetDatabase.CreateAsset(m, path);
            }
            m.SetFloat("_SunSize", 0.035f);
            m.SetFloat("_SunSizeConvergence", 6f);
            m.SetFloat("_AtmosphereThickness", 0.85f);
            m.SetColor("_SkyTint", new Color(0.52f, 0.56f, 0.62f));
            m.SetColor("_GroundColor", new Color(0.38f, 0.37f, 0.34f));
            m.SetFloat("_Exposure", 1.15f);
            EditorUtility.SetDirty(m);
            return m;
        }

        static Material GetOrCreate(string path)
        {
            GridlinePaths.EnsureFolder(System.IO.Path.GetDirectoryName(path).Replace('\\', '/'));
            var m = AssetDatabase.LoadAssetAtPath<Material>(path);
            if (m == null)
            {
                m = new Material(Shader.Find(LitShader));
                AssetDatabase.CreateAsset(m, path);
            }
            return m;
        }
    }
}
