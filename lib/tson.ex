defmodule TSON do
  use Bitwise, only_operators: true

  @moduledoc """
  Documentation for `TSON`.
  """

  @opDocument 1
  @opArray 2
  @opBytes 3
  @opPositiveTimestamp 4
  @opTrue 5
  @opFalse 6
  @opEmpty 7
  @opNegativeTimestamp 8
  @opLatLon 9
  # 10 - 13 unused
  @opTerminatedString 14
  @opRepeatedString 15
  @opSmallString1 16
  # @opSmallString24 39
  @opSmallDocument1 40
  # @opSmallDocument4 43
  @opSmallArray1 44
  # @opSmallArray4 47
  # 48 - 55 unused
  @opDuration 55
  # 56 - 57 unused
  @opPositiveVLI 58
  @opNegativeVLI 59
  @opFloat4 60
  @opFloat8 61
  # @opPositiveFraction 62
  # @opPositiveFraction 63
  @opSmallInt0 64
  # @opSmallInt63 127

  @epoch DateTime.from_iso8601("2016-01-01T00:00:00Z") |> elem(1)

  defmodule String do
    defstruct utf8: ""
  end

  defmodule LatLon do
    defstruct latitude: 0.0, longitude: 0.0
  end

  defmodule Duration do
    defstruct amount: 0, unit: :second

    def reduced(%Duration{amount: amount, unit: unit}) do
      cond do
        unit == :minute and rem(amount, 60) == 0 ->
          %TSON.Duration{amount: div(amount, 60), unit: :hour}

        unit == :second and rem(amount, 60) == 0 ->
          TSON.Duration.reduced(%TSON.Duration{amount: div(amount, 60), unit: :minute})

        unit == :millisecond and rem(amount, 1000) == 0 ->
          TSON.Duration.reduced(%TSON.Duration{amount: div(amount, 1000), unit: :second})

        unit == :microsecond and rem(amount, 1000) == 0 ->
          TSON.Duration.reduced(%TSON.Duration{amount: div(amount, 1000), unit: :millisecond})

        unit == :nanosecond and rem(amount, 1000) == 0 ->
          TSON.Duration.reduced(%TSON.Duration{amount: div(amount, 1000), unit: :microsecond})

        true ->
          %Duration{amount: amount, unit: unit}
      end
    end
  end

  defmodule RepetitionEncoder do
    use Agent

    def start_link do
      Agent.start_link(fn -> %{} end)
    end

    def lookup(pid, value) do
      Agent.get_and_update(pid, fn map -> _lookup(map, value) end)
    end

    defp _lookup(map, value) do
      case Map.fetch(map, value) do
        {:ok, index} ->
          {index, map}

        :error ->
          {nil, map |> Map.put(value, map_size(map))}
      end
    end
  end

  def decode(<<@opTrue>>) do
    true
  end

  def decode(<<@opFalse>>) do
    false
  end

  def decode(<<@opEmpty>>) do
    nil
  end

  def vli(value) when value >= 0 do
    cond do
      value in 0..0x7F -> <<value>>
      true -> <<(value &&& 0x7F) ||| 0x80>> <> vli(value >>> 7)
    end
  end

  def encode(value) do
    {:ok, stringTable} = RepetitionEncoder.start_link()
    {:ok, keyTable} = RepetitionEncoder.start_link()
    iodata = _encode(value, stringTable, keyTable)
    stringTable |> Agent.stop()
    keyTable |> Agent.stop()
    iodata |> IO.iodata_to_binary()
  end

  defp _encode(value, _, _) when is_integer(value) do
    cond do
      value in 0..63 -> <<@opSmallInt0 + value>>
      value < 0 -> [@opNegativeVLI, vli(-value)]
      true -> [@opPositiveVLI, vli(value)]
    end
  end

  defp _encode(true, _, _) do
    <<@opTrue>>
  end

  defp _encode(false, _, _) do
    <<@opFalse>>
  end

  defp _encode(nil, _, _) do
    <<@opEmpty>>
  end

  defp _encode(value, _, _) when is_binary(value) do
    [@opBytes, vli(byte_size(value)), value]
  end

  defp _encode(value, stringTable, keyTable) when is_list(value) do
    elements = value |> Enum.map(fn v -> _encode(v, stringTable, keyTable) end)
    listLength = length(value)

    cond do
      listLength in 1..4 -> [@opSmallArray1 - 1 + listLength, elements]
      true -> [@opArray, elements, 0]
    end
  end

  defp _encode(%String{utf8: utf8}, stringTable, _) do
    index = stringTable |> RepetitionEncoder.lookup(utf8)

    cond do
      is_integer(index) ->
        [@opRepeatedString, vli(index)]

      true ->
        byteCount = byte_size(utf8)

        cond do
          byteCount in 1..24 -> [@opSmallString1 - 1 + byteCount, utf8]
          true -> [@opTerminatedString, utf8, 0]
        end
    end
  end

  defp _encode(%LatLon{latitude: latitude, longitude: longitude}, _, _) do
    precision = 25
    lat_hash = geo_hash2(latitude, -90.0, 90.0, precision)
    lon_hash = geo_hash2(longitude, -180.0, 180.0, precision)
    spliced = lon_hash <<< 1 ||| lat_hash
    [@opLatLon, vli(spliced)]
  end

  defp _encode(%DateTime{} = datetime, _, _) do
    milliseconds = DateTime.diff(datetime, @epoch, :millisecond)

    if milliseconds >= 0 do
      [@opPositiveTimestamp, vli(milliseconds)]
    else
      [@opNegativeTimestamp, vli(-milliseconds)]
    end
  end

  defp _encode(%Duration{} = duration, _, _) do
    canonized = Duration.reduced(duration)
    magnitude = abs(canonized.amount)

    negateMask =
      if magnitude == canonized.amount do
        0x00
      else
        0x80
      end

    opUnit =
      negateMask |||
        case canonized.unit do
          :hour -> 0x04
          :minute -> 0x02
          :second -> 0x01
          :millisecond -> 0x03
          :microsecond -> 0x06
          :nanosecond -> 0x09
        end

    [@opDuration, opUnit, vli(magnitude)]
  end

  defp _encode(value, stringTable, keyTable) when is_float(value) do
    nearestInt = round(value)

    if nearestInt == value do
      _encode(nearestInt, stringTable, keyTable)
    else
      bytes4 = <<value::float-32-little>>
      <<value32::float-32-little>> = bytes4

      if value32 == value do
        [@opFloat4, bytes4]
      else
        [@opFloat8, <<value::float-64-little>>]
      end
    end
  end

  defp _encode(value, stringTable, keyTable) when is_map(value) do
    sortedKeys =
      value
      |> Map.keys()
      |> Enum.map(fn k ->
        if is_atom(k) do
          Atom.to_string(k)
        else
          k
        end
      end)
      |> Enum.sort()

    mapper = fn k ->
      bits_v = _encode(Map.get(value, k), stringTable, keyTable)
      index = keyTable |> RepetitionEncoder.lookup(k)

      if is_integer(index) do
        <<_::size(1), rest::bitstring>> = bits_v
        [<<1::size(1), rest::bitstring>>, vli(index)]
      else
        [bits_v, k, 0]
      end
    end

    elements = sortedKeys |> Enum.map(mapper)
    mapSize = map_size(value)

    cond do
      mapSize in 1..4 -> [@opSmallDocument1 - 1 + mapSize, elements]
      true -> [@opDocument, elements, 0]
    end
  end

  defp geo_hash2(_, _, _, 0) do
    0
  end

  defp geo_hash2(value, low, high, precision) do
    mid = (high + low) / 2
    shift = (precision - 1) * 2

    if value > mid do
      1 <<< shift ||| geo_hash2(value, mid, high, precision - 1)
    else
      0 <<< shift ||| geo_hash2(value, low, mid, precision - 1)
    end
  end
end
