using System.IO;
using Gridline.Core;
using Gridline.Platform;
using Gridline.Track;
using NUnit.Framework;
using UnityEngine;

namespace Gridline.Tests
{
    public class TrackPathTests
    {
        TrackPath track;

        [SetUp]
        public void SetUp()
        {
            track = new GameObject("Track").AddComponent<TrackPath>();
            track.points = CircuitLayout.BuildCentreline(CircuitLayout.AshfordControlPoints, 2f);
            track.Rebuild();
        }

        [TearDown]
        public void TearDown()
        {
            Object.DestroyImmediate(track.gameObject);
        }

        [Test]
        public void AshfordLengthIsAsDesigned()
        {
            Assert.That(track.Length, Is.InRange(2300f, 2420f));
        }

        [Test]
        public void ProjectionRoundTripsDistance()
        {
            int hint = -1;
            for (float d = 0f; d < track.Length; d += 37f)
            {
                Vector3 p = track.PositionAt(d) + track.RightAt(d) * 2f;
                float back = track.Project(p, ref hint, out float lateral);
                float err = Mathf.Abs(Mathf.DeltaAngle(back / track.Length * 360f, d / track.Length * 360f)) / 360f * track.Length;
                Assert.Less(err, 1.0f, "distance at d=" + d);
                Assert.AreEqual(2f, lateral, 0.2f, "lateral at d=" + d);
            }
        }

        [Test]
        public void SpeedProfileIsSane()
        {
            float min = float.MaxValue, max = 0f;
            for (float d = 0f; d < track.Length; d += 2f)
            {
                float v = track.TargetSpeedAt(d);
                min = Mathf.Min(min, v);
                max = Mathf.Max(max, v);
            }
            Assert.Greater(min, 9f, "slowest corner");
            Assert.LessOrEqual(max, track.maxSpeed + 0.01f);
            Assert.Greater(max, 40f, "main straight should allow high speed");
        }

        [Test]
        public void RacingLineStaysOnTarmac()
        {
            for (float d = 0f; d < track.Length; d += 3f)
                Assert.LessOrEqual(Mathf.Abs(track.RacingLineOffsetAt(d)), track.halfWidth, "d=" + d);
        }

        [Test]
        public void StartStraightRunsAlongPositiveX()
        {
            Vector3 t = track.TangentAt(10f);
            Assert.Greater(t.x, 0.99f);
        }
    }

    public class SaveSystemTests
    {
        string dir;

        [SetUp]
        public void SetUp()
        {
            dir = Path.Combine(Path.GetTempPath(), "gridline-save-" + System.Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(dir);
            SaveSystem.Directory = dir;
        }

        [TearDown]
        public void TearDown()
        {
            SaveSystem.Directory = null;
            GameServices.ClearCache();
            if (Directory.Exists(dir)) Directory.Delete(dir, true);
        }

        [Test]
        public void RoundTripPreservesCareerAndRoster()
        {
            var cfg = EconomyConfig.Default();
            var save = SaveGame.CreateNew(cfg, "Tester");
            CareerService.EnterRace(save.career, cfg, "Test Event");
            CareerService.ApplyResult(save.career, cfg, "Test Event", "ashford", 1, 5, 75000, true);
            save.aiDrivers[0].RecordResult(2);
            save.settings.steeringMode = SteeringMode.Tilt;
            SaveSystem.Write(save);

            var loaded = SaveSystem.LoadOrCreate(cfg, out string source);
            Assert.AreEqual(SaveSystem.MainPath, source);
            Assert.AreEqual(save.career.money, loaded.career.money);
            Assert.AreEqual(1, loaded.career.wins);
            Assert.AreEqual(75000, loaded.career.GetBestLap("ashford"));
            Assert.AreEqual(save.career.ledger.Count, loaded.career.ledger.Count);
            Assert.AreEqual(1, loaded.aiDrivers[0].stats.starts);
            Assert.AreEqual(SteeringMode.Tilt, loaded.settings.steeringMode);
        }

        [Test]
        public void CorruptMainSaveFallsBackToBackup()
        {
            var cfg = EconomyConfig.Default();
            var first = SaveGame.CreateNew(cfg, "Backup");
            SaveSystem.Write(first);
            var second = SaveGame.CreateNew(cfg, "Main");
            SaveSystem.Write(second); // first is now the backup
            File.WriteAllText(SaveSystem.MainPath, "{ not json");
            var loaded = SaveSystem.LoadOrCreate(cfg, out string source);
            Assert.AreEqual(SaveSystem.BackupPath, source);
            Assert.AreEqual("Backup", loaded.career.driverName);
        }

        [Test]
        public void MissingSaveCreatesFreshCareer()
        {
            var loaded = SaveSystem.LoadOrCreate(EconomyConfig.Default(), out string source);
            Assert.AreEqual("new", source);
            Assert.AreEqual(EconomyConfig.Default().startingMoney, loaded.career.money);
        }
    }
}
