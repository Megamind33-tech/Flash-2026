using System;
using System.Collections.Generic;
using Gridline.Track;
using UnityEngine;

namespace Gridline.EditorTools
{
    /// <summary>Procedural mesh helpers for track-following geometry. UVs are in metres (u lateral / vertical, v along track).</summary>
    public static class MeshKit
    {
        public static Vector3 Right(TrackPath t, int i)
        {
            int n = t.points.Length;
            Vector3 dir = t.points[(i + 1) % n] - t.points[(i - 1 + n) % n];
            dir.y = 0f;
            dir.Normalize();
            return new Vector3(dir.z, 0f, -dir.x);
        }

        /// <summary>
        /// Flat strip between two lateral offsets along the closed centreline. Only segments where
        /// <paramref name="include"/> is true are emitted. Height may vary across the strip (kerb profile).
        /// </summary>
        public static Mesh Strip(TrackPath t, Func<int, float> from, Func<int, float> to, float yFrom, float yTo, Func<int, bool> include, string name)
        {
            int n = t.points.Length;
            var verts = new List<Vector3>();
            var uvs = new List<Vector2>();
            var tris = new List<int>();
            float length = t.Length;
            for (int i = 0; i <= n; i++)
            {
                int k = i % n;
                Vector3 p = t.points[k];
                Vector3 r = Right(t, k);
                float v = i == n ? length : t.DistanceOfPoint(k);
                float a = from(k), b = to(k);
                verts.Add(p + r * a + Vector3.up * yFrom);
                verts.Add(p + r * b + Vector3.up * yTo);
                uvs.Add(new Vector2(a, v));
                uvs.Add(new Vector2(b, v));
            }
            for (int i = 0; i < n; i++)
            {
                if (include != null && !include(i)) continue;
                int a0 = i * 2, b0 = a0 + 1, a1 = a0 + 2, b1 = a0 + 3;
                tris.Add(a0); tris.Add(a1); tris.Add(b1);
                tris.Add(a0); tris.Add(b1); tris.Add(b0);
            }
            var mesh = Build(name, verts, uvs, tris);
            // Make sure the surface faces up regardless of which offset is further left.
            if (mesh.normals.Length > 0 && AverageNormalY(mesh) < 0f) Flip(mesh);
            return mesh;
        }

        /// <summary>Double-sided vertical wall following a lateral offset.</summary>
        public static Mesh Wall(TrackPath t, Func<int, float> offset, float bottom, float top, Func<int, bool> include, string name)
        {
            int n = t.points.Length;
            var verts = new List<Vector3>();
            var uvs = new List<Vector2>();
            var tris = new List<int>();
            for (int i = 0; i <= n; i++)
            {
                int k = i % n;
                Vector3 p = t.points[k] + Right(t, k) * offset(k);
                float v = i == n ? t.Length : t.DistanceOfPoint(k);
                verts.Add(p + Vector3.up * bottom);
                verts.Add(p + Vector3.up * top);
                uvs.Add(new Vector2(v, bottom));
                uvs.Add(new Vector2(v, top));
            }
            for (int i = 0; i < n; i++)
            {
                if (include != null && !include(i)) continue;
                int a0 = i * 2, a1 = a0 + 1, b0 = a0 + 2, b1 = a0 + 3;
                tris.Add(a0); tris.Add(a1); tris.Add(b1);
                tris.Add(a0); tris.Add(b1); tris.Add(b0);
                tris.Add(a0); tris.Add(b1); tris.Add(a1);
                tris.Add(a0); tris.Add(b0); tris.Add(b1);
            }
            return Build(name, verts, uvs, tris);
        }

        /// <summary>Axis-aligned box in a local frame (used for structural beams and pillars).</summary>
        public static void AddBox(List<Vector3> verts, List<Vector2> uvs, List<int> tris, Vector3 center, Vector3 size, Quaternion rot)
        {
            Vector3 h = size * 0.5f;
            Vector3[] c =
            {
                new Vector3(-h.x, -h.y, -h.z), new Vector3(h.x, -h.y, -h.z), new Vector3(h.x, h.y, -h.z), new Vector3(-h.x, h.y, -h.z),
                new Vector3(-h.x, -h.y, h.z), new Vector3(h.x, -h.y, h.z), new Vector3(h.x, h.y, h.z), new Vector3(-h.x, h.y, h.z),
            };
            int[][] faces = { new[] { 0, 3, 2, 1 }, new[] { 5, 6, 7, 4 }, new[] { 4, 7, 3, 0 }, new[] { 1, 2, 6, 5 }, new[] { 3, 7, 6, 2 }, new[] { 4, 0, 1, 5 } };
            foreach (var f in faces)
            {
                int start = verts.Count;
                for (int k = 0; k < 4; k++)
                {
                    verts.Add(center + rot * c[f[k]]);
                    uvs.Add(new Vector2(k == 1 || k == 2 ? 1 : 0, k >= 2 ? 1 : 0));
                }
                tris.Add(start); tris.Add(start + 1); tris.Add(start + 2);
                tris.Add(start); tris.Add(start + 2); tris.Add(start + 3);
            }
        }

        public static void AddQuad(List<Vector3> verts, List<Vector2> uvs, List<int> tris, Vector3 a, Vector3 b, Vector3 c, Vector3 d)
        {
            int s = verts.Count;
            verts.Add(a); verts.Add(b); verts.Add(c); verts.Add(d);
            uvs.Add(new Vector2(0, 0)); uvs.Add(new Vector2(0, 1)); uvs.Add(new Vector2(1, 1)); uvs.Add(new Vector2(1, 0));
            tris.Add(s); tris.Add(s + 1); tris.Add(s + 2);
            tris.Add(s); tris.Add(s + 2); tris.Add(s + 3);
        }

        public static Mesh Build(string name, List<Vector3> verts, List<Vector2> uvs, List<int> tris)
        {
            var mesh = new Mesh { name = name };
            if (verts.Count > 65000) mesh.indexFormat = UnityEngine.Rendering.IndexFormat.UInt32;
            mesh.SetVertices(verts);
            mesh.SetUVs(0, uvs);
            mesh.SetTriangles(tris, 0);
            mesh.RecalculateNormals();
            mesh.RecalculateTangents();
            mesh.RecalculateBounds();
            return mesh;
        }

        static float AverageNormalY(Mesh m)
        {
            float sum = 0f;
            foreach (var nrm in m.normals) sum += nrm.y;
            return sum;
        }

        static void Flip(Mesh m)
        {
            var t = m.triangles;
            for (int i = 0; i < t.Length; i += 3)
            {
                int tmp = t[i + 1];
                t[i + 1] = t[i + 2];
                t[i + 2] = tmp;
            }
            m.triangles = t;
            m.RecalculateNormals();
            m.RecalculateTangents();
        }
    }
}
