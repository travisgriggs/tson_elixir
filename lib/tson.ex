defmodule TSON do
  use Bitwise, only_operators: true

  @moduledoc """
  Documentation for `TSON`.
  """

  # @opDocument 1
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
  # @opRepeatedString 15
  @opSmallString1 16
  # @opSmallString24 39
  # @opSmallDocument1 40
  # @opSmallDocument4 43
  @opSmallArray1 44
  # @opSmallArray4 47
  # 48 - 55 unused
  @opDuration 55
  # 56 - 57 unused
  @opPositiveVLI 58
  @opNegativeVLI 59
  # @opFloat4 60
  # @opFloat8 61
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

  def decode(<<@opTrue>>) do
    true
  end

  def decode(<<@opFalse>>) do
    false
  end

  def decode(<<@opEmpty>>) do
    nil
  end

  def vli(int) when int >= 0 do
    cond do
      int in 0..0x7F -> <<int>>
      true -> <<(int &&& 0x7F) ||| 0x80>> <> vli(int >>> 7)
    end
  end

  def encode(value) when is_integer(value) do
    cond do
      value in 0..63 -> <<@opSmallInt0 + value>>
      value < 0 -> <<@opNegativeVLI>> <> vli(-value)
      true -> <<@opPositiveVLI>> <> vli(value)
    end
  end

  def encode(true, _) do
    <<@opTrue>>
  end

  def encode(false) do
    <<@opFalse>>
  end

  def encode(nil, _) do
    <<@opEmpty>>
  end

  def encode(binary) when is_binary(binary) do
    <<@opBytes>> <> vli(byte_size(binary)) <> binary
  end

  def encode(list) when is_list(list) do
    allEncoded = Enum.map_join(list, &encode/1)
    listLength = length(list)

    cond do
      listLength in 1..4 -> <<@opSmallArray1 - 1 + listLength>> <> allEncoded
      true -> <<@opArray>> <> allEncoded <> <<0>>
    end
  end

  def encode(%String{utf8: utf8}) do
    with byteCount = byte_size(utf8) do
      cond do
        byteCount == 0 -> <<@opTerminatedString, 0>>
        byteCount in 1..24 -> <<@opSmallString1 - 1 + byteCount>> <> utf8
        true -> <<@opTerminatedString>> <> utf8 <> <<0>>
      end
    end
  end

  def encode(%LatLon{latitude: latitude, longitude: longitude}) do
    precision = 25
    lat_hash = geo_hash2(latitude, -90.0, 90.0, precision)
    lon_hash = geo_hash2(longitude, -180.0, 180.0, precision)
    spliced = lon_hash <<< 1 ||| lat_hash
    <<@opLatLon>> <> vli(spliced)
  end

  def encode(%DateTime{} = datetime) do
    milliseconds = DateTime.diff(datetime, @epoch, :millisecond)

    if milliseconds >= 0 do
      <<@opPositiveTimestamp>> <> vli(milliseconds)
    else
      <<@opNegativeTimestamp>> <> vli(-milliseconds)
    end
  end

  def encode(%Duration{} = duration) do
    canonized = Duration.reduced(duration)
    magnitude = abs(canonized.amount)

    negateMask =
      if magnitude == canonized.amount do
        0x00
      else
        0x80
      end

    case canonized.unit do
      :hour -> <<@opDuration, negateMask ||| 0x04>> <> vli(magnitude)
      :minute -> <<@opDuration, negateMask ||| 0x02>> <> vli(magnitude)
      :second -> <<@opDuration, negateMask ||| 0x01>> <> vli(magnitude)
      :millisecond -> <<@opDuration, negateMask ||| 0x03>> <> vli(magnitude)
      :microsecond -> <<@opDuration, negateMask ||| 0x06>> <> vli(magnitude)
      :nanosecond -> <<@opDuration, negateMask ||| 0x09>> <> vli(magnitude)
    end
  end

  def encode(float) when is_float(float) do
    <<42>>
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
