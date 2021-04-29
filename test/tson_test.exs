defmodule TSONTest do
  use ExUnit.Case
  doctest TSON

  def hexs(s) when is_binary(s) do
    Regex.replace(~R{[^A-Fa-f0-9]}, s, "") |> Base.decode16!(case: :mixed)
  end

  def hexs(s) when is_list(s) do
    to_string(s) |> hexs
  end

  test "empty" do
    assert TSON.encode(nil) == <<7>>
    assert TSON.decode(<<7>>) == nil
  end

  test "true" do
    assert TSON.encode(true) == <<5>>
    assert TSON.decode(<<5>>) == true
  end

  test "false" do
    assert TSON.encode(false) == <<6>>
    assert TSON.decode(<<6>>) == false
  end

  test "int0" do
    original = 0
    result = TSON.encode(original)
    assert result == hexs('40')
    # decoded = TSON.decode(result)
    # self.assertEqual(decoded, original)
  end

  test "int27" do
    original = 27
    result = TSON.encode(original)
    assert result == hexs('5B')
    # decoded = TSON.decode(result)
    # self.assertEqual(decoded, original)
  end

  test "intNeg13" do
    original = -13
    result = TSON.encode(original)
    assert result == hexs('3B 0D')
    # decoded = TSON.decode(result)
    # self.assertEqual(decoded, original)
  end

  test "intNeg2000" do
    original = -2000
    result = TSON.encode(original)
    assert result == hexs('3B D00F')
    # decoded = TSON.decode(result)
    # self.assertEqual(decoded, original)
  end

  test "int63" do
    original = 63
    result = TSON.encode(original)
    assert result == hexs('7F')
    # decoded = TSON.decode(result)
    # self.assertEqual(decoded, original)
  end

  test "int64" do
    original = 64
    result = TSON.encode(original)
    assert result == hexs('3A 40')
    # decoded = TSON.decode(result)
    # self.assertEqual(decoded, original)
  end

  test "int123456" do
    original = 123_456
    result = TSON.encode(original)
    assert result == hexs('3A C0C407')
    # decoded = TSON.decode(result)
    # self.assertEqual(decoded, original)
  end

  test "string0" do
    original = %TSON.String{utf8: ""}
    assert TSON.encode(original) == hexs("0E 00")
    #   assert TSON.decodeString(<<0x0E, 0x00>>) == ""
  end

  test "string1" do
    original = %TSON.String{utf8: "1"}
    assert TSON.encode(original) == hexs("10 31")
    #   assert TSON.decodeString(<<0x0E, 0x00>>) == ""
  end

  test "string13" do
    original = %TSON.String{utf8: "\t13th Friday\n"}
    assert TSON.encode(original) == hexs('1C 0931337468204672696461790A')
    #   assert TSON.decodeString(<<0x0E, 0x00>>) == ""
  end

  test "string24" do
    s24 = %TSON.String{utf8: String.duplicate("Z", 24)}

    assert TSON.encode(s24) == hexs('27 5A5A5A5A5A5A5A5A 5A5A5A5A5A5A5A5A 5A5A5A5A5A5A5A5A')

    #   assert TSON.decodeString(<<0x0E, 0x00>>) == ""
  end

  test "string25" do
    s25 = %TSON.String{utf8: String.duplicate("y", 25)}

    assert TSON.encode(s25) == hexs('0E 7979797979797979 7979797979797979 7979797979797979 7900')

    #   assert TSON.decodeString(<<0x0E, 0x00>>) == ""
  end

  test "binaryBytes" do
    original = <<11, 22, 33, 44, 55, 66, 77>>
    assert TSON.encode(original) == hexs('03 07 0B16212C37424D')
    #   assert TSON.decodeString(<<0x0E, 0x00>>) == ""
  end

  test "array0" do
    original = []
    result = TSON.encode(original)
    assert result == hexs('02 00')
    #   assert TSON.decodeString(<<0x0E, 0x00>>) == ""
  end

  test "array1" do
    original = [%TSON.String{utf8: "t"}]
    result = TSON.encode(original)
    assert result == hexs('2C 1074')
    #   assert TSON.decodeString(<<0x0E, 0x00>>) == ""
  end

  test "array4" do
    original = [true, false, false, true]
    result = TSON.encode(original)
    assert result == hexs('2F 05 06 06 05')
    #   assert TSON.decodeString(<<0x0E, 0x00>>) == ""
  end

  test "array5" do
    original = [0, 2, 0, 63, 200]
    result = TSON.encode(original)
    assert result == hexs('02 40 42 40 7F 3A C8 01 00')
    #   assert TSON.decodeString(<<0x0E, 0x00>>) == ""
  end

  test "LatLon" do
    coord = %TSON.LatLon{latitude: 46.083529, longitude: -118.283026}
    result = TSON.encode(coord)
    assert result == hexs('09 A8 D4 E4 89 FA C5 58')
    # decoded = TSON.decode(result)
    # self.assertIsNotNone(decoded)
    # self.assertIsInstance(decoded, TSON.LatLon)
    # self.assertTrue((coord.latitude - decoded.latitude) < 0.00001)
    # self.assertTrue((coord.longitude - decoded.longitude) < 0.00001)
  end

  test "timestamp" do
    {:ok, original, _} = DateTime.from_iso8601("2016-09-19T07:00:00Z")
    result = TSON.encode(original)
    assert result == hexs('0480DB8AB654')
    # decoded = TSON.decode(result)
    # self.assertEqual(decoded, original)
  end

  test "negativeTimestamp" do
    {:ok, original, _} = DateTime.from_iso8601("1970-09-19T07:00:00Z")
    result = TSON.encode(original)
    assert result == hexs('088095FEC6CB29')
    # decoded = TSON.decode(result)
    # self.assertEqual(decoded, original)
  end

  test "duration500" do
    duration = %TSON.Duration{amount: 500, unit: :minute}
    result = TSON.encode(duration)
    assert result == hexs('37 02 F403')
    # decoded = TSON.decode(result)
    # self.assertEqual(decoded, duration)
  end

  test "duration500MinNeg" do
    duration = %TSON.Duration{amount: -500, unit: :minute}
    result = TSON.encode(duration)
    assert result == hexs('37 82 F403')
    # decoded = TSON.decode(result)
    # self.assertEqual(decoded, duration)
  end

  test "duration30Seconds" do
    duration = %TSON.Duration{amount: 30, unit: :second}
    result = TSON.encode(duration)
    assert result == hexs('37 01 1E')
    # decoded = TSON.decode(result)
    # self.assertEqual(decoded, duration)
  end

  test "duration60SecondsNeg" do
    duration = %TSON.Duration{amount: -60, unit: :second}
    result = TSON.encode(duration)
    assert result == hexs('37 82 01')
    # decoded = TSON.decode(result)
    # self.assertEqual(decoded, duration)
  end

  test "duration61SecondsNeg" do
    duration = %TSON.Duration{amount: -61, unit: :second}
    result = TSON.encode(duration)
    assert result == hexs('37 81 3D')
    # decoded = TSON.decode(result)
    # self.assertEqual(decoded, duration)
  end

  test "duration8000Milliseconds" do
    duration = %TSON.Duration{amount: 8000, unit: :millisecond}
    result = TSON.encode(duration)
    assert result == hexs('37 01 08')
    # decoded = TSON.decode(result)
    # self.assertEqual(decoded, duration)
  end

  test "duration8001Milliseconds" do
    duration = %TSON.Duration{amount: 8001, unit: :millisecond}
    result = TSON.encode(duration)
    assert result == hexs('37 03 C13E')
    # decoded = TSON.decode(result)
    # self.assertEqual(decoded, duration)
  end

  test "duration7777MillisecondsNeg" do
    duration = %TSON.Duration{amount: -7777, unit: :millisecond}
    result = TSON.encode(duration)
    assert result == hexs('37 83 E13C')
    # decoded = TSON.decode(result)
    # self.assertEqual(decoded, duration)
  end

  test "duration15Microseconds" do
    duration = %TSON.Duration{amount: 15, unit: :microsecond}
    result = TSON.encode(duration)
    assert result == hexs('37 06 0F')
    # decoded = TSON.decode(result)
    # self.assertEqual(decoded, duration)
  end

  test "duration1MicrosecondsNeg" do
    duration = %TSON.Duration{amount: -1, unit: :microsecond}
    result = TSON.encode(duration)
    assert result == hexs('37 86 01')
    # decoded = TSON.decode(result)
    # self.assertEqual(decoded, duration)
  end

  test "duration24Hours" do
    duration = %TSON.Duration{amount: 24, unit: :hour}
    result = TSON.encode(duration)
    assert result == hexs('37 04 18')
    # decoded = TSON.decode(result)
    # self.assertEqual(decoded, duration)
  end

  test "duration180HoursNeg" do
    duration = %TSON.Duration{amount: -180, unit: :hour}
    result = TSON.encode(duration)
    assert result == hexs('37 84 B401')
    # decoded = TSON.decode(result)
    # self.assertEqual(decoded, duration)
  end

  test "float200_0" do
    original = 200.0
    result = TSON.encode(original)
    assert result == hexs('3AC801')
    # decoded = TSON.decode(result)
    # self.assertEqual(decoded, original)
  end

  test "floatNeg6789_0" do
    original = -6789.0
    result = TSON.encode(original)
    assert result == hexs('3B8535')
    # decoded = TSON.decode(result)
    # self.assertEqual(decoded, original)
  end

  test "float0_25" do
    original = 0.25
    result = TSON.encode(original)
    assert result == hexs('3C0000803E')
    # decoded = TSON.decode(result)
    # self.assertEqual(decoded, original)
  end

  test "float0_3333" do
    original = 0.3333
    result = TSON.encode(original)
    assert result == hexs('3D696FF085C954D53F')
    # decoded = TSON.decode(result)
    # self.assertEqual(decoded, original)
  end

  test "repeatedStrings" do
    original =
      ["hello", "kitty", "hello", "world", "here", "kitty", "kitty", "kitty"]
      |> Enum.map(fn x -> %TSON.String{utf8: x} end)

    result = TSON.encode(original)
    expected = hexs('02 1468656C6C6F 146B69747479 0F00 14776F726C64 1368657265 0F01 0F01 0F01 00')
    assert result == expected
    # decoded = tson.decode(result)
    # self.assertEqual(decoded, original)
  end

  test "nested repeated strings" do
    a =
      ["hello", "kitty", "hello", "world"]
      |> Enum.map(fn x -> %TSON.String{utf8: x} end)

    b =
      ["here", "kitty", "kitty", "kitty"]
      |> Enum.map(fn x -> %TSON.String{utf8: x} end)

    original = [a, b]
    result = TSON.encode(original)

    expected =
      hexs('2D 2F 1468656C6C6F 146B69747479 0F00 14776F726C64 2F 1368657265 0F01 0F01 0F01')

    assert result == expected
    # decoded = tson.decode(result)
    # self.assertEqual(decoded, original)
  end

  test "Doc0" do
    original = %{}
    result = TSON.encode(original)
    assert result == hexs('01 00')
    # decoded = tson.decode(result)
    # self.assertEqual(decoded, original)
  end

  test "Doc1" do
    original = %{"1": nil}
    result = TSON.encode(original)
    assert result == hexs('28073100')
    # decoded = tson.decode(result)
    # self.assertEqual(decoded, original)
  end

  test "Doc4" do
    original = %{"1" => nil, "2" => nil, "3" => nil, "4" => nil}
    result = TSON.encode(original)
    assert result == hexs('2B 073100 073200 073300 073400')
    # decoded = tson.decode(result)
    # self.assertEqual(decoded, original)
  end

  test "Doc5" do
    original = %{"1" => nil, "2" => nil, "3" => nil, "4" => nil, "5" => nil}
    result = TSON.encode(original)
    assert result == hexs('01 073100 073200 073300 073400 073500 00')
    # decoded = tson.decode(result)
    # self.assertEqual(decoded, original)
  end
end
