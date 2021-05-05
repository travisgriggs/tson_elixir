defmodule TSON.Opcodes do
  defmacro document, do: 1
  defmacro array, do: 2
  defmacro bytes, do: 3
  defmacro positive_timestamp, do: 4
  defmacro _true, do: 5
  defmacro _false, do: 6
  defmacro none, do: 7
  defmacro negative_timestamp, do: 8
  defmacro lat_lon, do: 9
  # 10 - 13 unused
  defmacro terminated_string, do: 14
  defmacro repeated_string, do: 15
  defmacro small_string_1, do: 16
  defmacro small_string_24, do: 39
  defmacro small_document_1, do: 40
  defmacro small_document_4, do: 43
  defmacro small_array_1, do: 44
  defmacro small_array_4, do: 47
  # 48 - 55 unused
  defmacro duration, do: 55
  # 56 - 57 unused
  defmacro positive_varuint, do: 58
  defmacro negative_varuint, do: 59
  defmacro float_4, do: 60
  defmacro float_8, do: 61
  # def opPositiveFraction, do:  62
  # def opPositiveFraction, do:  63
  defmacro small_int_0, do: 64
  defmacro small_int_63, do: 127

  def epoch() do
    {:ok, epoch, _} = DateTime.from_iso8601("2016-01-01T00:00:00Z")
    epoch
  end
end
