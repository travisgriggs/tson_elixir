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

  defmodule RepeatedStringEncoder do
    use Agent

    def start_link do
      Agent.start_link(fn -> %{} end)
    end

    def encode(pid, value) do
      Agent.get_and_update(pid, fn map -> _encode(map, value) end)
    end

    defp _encode(map, value) when is_atom(value) do
      _encode(map, Atom.to_string(value))
    end

    defp _encode(map, value) when is_binary(value) do
      case Map.fetch(map, value) do
        {:ok, index} ->
          {index, map}

        :error ->
          {value, map |> Map.put(value, map_size(map))}
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
    {:ok, stringTable} = RepeatedStringEncoder.start_link()
    _encode(value, stringTable)
  end

  defp _encode(value, stringTable) when is_integer(value) do
    cond do
      value in 0..63 -> <<@opSmallInt0 + value>>, stringLUT}
      value < 0 -> <<@opNegativeVLI>> <> vli(-value), stringLUT}
      true -> <<@opPositiveVLI>> <> vli(value), stringLUT}
    end
  end

  defp _encode(true, stringLUT) do
    {<<@opTrue>>, stringLUT}
  end

  defp _encode(false, stringLUT) do
    {<<@opFalse>>, stringLUT}
  end

  defp _encode(nil, stringLUT) do
    {<<@opEmpty>>, stringLUT}
  end

  defp _encode(value, stringLUT) when is_binary(value) do
    {<<@opBytes>> <> vli(byte_size(value)) <> value, stringLUT}
  end

  defp _encode(value, stringLUT) when is_list(value) do
    reducer = fn x, {bits1, lut1} ->
      {bits2, lut2} = _encode(x, lut1)
      {bits1 <> bits2, lut2}
    end

    {bitsAll, lut3} = value |> Enum.reduce({<<>>, stringLUT}, reducer)
    listLength = length(value)

    cond do
      listLength in 1..4 -> {<<@opSmallArray1 - 1 + listLength>> <> bitsAll, lut3}
      true -> {<<@opArray>> <> bitsAll <> <<0>>, lut3}
    end
  end

  defp _encode(%String{utf8: utf8}, stringLUT) do
    case Map.fetch(stringLUT, utf8) do
      {:ok, index} ->
        {<<@opRepeatedString>> <> vli(index), stringLUT}

      :error ->
        lut2 = stringLUT |> Map.map(utf8, map_size(stringLUT))
        byteCount = byte_size(utf8)

        cond do
          byteCount == 0 -> {<<@opTerminatedString, 0>>, lut2}
          byteCount in 1..24 -> {<<@opSmallString1 - 1 + byteCount>> <> utf8, lut2}
          true -> {<<@opTerminatedString>> <> utf8 <> <<0>>, lut2}
        end
    end
  end

  defp _encode(%LatLon{latitude: latitude, longitude: longitude}, stringLUT) do
    precision = 25
    lat_hash = geo_hash2(latitude, -90.0, 90.0, precision)
    lon_hash = geo_hash2(longitude, -180.0, 180.0, precision)
    spliced = lon_hash <<< 1 ||| lat_hash
    {<<@opLatLon>> <> vli(spliced), stringLUT}
  end

  defp _encode(%DateTime{} = datetime, stringLUT) do
    milliseconds = DateTime.diff(datetime, @epoch, :millisecond)

    if milliseconds >= 0 do
      {<<@opPositiveTimestamp>> <> vli(milliseconds), stringLUT}
    else
      {<<@opNegativeTimestamp>> <> vli(-milliseconds), stringLUT}
    end
  end

  defp _encode(%Duration{} = duration, stringLUT) do
    canonized = Duration.reduced(duration)
    magnitude = abs(canonized.amount)

    negateMask =
      if magnitude == canonized.amount do
        0x00
      else
        0x80
      end

    case canonized.unit do
      :hour -> {<<@opDuration, negateMask ||| 0x04>> <> vli(magnitude), stringLUT}
      :minute -> {<<@opDuration, negateMask ||| 0x02>> <> vli(magnitude), stringLUT}
      :second -> {<<@opDuration, negateMask ||| 0x01>> <> vli(magnitude), stringLUT}
      :millisecond -> {<<@opDuration, negateMask ||| 0x03>> <> vli(magnitude), stringLUT}
      :microsecond -> {<<@opDuration, negateMask ||| 0x06>> <> vli(magnitude), stringLUT}
      :nanosecond -> {<<@opDuration, negateMask ||| 0x09>> <> vli(magnitude), stringLUT}
    end
  end

  defp _encode(value, stringLUT) when is_float(value) do
    nearestInt = round(value)

    if nearestInt == value do
      _encode(nearestInt, stringLUT)
    else
      bytes4 = <<value::float-32-little>>
      <<value32::float-32-little>> = bytes4

      if value32 == value do
        {<<@opFloat4>> <> bytes4, stringLUT}
      else
        bytes8 = <<value::float-64-little>>
        {<<@opFloat8>> <> bytes8, stringLUT}
      end
    end
  end

  defp _encode(value, stringLUT) when is_map(value) do
    reducer = fn {k, v}, {bits1, lut1} ->
      bits_k =
        if is_atom(k) do
          Atom.to_string(k) <> <<0>>
        else
          k <> <<0>>
        end

      {bits_v, lut2} = _encode(v, lut1)
      {bits1 <> bits_v <> bits_k, lut2}
    end

    sortedKeys = value |> Map.keys() |> Enum.sort()
    associations = for key <- sortedKeys, do: {key, Map.get(value, key)}

    {bitsAll, lut3} = associations |> Enum.reduce({<<>>, stringLUT}, reducer)
    mapSize = map_size(value)

    cond do
      mapSize in 1..4 -> {<<@opSmallDocument1 - 1 + mapSize>> <> bitsAll, lut3}
      true -> {<<@opDocument>> <> bitsAll <> <<0>>, lut3}
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
