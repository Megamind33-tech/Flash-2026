using System.Collections.Generic;
using Gridline.CameraRig;
using Gridline.Platform;
using Gridline.Race;
using Gridline.Track;
using Gridline.UI;
using RVP;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;

namespace Gridline.EditorTools
{
    /// <summary>
    /// Generates the playable scenes from code: the Ashford Airfield circuit (surfaces, kerbs, gravel, barriers,
    /// grandstand, gantry, lighting) with its race director, and the menu showroom. Deterministic and idempotent.
    /// </summary>
    public static class TrackBuilder
    {
        const float KerbWidth = 1.2f;
        const float BarrierOffset = 18f;
        const float KerbCurvature = 1f / 80f;
        const float GravelCurvature = 1f / 60f;

        // RVP GroundSurfaceMaster indices (see GlobalControl prefab): 0 Default/asphalt, 2 Dirt, 4 Wall.
        const int SurfaceAsphalt = 0, SurfaceDirt = 2, SurfaceWall = 4;

        [MenuItem("GRIDLINE/Build Scenes")]
        public static void BuildAll()
        {
            GridlinePaths.EnsureFolder(GridlinePaths.Scenes);
            GridlinePaths.EnsureFolder(GridlinePaths.Meshes);
            GridlinePaths.EnsureFolder(GridlinePaths.Materials);
            GridlinePaths.EnsureFolder(GridlinePaths.Textures);
            BuildRaceScene();
            BuildMenuScene();
            EditorBuildSettings.scenes = new[]
            {
                new EditorBuildSettingsScene(GridlinePaths.MenuScene, true),
                new EditorBuildSettingsScene(GridlinePaths.RaceScene, true),
            };
            AssetDatabase.SaveAssets();
            Debug.Log("[GRIDLINE] Scenes built: " + GridlinePaths.MenuScene + ", " + GridlinePaths.RaceScene);
        }

        // ------------------------------------------------------------------ Race scene

        static void BuildRaceScene()
        {
            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);

            var trackGo = new GameObject("Track");
            var track = trackGo.AddComponent<TrackPath>();
            track.trackId = CircuitLayout.AshfordId;
            track.displayName = CircuitLayout.AshfordName;
            track.halfWidth = CircuitLayout.AshfordHalfWidth;
            track.points = CircuitLayout.BuildCentreline(CircuitLayout.AshfordControlPoints, 2f);
            track.Rebuild();

            var mats = new TrackMaterials();
            var geometry = new GameObject("Geometry").transform;
            BuildSurfaces(track, geometry, mats);
            BuildBarriers(track, geometry, mats);
            BuildStartArea(track, geometry, mats);
            BuildGrandstand(track, geometry, mats);
            BuildGround(track, geometry, mats);
            foreach (Transform child in geometry) GameObjectUtility.SetStaticEditorFlags(child.gameObject, StaticEditorFlags.BatchingStatic);

            var sun = BuildLighting(mats, new Vector3(140f, 12f, -215f));
            var globalControl = InstantiatePrefab(GridlinePaths.GlobalControlPrefab);
            // RVP's quick-restart listens for a keyboard key; GRIDLINE is touch-only and restarts from the pause menu.
            if (globalControl != null)
            {
                var gc = globalControl.GetComponent<GlobalControl>();
                gc.quickRestart = false;
                PrefabUtility.RecordPrefabInstancePropertyModifications(gc);
            }

            var camGo = new GameObject("RaceCamera", typeof(Camera), typeof(AudioListener));
            camGo.tag = "MainCamera";
            var cam = camGo.GetComponent<Camera>();
            cam.nearClipPlane = 0.25f;
            cam.farClipPlane = 1400f;
            cam.fieldOfView = 58f;
            var raceCam = camGo.AddComponent<RaceCamera>();
            camGo.transform.position = track.PositionAt(-60f) + Vector3.up * 4f;

            var directorGo = new GameObject("RaceDirector");
            var director = directorGo.AddComponent<RaceDirector>();
            director.track = track;
            director.carPrefab = AssetDatabase.LoadAssetAtPath<GameObject>(GridlinePaths.CarPrefab);
            director.liveries = MaterialLibrary.Liveries();
            director.raceCamera = raceCam;
            director.perfLogger = directorGo.AddComponent<PerformanceLogger>();
            var hudGo = new GameObject("RaceHud");
            UiAssets.AddDocument(hudGo, UiAssets.HudUxml);
            hudGo.AddComponent<Gridline.Input.TouchControls>();
            director.hud = hudGo.AddComponent<RaceHudController>();
            if (director.carPrefab == null) Debug.LogError("[GRIDLINE] Car prefab missing at " + GridlinePaths.CarPrefab);

            RenderSettings.sun = sun;
            EditorSceneManager.SaveScene(scene, GridlinePaths.RaceScene);
        }

        sealed class TrackMaterials
        {
            public readonly Material Asphalt = MaterialLibrary.Surface("asphalt", 8f, 0.55f, new Color(0.82f, 0.82f, 0.84f));
            public readonly Material Grass = MaterialLibrary.Surface("grass", 5f, 0.35f, new Color(0.78f, 0.84f, 0.74f));
            public readonly Material Gravel = MaterialLibrary.Surface("gravel", 4f, 0.4f, new Color(0.93f, 0.9f, 0.84f));
            public readonly Material Concrete = MaterialLibrary.Surface("concrete", 4f, 0.5f, new Color(0.86f, 0.86f, 0.86f));
            public readonly Material Paint = MaterialLibrary.Solid("Paint_White", new Color(0.92f, 0.92f, 0.9f), 0f, 0.35f);
            public readonly Material Steel = MaterialLibrary.Solid("Steel_Armco", new Color(0.7f, 0.72f, 0.74f), 0.85f, 0.55f);
            public readonly Material DarkMetal = MaterialLibrary.Solid("Steel_Dark", new Color(0.16f, 0.17f, 0.19f), 0.6f, 0.45f);
            public readonly Material Seats = MaterialLibrary.Solid("Grandstand_Seats", new Color(0.17f, 0.29f, 0.46f), 0f, 0.4f);
            public readonly Material Lamp = MaterialLibrary.Solid("Gantry_Lamp", new Color(0.25f, 0.03f, 0.03f), 0f, 0.8f, new Color(0.9f, 0.08f, 0.05f));
            public readonly Material Kerb = MaterialLibrary.Textured("Kerb_RedWhite", KerbTexture(), Color.white, 0.4f);
            public readonly Material Sky = MaterialLibrary.Skybox();

            public TrackMaterials()
            {
                // Kerb UV v runs in metres: one red/white pair every 3 m.
                Kerb.SetTextureScale("_BaseMap", new Vector2(1f, 1f / 3f));
            }
        }

        static void BuildSurfaces(TrackPath t, Transform parent, TrackMaterials m)
        {
            float hw = t.halfWidth;
            AddPiece(parent, "Road", MeshKit.Strip(t, i => -hw, i => hw, 0.02f, 0.02f, null, "Road"), m.Asphalt, SurfaceAsphalt, 1f, true);
            AddPiece(parent, "EdgeLines", Combine("EdgeLines",
                MeshKit.Strip(t, i => -hw + 0.15f, i => -hw + 0.4f, 0.03f, 0.03f, null, "EdgeL"),
                MeshKit.Strip(t, i => hw - 0.4f, i => hw - 0.15f, 0.03f, 0.03f, null, "EdgeR")), m.Paint, SurfaceAsphalt, 1f, false);

            // Kerbs on both edges through corners, with a raised outer lip.
            var curvature = new float[t.Count];
            for (int i = 0; i < t.Count; i++) curvature[i] = t.SignedCurvature(i);
            System.Func<int, bool> corner = i => Mathf.Abs(curvature[i]) > KerbCurvature || Mathf.Abs(curvature[(i + 1) % t.Count]) > KerbCurvature;
            AddPiece(parent, "Kerbs", Combine("Kerbs",
                MeshKit.Strip(t, i => hw, i => hw + KerbWidth, 0.03f, 0.09f, corner, "KerbR"),
                MeshKit.Strip(t, i => -hw - KerbWidth, i => -hw, 0.09f, 0.03f, corner, "KerbL")), m.Kerb, SurfaceAsphalt, 0.9f, true);

            // Gravel traps on the outside of tight corners (outside = opposite side to the turn direction).
            System.Func<int, bool> gravelRight = i => curvature[i] < -GravelCurvature;
            System.Func<int, bool> gravelLeft = i => curvature[i] > GravelCurvature;
            AddPiece(parent, "Gravel", Combine("Gravel",
                MeshKit.Strip(t, i => hw + 3f, i => hw + 15f, 0.0f, 0.0f, gravelRight, "GravelR"),
                MeshKit.Strip(t, i => -hw - 15f, i => -hw - 3f, 0.0f, 0.0f, gravelLeft, "GravelL")), m.Gravel, SurfaceDirt, 0.45f, true);
        }

        static void BuildBarriers(TrackPath t, Transform parent, TrackMaterials m)
        {
            float hw = t.halfWidth;
            int n = t.Count;
            var right = new float[n];
            var left = new float[n];
            for (int i = 0; i < n; i++)
            {
                float k = t.SignedCurvature(i, 8);
                float desired = hw + BarrierOffset;
                // On the inside of a bend the offset must stay well inside the turning radius or the wall folds over itself.
                float insideLimit = Mathf.Abs(k) > 1e-4f ? 0.8f / Mathf.Abs(k) : desired;
                right[i] = k > 0f ? Mathf.Min(desired, insideLimit) : desired;
                left[i] = k < 0f ? -Mathf.Min(desired, insideLimit) : -desired;
            }
            right = SmoothLoop(right, 6);
            left = SmoothLoop(left, 6);
            float length = t.Length;
            // Pit straight (approach to and past the line) gets a concrete wall on the outside instead of armco.
            System.Func<int, bool> pitStraight = i => { float d = t.DistanceOfPoint(i); return d < 320f || d > length - 60f; };
            AddPiece(parent, "Armco", Combine("Armco",
                MeshKit.Wall(t, i => right[i], 0.25f, 0.95f, null, "ArmcoR"),
                MeshKit.Wall(t, i => left[i], 0.25f, 0.95f, i => !pitStraight(i), "ArmcoL")), m.Steel, SurfaceWall, 0f, true);
            AddPiece(parent, "ArmcoPosts", Combine("ArmcoPosts",
                MeshKit.Wall(t, i => right[i] + 0.15f, 0f, 0.25f, null, "PostR"),
                MeshKit.Wall(t, i => left[i] - 0.15f, 0f, 0.25f, i => !pitStraight(i), "PostL")), m.DarkMetal, SurfaceWall, 0f, false);
            AddPiece(parent, "PitWall", MeshKit.Wall(t, i => left[i], 0f, 1.2f, pitStraight, "PitWall"), m.Concrete, SurfaceWall, 0f, true);
        }

        static void BuildStartArea(TrackPath t, Transform parent, TrackMaterials m)
        {
            float hw = t.halfWidth;
            var verts = new List<Vector3>();
            var uvs = new List<Vector2>();
            var tris = new List<int>();

            // Start/finish line at distance 0 plus grid boxes matching RaceDirector's slot layout (12 m + 8 m per slot, +-2.6 m).
            Stripe(t, verts, uvs, tris, 0f, 0.8f, -hw, hw);
            for (int slot = 0; slot < 8; slot++)
            {
                float d = -(12f + slot * 8f) + 2.6f;
                float lateral = slot % 2 == 0 ? -2.6f : 2.6f;
                Stripe(t, verts, uvs, tris, d, 0.25f, lateral - 1.3f, lateral + 1.3f);
                Stripe(t, verts, uvs, tris, d - 1.6f, 1.6f, lateral - 1.3f, lateral - 1.05f);
                Stripe(t, verts, uvs, tris, d - 1.6f, 1.6f, lateral + 1.05f, lateral + 1.3f);
            }
            AddPiece(parent, "GridMarkings", MeshKit.Build("GridMarkings", verts, uvs, tris), m.Paint, SurfaceAsphalt, 1f, false);

            // Start gantry spanning the track at the line.
            verts.Clear(); uvs.Clear(); tris.Clear();
            Vector3 c = t.PositionAt(0f);
            Quaternion rot = Quaternion.LookRotation(t.TangentAt(0f), Vector3.up);
            Vector3 r = t.RightAt(0f);
            float span = hw + 2.4f;
            MeshKit.AddBox(verts, uvs, tris, c + r * span + Vector3.up * 3.6f, new Vector3(0.6f, 7.2f, 0.6f), rot);
            MeshKit.AddBox(verts, uvs, tris, c - r * span + Vector3.up * 3.6f, new Vector3(0.6f, 7.2f, 0.6f), rot);
            MeshKit.AddBox(verts, uvs, tris, c + Vector3.up * 6.6f, new Vector3(span * 2f + 0.6f, 1.1f, 0.7f), rot);
            var gantry = AddPiece(parent, "StartGantry", MeshKit.Build("StartGantry", verts, uvs, tris), m.DarkMetal, SurfaceWall, 0f, true);

            verts.Clear(); uvs.Clear(); tris.Clear();
            Vector3 back = -t.TangentAt(0f) * 0.37f;
            for (int i = 0; i < 5; i++)
            {
                Vector3 lamp = c + back + Vector3.up * 6.6f + r * ((i - 2) * 1.1f);
                MeshKit.AddBox(verts, uvs, tris, lamp, new Vector3(0.7f, 0.7f, 0.06f), rot);
            }
            AddPiece(gantry.transform, "Lamps", MeshKit.Build("GantryLamps", verts, uvs, tris), m.Lamp, SurfaceWall, 0f, false);
        }

        static void Stripe(TrackPath t, List<Vector3> verts, List<Vector2> uvs, List<int> tris, float d, float length, float from, float to)
        {
            const float y = 0.035f;
            Vector3 p0 = t.PositionAt(d), p1 = t.PositionAt(d + length);
            Vector3 r0 = t.RightAt(d), r1 = t.RightAt(d + length);
            MeshKit.AddQuad(verts, uvs, tris, p0 + r0 * from + Vector3.up * y, p1 + r1 * from + Vector3.up * y, p1 + r1 * to + Vector3.up * y, p0 + r0 * to + Vector3.up * y);
        }

        static void BuildGrandstand(TrackPath t, Transform parent, TrackMaterials m)
        {
            // Covered grandstand on the outside of the pit straight, facing the grid.
            var concrete = new List<Vector3>(); var cuv = new List<Vector2>(); var ctris = new List<int>();
            var seats = new List<Vector3>(); var suv = new List<Vector2>(); var stris = new List<int>();
            float startD = -40f, endD = 150f;
            Vector3 a = t.PositionAt(startD), b = t.PositionAt(endD);
            Vector3 along = (b - a).normalized;
            Vector3 outward = -t.RightAt(50f);
            float baseOffset = t.halfWidth + BarrierOffset + 6f;
            const int rows = 9;
            const float rowDepth = 0.85f, rowRise = 0.5f, plinth = 1.2f;
            float len = Vector3.Distance(a, b);
            Vector3 origin = a + outward * baseOffset;
            for (int row = 0; row < rows; row++)
            {
                float z0 = row * rowDepth, z1 = z0 + rowDepth;
                float y0 = plinth + row * rowRise, y1 = y0 + rowRise;
                Vector3 s0 = origin + outward * z0, s1 = origin + outward * z1;
                // Riser (concrete) then seating tread.
                MeshKit.AddQuad(concrete, cuv, ctris, s0 + Vector3.up * y0, s0 + Vector3.up * y1, s0 + along * len + Vector3.up * y1, s0 + along * len + Vector3.up * y0);
                MeshKit.AddQuad(seats, suv, stris, s0 + Vector3.up * y1, s1 + Vector3.up * y1, s1 + along * len + Vector3.up * y1, s0 + along * len + Vector3.up * y1);
            }
            float depth = rows * rowDepth, top = plinth + rows * rowRise;
            Quaternion rot = Quaternion.LookRotation(along, Vector3.up);
            // Front plinth wall, back wall, end walls and a cantilever roof on columns.
            MeshKit.AddQuad(concrete, cuv, ctris, origin, origin + Vector3.up * plinth, origin + along * len + Vector3.up * plinth, origin + along * len);
            Vector3 backBase = origin + outward * depth;
            MeshKit.AddBox(concrete, cuv, ctris, backBase + along * len * 0.5f + Vector3.up * (top + 1.5f) * 0.5f, new Vector3(len, top + 1.5f, 0.4f), rot);
            MeshKit.AddBox(concrete, cuv, ctris, origin + outward * depth * 0.5f + Vector3.up * (top * 0.5f), new Vector3(0.4f, top, depth), rot);
            MeshKit.AddBox(concrete, cuv, ctris, origin + along * len + outward * depth * 0.5f + Vector3.up * (top * 0.5f), new Vector3(0.4f, top, depth), rot);
            var steel = new List<Vector3>(); var guv = new List<Vector2>(); var gtris = new List<int>();
            MeshKit.AddBox(steel, guv, gtris, origin + along * len * 0.5f + outward * (depth * 0.45f) + Vector3.up * (top + 3.2f), new Vector3(len + 2f, 0.3f, depth + 3f), rot);
            for (float x = 0f; x <= len + 0.01f; x += len / 6f)
                MeshKit.AddBox(steel, guv, gtris, backBase + along * x + Vector3.up * (top + 3.2f) * 0.5f, new Vector3(0.35f, top + 3.2f, 0.35f), rot);
            var stand = AddPiece(parent, "Grandstand", MeshKit.Build("GrandstandStructure", concrete, cuv, ctris), m.Concrete, SurfaceWall, 0f, true);
            AddPiece(stand.transform, "Seating", MeshKit.Build("GrandstandSeats", seats, suv, stris), m.Seats, SurfaceWall, 0f, false);
            AddPiece(stand.transform, "Roof", MeshKit.Build("GrandstandRoof", steel, guv, gtris), m.DarkMetal, SurfaceWall, 0f, false);
        }

        static void BuildGround(TrackPath t, Transform parent, TrackMaterials m)
        {
            var bounds = new Bounds(t.points[0], Vector3.zero);
            foreach (var p in t.points) bounds.Encapsulate(p);
            bounds.Expand(new Vector3(700f, 0f, 700f));
            var verts = new List<Vector3>();
            var uvs = new List<Vector2>();
            var tris = new List<int>();
            const int cells = 16;
            Vector3 min = bounds.min, size = bounds.size;
            for (int z = 0; z <= cells; z++)
            for (int x = 0; x <= cells; x++)
            {
                var p = new Vector3(min.x + size.x * x / cells, -0.05f, min.z + size.z * z / cells);
                verts.Add(p);
                uvs.Add(new Vector2(p.x, p.z));
            }
            for (int z = 0; z < cells; z++)
            for (int x = 0; x < cells; x++)
            {
                int i = z * (cells + 1) + x;
                tris.Add(i); tris.Add(i + cells + 1); tris.Add(i + cells + 2);
                tris.Add(i); tris.Add(i + cells + 2); tris.Add(i + 1);
            }
            AddPiece(parent, "Ground", MeshKit.Build("Ground", verts, uvs, tris), m.Grass, SurfaceDirt, 0.65f, true);
        }

        static Light BuildLighting(TrackMaterials m, Vector3 probeCentre)
        {
            var sunGo = new GameObject("Sun");
            var sun = sunGo.AddComponent<Light>();
            sun.type = LightType.Directional;
            sun.color = new Color(1f, 0.95f, 0.88f);
            sun.intensity = 1.35f;
            sun.shadows = LightShadows.Soft;
            sun.shadowStrength = 0.85f;
            sunGo.transform.rotation = Quaternion.Euler(42f, -35f, 0f);

            RenderSettings.skybox = m.Sky;
            RenderSettings.ambientMode = AmbientMode.Trilight;
            RenderSettings.ambientSkyColor = new Color(0.56f, 0.63f, 0.74f);
            RenderSettings.ambientEquatorColor = new Color(0.46f, 0.48f, 0.47f);
            RenderSettings.ambientGroundColor = new Color(0.24f, 0.23f, 0.2f);
            RenderSettings.fog = true;
            RenderSettings.fogMode = FogMode.Linear;
            RenderSettings.fogColor = new Color(0.68f, 0.73f, 0.79f);
            RenderSettings.fogStartDistance = 280f;
            RenderSettings.fogEndDistance = 1300f;
            RenderSettings.defaultReflectionMode = DefaultReflectionMode.Skybox;

            // One realtime probe captured at load gives car paint believable reflections without baking.
            var probeGo = new GameObject("ReflectionProbe");
            probeGo.transform.position = probeCentre;
            var probe = probeGo.AddComponent<ReflectionProbe>();
            probe.mode = ReflectionProbeMode.Realtime;
            probe.refreshMode = ReflectionProbeRefreshMode.OnAwake;
            probe.timeSlicingMode = ReflectionProbeTimeSlicingMode.AllFacesAtOnce;
            probe.resolution = 128;
            probe.size = new Vector3(3000f, 400f, 3000f);
            probe.hdr = false;
            probe.farClipPlane = 900f;
            return sun;
        }

        // ------------------------------------------------------------------ Menu scene

        static void BuildMenuScene()
        {
            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            var mats = new TrackMaterials();
            var sun = BuildLighting(mats, new Vector3(0f, 3f, 0f));
            sun.transform.rotation = Quaternion.Euler(35f, 150f, 0f);
            RenderSettings.sun = sun;
            RenderSettings.fogStartDistance = 40f;
            RenderSettings.fogEndDistance = 160f;

            var verts = new List<Vector3>();
            var uvs = new List<Vector2>();
            var tris = new List<int>();
            MeshKit.AddQuad(verts, uvs, tris, new Vector3(-60, 0, -60), new Vector3(-60, 0, 60), new Vector3(60, 0, 60), new Vector3(60, 0, -60));
            for (int i = 0; i < uvs.Count; i++) uvs[i] = new Vector2(verts[i].x, verts[i].z);
            AddPiece(null, "ShowroomFloor", MeshKit.Build("ShowroomFloor", verts, uvs, tris), mats.Asphalt, SurfaceAsphalt, 1f, false);

            var anchor = new GameObject("ShowroomAnchor").transform;
            var camGo = new GameObject("MenuCamera", typeof(Camera), typeof(AudioListener));
            camGo.tag = "MainCamera";
            var cam = camGo.GetComponent<Camera>();
            cam.fieldOfView = 40f;
            cam.farClipPlane = 300f;
            camGo.transform.position = new Vector3(0f, 1.8f, -6f);

            var menuGo = new GameObject("MainMenu");
            UiAssets.AddDocument(menuGo, UiAssets.MenuUxml);
            var menu = menuGo.AddComponent<MainMenuController>();
            menu.carPrefab = AssetDatabase.LoadAssetAtPath<GameObject>(GridlinePaths.CarPrefab);
            var liveries = MaterialLibrary.Liveries();
            menu.playerLivery = liveries.Length > 0 ? liveries[0] : null;
            menu.showroomAnchor = anchor;
            menu.menuCamera = cam;
            EditorSceneManager.SaveScene(scene, GridlinePaths.MenuScene);
        }

        // ------------------------------------------------------------------ helpers

        static GameObject AddPiece(Transform parent, string name, Mesh mesh, Material mat, int surfaceType, float friction, bool collider)
        {
            mesh = SaveMesh(mesh, name);
            var go = new GameObject(name, typeof(MeshFilter), typeof(MeshRenderer));
            if (parent != null) go.transform.SetParent(parent, false);
            go.GetComponent<MeshFilter>().sharedMesh = mesh;
            var r = go.GetComponent<MeshRenderer>();
            r.sharedMaterial = mat;
            r.shadowCastingMode = name == "Grandstand" || name == "StartGantry" || name == "Roof" ? ShadowCastingMode.On : ShadowCastingMode.Off;
            if (collider)
            {
                go.AddComponent<MeshCollider>().sharedMesh = mesh;
                var surface = go.AddComponent<GroundSurfaceInstance>();
                surface.surfaceType = surfaceType;
                surface.friction = friction;
            }
            return go;
        }

        static Mesh SaveMesh(Mesh mesh, string name)
        {
            string path = GridlinePaths.Meshes + "/" + name + ".asset";
            var existing = AssetDatabase.LoadAssetAtPath<Mesh>(path);
            if (existing == null)
            {
                AssetDatabase.CreateAsset(mesh, path);
                return mesh;
            }
            EditorUtility.CopySerialized(mesh, existing);
            existing.name = name;
            EditorUtility.SetDirty(existing);
            return existing;
        }

        static Mesh Combine(string name, params Mesh[] parts)
        {
            var combine = new CombineInstance[parts.Length];
            for (int i = 0; i < parts.Length; i++) combine[i] = new CombineInstance { mesh = parts[i], transform = Matrix4x4.identity };
            var mesh = new Mesh { name = name, indexFormat = IndexFormat.UInt32 };
            mesh.CombineMeshes(combine, true, true);
            mesh.RecalculateBounds();
            foreach (var p in parts) Object.DestroyImmediate(p);
            return mesh;
        }

        static float[] SmoothLoop(float[] src, int radius)
        {
            int n = src.Length;
            var dst = new float[n];
            for (int i = 0; i < n; i++)
            {
                float sum = 0f;
                for (int k = -radius; k <= radius; k++) sum += src[((i + k) % n + n) % n];
                dst[i] = sum / (2 * radius + 1);
            }
            return dst;
        }

        static GameObject InstantiatePrefab(string path)
        {
            var prefab = AssetDatabase.LoadAssetAtPath<GameObject>(path);
            if (prefab == null)
            {
                Debug.LogError("[GRIDLINE] Missing prefab " + path);
                return null;
            }
            return (GameObject)PrefabUtility.InstantiatePrefab(prefab);
        }

        static Texture2D KerbTexture()
        {
            string path = GridlinePaths.Textures + "/kerb_redwhite.png";
            var existing = AssetDatabase.LoadAssetAtPath<Texture2D>(path);
            if (existing != null) return existing;
            // Kerb UVs: u = lateral metres, v = metres along track; one red + one white block per 3 m.
            const int w = 4, h = 32;
            var tex = new Texture2D(w, h, TextureFormat.RGBA32, false);
            var red = new Color(0.72f, 0.09f, 0.08f);
            var white = new Color(0.92f, 0.92f, 0.9f);
            for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
                tex.SetPixel(x, y, y < h / 2 ? red : white);
            System.IO.File.WriteAllBytes(path, tex.EncodeToPNG());
            Object.DestroyImmediate(tex);
            AssetDatabase.ImportAsset(path);
            var importer = (TextureImporter)AssetImporter.GetAtPath(path);
            importer.filterMode = FilterMode.Bilinear;
            importer.wrapMode = TextureWrapMode.Repeat;
            importer.SaveAndReimport();
            return AssetDatabase.LoadAssetAtPath<Texture2D>(path);
        }
    }
}
