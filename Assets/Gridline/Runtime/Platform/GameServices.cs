using Gridline.Core;
using UnityEngine;

namespace Gridline.Platform
{
    /// <summary>Process-wide access to the save, settings and balancing data. Lazily loaded; safe to call from any scene.</summary>
    public static class GameServices
    {
        static SaveGame save;
        static EconomyConfig economy;

        public static EconomyConfig Economy
        {
            get
            {
                if (economy == null)
                {
                    economy = EconomyConfig.Default();
                    var asset = Resources.Load<TextAsset>("gridline_economy");
                    if (asset != null)
                    {
                        try { JsonUtility.FromJsonOverwrite(asset.text, economy); }
                        catch (System.Exception e) { Debug.LogWarning("[GRIDLINE] Bad economy config, using defaults: " + e.Message); }
                    }
                }
                return economy;
            }
        }

        public static SaveGame Save
        {
            get
            {
                if (save == null)
                {
                    save = SaveSystem.LoadOrCreate(Economy, out string source);
                    Debug.Log("[GRIDLINE] Save loaded from " + source + " money=" + save.career.money);
                }
                return save;
            }
        }

        public static GameSettings Settings { get { return Save.settings; } }

        public static void Persist()
        {
            try { SaveSystem.Write(Save); }
            catch (System.Exception e) { Debug.LogError("[GRIDLINE] Save failed: " + e); }
        }

        public static void ResetCareer()
        {
            var settings = Save.settings;
            save = SaveGame.CreateNew(Economy, "Rookie");
            save.settings = settings;
            Persist();
        }

        /// <summary>Drops cached state so the next access reloads from disk. Used by tests.</summary>
        public static void ClearCache()
        {
            save = null;
            economy = null;
        }

        public static void ApplySettings()
        {
            var s = Settings;
            s.Sanitise();
            if (QualitySettings.names.Length > s.qualityLevel) QualitySettings.SetQualityLevel(s.qualityLevel, true);
            Application.targetFrameRate = s.qualityLevel == 0 ? 30 : 60;
            AudioListener.volume = s.masterVolume;
            Screen.sleepTimeout = SleepTimeout.NeverSleep;
        }
    }
}
