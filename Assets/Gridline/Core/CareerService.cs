using System;

namespace Gridline.Core
{
    [Serializable]
    public class RaceEntryReceipt
    {
        public int feeCharged;
        public bool sponsorCovered;
        public bool accepted;
    }

    [Serializable]
    public class RaceReward
    {
        public int position;
        public int fieldSize;
        public int prizeMoney;
        public int fastestLapBonus;
        public int reputationGained;
        public int championshipPoints;
        public bool newTrackRecord;
        public int TotalMoney { get { return prizeMoney + fastestLapBonus; } }
    }

    /// <summary>Applies race outcomes to a career. Stateless; all balancing comes from EconomyConfig.</summary>
    public static class CareerService
    {
        public static CareerState NewCareer(EconomyConfig cfg, string driverName)
        {
            var c = new CareerState { driverName = string.IsNullOrEmpty(driverName) ? "Rookie" : driverName };
            c.Post(cfg.startingMoney, "Start", "Personal savings at career start");
            return c;
        }

        public static RaceEntryReceipt EnterRace(CareerState career, EconomyConfig cfg, string eventName)
        {
            var receipt = new RaceEntryReceipt();
            int fee = Math.Max(0, cfg.amateurEntryFee);
            if (career.money >= fee)
            {
                if (fee > 0) career.Post(-fee, "EntryFee", "Entry fee: " + eventName);
                receipt.feeCharged = fee;
                receipt.accepted = true;
            }
            else if (cfg.sponsorCoversEntryWhenBroke)
            {
                career.Post(0, "EntryFee", "Entry fee for " + eventName + " covered by grassroots sponsor");
                receipt.sponsorCovered = true;
                receipt.accepted = true;
            }
            if (receipt.accepted) career.racesEntered++;
            return receipt;
        }

        public static RaceReward ApplyResult(CareerState career, EconomyConfig cfg, string eventName, string trackId,
            int position, int fieldSize, int playerBestLapMs, bool playerSetFastestLap)
        {
            if (position < 1 || position > fieldSize) throw new ArgumentOutOfRangeException(nameof(position));
            var reward = new RaceReward
            {
                position = position,
                fieldSize = fieldSize,
                prizeMoney = cfg.PrizeFor(position),
                fastestLapBonus = playerSetFastestLap ? cfg.fastestLapBonus : 0,
                reputationGained = cfg.ReputationFor(position) + (playerSetFastestLap ? cfg.reputationForFastestLap : 0),
                championshipPoints = ChampionshipPoints.ForPosition(position),
            };
            if (reward.prizeMoney > 0) career.Post(reward.prizeMoney, "Prize", "Prize money: P" + position + " at " + eventName);
            if (reward.fastestLapBonus > 0) career.Post(reward.fastestLapBonus, "Prize", "Fastest lap bonus at " + eventName);
            career.reputation = Math.Max(cfg.minimumReputation, career.reputation + reward.reputationGained);
            career.championshipPoints += reward.championshipPoints;
            if (position == 1) career.wins++;
            if (position <= 3) career.podiums++;
            reward.newTrackRecord = career.SubmitLap(trackId, playerBestLapMs);
            return reward;
        }
    }
}
