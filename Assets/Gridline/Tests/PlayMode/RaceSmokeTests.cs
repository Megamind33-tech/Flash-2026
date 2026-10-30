using System.Collections;
using System.IO;
using Gridline.Core;
using Gridline.Platform;
using Gridline.Race;
using NUnit.Framework;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.TestTools;
using UnityEngine.UIElements;

namespace Gridline.Tests
{
    /// <summary>Regenerates project content in the editor before play mode starts.</summary>
    public class PrepareGridlineProject : IPrebuildSetup
    {
        public void Setup()
        {
#if UNITY_EDITOR
            var type = System.Type.GetType("BuildScript, Gridline.Editor");
            if (type == null) throw new System.InvalidOperationException("BuildScript not found in Gridline.Editor");
            type.GetMethod("PrepareProject").Invoke(null, null);
#endif
        }
    }

    [PrebuildSetup(typeof(PrepareGridlineProject))]
    public class RaceSmokeTests
    {
        const string RaceScenePath = "Assets/Gridline/Scenes/Race.unity";
        const string MenuScenePath = "Assets/Gridline/Scenes/Menu.unity";
        string saveDir;

        [SetUp]
        public void SetUp()
        {
            saveDir = Path.Combine(Application.temporaryCachePath, "gridline-playmode-" + System.Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(saveDir);
            SaveSystem.Directory = saveDir;
            GameServices.ClearCache();
        }

        [TearDown]
        public void TearDown()
        {
            Time.timeScale = 1f;
            RaceSession.Laps = 3;
            RaceSession.AutopilotPlayer = false;
            RaceSession.AffectsCareer = true;
            RaceSession.EntryPaid = false;
            SaveSystem.Directory = null;
            GameServices.ClearCache();
            if (Directory.Exists(saveDir)) Directory.Delete(saveDir, true);
        }

        static IEnumerator Load(string path)
        {
#if UNITY_EDITOR
            var op = UnityEditor.SceneManagement.EditorSceneManager.LoadSceneAsyncInPlayMode(path, new LoadSceneParameters(LoadSceneMode.Single));
#else
            var op = SceneManager.LoadSceneAsync(Path.GetFileNameWithoutExtension(path));
#endif
            while (!op.isDone) yield return null;
        }

        [UnityTest, Timeout(900000)]
        public IEnumerator AiFieldCompletesOneLapRaceAndClassifies()
        {
            RaceSession.ResetForTests(1);
            yield return Load(RaceScenePath);
            var director = Object.FindAnyObjectByType<RaceDirector>();
            Assert.IsNotNull(director, "RaceDirector missing from race scene");
            Time.timeScale = 3f;

            float start = Time.realtimeSinceStartup;
            while (director.Phase != RacePhase.Results && Time.realtimeSinceStartup - start < 600f) yield return null;
            Time.timeScale = 1f;

            foreach (var car in director.Cars)
                Debug.Log("[GRIDLINE_TEST] " + car.displayName + " P" + car.Position + " progress=" + car.Laps.Progress.ToString("F0") +
                          " laps=" + car.Laps.LapsCompleted + " best=" + RaceClassification.FormatTime(car.Laps.BestLapMs) +
                          " recoveries=" + car.Recoveries + " rejected=" + car.Laps.RejectedSteps + " penalty=" + car.PenaltySeconds);
            Debug.Log("[GRIDLINE_TEST] race_time_s=" + director.RaceTime.ToString("F1") + " real_s=" + (Time.realtimeSinceStartup - start).ToString("F0"));

            Assert.AreEqual(RacePhase.Results, director.Phase, "Race did not reach results within the time limit");
            Assert.AreEqual(5, director.Cars.Count, "Expected the player plus four AI opponents");
            Assert.IsTrue(director.Player.Laps.Finished, "Autopilot player did not finish");
            int finishers = 0;
            foreach (var car in director.Cars)
            {
                if (car.Laps.Finished) finishers++;
                Assert.Greater(car.Laps.Progress, director.track.Length * 0.5f, car.displayName + " made too little progress");
            }
            Assert.GreaterOrEqual(finishers, 3, "Most of the field should finish a lap");
            Assert.AreEqual(director.Cars.Count, director.Standings.Count);
        }

        [UnityTest, Timeout(120000)]
        public IEnumerator MenuSceneLoadsAndBuildsUi()
        {
            yield return Load(MenuScenePath);
            yield return null;
            yield return null;
            var menu = Object.FindAnyObjectByType<Gridline.UI.MainMenuController>();
            Assert.IsNotNull(menu, "MainMenuController missing");
            var root = menu.GetComponent<UIDocument>().rootVisualElement;
            Assert.IsNotNull(root.Q("race-button"), "Menu UI was not built");
            var name = root.Q<Label>("driver-name");
            Assert.IsNotNull(name);
            Assert.IsFalse(string.IsNullOrEmpty(name.text), "Career card was not populated");
        }

        [UnityTest, Timeout(300000)]
        public IEnumerator CareerRaceChargesEntryAndPaysPrize()
        {
            RaceSession.ResetForTests(1);
            RaceSession.AffectsCareer = true;
            RaceSession.EntryPaid = false;
            int before = GameServices.Save.career.money;
            yield return Load(RaceScenePath);
            var director = Object.FindAnyObjectByType<RaceDirector>();
            Time.timeScale = 3f;
            float start = Time.realtimeSinceStartup;
            while (director.Phase != RacePhase.Results && Time.realtimeSinceStartup - start < 240f) yield return null;
            Time.timeScale = 1f;
            Assert.AreEqual(RacePhase.Results, director.Phase);
            Assert.IsNotNull(director.Entry);
            Assert.IsNotNull(director.Reward);
            int expected = before - director.Entry.feeCharged + director.Reward.TotalMoney;
            Assert.AreEqual(expected, GameServices.Save.career.money);
            Assert.IsTrue(File.Exists(SaveSystem.MainPath), "Result was not persisted");
        }
    }
}
