defmodule TSON.Encoder do
  use Bitwise, only_operators: true
  alias __MODULE__
  alias TSON.Op
  require Op

  defstruct iodata: [], strings: %{}, keys: %{}

  def encode(value) do
    encoder = %Encoder{} |> encode(value)
    encoder.iodata |> IO.iodata_to_binary()
  end

  defp encode(encoder, value) when is_integer(value) do
    cond do
      value in 0..63 -> encoder |> add(Op.small_int_0() + value)
      value < 0 -> encoder |> add([Op.negative_varuint(), -value |> varuint])
      true -> encoder |> add([Op.positive_varuint(), value |> varuint])
    end
  end

  defp encode(encoder, true) do
    encoder |> add(Op._true())
  end

  defp encode(encoder, false) do
    encoder |> add(Op._false())
  end

  defp encode(encoder, nil) do
    encoder |> add(Op.none())
  end

  defp encode(encoder, value) when is_binary(value) do
    encoder |> add([Op.bytes(), byte_size(value) |> varuint, value])
  end

  defp encode(encoder, value) when is_list(value) do
    subcoder =
      value
      |> Enum.reduce(encoder |> subcoder(), fn element, subcoder ->
        subcoder |> encode(element)
      end)

    list_length = length(value)

    if list_length in 1..4 do
      encoder |> add(Op.small_array_1() - 1 + list_length) |> add_subcoder(subcoder)
    else
      encoder |> add(Op.array()) |> add_subcoder(subcoder) |> add(0)
    end
  end

  defp encode(encoder, %TSON.String{utf8: utf8}) do
    {encoder, index} = encoder |> note_string(utf8)

    if is_integer(index) do
      encoder |> add([Op.repeated_string(), varuint(index)])
    else
      byte_size_ = byte_size(utf8)

      if byte_size_ in 1..24 do
        encoder |> add([Op.small_string_1() - 1 + byte_size_, utf8])
      else
        encoder |> add([Op.terminated_string(), utf8, 0])
      end
    end
  end

  defp encode(encoder, %TSON.LatLon{} = latlon) do
    precision = 25
    hashed = latlon |> TSON.LatLon.to_geohash(precision)
    encoder |> add([Op.lat_lon(), hashed |> varuint])
  end

  defp encode(encoder, %DateTime{} = datetime) do
    milliseconds = DateTime.diff(datetime, Op.epoch(), :millisecond)

    encoder
    |> add(
      if milliseconds >= 0 do
        [Op.positive_timestamp(), milliseconds |> varuint]
      else
        [Op.negative_timestamp(), -milliseconds |> varuint]
      end
    )
  end

  defp encode(encoder, %TSON.Duration{} = duration) do
    reduced = duration |> TSON.Duration.reduced()
    positive_amount = reduced.amount |> abs

    negate_mask =
      if positive_amount == reduced.amount do
        0x00
      else
        0x80
      end

    unit_op =
      case reduced.unit do
        :hour -> 0x04
        :minute -> 0x02
        :second -> 0x01
        :millisecond -> 0x03
        :microsecond -> 0x06
        :nanosecond -> 0x09
      end

    encoder |> add([Op.duration(), negate_mask ||| unit_op, positive_amount |> varuint])
  end

  defp encode(encoder, value) when is_float(value) do
    nearest_int = value |> round

    if nearest_int == value do
      encoder |> encode(nearest_int)
    else
      bytes4 = <<value::float-32-little>>
      <<value32::float-32-little>> = bytes4

      encoder
      |> add(
        if value32 == value do
          [Op.float_4(), bytes4]
        else
          [Op.float_8(), <<value::float-64-little>>]
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
          k |> Atom.to_string()
        else
          k
        end
      end)
      |> Enum.sort()

    subcoder =
      sorted_keys
      |> Enum.reduce(encoder |> subcoder(), fn key, subcoder ->
        subcoder |> add_key_value(key, value[key])
      end)

    map_size = map_size(value)

    if map_size in 1..4 do
      encoder |> add(Op.small_document_1() - 1 + map_size) |> add_subcoder(subcoder)
    else
      encoder |> add(Op.document()) |> add_subcoder(subcoder) |> add(0)
    end
  end

  defp add_key_value(encoder, key, value) do
    subcoder = encoder |> subcoder() |> encode(value)
    {subcoder, index} = subcoder |> note_key(key)

    if is_integer(index) do
      bits_v = subcoder.iodata |> IO.iodata_to_binary()
      <<_::size(1), rest::bitstring>> = bits_v

      encoder
      |> copying_memory(subcoder)
      |> add([<<1::size(1), rest::bitstring>>, index |> varuint])
    else
      encoder |> add_subcoder(subcoder) |> add([key, 0])
    end
  end

  defp varuint(value) when value in 0..0x7F do
    <<value>>
  end

  defp varuint(value) when value > 0x7F do
    <<(value &&& 0x7F) ||| 0x80>> <> (value >>> 7 |> varuint)
  end

  defp add(%Encoder{iodata: iodata, strings: strings, keys: keys}, more) do
    %Encoder{iodata: [iodata, more], strings: strings, keys: keys}
  end

  defp add_subcoder(%Encoder{} = encoder, %Encoder{} = subcoder) do
    %Encoder{
      iodata: [encoder.iodata, subcoder.iodata],
      strings: subcoder.strings,
      keys: subcoder.keys
    }
  end

  defp copying_memory(%Encoder{} = encoder, %Encoder{} = subcoder) do
    %Encoder{
      iodata: encoder.iodata,
      strings: subcoder.strings,
      keys: subcoder.keys
    }
  end

  defp note_string(%Encoder{} = encoder, string) do
    {strings, index} =
      case Map.fetch(encoder.strings, string) do
        {:ok, index} ->
          {encoder.strings, index}

        :error ->
          {encoder.strings |> Map.put(string, map_size(encoder.strings)), nil}
      end

    {%Encoder{iodata: encoder.iodata, strings: strings, keys: encoder.keys}, index}
  end

  defp note_key(%Encoder{} = encoder, key) do
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
end
