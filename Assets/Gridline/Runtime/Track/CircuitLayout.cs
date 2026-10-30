using System.Collections.Generic;
using UnityEngine;

namespace Gridline.Track
{
    /// <summary>
    /// Authoritative circuit definitions. Control points are in metres on the XZ plane, driven in list order;
    /// the start/finish line sits on the first control point. Converted to a dense centreline by Catmull-Rom.
    /// </summary>
    public static class CircuitLayout
    {
        public const string AshfordId = "ashford";
        public const string AshfordName = "Ashford Airfield Circuit";
        public const float AshfordHalfWidth = 6f;

        static readonly Vector2[] Ashford =
        {
            new Vector2(0, 0), new Vector2(120, 0), new Vector2(240, 0), new Vector2(330, 0), new Vector2(385, -12),
            new Vector2(405, -55), new Vector2(385, -98), new Vector2(340, -110), new Vector2(280, -104), new Vector2(232, -128),
            new Vector2(214, -180), new Vector2(236, -240), new Vector2(292, -276), new Vector2(362, -292), new Vector2(432, -288),
            new Vector2(482, -318), new Vector2(494, -378), new Vector2(456, -420), new Vector2(385, -432), new Vector2(250, -432),
            new Vector2(120, -432), new Vector2(0, -428), new Vector2(-48, -412), new Vector2(-66, -382), new Vector2(-96, -368),
            new Vector2(-136, -358), new Vector2(-190, -330), new Vector2(-222, -272), new Vector2(-214, -205), new Vector2(-178, -155),
            new Vector2(-196, -95), new Vector2(-184, -36), new Vector2(-132, -4), new Vector2(-60, 0),
        };

        public static Vector2[] AshfordControlPoints { get { return (Vector2[])Ashford.Clone(); } }

        /// <summary>Closed uniform Catmull-Rom through the control points, resampled to roughly <paramref name="spacing"/> metres.</summary>
        public static Vector3[] BuildCentreline(Vector2[] control, float spacing, float height = 0f)
        {
            var dense = new List<Vector3>();
            int n = control.Length;
            const int sub = 48;
            for (int i = 0; i < n; i++)
            {
                Vector2 p0 = control[(i - 1 + n) % n], p1 = control[i], p2 = control[(i + 1) % n], p3 = control[(i + 2) % n];
                for (int k = 0; k < sub; k++)
                {
                    Vector2 p = CatmullRom(p0, p1, p2, p3, k / (float)sub);
                    dense.Add(new Vector3(p.x, height, p.y));
                }
            }
            return Resample(dense, spacing);
        }

        static Vector2 CatmullRom(Vector2 p0, Vector2 p1, Vector2 p2, Vector2 p3, float t)
        {
            float t2 = t * t, t3 = t2 * t;
            return 0.5f * (2f * p1 + (-p0 + p2) * t + (2f * p0 - 5f * p1 + 4f * p2 - p3) * t2 + (-p0 + 3f * p1 - 3f * p2 + p3) * t3);
        }

        static Vector3[] Resample(List<Vector3> loop, float spacing)
        {
            float total = 0f;
            for (int i = 0; i < loop.Count; i++) total += Vector3.Distance(loop[i], loop[(i + 1) % loop.Count]);
            int count = Mathf.Max(8, Mathf.RoundToInt(total / spacing));
            float step = total / count;
            var result = new Vector3[count];
            int seg = 0;
            float segStart = 0f;
            float segLen = Vector3.Distance(loop[0], loop[1 % loop.Count]);
            for (int k = 0; k < count; k++)
            {
                float d = k * step;
                while (d > segStart + segLen && seg < loop.Count - 1)
                {
                    segStart += segLen;
                    seg++;
                    segLen = Vector3.Distance(loop[seg], loop[(seg + 1) % loop.Count]);
                }
                float t = segLen > 1e-5f ? (d - segStart) / segLen : 0f;
                result[k] = Vector3.Lerp(loop[seg], loop[(seg + 1) % loop.Count], Mathf.Clamp01(t));
            }
            return result;
        }
    }
}
