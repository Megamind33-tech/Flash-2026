using System;
using System.Collections.Generic;

namespace Gridline.Core
{
    [Serializable]
    public class DriverCareerStats
    {
        public int starts;
        public int wins;
        public int podiums;
        public int points;
        public int bestFinish;
    }

    /// <summary>A persistent competitor. Attributes are 0..100. AI drivers exist between races, not only during them.</summary>
    [Serializable]
    public class DriverProfile
    {
        public string id;
        public string displayName;
        public string nationality;
        public string teamId;
        public int skill;
        public int experience;
        public int aggression;
        public int consistency;
        public int wetSkill;
        public int tyreManagement;
        public int teamLoyalty;
        public int contractValue;
        public int reputation;
        public DriverCareerStats stats = new DriverCareerStats();

        /// <summary>Fraction of the track's theoretical speed profile this driver commits to (0.86..1.0).</summary>
        public float PaceFactor { get { return 0.86f + 0.14f * Clamp01(skill / 100f) + 0.02f * Clamp01(experience / 100f) - 0.02f; } }

        /// <summary>Lap-to-lap pace variation (fraction). Lower consistency = more variation.</summary>
        public float PaceNoise { get { return 0.004f + 0.03f * (1f - Clamp01(consistency / 100f)); } }

        /// <summary>0..1, how readily the driver commits to overtakes and holds tight gaps.</summary>
        public float Aggression01 { get { return Clamp01(aggression / 100f); } }

        public void RecordResult(int position)
        {
            stats.starts++;
            if (position == 1) stats.wins++;
            if (position <= 3) stats.podiums++;
            stats.points += ChampionshipPoints.ForPosition(position);
            if (stats.bestFinish == 0 || position < stats.bestFinish) stats.bestFinish = position;
        }

        static float Clamp01(float v) { return v < 0 ? 0 : v > 1 ? 1 : v; }
    }

    [Serializable]
    public class TeamProfile
    {
        public string id;
        public string displayName;
        public int budget;
        public int technicalCapability;
        public string primaryColorHex;
    }

    /// <summary>Seed data for the first season. Names and teams are fictional.</summary>
    public static class DefaultLeague
    {
        public static List<TeamProfile> Teams()
        {
            return new List<TeamProfile>
            {
                new TeamProfile { id = "halden", displayName = "Halden Motorsport", budget = 180000, technicalCapability = 62, primaryColorHex = "#1F4E8C" },
                new TeamProfile { id = "corsair", displayName = "Corsair Racing", budget = 140000, technicalCapability = 55, primaryColorHex = "#B3261E" },
                new TeamProfile { id = "vantor", displayName = "Vantor Engineering", budget = 95000, technicalCapability = 48, primaryColorHex = "#E0A100" },
                new TeamProfile { id = "northline", displayName = "Northline GP", budget = 70000, technicalCapability = 41, primaryColorHex = "#2E7D32" },
            };
        }

        public static List<DriverProfile> Drivers()
        {
            return new List<DriverProfile>
            {
                D("ai_reyes", "Mateo Reyes", "ESP", "halden", 78, 70, 55, 80, 66, 72, 60, 42000, 55),
                D("ai_lindqvist", "Elin Lindqvist", "SWE", "corsair", 72, 52, 68, 66, 74, 58, 45, 30000, 40),
                D("ai_okafor", "Daniel Okafor", "NGA", "vantor", 66, 40, 74, 58, 55, 61, 70, 21000, 28),
                D("ai_brandt", "Jonas Brandt", "DEU", "northline", 60, 85, 38, 84, 62, 80, 82, 18000, 33),
            };
        }

        static DriverProfile D(string id, string name, string nat, string team, int skill, int exp, int aggr, int cons, int wet, int tyre, int loyalty, int contract, int rep)
        {
            return new DriverProfile
            {
                id = id, displayName = name, nationality = nat, teamId = team, skill = skill, experience = exp, aggression = aggr,
                consistency = cons, wetSkill = wet, tyreManagement = tyre, teamLoyalty = loyalty, contractValue = contract, reputation = rep,
            };
        }
    }
}
