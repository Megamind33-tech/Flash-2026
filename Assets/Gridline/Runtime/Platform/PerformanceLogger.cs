using System.Collections.Generic;
using System.IO;
using System.Text;
using Unity.Profiling;
using UnityEngine;
using UnityEngine.Profiling;

namespace Gridline.Platform
{
    /// <summary>
    /// Lightweight in-game performance capture. Samples every frame, writes a per-second CSV to
    /// persistentDataPath/perf/ and logs a summary line tagged GRIDLINE_PERF (visible in adb logcat).
    /// Render counters are only available in development builds; they are recorded as -1 otherwise.
    /// </summary>
    public class PerformanceLogger : MonoBehaviour
    {
        public string sessionLabel = "race";
        public bool writeCsv = true;

        readonly List<float> frameMs = new List<float>(4096);
        readonly StringBuilder csv = new StringBuilder();
        readonly FrameTiming[] timings = new FrameTiming[1];
        ProfilerRecorder drawCalls, triangles, physicsMs;
        float windowTime;
        int windowFrames;
        float windowWorstMs;
        float startTime;

        public float CurrentFps { get; private set; }

        void OnEnable()
        {
            drawCalls = ProfilerRecorder.StartNew(ProfilerCategory.Render, "Draw Calls Count");
            triangles = ProfilerRecorder.StartNew(ProfilerCategory.Render, "Triangles Count");
            physicsMs = ProfilerRecorder.StartNew(ProfilerCategory.Physics, "Physics.Simulate");
            csv.AppendLine("t_s,fps,avg_frame_ms,worst_frame_ms,cpu_main_ms,gpu_ms,draw_calls,triangles,physics_ms,mono_mb,total_alloc_mb,quality");
            startTime = Time.realtimeSinceStartup;
        }

        void OnDisable()
        {
            drawCalls.Dispose();
            triangles.Dispose();
            physicsMs.Dispose();
        }

        void Update()
        {
            float dt = Time.unscaledDeltaTime * 1000f;
            frameMs.Add(dt);
            windowTime += Time.unscaledDeltaTime;
            windowFrames++;
            windowWorstMs = Mathf.Max(windowWorstMs, dt);
            FrameTimingManager.CaptureFrameTimings();
            if (windowTime < 1f) return;

            CurrentFps = windowFrames / windowTime;
            double cpu = -1, gpu = -1;
            if (FrameTimingManager.GetLatestTimings(1, timings) > 0)
            {
                cpu = timings[0].cpuMainThreadFrameTime;
                gpu = timings[0].gpuFrameTime;
            }
            csv.AppendFormat(System.Globalization.CultureInfo.InvariantCulture,
                "{0:F1},{1:F1},{2:F2},{3:F2},{4:F2},{5:F2},{6},{7},{8:F2},{9:F1},{10:F1},{11}\n",
                Time.realtimeSinceStartup - startTime, CurrentFps, windowTime * 1000f / windowFrames, windowWorstMs, cpu, gpu,
                drawCalls.Valid ? drawCalls.LastValue : -1, triangles.Valid ? triangles.LastValue : -1,
                physicsMs.Valid ? physicsMs.LastValue * 1e-6 : -1,
                Profiler.GetMonoUsedSizeLong() / 1048576f, Profiler.GetTotalAllocatedMemoryLong() / 1048576f, QualitySettings.GetQualityLevel());
            windowTime = 0f;
            windowFrames = 0;
            windowWorstMs = 0f;
        }

        public string Summary()
        {
            if (frameMs.Count == 0) return "no frames";
            var sorted = new List<float>(frameMs);
            sorted.Sort();
            float sum = 0f;
            foreach (var f in frameMs) sum += f;
            float avg = sum / frameMs.Count;
            float p99 = sorted[Mathf.Clamp(Mathf.FloorToInt(sorted.Count * 0.99f), 0, sorted.Count - 1)];
            return string.Format(System.Globalization.CultureInfo.InvariantCulture,
                "frames={0} avg_fps={1:F1} avg_ms={2:F2} p99_ms={3:F2} 1%low_fps={4:F1} device={5} gpu={6} quality={7}",
                frameMs.Count, 1000f / avg, avg, p99, 1000f / p99, SystemInfo.deviceModel, SystemInfo.graphicsDeviceName, QualitySettings.GetQualityLevel());
        }

        /// <summary>Writes the CSV and logs the summary. Returns the CSV path, or null when nothing was written.</summary>
        public string Flush()
        {
            Debug.Log("[GRIDLINE_PERF] " + sessionLabel + " " + Summary());
            if (!writeCsv || frameMs.Count == 0) return null;
            try
            {
                string dir = Path.Combine(Application.persistentDataPath, "perf");
                Directory.CreateDirectory(dir);
                string path = Path.Combine(dir, sessionLabel + "_" + System.DateTime.UtcNow.ToString("yyyyMMdd_HHmmss") + ".csv");
                File.WriteAllText(path, csv.ToString());
                Debug.Log("[GRIDLINE_PERF] csv=" + path);
                return path;
            }
            catch (System.Exception e)
            {
                Debug.LogWarning("[GRIDLINE_PERF] csv write failed: " + e.Message);
                return null;
            }
        }
    }
}
