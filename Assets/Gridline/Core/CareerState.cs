using System;
using System.Collections.Generic;

namespace Gridline.Core
{
    /// <summary>A single money movement. Every transaction must carry a reason.</summary>
    [Serializable]
    public class LedgerEntry
    {
        public int amount;
        public string reason;
        public string category;
        public int balanceAfter;
        public int raceIndex;
    }

    [Serializable]
    public class TrackRecord
    {
        public string trackId;
        public int bestLapMs;
    }

    /// <summary>The player's persistent driver career.</summary>
    [Serializable]
    public class CareerState
    {
        public string driverName = "Rookie";
        public int money;
        public int reputation;
        public int racesEntered;
        public int wins;
        public int podiums;
        public int championshipPoints;
        public List<LedgerEntry> ledger = new List<LedgerEntry>();
        public List<TrackRecord> trackRecords = new List<TrackRecord>();

        /// <summary>Keeps the save small; older entries are summarised by the balance on the remaining ones.</summary>
        public const int MaxLedgerEntries = 200;

        public int GetBestLap(string trackId)
        {
            foreach (var r in trackRecords)
                if (r.trackId == trackId) return r.bestLapMs;
            return 0;
        }

        /// <summary>Returns true when the lap is a new personal record for the track.</summary>
        public bool SubmitLap(string trackId, int lapMs)
        {
            if (lapMs <= 0) return false;
            foreach (var r in trackRecords)
            {
                if (r.trackId != trackId) continue;
                if (r.bestLapMs > 0 && r.bestLapMs <= lapMs) return false;
                r.bestLapMs = lapMs;
                return true;
            }
            trackRecords.Add(new TrackRecord { trackId = trackId, bestLapMs = lapMs });
            return true;
        }

        public void Post(int amount, string category, string reason)
        {
            if (string.IsNullOrEmpty(reason)) throw new ArgumentException("Every transaction needs a reason", nameof(reason));
            money += amount;
            ledger.Add(new LedgerEntry { amount = amount, category = category, reason = reason, balanceAfter = money, raceIndex = racesEntered });
            if (ledger.Count > MaxLedgerEntries) ledger.RemoveRange(0, ledger.Count - MaxLedgerEntries);
        }
    }
}
