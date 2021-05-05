defmodule TSON.LatLon do
  alias __MODULE__
  use Bitwise, only_operators: true

  defstruct latitude: 0.0, longitude: 0.0

  def to_geohash(%LatLon{latitude: latitude, longitude: longitude}, precision) do
    lat_hash = latitude |> enhash_by2(-90.0, 90.0, precision)
    lon_hash = longitude |> enhash_by2(-180.0, 180.0, precision)
    lon_hash <<< 1 ||| lat_hash
  end

  defp enhash_by2(_, _, _, 0) do
    0
  end

  defp enhash_by2(value, low, high, precision) do
    mid = (high + low) / 2
    shift = (precision - 1) * 2

    if value > mid do
      1 <<< shift ||| enhash_by2(value, mid, high, precision - 1)
    else
      0 <<< shift ||| enhash_by2(value, low, mid, precision - 1)
    end
  end

  def from_geohash(hash_value, precision) do
    latitude = hash_value >>> 0 |> dehash_by2(-90.0, 90.0, precision)
    longitude = hash_value >>> 1 |> dehash_by2(-180.0, 180.0, precision)
    %LatLon{latitude: latitude, longitude: longitude}
  end

  defp dehash_by2(_, low, high, 0) do
    (low + high) / 2.0
  end

  defp dehash_by2(bitvec, low, high, precision) do
    mid = (high + low) / 2
    bit = bitvec >>> ((precision - 1) * 2) &&& 0b1

    if bit == 1 do
      bitvec |> dehash_by2(mid, high, precision - 1)
    else
      bitvec |> dehash_by2(low, mid, precision - 1)
    end
  end
end
