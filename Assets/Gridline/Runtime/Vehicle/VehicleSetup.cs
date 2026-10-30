using RVP;
using UnityEngine;

namespace Gridline.Vehicle
{
    /// <summary>Adapts a stock RVP vehicle prefab instance for GRIDLINE races without modifying the vendored prefab.</summary>
    public static class VehicleSetup
    {
        public const string BodyMaterialName = "Body";

        public static VehicleParent Prepare(GameObject car, Material livery, bool manualGearbox)
        {
            // Remove the demo input/debug drivers that ship on RVP prefabs; GRIDLINE supplies its own input.
            Strip<MobileInputGet>(car);
            Strip<BasicInput>(car);
            Strip<MobileInput>(car);
            Strip<VehicleDebug>(car);
            Strip<FollowAI>(car);

            foreach (var gearbox in car.GetComponentsInChildren<GearboxTransmission>(true)) gearbox.automatic = !manualGearbox;
            if (livery != null) ApplyLivery(car, livery);
            return car.GetComponent<VehicleParent>();
        }

        static void Strip<T>(GameObject go) where T : Component
        {
            foreach (var c in go.GetComponentsInChildren<T>(true)) Object.DestroyImmediate(c);
        }

        public static void ApplyLivery(GameObject car, Material livery)
        {
            foreach (var r in car.GetComponentsInChildren<Renderer>(true))
            {
                var mats = r.sharedMaterials;
                bool changed = false;
                for (int i = 0; i < mats.Length; i++)
                {
                    if (mats[i] != null && mats[i].name.StartsWith(BodyMaterialName))
                    {
                        mats[i] = livery;
                        changed = true;
                    }
                }
                if (changed) r.sharedMaterials = mats;
            }
        }

        /// <summary>Display string for the selected gear: R, N or 1..n.</summary>
        public static string GearLabel(VehicleParent vp)
        {
            var gb = vp != null ? vp.GetComponentInChildren<GearboxTransmission>() : null;
            if (gb == null || gb.gears == null || gb.gears.Length == 0) return "-";
            int g = Mathf.Clamp(gb.currentGear, 0, gb.gears.Length - 1);
            float ratio = gb.gears[g].ratio;
            if (ratio < 0f) return "R";
            if (Mathf.Approximately(ratio, 0f)) return "N";
            int forward = 0;
            for (int i = 0; i <= g; i++) if (gb.gears[i].ratio > 0f) forward++;
            return forward.ToString();
        }

        /// <summary>
        /// Builds a render-only copy of a vehicle prefab (meshes and materials, no physics or scripts), e.g. for the menu showroom.
        /// </summary>
        public static GameObject CreateVisualClone(GameObject prefab, Transform parent, Material livery)
        {
            var root = new GameObject(prefab.name + " (Showroom)");
            root.transform.SetParent(parent, false);
            CloneRenderers(prefab.transform, root.transform, livery);
            return root;
        }

        static void CloneRenderers(Transform src, Transform dstParent, Material livery)
        {
            var go = new GameObject(src.name);
            go.transform.SetParent(dstParent, false);
            go.transform.localPosition = src.localPosition;
            go.transform.localRotation = src.localRotation;
            go.transform.localScale = src.localScale;
            var mf = src.GetComponent<MeshFilter>();
            var mr = src.GetComponent<MeshRenderer>();
            if (mf != null && mr != null && mr.enabled && src.gameObject.activeSelf)
            {
                go.AddComponent<MeshFilter>().sharedMesh = mf.sharedMesh;
                var r = go.AddComponent<MeshRenderer>();
                var mats = mr.sharedMaterials;
                for (int i = 0; i < mats.Length; i++)
                    if (livery != null && mats[i] != null && mats[i].name.StartsWith(BodyMaterialName)) mats[i] = livery;
                r.sharedMaterials = mats;
            }
            foreach (Transform child in src)
            {
                // Collision-only helpers and inactive (e.g. broken-glass) variants are skipped.
                if (!child.gameObject.activeSelf || child.name.StartsWith("col_")) continue;
                CloneRenderers(child, go.transform, livery);
            }
        }
    }
}
