using System;
using System.IO;
using Gridline.Core;
using UnityEngine;

namespace Gridline.Platform
{
    /// <summary>JSON save with atomic replace and a single backup generation.</summary>
    public static class SaveSystem
    {
        public const string FileName = "gridline_save.json";

        /// <summary>Overridable for tests.</summary>
        public static string Directory = null;

        public static string PathFor(string file)
        {
            return Path.Combine(Directory ?? Application.persistentDataPath, file);
        }

        public static string MainPath { get { return PathFor(FileName); } }
        public static string BackupPath { get { return PathFor(FileName + ".bak"); } }

        public static void Write(SaveGame save)
        {
            string json = JsonUtility.ToJson(save, true);
            string main = MainPath;
            string tmp = main + ".tmp";
            System.IO.Directory.CreateDirectory(Path.GetDirectoryName(main));
            File.WriteAllText(tmp, json);
            if (File.Exists(main))
            {
                File.Copy(main, BackupPath, true);
                File.Delete(main);
            }
            File.Move(tmp, main);
        }

        /// <summary>Loads the save, falling back to the backup, then to a fresh career. Never throws.</summary>
        public static SaveGame LoadOrCreate(EconomyConfig cfg, out string source)
        {
            foreach (var path in new[] { MainPath, BackupPath })
            {
                try
                {
                    if (!File.Exists(path)) continue;
                    var save = JsonUtility.FromJson<SaveGame>(File.ReadAllText(path));
                    if (save != null && save.Validate(cfg))
                    {
                        source = path;
                        return save;
                    }
                    Debug.LogWarning("[GRIDLINE] Save at " + path + " failed validation");
                }
                catch (Exception e)
                {
                    Debug.LogWarning("[GRIDLINE] Could not read save " + path + ": " + e.Message);
                }
            }
            source = "new";
            return SaveGame.CreateNew(cfg, "Rookie");
        }

        public static void DeleteAll()
        {
            foreach (var p in new[] { MainPath, BackupPath })
                if (File.Exists(p)) File.Delete(p);
        }
    }
}
