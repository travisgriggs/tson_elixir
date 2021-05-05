defmodule TSON.Decode do
  use Bitwise, only_operators: true
  alias TSON.Opcodes, as: Op
  require Op

  @small_string_range Op.small_string_1()..Op.small_string_24()
  @small_array_range Op.small_array_1()..Op.small_array_4()
  @small_document_range Op.small_document_1()..Op.small_document_4()

  defmodule Memory do
    defstruct strings: %{}, keys: %{}

    def note_string(%Memory{strings: strings, keys: keys}, string) do
      %Memory{strings: strings |> Map.put(map_size(strings), string), keys: keys}
    end

    def note_key(%Memory{strings: strings, keys: keys}, key) do
      %Memory{strings: strings, keys: keys |> Map.put(map_size(keys), key)}
    end
  end

  def decode(binary) when is_binary(binary) do
    binary |> :binary.bin_to_list() |> decode
  end

  def decode([opCode | tail]) do
    memory = %Memory{}
    {thing, _, _} = decode(opCode, tail, memory)
    thing
  end

  defp decode(Op._true(), tail, memory) do
    {true, tail, memory}
  end

  defp decode(Op._false(), tail, memory) do
    {false, tail, memory}
  end

  defp decode(Op.none(), tail, memory) do
    {nil, tail, memory}
  end

  defp decode(Op.positive_varuint(), tail, memory) do
    tail |> varuint |> Tuple.append(memory)
  end

  defp decode(Op.negative_varuint(), tail, memory) do
    {value, tail} = tail |> varuint
    {-value, tail, memory}
  end

  defp decode(Op.terminated_string(), tail, memory) do
    {utf8, [0 | tail]} = tail |> Enum.split_while(fn code -> code != 0 end)
    string = utf8 |> TSON.String.utf8()
    {string, tail, memory |> Memory.note_string(string)}
  end

  defp decode(Op.repeated_string(), tail, memory) do
    {index, tail} = tail |> varuint
    {memory.strings[index], tail, memory}
  end

  defp decode(Op.bytes(), tail, memory) do
    {count, tail} = tail |> varuint
    {body, tail} = tail |> Enum.split(count)
    {body |> IO.iodata_to_binary(), tail, memory}
  end

  defp decode(Op.duration(), [unitOp | tail], memory) do
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

    {magnitude, tail} = tail |> varuint
    {%TSON.Duration{amount: magnitude * multiplier, unit: unit}, tail, memory}
  end

  defp decode(Op.positive_timestamp(), tail, memory) do
    {offset, tail} = tail |> varuint
    {DateTime.add(Op.epoch(), offset, :millisecond), tail, memory}
  end

  defp decode(Op.negative_timestamp(), tail, memory) do
    {offset, tail} = tail |> varuint
    {DateTime.add(Op.epoch(), -offset, :millisecond), tail, memory}
  end

  defp decode(Op.float_4(), tail, memory) do
    {first4, tail} = tail |> Enum.split(4)
    <<value32::float-32-little>> = first4 |> :binary.list_to_bin()
    {value32, tail, memory}
  end

  defp decode(Op.float_8(), tail, memory) do
    {first8, tail} = tail |> Enum.split(8)
    <<value64::float-64-little>> = first8 |> :binary.list_to_bin()
    {value64, tail, memory}
  end

  defp decode(Op.lat_lon(), tail, memory) do
    {geohash, tail} = tail |> varuint
    precision = 25
    {geohash |> TSON.LatLon.from_geohash(precision), tail, memory}
  end

  defp decode(Op.array(), tail, memory) do
    decode_list_to_0(tail, memory)
  end

  defp decode(Op.document(), tail, memory) do
    decode_map_to_0(tail, memory)
  end

  defp decode(small_array, tail, memory) when small_array in @small_array_range do
    decode_list_while_n(tail, memory, small_array - Op.small_array_1() + 1)
  end

  defp decode(small_doc, tail, memory) when small_doc in @small_document_range do
    decode_map_while_n(tail, memory, small_doc - Op.small_document_1() + 1)
  end

  defp decode(small_int, tail, memory) when small_int in Op.small_int_0()..Op.small_int_63() do
    {small_int - Op.small_int_0(), tail, memory}
  end

  defp decode(small_string, tail, memory) when small_string in @small_string_range do
    count = small_string - Op.small_string_1() + 1
    {utf8, tail} = tail |> Enum.split(count)
    string = utf8 |> TSON.String.utf8()
    {string, tail, memory |> Memory.note_string(string)}
  end

  defp decode_list_to_0([0 | tail], memory) do
    {[], tail, memory}
  end

  defp decode_list_to_0([op | tail], memory) do
    {value, tail, memory} = decode(op, tail, memory)
    {rest, tail, memory} = decode_list_to_0(tail, memory)
    {[value | rest], tail, memory}
  end

  defp decode_list_while_n(tail, memory, 0) do
    {[], tail, memory}
  end

  defp decode_list_while_n([op | tail], memory, count) do
    {value, tail, memory} = decode(op, tail, memory)
    {rest, tail, memory} = decode_list_while_n(tail, memory, count - 1)
    {[value | rest], tail, memory}
  end

  defp decode_map_to_0([0 | tail], memory) do
    {%{}, tail, memory}
  end

  defp decode_map_to_0([op | tail], memory) do
    {value, tail, memory} = decode(op &&& 0x7F, tail, memory)

    {key, tail, memory} =
      if (op &&& 0x80) == 0x80 do
        {index, tail} = tail |> varuint
        {memory.keys[index], tail, memory}
      else
        {charlist, [0 | tail]} = tail |> Enum.split_while(fn code -> code != 0 end)
        key = charlist |> IO.iodata_to_binary()
        memory = memory |> Memory.note_key(key)
        {key, tail, memory}
      end

    {rest, tail, memory} = decode_map_to_0(tail, memory)
    {rest |> Map.put(key, value), tail, memory}
  end

  defp decode_map_while_n(tail, memory, 0) do
    {%{}, tail, memory}
  end

  defp decode_map_while_n([op | tail], memory, count) do
    {value, tail, memory} = decode(op &&& 0x7F, tail, memory)

    {key, tail, memory} =
      if (op &&& 0x80) == 0x80 do
        {index, tail} = tail |> varuint
        {memory.keys[index], tail, memory}
      else
        {charlist, [0 | tail]} = tail |> Enum.split_while(fn code -> code != 0 end)
        key = charlist |> IO.iodata_to_binary()
        memory = memory |> Memory.note_key(key)
        {key, tail, memory}
      end

    {rest, tail, memory} = decode_map_while_n(tail, memory, count - 1)
    {rest |> Map.put(key, value), tail, memory}
  end

  defp varuint([byte | tail]) when byte in 0..0x7F do
    {byte, tail}
  end

  defp varuint([byte | tail]) when byte > 0x7F do
    {high, tail} = tail |> varuint
    {(high <<< 7) + (byte &&& 0x7F), tail}
  end
end
