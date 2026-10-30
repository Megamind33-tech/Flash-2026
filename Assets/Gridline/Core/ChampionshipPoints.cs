namespace Gridline.Core
{
    public static class ChampionshipPoints
    {
        static readonly int[] Table = { 25, 18, 15, 12, 10, 8, 6, 4, 2, 1 };

        public static int ForPosition(int position)
        {
            return position >= 1 && position <= Table.Length ? Table[position - 1] : 0;
        }
    }
}
