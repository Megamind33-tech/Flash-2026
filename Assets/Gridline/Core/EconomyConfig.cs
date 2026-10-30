using System;

namespace Gridline.Core
{
    /// <summary>
    /// All economy numbers live here so balancing never requires code changes.
    /// Loaded at runtime from Resources/gridline_economy.json when present; these are the fallback defaults.
    /// Public fields keep it compatible with UnityEngine.JsonUtility.
    /// </summary>
    [Serializable]
    public class EconomyConfig
    {
        public int startingMoney = 5000;
        public int amateurEntryFee = 250;
        /// <summary>Prize money by finishing position (index 0 = P1). Positions beyond the table earn nothing.</summary>
        public int[] prizeByPosition = { 3000, 1800, 1200, 800, 500, 300, 200, 100 };
        /// <summary>Reputation gained by finishing position (index 0 = P1).</summary>
        public int[] reputationByPosition = { 12, 8, 6, 4, 3, 2, 1, 1 };
        public int reputationForFastestLap = 2;
        public int fastestLapBonus = 250;
        /// <summary>When the player cannot afford the entry fee, a grassroots sponsor covers it so a career can never soft-lock.</summary>
        public bool sponsorCoversEntryWhenBroke = true;
        /// <summary>Hard floor for reputation.</summary>
        public int minimumReputation = 0;

        public int PrizeFor(int position)
        {
            return Lookup(prizeByPosition, position);
        }

        public int ReputationFor(int position)
        {
            return Lookup(reputationByPosition, position);
        }

        static int Lookup(int[] table, int position)
        {
            if (table == null || position < 1 || position > table.Length) return 0;
            return table[position - 1];
        }

        public static EconomyConfig Default()
        {
            return new EconomyConfig();
        }
    }
}
