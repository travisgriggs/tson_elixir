defmodule TSON do
  use Bitwise, only_operators: true

  @moduledoc """
  TSON is a an "object/data" [de]serialization protocol that was inspired by an application specific need to have an interchange encoder/decoder
  that was JSON like. It was further inspired by BSON (which was smaller but includes lots of offsets convenient for address jumping AND has a richer
  typeset).

  The basic structue is an opcode[moredata] recursive chaining of data.

  It was tuned to fit our own application's nuances and further inspired by far too much familiarity with Smalltalk Virtual Machine bytecode design as well
  a general appreciate for Benford's Law (smaller values show up more often than not in many real world cases).

  The "T" stands for Tiny, Tight, Terse, or TWiG, but not Travis.
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

  # we need a struct wrapper around strings, because we have to preserve/disambiguate the difference between a raw binary and a utf8 string
  defmodule String do
    defstruct utf8: ""
  end

  # basic structure for modeling a GIS coordinate
  defmodule LatLon do
    defstruct latitude: 0.0, longitude: 0.0
  end

  # simple structure for modelling a duration in various units, with the ability to reduce to least needed unit
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

  # a caching Look Up Table that is used record occurences of keys/strings as they are encountered and vend those occurence indices on future lookups
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

  # main api, use type specific encoders to recursively traverse value with repeatition tables
  # flatten (iodata) results into single binary when done
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
      value < 0 -> [@opNegativeVLI, varuint(-value)]
      true -> [@opPositiveVLI, varuint(value)]
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
    [@opBytes, varuint(byte_size(value)), value]
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
        [@opRepeatedString, varuint(index)]

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
    [@opLatLon, varuint(spliced)]
  end

  defp _encode(%DateTime{} = datetime, _, _) do
    milliseconds = DateTime.diff(datetime, @epoch, :millisecond)

    if milliseconds >= 0 do
      [@opPositiveTimestamp, varuint(milliseconds)]
    else
      [@opNegativeTimestamp, varuint(-milliseconds)]
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

    [@opDuration, opUnit, varuint(magnitude)]
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
      subEncoding = _encode(Map.get(value, k), stringTable, keyTable)
      index = keyTable |> RepetitionEncoder.lookup(k)

      if is_integer(index) do
        bits_v = subEncoding |> IO.iodata_to_binary()
        <<_::size(1), rest::bitstring>> = bits_v
        [<<1::size(1), rest::bitstring>>, varuint(index)]
      else
        [subEncoding, k, 0]
      end
    end

    elements = sortedKeys |> Enum.map(mapper)
    mapSize = map_size(value)

    cond do
      mapSize in 1..4 -> [@opSmallDocument1 - 1 + mapSize, elements]
      true -> [@opDocument, elements, 0]
    end
  end

  # given a range and coordinate, successively divide the range in half and record in bitmap which half contains the value, repeate precision times
  # our bitmap is actually 2 bits per decision, so that we can shift one and or them as an interleaved value for the lat and lon
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

  defp varuint(value) when value >= 0 do
    cond do
      value in 0..0x7F -> <<value>>
      true -> <<(value &&& 0x7F) ||| 0x80>> <> varuint(value >>> 7)
    end
  end

  # the beginning of a the decoding ability, set aside until encoding is iterated on a bit
  def decode(<<@opTrue>>) do
    true
  end

  def decode(<<@opFalse>>) do
    false
  end

  def decode(<<@opEmpty>>) do
    nil
  end
end
