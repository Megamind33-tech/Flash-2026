using System;
using System.Collections.Generic;

namespace Gridline.Core
{
    [Serializable]
    public class RacerSnapshot
    {
        public string id;
        public string displayName;
        public bool isPlayer;
        public bool finished;
        public double finishTime;      // race clock seconds, before penalties
        public float penaltySeconds;
        public float progress;         // metres from the start line, continuous across laps
        public int lapsCompleted;
        public int bestLapMs;
        public int gridSlot;

        public double ClassifiedTime { get { return finishTime + penaltySeconds; } }
    }

    public static class RaceClassification
    {
        /// <summary>
        /// Orders competitors: finishers by time including penalties, then running cars by progress, ties broken by grid slot.
        /// Returns a new list; the input is untouched.
        /// </summary>
        public static List<RacerSnapshot> Classify(IEnumerable<RacerSnapshot> racers)
        {
            var list = new List<RacerSnapshot>(racers);
            list.Sort(Compare);
            return list;
        }

        public static int Compare(RacerSnapshot a, RacerSnapshot b)
        {
            if (a.finished != b.finished) return a.finished ? -1 : 1;
            int c = a.finished ? a.ClassifiedTime.CompareTo(b.ClassifiedTime) : b.progress.CompareTo(a.progress);
            return c != 0 ? c : a.gridSlot.CompareTo(b.gridSlot);
        }

        /// <summary>Id of the competitor with the quickest single lap, or null.</summary>
        public static string FastestLapHolder(IEnumerable<RacerSnapshot> racers)
        {
            string id = null;
            int best = int.MaxValue;
            foreach (var r in racers)
            {
                if (r.bestLapMs > 0 && r.bestLapMs < best)
                {
                    best = r.bestLapMs;
                    id = r.id;
                }
            }
            return id;
        }

        public static string FormatTime(int ms)
        {
            if (ms <= 0) return "--:--.---";
            int minutes = ms / 60000;
            int seconds = ms / 1000 % 60;
            return minutes + ":" + seconds.ToString("00") + "." + (ms % 1000).ToString("000");
        }
    }
}
