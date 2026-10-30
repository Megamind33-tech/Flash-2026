using System.Collections.Generic;
using System.Linq;
using Gridline.Core;
using NUnit.Framework;

namespace Gridline.Tests
{
    public class LapTrackerTests
    {
        const float L = 1000f;

        static void Drive(LapTracker t, float from, float to, double t0, double t1, int steps = 400)
        {
            for (int i = 1; i <= steps; i++)
            {
                float u = i / (float)steps;
                t.Update(from + (to - from) * u, t0 + (t1 - t0) * u);
            }
        }

        [Test]
        public void GridSlotBehindLineStartsWithNegativeProgress()
        {
            var t = new LapTracker(L, 3);
            t.Initialise(L - 24f);
            Assert.AreEqual(-24f, t.Progress, 1e-3);
            Assert.AreEqual(1, t.CurrentLap);
        }

        [Test]
        public void CountsThreeLapsAndFinishes()
        {
            var t = new LapTracker(L, 3);
            var laps = new List<int>();
            t.LapCompleted += (lap, ms) => laps.Add(ms);
            t.Initialise(L - 10f);
            t.StartClock(0);
            // Each lap 60 s. Distances fed raw in 0..L, wrapping like a real projection.
            double time = 0;
            float pos = -10f;
            for (int lap = 0; lap < 3; lap++)
            {
                float target = pos + L;
                for (int i = 1; i <= 500; i++)
                {
                    float p = pos + (target - pos) * i / 500f;
                    time += 60.0 / 500.0;
                    t.Update(((p % L) + L) % L, time);
                }
                pos = target;
            }
            // Not finished yet: the car started 10 m behind the line.
            Assert.IsFalse(t.Finished);
            Drive(t, pos, pos + 20f, time, time + 1);
            Assert.IsTrue(t.Finished);
            Assert.AreEqual(3, t.LapsCompleted);
            Assert.AreEqual(3, laps.Count);
            Assert.AreEqual(9, t.SectorTimesMs.Count);
            Assert.Greater(t.BestLapMs, 0);
        }

        [Test]
        public void ReversingAcrossTheLineDoesNotDoubleCountLaps()
        {
            var t = new LapTracker(L, 5);
            t.Initialise(L - 5f);
            t.StartClock(0);
            Drive(t, -5f, L + 5f, 0, 60);
            Assert.AreEqual(1, t.LapsCompleted);
            Drive(t, L + 5f, L - 20f, 60, 70); // back over the line
            Drive(t, L - 20f, L + 30f, 70, 80); // and forward again
            Assert.AreEqual(1, t.LapsCompleted);
        }

        [Test]
        public void LargeJumpIsRejectedAsCut()
        {
            var t = new LapTracker(L, 3);
            t.Initialise(0f);
            t.StartClock(0);
            t.Update(10f, 0.5);
            t.Update(400f, 0.6); // 390 m in 0.1 s: shortcut / teleport
            Assert.AreEqual(10f, t.Progress, 1e-3);
            Assert.AreEqual(1, t.RejectedSteps);
        }

        [Test]
        public void SectorEventsFireInOrder()
        {
            var t = new LapTracker(L, 1, 3);
            var sectors = new List<int>();
            t.SectorCompleted += (s, ms) => sectors.Add(s);
            t.Initialise(L - 1f);
            t.StartClock(0);
            Drive(t, -1f, L + 1f, 0, 30);
            CollectionAssert.AreEqual(new[] { 0, 1, 2 }, sectors);
            Assert.IsTrue(t.Finished);
        }
    }

    public class ClassificationTests
    {
        [Test]
        public void FinishersAheadOfRunnersAndPenaltiesApplied()
        {
            var racers = new[]
            {
                new RacerSnapshot { id = "a", finished = true, finishTime = 180, penaltySeconds = 5, gridSlot = 0 },
                new RacerSnapshot { id = "b", finished = true, finishTime = 183, gridSlot = 1 },
                new RacerSnapshot { id = "c", finished = false, progress = 2950, gridSlot = 2 },
                new RacerSnapshot { id = "d", finished = false, progress = 2990, gridSlot = 3 },
            };
            var order = RaceClassification.Classify(racers).Select(r => r.id).ToArray();
            CollectionAssert.AreEqual(new[] { "b", "a", "d", "c" }, order);
        }

        [Test]
        public void FastestLapHolderIgnoresZeroLaps()
        {
            var racers = new[]
            {
                new RacerSnapshot { id = "a", bestLapMs = 0 },
                new RacerSnapshot { id = "b", bestLapMs = 61000 },
                new RacerSnapshot { id = "c", bestLapMs = 60500 },
            };
            Assert.AreEqual("c", RaceClassification.FastestLapHolder(racers));
        }

        [Test]
        public void FormatsLapTimes()
        {
            Assert.AreEqual("1:01.234", RaceClassification.FormatTime(61234));
            Assert.AreEqual("--:--.---", RaceClassification.FormatTime(0));
        }
    }

    public class CareerTests
    {
        [Test]
        public void NewCareerStartsWithLedgeredSavings()
        {
            var cfg = EconomyConfig.Default();
            var c = CareerService.NewCareer(cfg, "Test");
            Assert.AreEqual(cfg.startingMoney, c.money);
            Assert.AreEqual(1, c.ledger.Count);
            Assert.IsFalse(string.IsNullOrEmpty(c.ledger[0].reason));
        }

        [Test]
        public void EntryFeeThenPrizeMoney()
        {
            var cfg = EconomyConfig.Default();
            var c = CareerService.NewCareer(cfg, "Test");
            var receipt = CareerService.EnterRace(c, cfg, "Club Sprint");
            Assert.IsTrue(receipt.accepted);
            Assert.AreEqual(cfg.startingMoney - cfg.amateurEntryFee, c.money);
            var reward = CareerService.ApplyResult(c, cfg, "Club Sprint", "ashford", 2, 5, 72000, false);
            Assert.AreEqual(cfg.prizeByPosition[1], reward.prizeMoney);
            Assert.AreEqual(cfg.startingMoney - cfg.amateurEntryFee + cfg.prizeByPosition[1], c.money);
            Assert.AreEqual(18, c.championshipPoints);
            Assert.AreEqual(1, c.podiums);
            Assert.AreEqual(0, c.wins);
            Assert.IsTrue(reward.newTrackRecord);
            Assert.AreEqual(72000, c.GetBestLap("ashford"));
        }

        [Test]
        public void BrokePlayerIsSponsoredInsteadOfSoftLocked()
        {
            var cfg = EconomyConfig.Default();
            var c = CareerService.NewCareer(cfg, "Test");
            c.Post(-c.money, "Test", "Drain for test");
            var receipt = CareerService.EnterRace(c, cfg, "Club Sprint");
            Assert.IsTrue(receipt.accepted);
            Assert.IsTrue(receipt.sponsorCovered);
            Assert.AreEqual(0, c.money);
        }

        [Test]
        public void SlowerLapIsNotARecord()
        {
            var c = new CareerState();
            Assert.IsTrue(c.SubmitLap("t", 70000));
            Assert.IsFalse(c.SubmitLap("t", 71000));
            Assert.IsTrue(c.SubmitLap("t", 69000));
            Assert.AreEqual(69000, c.GetBestLap("t"));
        }

        [Test]
        public void EveryTransactionNeedsAReason()
        {
            var c = new CareerState();
            Assert.Throws<System.ArgumentException>(() => c.Post(100, "X", ""));
        }

        [Test]
        public void FastestLapBonusAndReputation()
        {
            var cfg = EconomyConfig.Default();
            var c = CareerService.NewCareer(cfg, "Test");
            var reward = CareerService.ApplyResult(c, cfg, "E", "t", 1, 5, 60000, true);
            Assert.AreEqual(cfg.fastestLapBonus, reward.fastestLapBonus);
            Assert.AreEqual(cfg.reputationByPosition[0] + cfg.reputationForFastestLap, c.reputation);
            Assert.AreEqual(1, c.wins);
        }
    }

    public class LeagueDataTests
    {
        [Test]
        public void DefaultRosterHasFourDistinctAiDrivers()
        {
            var drivers = DefaultLeague.Drivers();
            Assert.AreEqual(4, drivers.Count);
            Assert.AreEqual(4, drivers.Select(d => d.id).Distinct().Count());
            foreach (var d in drivers)
            {
                Assert.That(d.PaceFactor, Is.InRange(0.84f, 1.01f));
                Assert.That(d.PaceNoise, Is.InRange(0f, 0.05f));
            }
        }

        [Test]
        public void DriverStatsAccumulate()
        {
            var d = DefaultLeague.Drivers()[0];
            d.RecordResult(3);
            d.RecordResult(1);
            Assert.AreEqual(2, d.stats.starts);
            Assert.AreEqual(1, d.stats.wins);
            Assert.AreEqual(2, d.stats.podiums);
            Assert.AreEqual(40, d.stats.points);
            Assert.AreEqual(1, d.stats.bestFinish);
        }

        [Test]
        public void DeterministicRandomIsReproducible()
        {
            var a = new DeterministicRandom(42);
            var b = new DeterministicRandom(42);
            for (int i = 0; i < 100; i++) Assert.AreEqual(a.NextUInt(), b.NextUInt());
            var r = new DeterministicRandom(7);
            for (int i = 0; i < 1000; i++) Assert.That(r.NextDouble(), Is.InRange(0.0, 1.0));
        }

        [Test]
        public void SaveValidationRepairsNullsAndRejectsFutureVersions()
        {
            var cfg = EconomyConfig.Default();
            var s = SaveGame.CreateNew(cfg, "P");
            s.history = null;
            s.settings = null;
            s.aiDrivers = null;
            Assert.IsTrue(s.Validate(cfg));
            Assert.IsNotNull(s.history);
            Assert.IsNotNull(s.settings);
            Assert.AreEqual(4, s.aiDrivers.Count);
            s.version = SaveGame.CurrentVersion + 1;
            Assert.IsFalse(s.Validate(cfg));
        }

        [Test]
        public void SettingsSanitiseClampsBadValues()
        {
            var g = new GameSettings { steeringSensitivity = 9f, qualityLevel = 7, masterVolume = -1f };
            g.Sanitise();
            Assert.AreEqual(1f, g.steeringSensitivity);
            Assert.AreEqual(1, g.qualityLevel);
            Assert.AreEqual(0.8f, g.masterVolume);
        }
    }
}
