using System;
using System.IO;
using System.Linq;
using Gridline.EditorTools;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEngine;

/// <summary>
/// Headless build entry points (global namespace so they can be invoked as -executeMethod BuildScript.BuildAndroid).
/// A build only counts as successful when the APK/AAB exists on disk with a plausible size.
///
/// Recognised command-line arguments (all optional; the GameCI unity-builder passes these):
///   -customBuildPath &lt;file&gt;   output file (default Builds/Android/Gridline.apk or .aab)
///   -buildVersion &lt;x.y.z&gt;     bundle version (default env GRIDLINE_VERSION or 0.1.0)
///   -androidVersionCode &lt;n&gt;   version code (default env GITHUB_RUN_NUMBER or 1)
///   -androidKeystoreName &lt;path&gt; -androidKeystorePass &lt;pw&gt; -androidKeyaliasName &lt;alias&gt; -androidKeyaliasPass &lt;pw&gt;
/// Environment: GRIDLINE_DEV_BUILD=1 adds Development + profiler connection to the debug APK.
/// </summary>
public static class BuildScript
{
    const long MinimumArtifactBytes = 5L * 1024 * 1024;

    [MenuItem("GRIDLINE/Build/Android APK")]
    public static void BuildAndroid()
    {
        Run(false);
    }

    [MenuItem("GRIDLINE/Build/Android Release AAB")]
    public static void BuildAndroidRelease()
    {
        Run(true);
    }

    /// <summary>Configures the project and regenerates content without building a player (used by tests and CI warm-up).</summary>
    [MenuItem("GRIDLINE/Prepare Project")]
    public static void PrepareProject()
    {
        ProjectConfigurator.Apply();
        MaterialLibrary.UpgradeRvpMaterials();
        TrackBuilder.BuildAll();
        AssetDatabase.SaveAssets();
        AssetDatabase.Refresh();
    }

    /// <summary>-executeMethod entry for CI preparation that exits the editor with a status code.</summary>
    public static void PrepareProjectAndExit()
    {
        int code = 0;
        try { PrepareProject(); }
        catch (Exception e)
        {
            Debug.LogException(e);
            code = 1;
        }
        if (Application.isBatchMode) EditorApplication.Exit(code);
    }

    static void Run(bool release)
    {
        var started = DateTime.UtcNow;
        string output = Arg("-customBuildPath") ?? (release ? "Builds/Android/Gridline.aab" : "Builds/Android/Gridline.apk");
        bool aab = release || output.EndsWith(".aab", StringComparison.OrdinalIgnoreCase);
        if (aab && !output.EndsWith(".aab", StringComparison.OrdinalIgnoreCase)) output = Path.ChangeExtension(output, ".aab");
        if (!aab && !output.EndsWith(".apk", StringComparison.OrdinalIgnoreCase)) output = Path.ChangeExtension(output, ".apk");

        bool ok = false;
        string message;
        BuildReport report = null;
        try
        {
            if (EditorUserBuildSettings.activeBuildTarget != BuildTarget.Android)
                EditorUserBuildSettings.SwitchActiveBuildTarget(BuildTargetGroup.Android, BuildTarget.Android);

            PrepareProject();

            PlayerSettings.bundleVersion = Arg("-buildVersion") ?? Environment.GetEnvironmentVariable("GRIDLINE_VERSION") ?? "0.1.0";
            PlayerSettings.Android.bundleVersionCode = ParseInt(Arg("-androidVersionCode") ?? Environment.GetEnvironmentVariable("GITHUB_RUN_NUMBER"), 1);
            EditorUserBuildSettings.buildAppBundle = aab;
            if (!ConfigureSigning(release, out message)) throw new BuildFailedException(message);

            var options = new BuildPlayerOptions
            {
                scenes = EditorBuildSettings.scenes.Where(s => s.enabled).Select(s => s.path).ToArray(),
                locationPathName = output,
                target = BuildTarget.Android,
                targetGroup = BuildTargetGroup.Android,
                options = BuildOptions.None,
            };
            if (!release && Environment.GetEnvironmentVariable("GRIDLINE_DEV_BUILD") == "1")
                options.options |= BuildOptions.Development | BuildOptions.ConnectWithProfiler;
            if (options.scenes.Length == 0) throw new BuildFailedException("No scenes in build settings");

            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(output)));
            report = BuildPipeline.BuildPlayer(options);
            var info = new FileInfo(output);
            ok = report.summary.result == BuildResult.Succeeded && info.Exists && info.Length >= MinimumArtifactBytes;
            message = ok
                ? "Built " + output + " (" + (info.Length / 1048576.0).ToString("F1") + " MB)"
                : "Build result " + report.summary.result + ", artifact exists=" + info.Exists + (info.Exists ? ", bytes=" + info.Length : "");
        }
        catch (Exception e)
        {
            Debug.LogException(e);
            message = e.Message;
        }

        WriteReport(output, release, ok, message, report, started);
        Debug.Log((ok ? "[GRIDLINE_BUILD] SUCCESS " : "[GRIDLINE_BUILD] FAILURE ") + message);
        if (Application.isBatchMode) EditorApplication.Exit(ok ? 0 : 1);
    }

    static bool ConfigureSigning(bool release, out string message)
    {
        string keystore = Arg("-androidKeystoreName") ?? Environment.GetEnvironmentVariable("GRIDLINE_KEYSTORE_PATH");
        string storePass = Arg("-androidKeystorePass") ?? Environment.GetEnvironmentVariable("GRIDLINE_KEYSTORE_PASS");
        string alias = Arg("-androidKeyaliasName") ?? Environment.GetEnvironmentVariable("GRIDLINE_KEYALIAS_NAME");
        string aliasPass = Arg("-androidKeyaliasPass") ?? Environment.GetEnvironmentVariable("GRIDLINE_KEYALIAS_PASS");
        bool hasKeystore = !string.IsNullOrEmpty(keystore) && File.Exists(keystore) && !string.IsNullOrEmpty(alias);
        if (hasKeystore)
        {
            PlayerSettings.Android.useCustomKeystore = true;
            PlayerSettings.Android.keystoreName = Path.GetFullPath(keystore);
            PlayerSettings.Android.keystorePass = storePass;
            PlayerSettings.Android.keyaliasName = alias;
            PlayerSettings.Android.keyaliasPass = aliasPass;
            message = "Signing with upload keystore";
            return true;
        }
        PlayerSettings.Android.useCustomKeystore = false;
        if (release)
        {
            message = "Release build requires a keystore (androidKeystoreName/GRIDLINE_KEYSTORE_PATH + alias). Refusing to ship a debug-signed AAB.";
            return false;
        }
        message = "Signing with the Unity debug keystore (side-load/testing only)";
        return true;
    }

    static void WriteReport(string output, bool release, bool ok, string message, BuildReport report, DateTime started)
    {
        try
        {
            string dir = Path.GetDirectoryName(Path.GetFullPath(output));
            Directory.CreateDirectory(dir);
            var info = new FileInfo(output);
            var json = new BuildRecord
            {
                success = ok,
                message = message,
                release = release,
                artifact = output,
                artifactBytes = info.Exists ? info.Length : 0,
                unityVersion = Application.unityVersion,
                bundleVersion = PlayerSettings.bundleVersion,
                versionCode = PlayerSettings.Android.bundleVersionCode,
                commit = Environment.GetEnvironmentVariable("GITHUB_SHA") ?? "",
                startedUtc = started.ToString("o"),
                durationSeconds = (DateTime.UtcNow - started).TotalSeconds,
                result = report != null ? report.summary.result.ToString() : "NotRun",
                totalErrors = report != null ? report.summary.totalErrors : -1,
                totalWarnings = report != null ? report.summary.totalWarnings : -1,
            };
            File.WriteAllText(Path.Combine(dir, release ? "build_report_release.json" : "build_report.json"), JsonUtility.ToJson(json, true));
        }
        catch (Exception e)
        {
            Debug.LogWarning("[GRIDLINE_BUILD] Could not write build report: " + e.Message);
        }
    }

    [Serializable]
    class BuildRecord
    {
        public bool success;
        public string message;
        public bool release;
        public string artifact;
        public long artifactBytes;
        public string unityVersion;
        public string bundleVersion;
        public int versionCode;
        public string commit;
        public string startedUtc;
        public double durationSeconds;
        public string result;
        public int totalErrors;
        public int totalWarnings;
    }

    static string Arg(string name)
    {
        var args = Environment.GetCommandLineArgs();
        for (int i = 0; i < args.Length - 1; i++)
            if (args[i] == name && !string.IsNullOrEmpty(args[i + 1]) && !args[i + 1].StartsWith("-")) return args[i + 1];
        return null;
    }

    static int ParseInt(string s, int fallback)
    {
        return int.TryParse(s, out int v) && v > 0 ? v : fallback;
    }
}
