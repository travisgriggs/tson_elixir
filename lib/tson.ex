defmodule TSON do
  use Bitwise, only_operators: true

  @moduledoc """
  TSON is a an "object/data" [de]serialization protocol that was inspired by an application specific need to have an interchange encoder/decoder
  that was JSON like. It was further inspired by BSON which is binary and has a richer typeset. But BSON has lots of extra byte offsets convenient for random access computations.

  The basic structue is an [opcode | moredata] recursive chaining of data.

  It was tuned to fit our own application's nuances and further inspired by far too much familiarity with Smalltalk Virtual Machine bytecode design as well
  a general appreciation for Benford's Law (smaller values show up more often than not in many real world cases).

  The "T" stands for Tiny, Tight, Terse, or TWiG, but not Travis.
  """

  @opDocument 1
  @opArray 2
  @opBytes 3
  @opPositiveTimestamp 4
  @opTrue 5
  @opFalse 6
  @opNone 7
  @opNegativeTimestamp 8
  @opLatLon 9
  # 10 - 13 unused
  @opTerminatedString 14
  @opRepeatedString 15
  @opSmallString1 16
  @opSmallString24 39
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
  @opSmallInt63 127

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

    def reduced(%Duration{amount: amount, unit: :minute}) when rem(amount, 60) == 0 do
      %Duration{amount: div(amount, 60), unit: :hour}
    end

    def reduced(%Duration{amount: amount, unit: :second}) when rem(amount, 60) == 0 do
      reduced(%Duration{amount: div(amount, 60), unit: :minute})
    end

    def reduced(%Duration{amount: amount, unit: :millisecond}) when rem(amount, 1000) == 0 do
      reduced(%Duration{amount: div(amount, 1000), unit: :second})
    end

    def reduced(%Duration{amount: amount, unit: :microsecond}) when rem(amount, 1000) == 0 do
      reduced(%Duration{amount: div(amount, 1000), unit: :millisecond})
    end

    def reduced(%Duration{amount: amount, unit: :nanosecond}) when rem(amount, 1000) == 0 do
      reduced(%Duration{amount: div(amount, 1000), unit: :microsecond})
    end

    def reduced(%Duration{} = d), do: d
  end

  defmodule Encoder do
    defstruct iodata: [], strings: %{}, keys: %{}
  end

  # main api, use type specific encoders to recursively traverse value with repeatition tables
  # flatten (iodata) results into single binary when done
  def encode(value) do
    encoder = %Encoder{}
    encoder = encoder |> encode(value)
    encoder.iodata |> IO.iodata_to_binary()
  end

  defp next_put(%Encoder{iodata: iodata, strings: strings, keys: keys}, more) do
    %Encoder{iodata: [iodata, more], strings: strings, keys: keys}
  end

  defp next_put_all(%Encoder{} = encoder, %Encoder{} = subcoder) do
    %Encoder{
      iodata: [encoder.iodata, subcoder.iodata],
      strings: subcoder.strings,
      keys: subcoder.keys
    }
  end

  defp with_caches(%Encoder{} = encoder, %Encoder{} = subcoder) do
    %Encoder{
      iodata: encoder.iodata,
      strings: subcoder.strings,
      keys: subcoder.keys
    }
  end

  defp cache_string(%Encoder{} = encoder, string) do
    {strings, index} =
      case Map.fetch(encoder.strings, string) do
        {:ok, index} ->
          {encoder.strings, index}

        :error ->
          {encoder.strings |> Map.put(string, map_size(encoder.strings)), nil}
      end

    {%Encoder{iodata: encoder.iodata, strings: strings, keys: encoder.keys}, index}
  end

  defp cache_key(%Encoder{} = encoder, key) do
    {keys, index} =
      case Map.fetch(encoder.keys, key) do
        {:ok, index} ->
          {encoder.keys, index}

        :error ->
          {encoder.keys |> Map.put(key, map_size(encoder.keys)), nil}
      end

    {%Encoder{iodata: encoder.iodata, strings: encoder.strings, keys: keys}, index}
  end

  defp subcoder(%Encoder{} = encoder) do
    %Encoder{iodata: [], strings: encoder.strings, keys: encoder.keys}
  end

  defp encode(encoder, value) when is_integer(value) do
    encoder
    |> next_put(
      cond do
        value in 0..63 -> @opSmallInt0 + value
        value < 0 -> [@opNegativeVLI, varuint(-value)]
        true -> [@opPositiveVLI, varuint(value)]
      end
    )
  end

  defp encode(encoder, true) do
    encoder |> next_put(@opTrue)
  end

  defp encode(encoder, false) do
    encoder |> next_put(@opFalse)
  end

  defp encode(encoder, nil) do
    encoder |> next_put(@opNone)
  end

  defp encode(encoder, value) when is_binary(value) do
    encoder |> next_put([@opBytes, varuint(byte_size(value)), value])
  end

  defp encode(encoder, value) when is_list(value) do
    subcoder =
      value
      |> Enum.reduce(encoder |> subcoder(), fn element, subcoder ->
        subcoder |> encode(element)
      end)

    listLength = length(value)

    if listLength in 1..4 do
      encoder |> next_put(@opSmallArray1 - 1 + listLength) |> next_put_all(subcoder)
    else
      encoder |> next_put(@opArray) |> next_put_all(subcoder) |> next_put(0)
    end
  end

  defp encode(encoder, %String{utf8: utf8}) do
    {encoder, index} = encoder |> cache_string(utf8)

    encoder
    |> next_put(
      if is_integer(index) do
        [@opRepeatedString, varuint(index)]
      else
        byteCount = byte_size(utf8)

        if byteCount in 1..24 do
          [@opSmallString1 - 1 + byteCount, utf8]
        else
          [@opTerminatedString, utf8, 0]
        end
      end
    )
  end

  defp encode(encoder, %LatLon{latitude: latitude, longitude: longitude}) do
    precision = 25
    lat_hash = geo_hash2(latitude, -90.0, 90.0, precision)
    lon_hash = geo_hash2(longitude, -180.0, 180.0, precision)
    spliced = lon_hash <<< 1 ||| lat_hash
    encoder |> next_put([@opLatLon, varuint(spliced)])
  end

  defp encode(encoder, %DateTime{} = datetime) do
    milliseconds = DateTime.diff(datetime, @epoch, :millisecond)

    encoder
    |> next_put(
      if milliseconds >= 0 do
        [@opPositiveTimestamp, varuint(milliseconds)]
      else
        [@opNegativeTimestamp, varuint(-milliseconds)]
      end
    )
  end

  defp encode(encoder, %Duration{} = duration) do
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

    encoder |> next_put([@opDuration, opUnit, varuint(magnitude)])
  end

  defp encode(encoder, value) when is_float(value) do
    nearest_int = round(value)

    if nearest_int == value do
      encoder |> encode(nearest_int)
    else
      bytes4 = <<value::float-32-little>>
      <<value32::float-32-little>> = bytes4

      encoder
      |> next_put(
        if value32 == value do
          [@opFloat4, bytes4]
        else
          [@opFloat8, <<value::float-64-little>>]
        end
      )
    end
  end

  defp encode(encoder, value) when is_map(value) do
    sorted_keys =
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

    subcoder =
      sorted_keys
      |> Enum.reduce(encoder |> subcoder(), fn key, subcoder ->
        subcoder |> next_put_key_value(key, value[key])
      end)

    map_size = map_size(value)

    if map_size in 1..4 do
      encoder |> next_put(@opSmallDocument1 - 1 + map_size) |> next_put_all(subcoder)
    else
      encoder |> next_put(@opDocument) |> next_put_all(subcoder) |> next_put(0)
    end
  end

  defp next_put_key_value(encoder, key, value) do
    subcoder = encoder |> subcoder() |> encode(value)
    {subcoder, index} = subcoder |> cache_key(key)

    if is_integer(index) do
      bits_v = subcoder.iodata |> IO.iodata_to_binary()
      <<_::size(1), rest::bitstring>> = bits_v

      encoder
      |> with_caches(subcoder)
      |> next_put([<<1::size(1), rest::bitstring>>, varuint(index)])
    else
      encoder |> next_put_all(subcoder) |> next_put([key, 0])
    end
  end

  # given a range and coordinate, successively divide the range in half and record in bitvec which half contains the value, repeate precision times
  # our bitvec is actually 2 bits per decision, so that we can shift one and or them as an interleaved value for the lat and lon
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

  defp varuint(value) when value in 0..0x7F do
    <<value>>
  end

  defp varuint(value) when value > 0x7F do
    <<(value &&& 0x7F) ||| 0x80>> <> varuint(value >>> 7)
  end

  defmodule Decoder do
    defstruct thing: :nothing, strings: %{}, keys: %{}
  end

  def decode(binary) when is_binary(binary) do
    binary |> :binary.bin_to_list() |> decode
  end

  def decode([opCode | tail]) do
    {thing, _} = decode(opCode, tail)
    thing
  end

  def decode(@opTrue, tail) do
    {true, tail}
  end

  def decode(@opFalse, tail) do
    {false, tail}
  end

  def decode(@opNone, tail) do
    {nil, tail}
  end

  def decode(@opPositiveVLI, tail) do
    d_varuint(tail)
  end

  def decode(@opNegativeVLI, tail) do
    {value, tail} = d_varuint(tail)
    {-value, tail}
  end

  def decode(@opTerminatedString, tail) do
    {body, [0 | tail]} = tail |> Enum.split_while(fn code -> code != 0 end)
    {%TSON.String{utf8: body |> IO.iodata_to_binary()}, tail}
  end

  def decode(@opBytes, tail) do
    {count, tail} = d_varuint(tail)
    {body, tail} = tail |> Enum.split(count)
    {body |> IO.iodata_to_binary(), tail}
  end

  def decode(@opDuration, [unitOp | tail]) do
    multiplier =
      case unitOp &&& 0x80 do
        0x80 -> -1
        0 -> 1
      end

    unit =
      case unitOp &&& 0x7F do
        0x04 -> :hour
        0x02 -> :minute
        0x01 -> :second
        0x03 -> :millisecond
        0x06 -> :microsecond
        0x09 -> :nanosecond
      end

    {magnitude, tail} = d_varuint(tail)
    {%TSON.Duration{amount: magnitude * multiplier, unit: unit}, tail}
  end

  def decode(@opPositiveTimestamp, tail) do
    {offset, tail} = d_varuint(tail)
    {DateTime.add(@epoch, offset, :millisecond), tail}
  end

  def decode(@opNegativeTimestamp, tail) do
    {offset, tail} = d_varuint(tail)
    {DateTime.add(@epoch, -offset, :millisecond), tail}
  end

  def decode(@opFloat4, tail) do
    {first4, tail} = tail |> Enum.split(4)
    <<value32::float-32-little>> = first4 |> :binary.list_to_bin()
    {value32, tail}
  end

  def decode(@opFloat8, tail) do
    {first8, tail} = tail |> Enum.split(8)
    <<value64::float-64-little>> = first8 |> :binary.list_to_bin()
    {value64, tail}
  end

  def decode(@opLatLon, tail) do
    {spliced, tail} = d_varuint(tail)
    precision = 25
    latitude = geo_unhash2(spliced, -90.0, 90.0, precision)
    longitude = geo_unhash2(spliced >>> 1, -180.0, 180.0, precision)
    {%LatLon{latitude: latitude, longitude: longitude}, tail}
  end

  def decode(smallInt, tail) when smallInt in @opSmallInt0..@opSmallInt63 do
    {smallInt - @opSmallInt0, tail}
  end

  def decode(sizedString, tail) when sizedString in @opSmallString1..@opSmallString24 do
    count = sizedString - @opSmallString1 + 1
    {body, tail} = tail |> Enum.split(count)
    {%TSON.String{utf8: body |> IO.iodata_to_binary()}, tail}
  end

  defp d_varuint([byte | tail]) when byte in 0..0x7F do
    {byte, tail}
  end

  defp d_varuint([byte | tail]) when byte > 0x7F do
    {high, tail} = d_varuint(tail)
    {(high <<< 7) + (byte &&& 0x7F), tail}
  end

  defp geo_unhash2(_, low, high, 0) do
    (low + high) / 2.0
  end

  defp geo_unhash2(bitvec, low, high, precision) do
    mid = (high + low) / 2
    bit = bitvec >>> ((precision - 1) * 2) &&& 0b1

    if bit == 1 do
      geo_unhash2(bitvec, mid, high, precision - 1)
    else
      geo_unhash2(bitvec, low, mid, precision - 1)
    end
  end
end
