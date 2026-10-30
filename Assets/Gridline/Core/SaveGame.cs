using System;
using System.Collections.Generic;

namespace Gridline.Core
{
    [Serializable]
    public class RaceHistoryEntry
    {
        public int raceIndex;
        public string trackId;
        public int position;
        public int fieldSize;
        public int bestLapMs;
        public int moneyEarned;
    }

    /// <summary>Root of the persistent save. Bump CurrentVersion and extend Migrate when the schema changes.</summary>
    [Serializable]
    public class SaveGame
    {
        public const int CurrentVersion = 1;
        public const int MaxHistory = 50;

        public int version = CurrentVersion;
        public CareerState career = new CareerState();
        public GameSettings settings = new GameSettings();
        public List<DriverProfile> aiDrivers = new List<DriverProfile>();
        public List<TeamProfile> teams = new List<TeamProfile>();
        public List<RaceHistoryEntry> history = new List<RaceHistoryEntry>();

        public static SaveGame CreateNew(EconomyConfig cfg, string driverName)
        {
            return new SaveGame
            {
                career = CareerService.NewCareer(cfg, driverName),
                aiDrivers = DefaultLeague.Drivers(),
                teams = DefaultLeague.Teams(),
            };
        }

        /// <summary>Repairs null collections and out-of-range values after deserialisation. Returns false if the data is unusable.</summary>
        public bool Validate(EconomyConfig cfg)
        {
            if (version > CurrentVersion) return false;
            if (career == null) return false;
            if (career.ledger == null) career.ledger = new List<LedgerEntry>();
            if (career.trackRecords == null) career.trackRecords = new List<TrackRecord>();
            if (settings == null) settings = new GameSettings();
            settings.Sanitise();
            if (aiDrivers == null || aiDrivers.Count == 0) aiDrivers = DefaultLeague.Drivers();
            foreach (var d in aiDrivers) if (d.stats == null) d.stats = new DriverCareerStats();
            if (teams == null || teams.Count == 0) teams = DefaultLeague.Teams();
            if (history == null) history = new List<RaceHistoryEntry>();
            version = CurrentVersion;
            return true;
        }

        public void AddHistory(RaceHistoryEntry entry)
        {
            history.Add(entry);
            if (history.Count > MaxHistory) history.RemoveRange(0, history.Count - MaxHistory);
        }
    }
}
